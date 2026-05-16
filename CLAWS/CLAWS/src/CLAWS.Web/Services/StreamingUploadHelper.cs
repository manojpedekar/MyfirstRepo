using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Net.Http.Headers;
using CLAWS.Core.Configuration;

namespace CLAWS.Web.Services;

/// <summary>
/// Result of a streaming upload operation.
/// </summary>
public class StreamingUploadResult
{
    public bool Success { get; set; }
    public string? FilePath { get; set; }
    public string? FileName { get; set; }
    public long FileSize { get; set; }
    public string? ErrorCode { get; set; }
    public string? ErrorMessage { get; set; }

    /// <summary>
    /// Additional form fields submitted with the upload.
    /// </summary>
    public Dictionary<string, string> FormFields { get; set; } = new();
}

/// <summary>
/// Helper for streaming large file uploads directly to disk without buffering.
/// </summary>
public interface IStreamingUploadHelper
{
    /// <summary>
    /// Streams an uploaded file directly to the configured upload path.
    /// </summary>
    /// <param name="request">The HTTP request containing the file.</param>
    /// <param name="uploadId">The unique upload identifier.</param>
    /// <param name="maxFileSize">Maximum allowed file size in bytes.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Result containing the saved file path and metadata.</returns>
    Task<StreamingUploadResult> StreamToFileAsync(
        HttpRequest request,
        Guid uploadId,
        long maxFileSize,
        CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of streaming upload helper.
/// </summary>
public class StreamingUploadHelper : IStreamingUploadHelper
{
    private readonly ILogger<StreamingUploadHelper> _logger;
    private readonly StorageSettings _storageSettings;
    private readonly AppSettings _appSettings;

    // Permitted file extensions
    private static readonly string[] PermittedExtensions = { ".zip" };

    public StreamingUploadHelper(
        ILogger<StreamingUploadHelper> logger,
        StorageSettings storageSettings,
        AppSettings appSettings)
    {
        _logger = logger;
        _storageSettings = storageSettings;
        _appSettings = appSettings;
    }

    /// <inheritdoc/>
    public async Task<StreamingUploadResult> StreamToFileAsync(
        HttpRequest request,
        Guid uploadId,
        long maxFileSize,
        CancellationToken cancellationToken)
    {
        // Verify content type is multipart
        if (!IsMultipartContentType(request.ContentType))
        {
            return new StreamingUploadResult
            {
                Success = false,
                ErrorCode = "INVALID_CONTENT_TYPE",
                ErrorMessage = "Expected multipart/form-data content type."
            };
        }

        var boundary = GetBoundary(
            MediaTypeHeaderValue.Parse(request.ContentType));

        if (string.IsNullOrEmpty(boundary))
        {
            return new StreamingUploadResult
            {
                Success = false,
                ErrorCode = "INVALID_BOUNDARY",
                ErrorMessage = "Could not parse multipart boundary."
            };
        }

        var reader = new MultipartReader(boundary, request.Body);
        var section = await reader.ReadNextSectionAsync(cancellationToken);

        string? fileName = null;
        string? savedPath = null;
        long totalBytes = 0;
        var formFields = new Dictionary<string, string>();

        while (section != null)
        {
            var hasContentDispositionHeader = ContentDispositionHeaderValue.TryParse(
                section.ContentDisposition, out var contentDisposition);

            if (hasContentDispositionHeader && contentDisposition != null)
            {
                // Check if this is a form field (not a file)
                if (HasFormFieldContentDisposition(contentDisposition))
                {
                    var fieldName = contentDisposition.Name.Value?.Trim('"');
                    if (!string.IsNullOrEmpty(fieldName))
                    {
                        using var streamReader = new StreamReader(section.Body);
                        var fieldValue = await streamReader.ReadToEndAsync(cancellationToken);
                        formFields[fieldName] = fieldValue;
                    }
                    section = await reader.ReadNextSectionAsync(cancellationToken);
                    continue;
                }
            }

            if (hasContentDispositionHeader &&
                contentDisposition != null &&
                HasFileContentDisposition(contentDisposition))
            {
                // Get filename from content disposition
                fileName = contentDisposition.FileName.Value?.Trim('"');

                if (string.IsNullOrEmpty(fileName))
                {
                    return new StreamingUploadResult
                    {
                        Success = false,
                        ErrorCode = "NO_FILENAME",
                        ErrorMessage = "File name not provided in upload."
                    };
                }

                // Validate file extension
                var extension = Path.GetExtension(fileName).ToLowerInvariant();
                if (!PermittedExtensions.Contains(extension))
                {
                    return new StreamingUploadResult
                    {
                        Success = false,
                        ErrorCode = "INVALID_FILE_TYPE",
                        ErrorMessage = "Only ZIP files are accepted."
                    };
                }

                // Ensure upload directory exists
                var uploadPath = _storageSettings.GetUploadPath();
                Directory.CreateDirectory(uploadPath);

                // Create target file path
                savedPath = Path.Combine(uploadPath, $"{uploadId}.zip");

                _logger.LogInformation(
                    "Streaming upload {UploadId} to {Path}",
                    uploadId, savedPath);

                try
                {
                    // Stream directly to file
                    await using var targetStream = new FileStream(
                        savedPath,
                        FileMode.Create,
                        FileAccess.Write,
                        FileShare.None,
                        bufferSize: 81920, // 80KB buffer
                        useAsync: true);

                    // Use a larger buffer for better performance
                    var buffer = new byte[81920];
                    int bytesRead;

                    // Upload diagnostics tracking
                    var enableDiagnostics = _appSettings.Logging.EnableUploadDiagnostics;
                    var progressIntervalBytes = _appSettings.Logging.UploadProgressIntervalMB * 1024L * 1024L;
                    var progressIntervalPercent = _appSettings.Logging.UploadProgressIntervalPercent;
                    var expectedSize = request.ContentLength ?? 0;
                    var startTime = DateTime.UtcNow;
                    var lastProgressLog = 0L;
                    var lastProgressPercent = 0;
                    var lastDataTime = DateTime.UtcNow;

                    while ((bytesRead = await section.Body.ReadAsync(
                        buffer, 0, buffer.Length, cancellationToken)) > 0)
                    {
                        totalBytes += bytesRead;
                        lastDataTime = DateTime.UtcNow;

                        // Check file size limit during streaming
                        if (totalBytes > maxFileSize)
                        {
                            if (enableDiagnostics)
                            {
                                _logger.LogWarning(
                                    "[UPLOAD-DIAG] Size limit exceeded: UploadId={UploadId}, " +
                                    "Received={Received} bytes, MaxAllowed={MaxAllowed} bytes",
                                    uploadId, totalBytes, maxFileSize);
                            }

                            // Clean up partial file
                            await targetStream.DisposeAsync();
                            if (File.Exists(savedPath))
                            {
                                File.Delete(savedPath);
                            }

                            return new StreamingUploadResult
                            {
                                Success = false,
                                FileSize = totalBytes,
                                ErrorCode = "FILE_TOO_LARGE",
                                ErrorMessage = $"File size exceeds maximum allowed ({maxFileSize / (1024 * 1024 * 1024.0):F1} GB)."
                            };
                        }

                        await targetStream.WriteAsync(
                            buffer.AsMemory(0, bytesRead), cancellationToken);

                        // Upload diagnostics: Log progress at configured intervals
                        if (enableDiagnostics)
                        {
                            var bytesSinceLastLog = totalBytes - lastProgressLog;
                            var currentPercent = expectedSize > 0 ? (int)(totalBytes * 100 / expectedSize) : 0;
                            var percentSinceLastLog = currentPercent - lastProgressPercent;

                            // Log if we've received enough bytes OR enough percentage
                            if (bytesSinceLastLog >= progressIntervalBytes ||
                                (progressIntervalPercent > 0 && percentSinceLastLog >= progressIntervalPercent))
                            {
                                var elapsed = DateTime.UtcNow - startTime;
                                var throughputMBps = elapsed.TotalSeconds > 0
                                    ? (totalBytes / (1024.0 * 1024.0)) / elapsed.TotalSeconds
                                    : 0;

                                var etaSeconds = (expectedSize > 0 && throughputMBps > 0)
                                    ? (expectedSize - totalBytes) / (throughputMBps * 1024 * 1024)
                                    : 0;

                                _logger.LogInformation(
                                    "[UPLOAD-DIAG] Streaming progress: UploadId={UploadId}, " +
                                    "Received={ReceivedMB:F1} MB / {ExpectedMB:F1} MB ({Percent}%), " +
                                    "Elapsed={Elapsed}, Throughput={Throughput:F1} MB/s, ETA={ETA}",
                                    uploadId,
                                    totalBytes / (1024.0 * 1024.0),
                                    expectedSize / (1024.0 * 1024.0),
                                    currentPercent,
                                    elapsed.ToString(@"hh\:mm\:ss"),
                                    throughputMBps,
                                    TimeSpan.FromSeconds(etaSeconds).ToString(@"hh\:mm\:ss"));

                                lastProgressLog = totalBytes;
                                lastProgressPercent = currentPercent;
                            }
                        }
                    }

                    await targetStream.FlushAsync(cancellationToken);

                    // Upload diagnostics: Log final stats
                    if (enableDiagnostics)
                    {
                        var totalElapsed = DateTime.UtcNow - startTime;
                        var avgThroughput = totalElapsed.TotalSeconds > 0
                            ? (totalBytes / (1024.0 * 1024.0)) / totalElapsed.TotalSeconds
                            : 0;

                        _logger.LogInformation(
                            "[UPLOAD-DIAG] Streaming complete: UploadId={UploadId}, " +
                            "TotalBytes={TotalBytes} ({TotalMB:F1} MB), " +
                            "Duration={Duration}, AvgThroughput={Throughput:F1} MB/s",
                            uploadId, totalBytes, totalBytes / (1024.0 * 1024.0),
                            totalElapsed.ToString(@"hh\:mm\:ss"), avgThroughput);
                    }
                }
                catch (OperationCanceledException)
                {
                    if (_appSettings.Logging.EnableUploadDiagnostics)
                    {
                        _logger.LogWarning(
                            "[UPLOAD-DIAG] Upload cancelled: UploadId={UploadId}, BytesReceived={Bytes}",
                            uploadId, totalBytes);
                    }

                    // Clean up partial file on cancellation
                    if (File.Exists(savedPath))
                    {
                        try { File.Delete(savedPath); }
                        catch { /* Best effort cleanup */ }
                    }
                    throw;
                }
                catch (IOException ioEx)
                {
                    // Detailed logging for I/O errors (common for network issues)
                    if (_appSettings.Logging.EnableUploadDiagnostics)
                    {
                        _logger.LogError(
                            "[UPLOAD-DIAG] I/O error during upload: UploadId={UploadId}, " +
                            "BytesReceived={Bytes}, ErrorType={ErrorType}, HResult={HResult}, Message={Message}",
                            uploadId, totalBytes, ioEx.GetType().Name, ioEx.HResult, ioEx.Message);
                    }
                    else
                    {
                        _logger.LogError(ioEx, "Error streaming upload {UploadId}", uploadId);
                    }

                    // Clean up partial file on error
                    if (File.Exists(savedPath))
                    {
                        try { File.Delete(savedPath); }
                        catch { /* Best effort cleanup */ }
                    }

                    return new StreamingUploadResult
                    {
                        Success = false,
                        FileSize = totalBytes,
                        ErrorCode = "STREAMING_ERROR",
                        ErrorMessage = $"Network or I/O error while receiving the file: {ioEx.Message}"
                    };
                }
                catch (Exception ex)
                {
                    if (_appSettings.Logging.EnableUploadDiagnostics)
                    {
                        _logger.LogError(
                            "[UPLOAD-DIAG] Error during upload: UploadId={UploadId}, " +
                            "BytesReceived={Bytes}, ErrorType={ErrorType}, Message={Message}",
                            uploadId, totalBytes, ex.GetType().Name, ex.Message);
                    }
                    else
                    {
                        _logger.LogError(ex, "Error streaming upload {UploadId}", uploadId);
                    }

                    // Clean up partial file on error
                    if (File.Exists(savedPath))
                    {
                        try { File.Delete(savedPath); }
                        catch { /* Best effort cleanup */ }
                    }

                    return new StreamingUploadResult
                    {
                        Success = false,
                        FileSize = totalBytes,
                        ErrorCode = "STREAMING_ERROR",
                        ErrorMessage = "An error occurred while receiving the file."
                    };
                }

                // Only process one file per request
                break;
            }

            section = await reader.ReadNextSectionAsync(cancellationToken);
        }

        if (string.IsNullOrEmpty(savedPath) || string.IsNullOrEmpty(fileName))
        {
            return new StreamingUploadResult
            {
                Success = false,
                ErrorCode = "NO_FILE",
                ErrorMessage = "No file provided in the request."
            };
        }

        _logger.LogInformation(
            "Upload {UploadId} streamed successfully: {FileName} ({Size:N0} bytes)",
            uploadId, fileName, totalBytes);

        return new StreamingUploadResult
        {
            Success = true,
            FilePath = savedPath,
            FileName = fileName,
            FileSize = totalBytes,
            FormFields = formFields
        };
    }

    private static bool IsMultipartContentType(string? contentType)
    {
        return !string.IsNullOrEmpty(contentType) &&
               contentType.Contains("multipart/", StringComparison.OrdinalIgnoreCase);
    }

    private static string? GetBoundary(MediaTypeHeaderValue contentType)
    {
        var boundary = HeaderUtilities.RemoveQuotes(contentType.Boundary).Value;

        if (string.IsNullOrWhiteSpace(boundary))
        {
            return null;
        }

        // Limit boundary length per spec
        if (boundary.Length > 70)
        {
            return null;
        }

        return boundary;
    }

    private static bool HasFileContentDisposition(ContentDispositionHeaderValue contentDisposition)
    {
        // Content-Disposition: form-data; name="file"; filename="example.zip"
        return contentDisposition.DispositionType.Equals("form-data") &&
               (!string.IsNullOrEmpty(contentDisposition.FileName.Value) ||
                !string.IsNullOrEmpty(contentDisposition.FileNameStar.Value));
    }

    private static bool HasFormFieldContentDisposition(ContentDispositionHeaderValue contentDisposition)
    {
        // Content-Disposition: form-data; name="fieldName"
        // (no filename means it's a form field, not a file)
        return contentDisposition.DispositionType.Equals("form-data") &&
               string.IsNullOrEmpty(contentDisposition.FileName.Value) &&
               string.IsNullOrEmpty(contentDisposition.FileNameStar.Value) &&
               !string.IsNullOrEmpty(contentDisposition.Name.Value);
    }
}
