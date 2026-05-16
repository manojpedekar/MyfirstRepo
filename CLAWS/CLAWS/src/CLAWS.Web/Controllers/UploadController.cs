using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Net.Http.Headers;
using CLAWS.Core.Configuration;
using CLAWS.Core.Models;
using CLAWS.Core.Services;
using CLAWS.Data.Repositories;
using CLAWS.Web.Filters;
using CLAWS.Web.Models;
using CLAWS.Web.Services;

namespace CLAWS.Web.Controllers;

/// <summary>
/// Controller for file upload operations.
/// All authenticated users can upload files.
/// </summary>
[Authorize]
public class UploadController : Controller
{
    private readonly ILogger<UploadController> _logger;
    private readonly IUploadService _uploadService;
    private readonly IUploadRepository _uploadRepository;
    private readonly IStreamingUploadHelper _streamingUploadHelper;
    private readonly IDiskSpaceService _diskSpaceService;
    private readonly IChunkedUploadService _chunkedUploadService;
    private readonly AppSettings _appSettings;

    public UploadController(
        ILogger<UploadController> logger,
        IUploadService uploadService,
        IUploadRepository uploadRepository,
        IStreamingUploadHelper streamingUploadHelper,
        IDiskSpaceService diskSpaceService,
        IChunkedUploadService chunkedUploadService,
        AppSettings appSettings)
    {
        _logger = logger;
        _uploadService = uploadService;
        _uploadRepository = uploadRepository;
        _streamingUploadHelper = streamingUploadHelper;
        _diskSpaceService = diskSpaceService;
        _chunkedUploadService = chunkedUploadService;
        _appSettings = appSettings;
    }

    /// <summary>
    /// Checks if the current user can manage the given upload.
    /// Users can manage their own uploads. Type-specific admins can manage uploads of their type.
    /// Site admins can manage all uploads.
    /// </summary>
    private bool CanManageUpload(Data.Entities.Upload upload, string userName)
    {
        // Owner can always manage their own
        if (upload.UploadedBy == userName)
            return true;

        // Site Admin can manage all
        if (!string.IsNullOrEmpty(_appSettings.Authorization.SiteAdminGroup) &&
            User.IsInRole(_appSettings.Authorization.SiteAdminGroup))
            return true;

        // Type-specific admins can manage their type
        if (upload.UploadType == "NTFSPermissions" &&
            !string.IsNullOrEmpty(_appSettings.Authorization.NtfsPermsAdminGroup) &&
            User.IsInRole(_appSettings.Authorization.NtfsPermsAdminGroup))
            return true;

        if (upload.UploadType == "ADInventory" &&
            !string.IsNullOrEmpty(_appSettings.Authorization.AdAdminGroup) &&
            User.IsInRole(_appSettings.Authorization.AdAdminGroup))
            return true;

        return false;
    }

    [HttpGet]
    public IActionResult Index()
    {
        var model = new UploadViewModel
        {
            IsDbConfigured = _appSettings.SqlServer.IsConfigured,
            IsAuthConfigured = _appSettings.Authorization.IsConfigured,
            IsUsingAppDirectory = _appSettings.Storage.IsUsingApplicationDirectory(
                Path.GetDirectoryName(typeof(Program).Assembly.Location) ?? ""),
            MaxFileSizeBytes = _appSettings.UploadLimits.MaxUploadSizeBytes,
            MaxFileSizeMB = _appSettings.UploadLimits.MaxUploadSizeBytes / (1024.0 * 1024.0),
            EnableAutomaticValidation = _appSettings.Import.EnableAutomaticValidation,
            EnableAutomaticMerge = _appSettings.Import.EnableAutomaticMerge
        };

        return View(model);
    }

