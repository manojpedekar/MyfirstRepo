using Hangfire;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Core.Services;
using CLAWS.Data.Repositories;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for deleting uploads and their associated files/data.
/// </summary>
public interface IUploadDeletionJob
{
    /// <summary>
    /// Deletes an upload and all associated files and database data with progress reporting.
    /// </summary>
    [JobDisplayName("Delete Upload: {0}")]
    [AutomaticRetry(Attempts = 0)]
    [Queue("deletion")]
    Task DeleteUploadAsync(Guid uploadId, string initiatedBy, CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of upload deletion job with progress reporting.
/// </summary>
public class UploadDeletionJob : IUploadDeletionJob
{
    private readonly ILogger<UploadDeletionJob> _logger;
    private readonly IUploadRepository _uploadRepository;
    private readonly IMigrationService _migrationService;
    private readonly StorageSettings _storageSettings;
    private readonly IBackgroundJobClient _backgroundJobClient;
    private readonly IHubNotifier? _hubNotifier;

    public UploadDeletionJob(
        ILogger<UploadDeletionJob> logger,
        IUploadRepository uploadRepository,
        IMigrationService migrationService,
        StorageSettings storageSettings,
        IBackgroundJobClient backgroundJobClient,
        IHubNotifier? hubNotifier = null)
    {
        _logger = logger;
        _uploadRepository = uploadRepository;
        _migrationService = migrationService;
        _storageSettings = storageSettings;
        _backgroundJobClient = backgroundJobClient;
        _hubNotifier = hubNotifier;
    }

    /// <inheritdoc/>
    public async Task DeleteUploadAsync(Guid uploadId, string initiatedBy, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting upload deletion for {UploadId} initiated by {User}", uploadId, initiatedBy);

        await SendProgressAsync(uploadId, "Starting", "", 0, "Initializing deletion...");

        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null)
        {
            await SendProgressAsync(uploadId, "Failed", "", 0, "Upload not found");
            _logger.LogWarning("Upload {UploadId} not found for deletion", uploadId);
            return;
        }

        var filesDeleted = 0;

        try
        {
            // Step 1: Cancel Hangfire job if exists and still pending/processing
            await SendProgressAsync(uploadId, "Cleaning", "", 10, "Cancelling any pending jobs...");

            if (!string.IsNullOrEmpty(upload.HangfireJobId) &&
                upload.Status is "Pending" or "Processing" or "Queued" or "Importing")
            {
                try
                {
                    _backgroundJobClient.Delete(upload.HangfireJobId);
                    _logger.LogDebug("Cancelled Hangfire job {JobId}", upload.HangfireJobId);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to delete Hangfire job {JobId}", upload.HangfireJobId);
                }
            }

            // Step 2: Clean up extraction folder
            await SendProgressAsync(uploadId, "Cleaning", "Extraction folder", 20, "Cleaning extraction folder...");

            var extractionFolder = Path.Combine(_storageSettings.GetExtractionPath(), uploadId.ToString());
            if (Directory.Exists(extractionFolder))
            {
                try
                {
                    Directory.Delete(extractionFolder, true);
                    filesDeleted++;
                    _logger.LogDebug("Deleted extraction folder: {Path}", extractionFolder);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to delete extraction folder: {Path}", extractionFolder);
                }
            }

            // Step 3: Clean up upload file
            await SendProgressAsync(uploadId, "Cleaning", "Upload file", 30, "Cleaning upload file...");

            if (!string.IsNullOrEmpty(upload.FilePath) && File.Exists(upload.FilePath))
            {
                try
                {
                    File.Delete(upload.FilePath);
                    filesDeleted++;
                    _logger.LogDebug("Deleted file: {Path}", upload.FilePath);

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

            // Step 4: Clean up completed folder files
            await SendProgressAsync(uploadId, "Cleaning", "Completed files", 40, "Cleaning completed folder...");

            var completedPath = _storageSettings.GetCompletedPath();
            foreach (var file in Directory.GetFiles(completedPath, $"{uploadId}_*"))
            {
                try
                {
                    File.Delete(file);
                    filesDeleted++;
                    _logger.LogDebug("Deleted completed file: {Path}", file);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to delete completed file: {Path}", file);
                }
            }

            // Step 5: Clean up errors folder files
            await SendProgressAsync(uploadId, "Cleaning", "Error files", 50, "Cleaning errors folder...");

            var errorsPath = _storageSettings.GetErrorsPath();
            foreach (var file in Directory.GetFiles(errorsPath, $"{uploadId}_*"))
            {
                try
                {
                    File.Delete(file);
                    filesDeleted++;
                    _logger.LogDebug("Deleted error file: {Path}", file);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to delete error file: {Path}", file);
                }
            }

            // Step 6: Clean up uploads folder ZIP
            await SendProgressAsync(uploadId, "Cleaning", "Upload ZIP", 60, "Cleaning upload ZIP...");

            var uploadZipPath = Path.Combine(_storageSettings.GetUploadPath(), $"{uploadId}.zip");
            if (File.Exists(uploadZipPath))
            {
                try
                {
                    File.Delete(uploadZipPath);
                    filesDeleted++;
                    _logger.LogDebug("Deleted upload ZIP: {Path}", uploadZipPath);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to delete upload ZIP: {Path}", uploadZipPath);
                }
            }

            // Step 7: Clean up imported data from staging schema (most time-consuming)
            await SendProgressAsync(uploadId, "Cleaning", "Staging data", 70, "Cleaning staging database data...");

            try
            {
                var (cleanupSuccess, cleanupMessage) = await _migrationService.CleanupImportDataAsync(
                    uploadId, CancellationToken.None);

                if (cleanupSuccess)
                {
                    _logger.LogDebug("Cleaned up import data for upload {UploadId}: {Message}",
                        uploadId, cleanupMessage);
                }
                else
                {
                    _logger.LogWarning("Import data cleanup had issues for upload {UploadId}: {Message}",
                        uploadId, cleanupMessage);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to cleanup import data for upload {UploadId}", uploadId);
            }

            // Step 8: Delete the database record
            await SendProgressAsync(uploadId, "Cleaning", "Database record", 90, "Deleting upload record...");

            await _uploadRepository.DeleteAsync(uploadId, CancellationToken.None);

            await SendProgressAsync(uploadId, "Completed", "", 100,
                $"Successfully deleted upload. {filesDeleted} files/folders removed.");

            _logger.LogInformation("Upload {UploadId} deleted. {FilesDeleted} files/folders removed.",
                uploadId, filesDeleted);
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("Upload deletion cancelled for {UploadId}", uploadId);
            await SendProgressAsync(uploadId, "Failed", "", 0, "Deletion cancelled");
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting upload {UploadId}", uploadId);
            await SendProgressAsync(uploadId, "Failed", "", 0, $"Error: {ex.Message}");
            throw;
        }
    }

    private async Task SendProgressAsync(Guid id, string phase, string currentTable, int percent, string message)
    {
        if (_hubNotifier != null)
        {
            await _hubNotifier.SendProgressAsync(id, phase, currentTable, percent, message);
        }
    }
}
