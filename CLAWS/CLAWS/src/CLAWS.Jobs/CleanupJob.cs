using Hangfire;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Data.Repositories;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for cleaning up old files.
/// </summary>
public interface ICleanupJob
{
    /// <summary>
    /// Cleans up files in the completed folder.
    /// </summary>
    [JobDisplayName("Cleanup: Completed Files")]
    Task CleanupCompletedAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Cleans up files in the errors folder.
    /// </summary>
    [JobDisplayName("Cleanup: Error Files")]
    Task CleanupErrorsAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Cleans up orphaned folders in the extraction folder.
    /// </summary>
    [JobDisplayName("Cleanup: Extraction Folder")]
    Task CleanupExtractionAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Cleans up old upload records from the database.
    /// </summary>
    [JobDisplayName("Cleanup: Upload Records")]
    Task CleanupUploadRecordsAsync(CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of the cleanup job.
/// </summary>
public class CleanupJob : ICleanupJob
{
    private readonly ILogger<CleanupJob> _logger;
    private readonly StorageSettings _storageSettings;
    private readonly CleanupSettings _cleanupSettings;
    private readonly IUploadRepository _uploadRepository;

    public CleanupJob(
        ILogger<CleanupJob> logger,
        StorageSettings storageSettings,
        CleanupSettings cleanupSettings,
        IUploadRepository uploadRepository)
    {
        _logger = logger;
        _storageSettings = storageSettings;
        _cleanupSettings = cleanupSettings;
        _uploadRepository = uploadRepository;
    }

    /// <inheritdoc/>
    public async Task CleanupCompletedAsync(CancellationToken cancellationToken)
    {
        if (!_cleanupSettings.AutoPruneCompleted)
        {
            _logger.LogInformation("Completed folder pruning is disabled");
            return;
        }

        var completedPath = _storageSettings.GetCompletedPath();
        if (!Directory.Exists(completedPath))
        {
            _logger.LogInformation("Completed folder does not exist: {Path}", completedPath);
            return;
        }

        var cutoffDate = DateTime.UtcNow.AddDays(-_cleanupSettings.CompletedRetentionDays);
        var deletedCount = 0;
        long deletedBytes = 0;

        _logger.LogInformation("Cleaning up completed files older than {CutoffDate}", cutoffDate);

        await Task.Run(() =>
        {
            // Only process primary files (.zip), skip .meta files - they'll be deleted with their parent
            var primaryFiles = Directory.GetFiles(completedPath)
                .Where(f => !f.EndsWith(".meta", StringComparison.OrdinalIgnoreCase))
                .ToList();

            foreach (var file in primaryFiles)
            {
                cancellationToken.ThrowIfCancellationRequested();

                try
                {
                    var fileInfo = new FileInfo(file);
                    if (!fileInfo.Exists)
                    {
                        continue; // File was deleted by another process
                    }

                    if (fileInfo.LastWriteTimeUtc < cutoffDate)
                    {
                        var size = fileInfo.Length;

                        // Clear read-only attribute if set
                        if (fileInfo.IsReadOnly)
                        {
                            fileInfo.IsReadOnly = false;
                        }

                        fileInfo.Delete();
                        deletedCount++;
                        deletedBytes += size;

                        // Also delete metadata file if exists
                        var metaPath = file + ".meta";
                        if (File.Exists(metaPath))
                        {
                            var metaInfo = new FileInfo(metaPath);
                            if (metaInfo.IsReadOnly)
                            {
                                metaInfo.IsReadOnly = false;
                            }
                            metaInfo.Delete();
                        }

                        _logger.LogDebug("Deleted completed file: {File} ({Size:N0} bytes)",
                            Path.GetFileName(file), size);
                    }
                }
                catch (IOException ex) when (ex.HResult == unchecked((int)0x80070020)) // ERROR_SHARING_VIOLATION
                {
                    _logger.LogWarning("File is in use, will retry next cleanup: {File}", Path.GetFileName(file));
                }
                catch (UnauthorizedAccessException ex)
                {
                    _logger.LogWarning(ex, "Access denied deleting file (may be locked by AV or backup): {File}", Path.GetFileName(file));
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to delete file: {File}", file);
                }
            }
        }, cancellationToken);

        _logger.LogInformation("Completed folder cleanup finished. Deleted {Count} files ({Bytes:N0} bytes)",
            deletedCount, deletedBytes);
    }

    /// <inheritdoc/>
    public async Task CleanupErrorsAsync(CancellationToken cancellationToken)
    {
        if (_cleanupSettings.ErrorRetentionDays <= 0)
        {
            _logger.LogInformation("Error folder pruning is disabled (retention = 0)");
            return;
        }

        var errorsPath = _storageSettings.GetErrorsPath();
        if (!Directory.Exists(errorsPath))
        {
            _logger.LogInformation("Errors folder does not exist: {Path}", errorsPath);
            return;
        }

        var cutoffDate = DateTime.UtcNow.AddDays(-_cleanupSettings.ErrorRetentionDays);
        var deletedCount = 0;
        long deletedBytes = 0;

        _logger.LogInformation("Cleaning up error files older than {CutoffDate}", cutoffDate);

        await Task.Run(() =>
        {
            // Only process primary files (.zip), skip .meta files - they'll be deleted with their parent
            var primaryFiles = Directory.GetFiles(errorsPath)
                .Where(f => !f.EndsWith(".meta", StringComparison.OrdinalIgnoreCase))
                .ToList();

            foreach (var file in primaryFiles)
            {
                cancellationToken.ThrowIfCancellationRequested();

                try
                {
                    var fileInfo = new FileInfo(file);
                    if (!fileInfo.Exists)
                    {
                        continue; // File was deleted by another process
                    }

                    if (fileInfo.LastWriteTimeUtc < cutoffDate)
                    {
                        var size = fileInfo.Length;

                        // Clear read-only attribute if set
                        if (fileInfo.IsReadOnly)
                        {
                            fileInfo.IsReadOnly = false;
                        }

                        fileInfo.Delete();
                        deletedCount++;
                        deletedBytes += size;

                        // Also delete metadata file if exists
                        var metaPath = file + ".meta";
                        if (File.Exists(metaPath))
                        {
                            var metaInfo = new FileInfo(metaPath);
                            if (metaInfo.IsReadOnly)
                            {
                                metaInfo.IsReadOnly = false;
                            }
                            metaInfo.Delete();
                        }

                        _logger.LogDebug("Deleted error file: {File} ({Size:N0} bytes)",
                            Path.GetFileName(file), size);
                    }
                }
                catch (IOException ex) when (ex.HResult == unchecked((int)0x80070020)) // ERROR_SHARING_VIOLATION
                {
                    _logger.LogWarning("File is in use, will retry next cleanup: {File}", Path.GetFileName(file));
                }
                catch (UnauthorizedAccessException ex)
                {
                    _logger.LogWarning(ex, "Access denied deleting file (may be locked by AV or backup): {File}", Path.GetFileName(file));
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to delete file: {File}", file);
                }
            }
        }, cancellationToken);

        _logger.LogInformation("Error folder cleanup finished. Deleted {Count} files ({Bytes:N0} bytes)",
            deletedCount, deletedBytes);
    }

    /// <inheritdoc/>
    public async Task CleanupExtractionAsync(CancellationToken cancellationToken)
    {
        if (_cleanupSettings.ExtractionRetentionDays <= 0)
        {
            _logger.LogInformation("Extraction folder pruning is disabled (retention = 0)");
            return;
        }

        var extractionPath = _storageSettings.GetExtractionPath();
        if (!Directory.Exists(extractionPath))
        {
            _logger.LogInformation("Extraction folder does not exist: {Path}", extractionPath);
            return;
        }

        var cutoffDate = DateTime.UtcNow.AddDays(-_cleanupSettings.ExtractionRetentionDays);
        var deletedCount = 0;
        long deletedBytes = 0;

        _logger.LogInformation("Cleaning up extraction folders older than {CutoffDate}", cutoffDate);

        await Task.Run(() =>
        {
            // Clean up subdirectories (each upload creates a GUID subdirectory)
            foreach (var directory in Directory.GetDirectories(extractionPath))
            {
                cancellationToken.ThrowIfCancellationRequested();

                try
                {
                    var dirInfo = new DirectoryInfo(directory);
                    if (!dirInfo.Exists)
                    {
                        continue; // Directory was deleted by another process
                    }

                    if (dirInfo.LastWriteTimeUtc < cutoffDate)
                    {
                        // Calculate size before deletion
                        long dirSize = 0;
                        try
                        {
                            foreach (var file in dirInfo.GetFiles("*", SearchOption.AllDirectories))
                            {
                                dirSize += file.Length;
                            }
                        }
                        catch (DirectoryNotFoundException)
                        {
                            continue; // Directory was deleted while we were iterating
                        }

                        // Clear read-only on all files first
                        try
                        {
                            foreach (var file in dirInfo.GetFiles("*", SearchOption.AllDirectories))
                            {
                                if (file.IsReadOnly)
                                {
                                    file.IsReadOnly = false;
                                }
                            }
                        }
                        catch (DirectoryNotFoundException)
                        {
                            continue;
                        }

                        dirInfo.Delete(true);
                        deletedCount++;
                        deletedBytes += dirSize;

                        _logger.LogDebug("Deleted orphaned extraction folder: {Folder} ({Size:N0} bytes)",
                            dirInfo.Name, dirSize);
                    }
                }
                catch (IOException ex) when (ex.HResult == unchecked((int)0x80070020)) // ERROR_SHARING_VIOLATION
                {
                    _logger.LogWarning("Folder is in use, will retry next cleanup: {Folder}", Path.GetFileName(directory));
                }
                catch (UnauthorizedAccessException ex)
                {
                    _logger.LogWarning(ex, "Access denied deleting folder (may be locked by AV or backup): {Folder}", Path.GetFileName(directory));
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to delete extraction folder: {Folder}", directory);
                }
            }

            // Also clean up any orphaned files directly in extraction folder (shouldn't exist but just in case)
            foreach (var file in Directory.GetFiles(extractionPath))
            {
                cancellationToken.ThrowIfCancellationRequested();

                try
                {
                    var fileInfo = new FileInfo(file);
                    if (!fileInfo.Exists)
                    {
                        continue;
                    }

                    if (fileInfo.LastWriteTimeUtc < cutoffDate)
                    {
                        var size = fileInfo.Length;

                        if (fileInfo.IsReadOnly)
                        {
                            fileInfo.IsReadOnly = false;
                        }

                        fileInfo.Delete();
                        deletedCount++;
                        deletedBytes += size;

                        _logger.LogDebug("Deleted orphaned extraction file: {File} ({Size:N0} bytes)",
                            Path.GetFileName(file), size);
                    }
                }
                catch (IOException ex) when (ex.HResult == unchecked((int)0x80070020))
                {
                    _logger.LogWarning("File is in use, will retry next cleanup: {File}", Path.GetFileName(file));
                }
                catch (UnauthorizedAccessException ex)
                {
                    _logger.LogWarning(ex, "Access denied deleting file (may be locked by AV or backup): {File}", Path.GetFileName(file));
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to delete file: {File}", file);
                }
            }
        }, cancellationToken);

        _logger.LogInformation("Extraction folder cleanup finished. Deleted {Count} items ({Bytes:N0} bytes)",
            deletedCount, deletedBytes);
    }

    /// <inheritdoc/>
    public async Task CleanupUploadRecordsAsync(CancellationToken cancellationToken)
    {
        if (_cleanupSettings.UploadRecordRetentionDays <= 0)
        {
            _logger.LogInformation("Upload record cleanup is disabled (retention = 0)");
            return;
        }

        var cutoffDate = DateTime.UtcNow.AddDays(-_cleanupSettings.UploadRecordRetentionDays);

        _logger.LogInformation("Cleaning up upload records older than {CutoffDate}", cutoffDate);

        try
        {
            var deletedCount = await _uploadRepository.DeleteOldUploadsAsync(cutoffDate, cancellationToken);

            if (deletedCount > 0)
            {
                _logger.LogInformation("Upload record cleanup finished. Deleted {Count} records", deletedCount);
            }
            else
            {
                _logger.LogInformation("Upload record cleanup finished. No records to delete");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to cleanup upload records");
            throw;
        }
    }
}