    [HttpPost]
    [DisableRequestSizeLimit] // Uses Kestrel's MaxRequestBodySize from AppSettings.UploadLimits.MaxUploadSizeBytes
    [DisableFormValueModelBinding]
    public async Task<IActionResult> Upload(CancellationToken cancellationToken)
    {
        // Generate upload ID upfront for streaming and logging
        var uploadId = Guid.NewGuid();
        var contentLength = Request.ContentLength;
        var estimatedSize = contentLength ?? _appSettings.UploadLimits.MaxUploadSizeBytes;

        // Upload diagnostics: Log request details
        if (_appSettings.Logging.EnableUploadDiagnostics)
        {
            var clientIp = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
            var userAgent = Request.Headers.UserAgent.ToString();
            var contentType = Request.ContentType ?? "unknown";
            var diagUser = User.Identity?.Name ?? "Unknown";

            _logger.LogInformation(
                "[UPLOAD-DIAG] Request received: UploadId={UploadId}, " +
                "ContentLength={ContentLength} ({ContentLengthMB:F1} MB), " +
                "ContentType={ContentType}, User={User}, ClientIP={ClientIP}, UserAgent={UserAgent}",
                uploadId,
                contentLength?.ToString() ?? "unknown",
                contentLength.HasValue ? contentLength.Value / (1024.0 * 1024.0) : 0,
                contentType,
                diagUser,
                clientIp,
                userAgent.Length > 100 ? userAgent[..100] + "..." : userAgent);
        }

        // Check disk space before accepting upload
        if (!_diskSpaceService.HasSufficientSpace(
            _appSettings.Storage.ImportBasePath,
            _appSettings.UploadLimits.MinFreeDiskSpaceBytes + estimatedSize * 2))
        {
            if (_appSettings.Logging.EnableUploadDiagnostics)
            {
                _logger.LogWarning("[UPLOAD-DIAG] Upload rejected - insufficient disk space: UploadId={UploadId}", uploadId);
            }
            return BadRequest(new { success = false, error = "Insufficient disk space. Please try again later." });
        }

        // Stream file directly to destination
        var streamResult = await _streamingUploadHelper.StreamToFileAsync(
            Request,
            uploadId,
            _appSettings.UploadLimits.MaxUploadSizeBytes,
            cancellationToken);

        if (!streamResult.Success)
        {
            if (_appSettings.Logging.EnableUploadDiagnostics)
            {
                _logger.LogError(
                    "[UPLOAD-DIAG] Streaming failed: UploadId={UploadId}, ErrorCode={ErrorCode}, Error={Error}, " +
                    "BytesReceived={BytesReceived}, ExpectedBytes={ExpectedBytes}",
                    uploadId, streamResult.ErrorCode, streamResult.ErrorMessage,
                    streamResult.FileSize, contentLength?.ToString() ?? "unknown");
            }
            return BadRequest(new
            {
                success = false,
                errorCode = streamResult.ErrorCode,
                error = streamResult.ErrorMessage
            });
        }

        // Upload diagnostics: Log successful streaming completion
        if (_appSettings.Logging.EnableUploadDiagnostics)
        {
            _logger.LogInformation(
                "[UPLOAD-DIAG] Streaming completed: UploadId={UploadId}, FileName={FileName}, " +
                "FileSize={FileSize} ({FileSizeMB:F1} MB), FilePath={FilePath}",
                uploadId, streamResult.FileName, streamResult.FileSize,
                streamResult.FileSize / (1024.0 * 1024.0), streamResult.FilePath);
        }

        // NOTE: Type detection is deferred to the processing job after ZIP extraction.
        // Authorization check happens there to avoid SQLite errors on ZIP files.
        // The processing job will reject unauthorized uploads after extraction.

        // Process the streamed file
        var userName = User.Identity?.Name ?? "Unknown";
        var sourceIp = HttpContext.Connection.RemoteIpAddress?.ToString();

        // Get the auto-processing override if specified
        string? autoProcessingOverride = null;
        if (streamResult.FormFields.TryGetValue("autoProcessingOverride", out var overrideValue)
            && !string.IsNullOrEmpty(overrideValue))
        {
            // Validate the override value
            var validOverrides = new[] { "ValidateOnly", "ValidateAndMerge", "Manual" };
            if (validOverrides.Contains(overrideValue))
            {
                autoProcessingOverride = overrideValue;
            }
        }

        var result = await _uploadService.ProcessStreamedUploadAsync(
            uploadId,
            streamResult.FilePath!,
            streamResult.FileName!,
            streamResult.FileSize,
            userName,
            sourceIp,
            autoProcessingOverride,
            cancellationToken);

        if (!result.Success)
        {
            return BadRequest(new
            {
                success = false,
                uploadId = result.UploadId,
                errorCode = result.ErrorCode,
                error = result.ErrorMessage
            });
        }

        return Ok(new
        {
            success = true,
            uploadId = result.UploadId,
            message = "File validated successfully. Import queued.",
            queuePosition = result.QueuePosition
        });
    }

