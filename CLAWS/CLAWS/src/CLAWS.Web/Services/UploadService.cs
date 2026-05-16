using Hangfire;
using CLAWS.Core.Configuration;
using CLAWS.Core.Models;
using CLAWS.Core.Services;
using CLAWS.Data.Entities;
using CLAWS.Data.Repositories;
using CLAWS.Jobs;

namespace CLAWS.Web.Services;

/// <summary>
/// Service for handling file uploads.
/// </summary>
public interface IUploadService
{
    /// <summary>
    /// Processes an uploaded file from a stream (legacy - buffers to temp first).
    /// </summary>
    Task<UploadResult> ProcessUploadAsync(
        Stream fileStream,
        string fileName,
        long fileSize,
        string userName,
        string? sourceIp,
        CancellationToken cancellationToken);

    /// <summary>
    /// Processes an upload that was already streamed directly to disk.
    /// This is the preferred method for large files as it avoids double-copying.
    /// </summary>
    /// <param name="uploadId">The pre-generated upload ID.</param>
    /// <param name="savedFilePath">Path where the file was already saved.</param>
    /// <param name="fileName">Original filename from the upload.</param>
    /// <param name="fileSize">Size of the uploaded file in bytes.</param>
    /// <param name="userName">User who uploaded the file.</param>
    /// <param name="sourceIp">Source IP address.</param>
    /// <param name="autoProcessingOverride">Optional override for auto-processing behavior.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task<UploadResult> ProcessStreamedUploadAsync(
        Guid uploadId,
        string savedFilePath,
        string fileName,
        long fileSize,
        string userName,
        string? sourceIp,
        string? autoProcessingOverride,
        CancellationToken cancellationToken);

    /// <summary>
    /// Gets the status of an upload.
    /// </summary>
    Task<UploadStatusData?> GetStatusAsync(Guid uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Cancels a pending upload.
    /// </summary>
    Task<bool> CancelUploadAsync(Guid uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Deletes an upload and its associated files.
    /// </summary>
    Task<bool> DeleteUploadAsync(Guid uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Restarts a failed or cancelled upload by re-queuing it for processing.
    /// </summary>
    /// <param name="uploadId">The upload ID to restart.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Result indicating success or failure with error details.</returns>
    Task<UploadResult> RestartUploadAsync(Guid uploadId, CancellationToken cancellationToken);
}

/// <summary>
/// Result of an upload operation.
/// </summary>
public class UploadResult
{
    public bool Success { get; set; }
    public Guid? UploadId { get; set; }
    public string? ErrorCode { get; set; }
    public string? ErrorMessage { get; set; }
    public int? QueuePosition { get; set; }
}

/// <summary>
/// Implementation of upload service.
/// Handles file uploads by saving them to disk and queuing them for processing.
/// Actual extraction, validation, and import happens in the background via UploadProcessingJob.
/// </summary>
public class UploadService : IUploadService
{
    private readonly ILogger<UploadService> _logger;
    private readonly IUploadRepository _uploadRepository;
    private readonly IDiskSpaceService _diskSpaceService;
    private readonly IBackgroundJobClient _backgroundJobClient;
    private readonly IMigrationService _migrationService;
    private readonly IAppLogService _appLogService;
    private readonly StorageSettings _storageSettings;
    private readonly UploadLimitSettings _uploadLimits;
    private readonly SqlServerSettings _sqlSettings;

    public UploadService(
        ILogger<UploadService> logger,
        IUploadRepository uploadRepository,
        IDiskSpaceService diskSpaceService,
        IBackgroundJobClient backgroundJobClient,
        IMigrationService migrationService,
        IAppLogService appLogService,
        StorageSettings storageSettings,
        UploadLimitSettings uploadLimits,
        SqlServerSettings sqlSettings)
    {
        _logger = logger;
        _uploadRepository = uploadRepository;
        _diskSpaceService = diskSpaceService;
        _backgroundJobClient = backgroundJobClient;
        _migrationService = migrationService;
        _appLogService = appLogService;
        _storageSettings = storageSettings;
        _uploadLimits = uploadLimits;
        _sqlSettings = sqlSettings;
    }

    /// <inheritdoc/>
    /// <remarks>
    /// This method saves the file to disk and queues it for background processing.
    /// Extraction, validation, and import happen in the UploadProcessingJob.
    /// </remarks>
    public async Task<UploadResult> ProcessUploadAsync(
        Stream fileStream,
        string fileName,
        long fileSize,
        string userName,
        string? sourceIp,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Processing upload: {FileName} ({Size:N0} bytes) from {User}",
            fileName, fileSize, userName);

        // Check database configuration
        if (!_sqlSettings.IsConfigured)
        {
            return new UploadResult
            {
                Success = false,
                ErrorCode = "DB_NOT_CONFIGURED",
                ErrorMessage = "Database connection required. Please configure SQL Server connection in Settings."
            };
        }

        // Check file size
        if (fileSize > _uploadLimits.MaxUploadSizeBytes)
        {
            return new UploadResult
            {
                Success = false,
                ErrorCode = "FILE_TOO_LARGE",
                ErrorMessage = $"File size exceeds maximum allowed ({_uploadLimits.MaxUploadSizeBytes / (1024 * 1024 * 1024.0):F1} GB)."
            };
        }

        // Check disk space (need space for ZIP + extracted)
        if (!_diskSpaceService.HasSufficientSpace(
            _storageSettings.ImportBasePath,
            _uploadLimits.MinFreeDiskSpaceBytes + fileSize * 2))
        {
            return new UploadResult
            {
                Success = false,
                ErrorCode = "INSUFFICIENT_DISK_SPACE",
                ErrorMessage = "Insufficient disk space. Please try again later."
            };
        }

        var uploadId = Guid.NewGuid();
        var uploadPath = _storageSettings.GetUploadPath();
        var savedPath = Path.Combine(uploadPath, $"{uploadId}.zip");

        try
        {
            // Save file to disk
            await using (var fileOut = File.Create(savedPath))
            {
                await fileStream.CopyToAsync(fileOut, cancellationToken);
            }

            // Create upload record with "Pending" status
            var upload = new Upload
            {
                UploadId = uploadId,
                OriginalFilename = fileName,
                FileSizeBytes = fileSize,
                UploadedBy = userName,
                SourceIP = sourceIp,
                FilePath = savedPath,
                Status = "Pending",
                StatusMessage = "Queued for processing..."
            };

            await _uploadRepository.CreateAsync(upload, cancellationToken);

            // Log upload start
            await _appLogService.LogUploadStartAsync(uploadId, fileName, fileSize, userName, sourceIp, cancellationToken);
            await _appLogService.LogUploadCompleteAsync(uploadId, fileName, userName, cancellationToken);

            // Queue processing job (extraction, validation, and import happen here)
            var jobId = _backgroundJobClient.Enqueue<IUploadProcessingJob>(
                job => job.ExecuteAsync(uploadId, savedPath, CancellationToken.None));

            upload.HangfireJobId = jobId;
            await _uploadRepository.UpdateAsync(upload, cancellationToken);

            // Get queue position
            var queuePosition = await GetQueuePositionAsync(uploadId, cancellationToken);

            _logger.LogInformation("Upload {UploadId} saved and queued for processing (position {Position})",
                uploadId, queuePosition);

            return new UploadResult
            {
                Success = true,
                UploadId = uploadId,
                QueuePosition = queuePosition
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving upload {UploadId}", uploadId);

            // Clean up file on error
            if (File.Exists(savedPath))
            {
                try { File.Delete(savedPath); }
                catch { /* Best effort */ }
            }

            // Log upload failure
            await _appLogService.LogUploadFailedAsync(uploadId, fileName, ex.Message, userName, CancellationToken.None);

            return new UploadResult
            {
                Success = false,
                UploadId = uploadId,
                ErrorCode = "UPLOAD_ERROR",
                ErrorMessage = "An error occurred while saving the upload."
            };
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    /// This method creates the upload record and queues it for background processing.
    /// The file has already been streamed directly to disk.
    /// Extraction, validation, and import happen in the UploadProcessingJob.
    /// </remarks>
    public async Task<UploadResult> ProcessStreamedUploadAsync(
        Guid uploadId,
        string savedFilePath,
        string fileName,
        long fileSize,
        string userName,
        string? sourceIp,
        string? autoProcessingOverride,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation(
            "Processing streamed upload {UploadId}: {FileName} ({Size:N0} bytes) from {User}, AutoProcessingOverride={Override}",
            uploadId, fileName, fileSize, userName, autoProcessingOverride ?? "default");

        // Check database configuration
        if (!_sqlSettings.IsConfigured)
        {
            // Clean up the streamed file
            if (File.Exists(savedFilePath))
            {
                try { File.Delete(savedFilePath); }
                catch { /* Best effort */ }
            }

            return new UploadResult
            {
                Success = false,
                ErrorCode = "DB_NOT_CONFIGURED",
                ErrorMessage = "Database connection required. Please configure SQL Server connection in Settings."
            };
        }

        try
        {
            // Create upload record with "Pending" status
            var upload = new Upload
            {
                UploadId = uploadId,
                OriginalFilename = fileName,
                FileSizeBytes = fileSize,
                UploadedBy = userName,
                SourceIP = sourceIp,
                FilePath = savedFilePath,
                Status = "Pending",
                StatusMessage = "Queued for processing...",
                AutoProcessingOverride = autoProcessingOverride
            };

            await _uploadRepository.CreateAsync(upload, cancellationToken);

            // Log upload start and complete (file was already streamed to disk)
            await _appLogService.LogUploadStartAsync(uploadId, fileName, fileSize, userName, sourceIp, cancellationToken);
            await _appLogService.LogUploadCompleteAsync(uploadId, fileName, userName, cancellationToken);

            // Queue processing job (extraction, validation, and import happen here)
            var jobId = _backgroundJobClient.Enqueue<IUploadProcessingJob>(
                job => job.ExecuteAsync(uploadId, savedFilePath, CancellationToken.None));

            upload.HangfireJobId = jobId;
            await _uploadRepository.UpdateAsync(upload, cancellationToken);

            // Get queue position
            var queuePosition = await GetQueuePositionAsync(uploadId, cancellationToken);

            _logger.LogInformation(
                "Streamed upload {UploadId} saved and queued for processing (position {Position})",
                uploadId, queuePosition);

            return new UploadResult
            {
                Success = true,
                UploadId = uploadId,
                QueuePosition = queuePosition
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing streamed upload {UploadId}", uploadId);

            // Log upload failure
            await _appLogService.LogUploadFailedAsync(uploadId, fileName, ex.Message, userName, CancellationToken.None);

            // Clean up the ZIP file on error
            if (File.Exists(savedFilePath))
            {
                try { File.Delete(savedFilePath); }
                catch { /* Best effort */ }
            }

            return new UploadResult
            {
                Success = false,
                UploadId = uploadId,
                ErrorCode = "UPLOAD_ERROR",
                ErrorMessage = "An error occurred while processing the upload."
            };
        }
    }

    /// <inheritdoc/>
    public async Task<UploadStatusData?> GetStatusAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null) return null;

        return new UploadStatusData
        {
            UploadId = upload.UploadId,
            OriginalFilename = upload.OriginalFilename,
            FileSizeBytes = upload.FileSizeBytes,
            Status = upload.Status,
            StatusMessage = upload.StatusMessage,
            CurrentPhase = upload.CurrentPhase,
            ImportProgress = upload.ImportProgress,
            UploadedAt = upload.UploadedAt,
            StartedAt = upload.StartedAt,
            CompletedAt = upload.CompletedAt,
            UploadedBy = upload.UploadedBy,
            ErrorDetails = upload.ErrorDetails
        };
    }

    /// <inheritdoc/>
    public async Task<bool> CancelUploadAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null) return false;

        // Allow cancellation of pending, processing, and importing uploads
        if (upload.Status is not ("Pending" or "Processing" or "Queued" or "Uploading" or "ValidatingZip" or "ValidatingDatabase" or "Importing"))
        {
            return false;
        }

        var wasImporting = upload.Status == "Importing";
        var wasProcessing = upload.Status is "Processing" or "Importing";

        // Cancel Hangfire job if exists
        if (!string.IsNullOrEmpty(upload.HangfireJobId))
        {
            try
            {
                _backgroundJobClient.Delete(upload.HangfireJobId);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to delete Hangfire job {JobId}", upload.HangfireJobId);
            }
        }

        upload.Status = "Cancelled";
        upload.StatusMessage = wasImporting
            ? "Import cancelled by user. Partially imported data may remain in database."
            : wasProcessing
                ? "Processing cancelled by user."
                : "Upload cancelled by user.";
        upload.CompletedAt = DateTime.UtcNow;
        await _uploadRepository.UpdateAsync(upload, cancellationToken);

        // Clean up files
        if (!string.IsNullOrEmpty(upload.FilePath) && File.Exists(upload.FilePath))
        {
            try
            {
                File.Delete(upload.FilePath);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to delete file: {Path}", upload.FilePath);
            }
        }

        // Clean up extraction folder
        var extractionFolder = Path.Combine(_storageSettings.GetExtractionPath(), uploadId.ToString());
        if (Directory.Exists(extractionFolder))
        {
            try
            {
                Directory.Delete(extractionFolder, true);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to delete extraction folder: {Path}", extractionFolder);
            }
        }

        _logger.LogInformation("Upload {UploadId} cancelled by user (was {Status})", uploadId, upload.Status);
        return true;
    }

    /// <summary>
    /// Gets the queue position for an upload.
    /// </summary>
    private async Task<int> GetQueuePositionAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var pendingUploads = await _uploadRepository.GetAllAsync(0, 100, "Pending", cancellationToken);
        var position = pendingUploads.FindIndex(u => u.UploadId == uploadId) + 1;
        return position > 0 ? position : 1;
    }

    /// <inheritdoc/>
    public async Task<bool> DeleteUploadAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null) return false;

        _logger.LogInformation("Deleting upload {UploadId} ({Filename})", uploadId, upload.OriginalFilename);

        // Cancel Hangfire job if exists and still pending/processing
        if (!string.IsNullOrEmpty(upload.HangfireJobId) && upload.Status is "Pending" or "Processing" or "Queued" or "Importing")
        {
            try
            {
                _backgroundJobClient.Delete(upload.HangfireJobId);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to delete Hangfire job {JobId}", upload.HangfireJobId);
            }
        }

        // Clean up files in various locations
        var filesDeleted = 0;

        // Check extraction folder (for failed validations or in-progress imports)
        var extractionFolder = Path.Combine(_storageSettings.GetExtractionPath(), uploadId.ToString());
        if (Directory.Exists(extractionFolder))
        {
            try
            {
                Directory.Delete(extractionFolder, true);
                filesDeleted++;
                _logger.LogInformation("Deleted extraction folder: {Path}", extractionFolder);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to delete extraction folder: {Path}", extractionFolder);
            }
        }

        // Check if FilePath points to a file that still exists
        if (!string.IsNullOrEmpty(upload.FilePath) && File.Exists(upload.FilePath))
        {
            try
            {
                File.Delete(upload.FilePath);
                filesDeleted++;
                _logger.LogInformation("Deleted file: {Path}", upload.FilePath);

                // Also delete metadata file if exists
                var metaPath = upload.FilePath + ".meta";
                if (File.Exists(metaPath))
                {
                    File.Delete(metaPath);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to delete file: {Path}", upload.FilePath);
            }
        }

        // Check completed folder
        var completedPath = _storageSettings.GetCompletedPath();
        foreach (var file in Directory.GetFiles(completedPath, $"{uploadId}_*"))
        {
            try
            {
                File.Delete(file);
                filesDeleted++;
                _logger.LogInformation("Deleted completed file: {Path}", file);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to delete completed file: {Path}", file);
            }
        }

        // Check errors folder
        var errorsPath = _storageSettings.GetErrorsPath();
        foreach (var file in Directory.GetFiles(errorsPath, $"{uploadId}_*"))
        {
            try
            {
                File.Delete(file);
                filesDeleted++;
                _logger.LogInformation("Deleted error file: {Path}", file);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to delete error file: {Path}", file);
            }
        }

        // Check uploads folder (ZIP file)
        var uploadZipPath = Path.Combine(_storageSettings.GetUploadPath(), $"{uploadId}.zip");
        if (File.Exists(uploadZipPath))
        {
            try
            {
                File.Delete(uploadZipPath);
                filesDeleted++;
                _logger.LogInformation("Deleted upload ZIP: {Path}", uploadZipPath);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to delete upload ZIP: {Path}", uploadZipPath);
            }
        }

        // Clean up imported data from fssimport schema
        // Use CancellationToken.None to ensure cleanup completes even if HTTP request is cancelled
        try
        {
            var (cleanupSuccess, cleanupMessage) = await _migrationService.CleanupImportDataAsync(uploadId, CancellationToken.None);
            if (cleanupSuccess)
            {
                _logger.LogInformation("Cleaned up import data for upload {UploadId}: {Message}", uploadId, cleanupMessage);
            }
            else
            {
                _logger.LogWarning("Import data cleanup had issues for upload {UploadId}: {Message}", uploadId, cleanupMessage);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to cleanup import data for upload {UploadId}", uploadId);
        }

        // Delete the database record
        // Use CancellationToken.None to ensure this completes
        await _uploadRepository.DeleteAsync(uploadId, CancellationToken.None);

        _logger.LogInformation("Upload {UploadId} deleted. {FilesDeleted} files/folders removed.", uploadId, filesDeleted);
        return true;
    }

    /// <inheritdoc/>
    public async Task<UploadResult> RestartUploadAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Attempting to restart upload {UploadId}", uploadId);

        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null)
        {
            return new UploadResult
            {
                Success = false,
                ErrorCode = "NOT_FOUND",
                ErrorMessage = "Upload not found."
            };
        }

        // Only allow restarting failed or cancelled uploads
        if (upload.Status is not ("Failed" or "Cancelled"))
        {
            return new UploadResult
            {
                Success = false,
                UploadId = uploadId,
                ErrorCode = "INVALID_STATUS",
                ErrorMessage = $"Cannot restart upload with status '{upload.Status}'. Only Failed or Cancelled uploads can be restarted."
            };
        }

        // Check database configuration
        if (!_sqlSettings.IsConfigured)
        {
            return new UploadResult
            {
                Success = false,
                ErrorCode = "DB_NOT_CONFIGURED",
                ErrorMessage = "Database connection required. Please configure SQL Server connection in Settings."
            };
        }

        // Determine the file path to use
        string? filePath = null;

        // Check if original FilePath still exists
        if (!string.IsNullOrEmpty(upload.FilePath) && File.Exists(upload.FilePath))
        {
            filePath = upload.FilePath;
        }
        else
        {
            // Check standard upload location
            var uploadZipPath = Path.Combine(_storageSettings.GetUploadPath(), $"{uploadId}.zip");
            if (File.Exists(uploadZipPath))
            {
                filePath = uploadZipPath;
            }
            else
            {
                // Check errors folder
                var errorsPath = _storageSettings.GetErrorsPath();
                var errorFiles = Directory.GetFiles(errorsPath, $"{uploadId}_*");
                if (errorFiles.Length > 0)
                {
                    filePath = errorFiles[0];
                }
            }
        }

        if (string.IsNullOrEmpty(filePath))
        {
            return new UploadResult
            {
                Success = false,
                UploadId = uploadId,
                ErrorCode = "FILE_NOT_FOUND",
                ErrorMessage = "The original upload file could not be found. The file may have been deleted or cleaned up."
            };
        }

        // Check disk space
        var fileInfo = new FileInfo(filePath);
        if (!_diskSpaceService.HasSufficientSpace(
            _storageSettings.ImportBasePath,
            _uploadLimits.MinFreeDiskSpaceBytes + fileInfo.Length * 2))
        {
            return new UploadResult
            {
                Success = false,
                UploadId = uploadId,
                ErrorCode = "INSUFFICIENT_DISK_SPACE",
                ErrorMessage = "Insufficient disk space to restart the import."
            };
        }

        try
        {
            // Clean up any existing extraction folder from previous attempt
            var extractionFolder = Path.Combine(_storageSettings.GetExtractionPath(), uploadId.ToString());
            if (Directory.Exists(extractionFolder))
            {
                try
                {
                    Directory.Delete(extractionFolder, true);
                    _logger.LogInformation("Cleaned up previous extraction folder: {Path}", extractionFolder);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to clean up previous extraction folder: {Path}", extractionFolder);
                }
            }

            // Clean up any partially imported data from previous attempt
            try
            {
                var (cleanupSuccess, cleanupMessage) = await _migrationService.CleanupImportDataAsync(uploadId, cancellationToken);
                if (cleanupSuccess)
                {
                    _logger.LogInformation("Cleaned up previous import data for upload {UploadId}: {Message}", uploadId, cleanupMessage);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to cleanup previous import data for upload {UploadId}", uploadId);
            }

            // Reset upload status
            upload.Status = "Pending";
            upload.StatusMessage = "Requeued for processing...";
            upload.ErrorDetails = null;
            upload.ImportProgress = null;
            upload.CurrentPhase = null;
            upload.StartedAt = null;
            upload.CompletedAt = null;
            upload.RowsProcessed = null;
            upload.TotalRows = null;
            upload.PhaseStartedAt = null;
            upload.FilePath = filePath;

            // Queue new processing job
            var jobId = _backgroundJobClient.Enqueue<IUploadProcessingJob>(
                job => job.ExecuteAsync(uploadId, filePath, CancellationToken.None));

            upload.HangfireJobId = jobId;
            await _uploadRepository.UpdateAsync(upload, cancellationToken);

            // Log the restart
            await _appLogService.LogAsync(
                uploadId,
                "ImportRestart",
                "INFO",
                $"Upload {upload.OriginalFilename} restarted and requeued for processing",
                cancellationToken: cancellationToken);

            // Get queue position
            var queuePosition = await GetQueuePositionAsync(uploadId, cancellationToken);

            _logger.LogInformation(
                "Upload {UploadId} ({Filename}) restarted and queued for processing (position {Position})",
                uploadId, upload.OriginalFilename, queuePosition);

            return new UploadResult
            {
                Success = true,
                UploadId = uploadId,
                QueuePosition = queuePosition
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error restarting upload {UploadId}", uploadId);

            return new UploadResult
            {
                Success = false,
                UploadId = uploadId,
                ErrorCode = "RESTART_ERROR",
                ErrorMessage = $"An error occurred while restarting the upload: {ex.Message}"
            };
        }
    }
}
