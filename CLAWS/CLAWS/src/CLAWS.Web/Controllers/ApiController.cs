using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using CLAWS.Core.Configuration;
using CLAWS.Core.Models;
using CLAWS.Core.Services;
using CLAWS.Data.Repositories;
using CLAWS.Web.Filters;
using CLAWS.Web.Services;

namespace CLAWS.Web.Controllers;

/// <summary>
/// REST API controller for upload operations.
/// Uses API key authentication for machine-to-machine communication.
///
/// Authorization Model:
/// - Most endpoints require a valid API key (enforced by ApiKeyAuthFilter)
/// - Health endpoints use [AllowAnonymous] for monitoring tools
/// - API keys are scoped to the application, not to specific roles
/// - Interactive users should use UploadController (web UI) which enforces role-based access
///
/// Future enhancements (see authorization-review-2026-01-06.md Phase 5):
/// - Add scope field to API keys for granular permissions
/// - Limit API operations based on key creator's roles
/// </summary>
[Route("api/v1")]
[ApiController]
[ServiceFilter(typeof(ApiKeyAuthFilter))]
public class ApiController : ControllerBase
{
    private readonly ILogger<ApiController> _logger;
    private readonly IUploadService _uploadService;
    private readonly IUploadRepository _uploadRepository;
    private readonly IDiskSpaceService _diskSpaceService;
    private readonly IStreamingUploadHelper _streamingUploadHelper;
    private readonly AppSettings _appSettings;

    public ApiController(
        ILogger<ApiController> logger,
        IUploadService uploadService,
        IUploadRepository uploadRepository,
        IDiskSpaceService diskSpaceService,
        IStreamingUploadHelper streamingUploadHelper,
        AppSettings appSettings)
    {
        _logger = logger;
        _uploadService = uploadService;
        _uploadRepository = uploadRepository;
        _diskSpaceService = diskSpaceService;
        _streamingUploadHelper = streamingUploadHelper;
        _appSettings = appSettings;
    }

    /// <summary>
    /// Health check endpoint (no authentication required).
    /// </summary>
    [HttpGet("health")]
    [AllowAnonymous]
    public IActionResult Health()
    {
        return Ok(ApiResponse<HealthCheckData>.Ok(new HealthCheckData
        {
            Status = "healthy",
            Version = typeof(Program).Assembly.GetName().Version?.ToString() ?? "1.0.0"
        }));
    }

    /// <summary>
    /// Readiness check endpoint (no authentication required).
    /// </summary>
    [HttpGet("health/ready")]
    [AllowAnonymous]
    public IActionResult Ready()
    {
        var checks = new Dictionary<string, HealthCheckComponent>();

        // Check database
        if (_appSettings.SqlServer.IsConfigured)
        {
            checks["database"] = new HealthCheckComponent { Status = "healthy" };
        }
        else
        {
            checks["database"] = new HealthCheckComponent
            {
                Status = "unhealthy",
                Details = "Database not configured"
            };
        }

        // Check disk space
        var diskStatus = _diskSpaceService.GetDiskSpaceStatus(
            _appSettings.Storage.ImportBasePath,
            _appSettings.UploadLimits.MinFreeDiskSpaceBytes);

        if (diskStatus.IsCritical)
        {
            checks["diskSpace"] = new HealthCheckComponent
            {
                Status = "unhealthy",
                Details = new { free = diskStatus.FreeFormatted, required = diskStatus.MinimumFreeBytes }
            };
        }
        else if (diskStatus.IsWarning)
        {
            checks["diskSpace"] = new HealthCheckComponent
            {
                Status = "degraded",
                Details = new { free = diskStatus.FreeFormatted }
            };
        }
        else
        {
            checks["diskSpace"] = new HealthCheckComponent { Status = "healthy" };
        }

        var overallStatus = checks.Values.All(c => c.Status == "healthy") ? "healthy"
            : checks.Values.Any(c => c.Status == "unhealthy") ? "unhealthy"
            : "degraded";

        var statusCode = overallStatus == "healthy" ? 200 : 503;

        return StatusCode(statusCode, new ApiResponse<HealthCheckData>
        {
            Success = overallStatus != "unhealthy",
            Data = new HealthCheckData
            {
                Status = overallStatus,
                Version = typeof(Program).Assembly.GetName().Version?.ToString() ?? "1.0.0",
                Checks = checks
            }
        });
    }