    [HttpGet("{id:guid}/status")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> Status(Guid id, CancellationToken cancellationToken)
    {
        var status = await _uploadService.GetStatusAsync(id, cancellationToken);
        if (status == null)
        {
            return NotFound(new { success = false, error = "Upload not found." });
        }

        return Ok(new { success = true, data = status });
    }

    /// <summary>
    /// Lightweight endpoint for real-time progress polling.
    /// </summary>
    [HttpGet("{id:guid}/progress")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> Progress(Guid id, CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(id, cancellationToken);
        if (upload == null)
        {
            return NotFound(new { success = false, error = "Upload not found." });
        }

        // Calculate records per second and ETA
        double recordsPerSecond = 0;
        int? estimatedSecondsRemaining = null;

        if (upload.RowsProcessed > 0 && upload.StartedAt.HasValue)
        {
            var elapsedSeconds = (DateTime.UtcNow - upload.StartedAt.Value).TotalSeconds;
            if (elapsedSeconds > 0)
            {
                recordsPerSecond = upload.RowsProcessed.Value / elapsedSeconds;

                if (upload.TotalRows.HasValue && upload.TotalRows > 0 && recordsPerSecond > 0)
                {
                    var remainingRows = upload.TotalRows.Value - upload.RowsProcessed.Value;
                    estimatedSecondsRemaining = (int)Math.Ceiling(remainingRows / recordsPerSecond);
                }
            }
        }

        var progress = new CLAWS.Core.Models.ProgressData
        {
            UploadId = upload.UploadId,
            Status = upload.Status,
            Phase = upload.CurrentPhase,
            Progress = upload.ImportProgress ?? 0,
            RowsProcessed = upload.RowsProcessed ?? 0,
            TotalRows = upload.TotalRows ?? 0,
            Message = upload.StatusMessage,
            PhaseStartedAt = upload.PhaseStartedAt,
            StartedAt = upload.StartedAt,
            RecordsPerSecond = Math.Round(recordsPerSecond, 1),
            EstimatedSecondsRemaining = estimatedSecondsRemaining,
            IsComplete = upload.Status is "Completed" or "Failed" or "Cancelled"
        };

        return Ok(new { success = true, data = progress });
    }

    [HttpPost]
    public async Task<IActionResult> Cancel(Guid id, CancellationToken cancellationToken)
    {
        var userName = User.Identity?.Name ?? "Unknown";

        // Check if user can manage this upload (owner, type-specific admin, or site admin)
        var upload = await _uploadRepository.GetByIdAsync(id, cancellationToken);
        if (upload == null)
        {
            return NotFound();
        }

        if (!CanManageUpload(upload, userName))
        {
            return Forbid();
        }

        _logger.LogInformation("User {User} cancelling upload {UploadId}", userName, id);

        var result = await _uploadService.CancelUploadAsync(id, cancellationToken);
        if (!result)
        {
            TempData["Error"] = "Unable to cancel. The upload may already be completed or failed.";
            return RedirectToAction("Details", "Status", new { id });
        }

        TempData["Success"] = "Upload cancelled successfully.";
        return RedirectToAction("Index", "Status");
    }

    /// <summary>
    /// API endpoint for cancelling uploads (returns JSON for programmatic access).
    /// </summary>
    [HttpPost("{id:guid}/cancel")]
    public async Task<IActionResult> CancelApi(Guid id, CancellationToken cancellationToken)
    {
        var userName = User.Identity?.Name ?? "Unknown";

        var upload = await _uploadRepository.GetByIdAsync(id, cancellationToken);
        if (upload == null)
        {
            return NotFound(new { success = false, error = "Upload not found." });
        }

        if (!CanManageUpload(upload, userName))
        {
            return Forbid();
        }

        var result = await _uploadService.CancelUploadAsync(id, cancellationToken);
        if (!result)
        {
            return BadRequest(new { success = false, error = "Unable to cancel upload. It may already be completed or failed." });
        }

        return Ok(new { success = true, message = "Upload cancelled." });
    }

    #region Chunked Upload Endpoints

    /// <summary>
    /// Gets chunked upload settings for the client.
    /// </summary>
    [HttpGet]
    public IActionResult ChunkedSettings()
    {
        var settings = _appSettings.ChunkedUpload;
        return Ok(new
        {
            enabled = settings.Enabled,
            chunkSizeBytes = settings.ChunkSizeBytes,
            chunkedThresholdBytes = settings.ChunkedThresholdBytes,
            maxConcurrentChunksPerUpload = settings.MaxConcurrentChunksPerUpload,
            maxChunkRetries = settings.MaxChunkRetries,
            sessionExpirationHours = settings.SessionExpirationHours,
            expirationWarningMinutes = settings.ExpirationWarningMinutes,
            enableHashVerificationByDefault = settings.EnableHashVerificationByDefault
        });
    }

    /// <summary>
    /// Initializes a chunked upload session.
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> InitChunked([FromBody] InitChunkedRequest request, CancellationToken cancellationToken)
    {
        var userName = User.Identity?.Name ?? "Unknown";
        var sourceIp = HttpContext.Connection.RemoteIpAddress?.ToString();

        if (_appSettings.Logging.EnableUploadDiagnostics)
        {
            _logger.LogInformation(
                "[UPLOAD-DIAG] InitChunked request: User={User}, FileName={FileName}, " +
                "FileSize={FileSize} ({FileSizeMB:F1} MB), TotalChunks={TotalChunks}",
                userName, request.FileName, request.FileSize,
                request.FileSize / (1024.0 * 1024.0), request.TotalChunks);
        }

        var result = await _chunkedUploadService.InitializeAsync(request, userName, sourceIp, cancellationToken);

        if (!result.Success)
        {
            return BadRequest(new
            {
                success = false,
                errorCode = result.ErrorCode,
                error = result.ErrorMessage
            });
        }

        return Ok(new
        {
            success = true,
            uploadId = result.UploadId,
            expiresAt = result.ExpiresAt
        });
    }

    /// <summary>
    /// Uploads a single chunk.
    /// </summary>
    [HttpPost]
    [DisableRequestSizeLimit]
    public async Task<IActionResult> UploadChunk(CancellationToken cancellationToken)
    {
        // Parse multipart form data
        if (!Request.HasFormContentType)
        {
            return BadRequest(new { success = false, errorCode = "INVALID_CONTENT_TYPE", error = "Expected multipart/form-data." });
        }

        var form = await Request.ReadFormAsync(cancellationToken);

        // Get uploadId
        if (!form.TryGetValue("uploadId", out var uploadIdStr) || !Guid.TryParse(uploadIdStr, out var uploadId))
        {
            return BadRequest(new { success = false, errorCode = "MISSING_UPLOAD_ID", error = "Upload ID is required." });
        }

        // Get chunkIndex
        if (!form.TryGetValue("chunkIndex", out var chunkIndexStr) || !int.TryParse(chunkIndexStr, out var chunkIndex))
        {
            return BadRequest(new { success = false, errorCode = "MISSING_CHUNK_INDEX", error = "Chunk index is required." });
        }

        // Get chunk file
        var chunkFile = form.Files.GetFile("chunk");
        if (chunkFile == null || chunkFile.Length == 0)
        {
            return BadRequest(new { success = false, errorCode = "MISSING_CHUNK_DATA", error = "Chunk data is required." });
        }

        await using var chunkStream = chunkFile.OpenReadStream();
        var result = await _chunkedUploadService.ReceiveChunkAsync(uploadId, chunkIndex, chunkStream, cancellationToken);

        if (!result.Success)
        {
            return BadRequest(new
            {
                success = false,
                errorCode = result.ErrorCode,
                error = result.ErrorMessage
            });
        }

        return Ok(new
        {
            success = true,
            uploadId = result.UploadId,
            chunkIndex = result.ChunkIndex,
            bytesReceived = result.BytesReceived,
            chunksReceived = result.ChunksReceived,
            totalChunks = result.TotalChunks,
            percentComplete = result.PercentComplete
        });
    }

    /// <summary>
    /// Gets the status of a chunked upload (for resume support).
    /// </summary>
    [HttpGet("ChunkStatus/{uploadId:guid}")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> ChunkStatus(Guid uploadId, CancellationToken cancellationToken)
    {
        var result = await _chunkedUploadService.GetStatusAsync(uploadId, cancellationToken);

        if (!result.Success)
        {
            return NotFound(new
            {
                success = false,
                errorCode = result.ErrorCode,
                error = result.ErrorMessage
            });
        }

        return Ok(new
        {
            success = true,
            uploadId = result.UploadId,
            fileName = result.FileName,
            fileSize = result.FileSize,
            totalChunks = result.TotalChunks,
            receivedChunks = result.ReceivedChunks,
            missingChunks = result.MissingChunks,
            percentComplete = result.PercentComplete,
            createdAt = result.CreatedAt,
            expiresAt = result.ExpiresAt,
            canResume = result.CanResume
        });
    }

    /// <summary>
    /// Finalizes a chunked upload by assembling chunks and queuing for processing.
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> FinalizeChunked([FromBody] FinalizeChunkedRequest request, CancellationToken cancellationToken)
    {
        if (_appSettings.Logging.EnableUploadDiagnostics)
        {
            _logger.LogInformation(
                "[UPLOAD-DIAG] FinalizeChunked request: UploadId={UploadId}, VerifyHash={VerifyHash}",
                request.UploadId, request.VerifyHash);
        }

        var result = await _chunkedUploadService.FinalizeAsync(request.UploadId, request.VerifyHash, cancellationToken);

        if (!result.Success)
        {
            return BadRequest(new
            {
                success = false,
                errorCode = result.ErrorCode,
                error = result.ErrorMessage,
                missingChunks = result.MissingChunks
            });
        }

        return Ok(new
        {
            success = true,
            uploadId = result.UploadId,
            message = result.Message,
            assembledSize = result.AssembledSize,
            queuePosition = result.QueuePosition
        });
    }

    /// <summary>
    /// Cancels and cleans up a chunked upload.
    /// </summary>
    [HttpDelete("{uploadId:guid}")]
    public async Task<IActionResult> CancelChunkedUpload(Guid uploadId, CancellationToken cancellationToken)
    {
        var userName = User.Identity?.Name ?? "Unknown";

        // Get session to verify ownership
        var status = await _chunkedUploadService.GetStatusAsync(uploadId, cancellationToken);
        if (!status.Success)
        {
            return NotFound(new { success = false, error = "Chunked upload not found." });
        }

        // TODO: Add ownership verification if needed

        var (success, bytesFreed) = await _chunkedUploadService.CancelAsync(uploadId, cancellationToken);

        if (!success)
        {
            return BadRequest(new { success = false, error = "Failed to cancel chunked upload." });
        }

        _logger.LogInformation("User {User} cancelled chunked upload {UploadId}, freed {Bytes} bytes",
            userName, uploadId, bytesFreed);

        return Ok(new
        {
            success = true,
            message = "Chunked upload cancelled and temporary files cleaned up.",
            bytesFreed
        });
    }

    #endregion
}
