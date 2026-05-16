using System.IO.Compression;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Core.Models;

namespace CLAWS.Core.Validation;

/// <summary>
/// Validates ZIP files for NTFS permissions database uploads.
/// </summary>
public interface IZipValidator
{
    /// <summary>
    /// Validates a ZIP file and extracts the SQLite database if valid.
    /// </summary>
    /// <param name="zipPath">Path to the ZIP file.</param>
    /// <param name="extractionPath">Path where the SQLite database should be extracted.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Validation result with extracted file path if successful.</returns>
    Task<ZipValidationResult> ValidateAndExtractAsync(
        string zipPath,
        string extractionPath,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Implementation of ZIP file validation.
/// </summary>
public class ZipValidator : IZipValidator
{
    private readonly ILogger<ZipValidator> _logger;
    private readonly UploadLimitSettings _limits;

    // SQLite magic header bytes
    private static readonly byte[] SqliteMagicHeader = new byte[]
    {
        0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
        0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
    };

    public ZipValidator(ILogger<ZipValidator> logger, UploadLimitSettings limits)
    {
        _logger = logger;
        _limits = limits;
    }

    /// <inheritdoc/>
    public async Task<ZipValidationResult> ValidateAndExtractAsync(
        string zipPath,
        string extractionPath,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("Starting ZIP validation for {ZipPath}", zipPath);

        try
        {
            // Open the ZIP archive
            using var archive = ZipFile.OpenRead(zipPath);

            // Check entry count
            if (archive.Entries.Count == 0)
            {
                _logger.LogWarning("ZIP file is empty: {ZipPath}", zipPath);
                return new ZipValidationResult
                {
                    IsValid = false,
                    ErrorCode = "ZIP_EMPTY",
                    ErrorMessage = "ZIP file is empty. Expected a single SQLite database file."
                };
            }

            if (archive.Entries.Count > 1)
            {
                _logger.LogWarning("ZIP file contains {Count} files: {ZipPath}", archive.Entries.Count, zipPath);
                return new ZipValidationResult
                {
                    IsValid = false,
                    ErrorCode = "ZIP_MULTIPLE_FILES",
                    ErrorMessage = "ZIP contains multiple files. Expected exactly one SQLite database file."
                };
            }

            var entry = archive.Entries[0];

            // Check for directory entry
            if (entry.FullName.EndsWith('/') || entry.FullName.EndsWith('\\'))
            {
                _logger.LogWarning("ZIP entry is a directory: {EntryName}", entry.FullName);
                return new ZipValidationResult
                {
                    IsValid = false,
                    ErrorCode = "ZIP_CONTAINS_FOLDER",
                    ErrorMessage = "ZIP contains directory structure. Please ZIP only the database file without folders."
                };
            }

            // Check for path traversal
            if (entry.FullName.Contains("..") ||
                entry.FullName.Contains('/') ||
                entry.FullName.Contains('\\'))
            {
                _logger.LogWarning("ZIP entry contains path traversal or folders: {EntryName}", entry.FullName);
                return new ZipValidationResult
                {
                    IsValid = false,
                    ErrorCode = "ZIP_PATH_TRAVERSAL",
                    ErrorMessage = "ZIP entry contains invalid path. Upload rejected for security reasons."
                };
            }

            // Check uncompressed size
            if (entry.Length > _limits.MaxExtractedSizeBytes)
            {
                var limitGb = _limits.MaxExtractedSizeBytes / (1024.0 * 1024 * 1024);
                _logger.LogWarning("ZIP entry exceeds size limit: {Size} bytes > {Limit} bytes",
                    entry.Length, _limits.MaxExtractedSizeBytes);
                return new ZipValidationResult
                {
                    IsValid = false,
                    ErrorCode = "ZIP_SIZE_EXCEEDED",
                    ErrorMessage = $"Extracted file size exceeds maximum allowed ({limitGb:F1} GB).",
                    UncompressedSize = entry.Length
                };
            }

            // Check compression ratio (zip bomb protection)
            var compressionRatio = entry.CompressedLength > 0
                ? (double)entry.Length / entry.CompressedLength
                : 0;

            if (compressionRatio > _limits.MaxCompressionRatio)
            {
                _logger.LogWarning("ZIP compression ratio is suspicious: {Ratio}:1", compressionRatio);
                return new ZipValidationResult
                {
                    IsValid = false,
                    ErrorCode = "ZIP_BOMB_SUSPECTED",
                    ErrorMessage = "ZIP file rejected: compression ratio exceeds safety threshold.",
                    CompressionRatio = compressionRatio
                };
            }

            // Extract to temp location
            var extractedFilePath = Path.Combine(extractionPath, entry.Name);
            Directory.CreateDirectory(extractionPath);

            _logger.LogInformation("Extracting {EntryName} to {Path}", entry.Name, extractedFilePath);

            await Task.Run(() =>
            {
                entry.ExtractToFile(extractedFilePath, overwrite: true);
            }, cancellationToken);

            // Verify SQLite magic header
            var headerBytes = new byte[16];
            await using (var fs = File.OpenRead(extractedFilePath))
            {
                var bytesRead = await fs.ReadAsync(headerBytes, cancellationToken);
                if (bytesRead < 16)
                {
                    File.Delete(extractedFilePath);
                    return new ZipValidationResult
                    {
                        IsValid = false,
                        ErrorCode = "NOT_SQLITE",
                        ErrorMessage = "File is not a valid SQLite database."
                    };
                }
            }

            if (!headerBytes.SequenceEqual(SqliteMagicHeader))
            {
                _logger.LogWarning("File does not have SQLite magic header");
                File.Delete(extractedFilePath);
                return new ZipValidationResult
                {
                    IsValid = false,
                    ErrorCode = "NOT_SQLITE",
                    ErrorMessage = "File is not a valid SQLite database."
                };
            }

            _logger.LogInformation("ZIP validation successful for {ZipPath}", zipPath);

            return new ZipValidationResult
            {
                IsValid = true,
                EntryFileName = entry.Name,
                UncompressedSize = entry.Length,
                CompressedSize = entry.CompressedLength,
                CompressionRatio = compressionRatio,
                Details = new Dictionary<string, object>
                {
                    ["ExtractedPath"] = extractedFilePath
                }
            };
        }
        catch (InvalidDataException ex)
        {
            _logger.LogError(ex, "Invalid ZIP file: {ZipPath}", zipPath);
            return new ZipValidationResult
            {
                IsValid = false,
                ErrorCode = "ZIP_CORRUPT",
                ErrorMessage = "ZIP file is corrupt or not a valid ZIP archive."
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error validating ZIP file: {ZipPath}", zipPath);
            return new ZipValidationResult
            {
                IsValid = false,
                ErrorCode = "ZIP_ERROR",
                ErrorMessage = $"Error processing ZIP file: {ex.Message}"
            };
        }
    }
}