    /// <summary>
    /// Upload a ZIP file using streaming (writes directly to storage, no temp buffering).
    /// </summary>
    /// <remarks>
    /// Upload a ZIP file containing an SQLite database for import. The file is streamed
    /// directly to disk without buffering, allowing uploads up to 3 GB.
    ///
    /// The ZIP file must contain exactly one SQLite database file with the correct schema.
    ///
    /// **Form Fields:**
    /// - `file` (required): The ZIP file to upload
    /// - `autoProcessingOverride` (optional): Override auto-processing behavior for this upload.
    ///   Valid values: `ValidateOnly`, `ValidateAndMerge`, `Manual`. If not specified, uses global settings.
    /// </remarks>
    /// <response code="201">File uploaded and queued for import</response>
    /// <response code="400">Validation failed (invalid file, schema error, etc.)</response>
    /// <response code="401">Missing or invalid API key</response>
    /// <response code="503">Insufficient disk space</response>
    [HttpPost("upload")]
    [DisableRequestSizeLimit] // Uses Kestrel's MaxRequestBodySize from AppSettings.UploadLimits.MaxUploadSizeBytes
    [DisableFormValueModelBinding]
    [ProducesResponseType(typeof(ApiResponse<UploadResponseData>), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> Upload(CancellationToken cancellationToken)
    {
        // Check disk space before accepting upload
        // Use a conservative estimate since we don't know actual size yet
        var estimatedSize = Request.ContentLength ?? _appSettings.UploadLimits.MaxUploadSizeBytes;
        if (!_diskSpaceService.HasSufficientSpace(
            _appSettings.Storage.ImportBasePath,
            _appSettings.UploadLimits.MinFreeDiskSpaceBytes + estimatedSize * 2))
        {
            return BadRequest(ApiResponse.Fail(
                "INSUFFICIENT_DISK_SPACE",
                "Insufficient disk space. Please try again later."));
        }

        // Generate upload ID upfront for streaming
        var uploadId = Guid.NewGuid();

        // Stream file directly to destination
        var streamResult = await _streamingUploadHelper.StreamToFileAsync(
            Request,
            uploadId,
            _appSettings.UploadLimits.MaxUploadSizeBytes,
            cancellationToken);

        if (!streamResult.Success)
        {
            return BadRequest(ApiResponse.Fail(
                streamResult.ErrorCode ?? "UPLOAD_FAILED",
                streamResult.ErrorMessage ?? "Upload failed."));
        }

        // Extract autoProcessingOverride from form fields if provided
        string? autoProcessingOverride = null;
        if (streamResult.FormFields.TryGetValue("autoProcessingOverride", out var overrideValue) &&
            !string.IsNullOrWhiteSpace(overrideValue))
        {
            // Validate the override value
            var validValues = new[] { "ValidateOnly", "ValidateAndMerge", "Manual" };
            if (!validValues.Contains(overrideValue, StringComparer.OrdinalIgnoreCase))
            {
                // Clean up the uploaded file since we're rejecting the request
                if (System.IO.File.Exists(streamResult.FilePath))
                {
                    try { System.IO.File.Delete(streamResult.FilePath); }
                    catch { /* Best effort cleanup */ }
                }

                return BadRequest(ApiResponse.Fail(
                    "INVALID_PROCESSING_OVERRIDE",
                    $"Invalid autoProcessingOverride value '{overrideValue}'. Valid values are: ValidateOnly, ValidateAndMerge, Manual."));
            }

            // Normalize to proper casing
            autoProcessingOverride = validValues.First(v => v.Equals(overrideValue, StringComparison.OrdinalIgnoreCase));
        }

        // Process the streamed file
        var userName = HttpContext.Items["ApiKeyUser"]?.ToString() ?? "API";
        var sourceIp = HttpContext.Connection.RemoteIpAddress?.ToString();

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
            return BadRequest(ApiResponse<UploadResponseData>.Fail(
                result.ErrorCode ?? "ERROR",
                result.ErrorMessage ?? "An error occurred.",
                new { uploadId = result.UploadId }));
        }

        return StatusCode(201, ApiResponse<UploadResponseData>.Ok(new UploadResponseData
        {
            UploadId = result.UploadId!.Value,
            Status = "Queued",
            Message = "File validated successfully. Import queued.",
            QueuePosition = result.QueuePosition
        }));
    }

    /// <summary>
    /// Get upload status.
    /// </summary>
    [HttpGet("upload/{uploadId:guid}/status")]
    public async Task<IActionResult> GetStatus(Guid uploadId, CancellationToken cancellationToken)
    {
        var status = await _uploadService.GetStatusAsync(uploadId, cancellationToken);
        if (status == null)
        {
            return NotFound(ApiResponse.Fail("NOT_FOUND", "Upload not found."));
        }

        return Ok(ApiResponse<UploadStatusData>.Ok(status));
    }

    /// <summary>
    /// Get upload logs.
    /// </summary>
    [HttpGet("upload/{uploadId:guid}/logs")]
    public async Task<IActionResult> GetLogs(Guid uploadId, CancellationToken cancellationToken)
    {
        // TODO: Implement log retrieval
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null)
        {
            return NotFound(ApiResponse.Fail("NOT_FOUND", "Upload not found."));
        }

        return Ok(ApiResponse<object>.Ok(new
        {
            uploadId,
            logs = new List<object>() // Placeholder
        }));
    }

    /// <summary>
    /// Cancel or delete an upload.
    /// </summary>
    [HttpDelete("upload/{uploadId:guid}")]
    public async Task<IActionResult> DeleteUpload(Guid uploadId, CancellationToken cancellationToken)
    {
        var result = await _uploadService.CancelUploadAsync(uploadId, cancellationToken);
        if (!result)
        {
            var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
            if (upload == null)
            {
                return NotFound(ApiResponse.Fail("NOT_FOUND", "Upload not found."));
            }
            return BadRequest(ApiResponse.Fail("CANNOT_CANCEL", "Cannot cancel this upload. It may already be completed or in progress."));
        }

        return Ok(ApiResponse.Ok());
    }

    /// <summary>
    /// List uploads.
    /// </summary>
    [HttpGet("uploads")]
    public async Task<IActionResult> ListUploads(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? status = null,
        CancellationToken cancellationToken = default)
    {
        var skip = (page - 1) * pageSize;
        var uploads = await _uploadRepository.GetAllAsync(skip, pageSize, status, cancellationToken);
        var total = await _uploadRepository.GetCountAsync(status, null, cancellationToken);

        var items = uploads.Select(u => new UploadStatusData
        {
            UploadId = u.UploadId,
            OriginalFilename = u.OriginalFilename,
            FileSizeBytes = u.FileSizeBytes,
            Status = u.Status,
            StatusMessage = u.StatusMessage,
            UploadedAt = u.UploadedAt,
            UploadedBy = u.UploadedBy
        }).ToList();

        return Ok(ApiResponse<object>.Ok(new
        {
            items,
            page,
            pageSize,
            totalPages = (int)Math.Ceiling(total / (double)pageSize),
            totalItems = total
        }));
    }
}
