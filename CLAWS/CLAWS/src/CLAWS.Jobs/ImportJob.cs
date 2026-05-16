using Hangfire;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Core.Import;
using CLAWS.Core.Models;
using CLAWS.Core.Services;
using CLAWS.Core.Validation;
using CLAWS.Data.Repositories;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for importing SQLite databases to SQL Server.
/// </summary>
public interface IImportJob
{
    /// <summary>
    /// Runs the import job for a specific upload.
    /// </summary>
    [JobDisplayName("Import: {0}")]
    [AutomaticRetry(Attempts = 0)]
    Task ExecuteAsync(Guid uploadId, string sqlitePath, CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of the import job.
/// </summary>
public class ImportJob : IImportJob
{
    private readonly ILogger<ImportJob> _logger;
    private readonly IUploadRepository _uploadRepository;
    private readonly ISqliteImporter _importer;
    private readonly IDatabaseValidator _dbValidator;
    private readonly IAppLogService _appLogService;
    private readonly SqlServerSettings _sqlSettings;
    private readonly StorageSettings _storageSettings;
    private readonly IHubNotifier? _hubNotifier;

    public ImportJob(
        ILogger<ImportJob> logger,
        IUploadRepository uploadRepository,
        ISqliteImporter importer,
        IDatabaseValidator dbValidator,
        IAppLogService appLogService,
        SqlServerSettings sqlSettings,
        StorageSettings storageSettings,
        IHubNotifier? hubNotifier = null)
    {
        _logger = logger;
        _uploadRepository = uploadRepository;
        _importer = importer;
        _dbValidator = dbValidator;
        _appLogService = appLogService;
        _sqlSettings = sqlSettings;
        _storageSettings = storageSettings;
        _hubNotifier = hubNotifier;
    }

    /// <inheritdoc/>
    public async Task ExecuteAsync(Guid uploadId, string sqlitePath, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting import job for upload {UploadId}", uploadId);

        try
        {
            // Update status to importing
            await _uploadRepository.UpdateStatusAsync(
                uploadId, "Importing", "Starting import...", 0, "Initializing",
                cancellationToken);

            await NotifyProgressAsync(uploadId, "Importing", "Initializing", 0, "Starting import...");

            // Log import start
            await _appLogService.LogImportStartAsync(uploadId, cancellationToken);

            // IMPORTANT: Extract InventoryIDs FIRST and create placeholder statistics
            // This ensures we can clean up fssimport data even if import fails mid-way
            _logger.LogInformation("Extracting InventoryIDs from SQLite for early registration...");
            var inventoryIds = await _importer.GetInventoryIdsFromSqliteAsync(sqlitePath, cancellationToken);

            if (inventoryIds.Count > 0)
            {
                // Create placeholder ImportStatistic records to link InventoryIDs to this upload
                // This enables cleanup even if the import fails partway through
                var placeholderStats = inventoryIds.Select(id => new Data.Entities.ImportStatistic
                {
                    UploadId = uploadId,
                    InventoryId = id,
                    TableName = "_InventoryLink", // Placeholder to track the link
                    RecordsImported = 0,
                    DurationMs = 0
                });

                await _uploadRepository.AddImportStatisticsAsync(uploadId, placeholderStats, cancellationToken);
                _logger.LogInformation("Registered {Count} InventoryID(s) for upload {UploadId} before import",
                    inventoryIds.Count, uploadId);
            }

            // Validate database integrity
            var integrityResult = await _dbValidator.RunIntegrityCheckAsync(sqlitePath, cancellationToken);
            if (!integrityResult.IsValid)
            {
                await _appLogService.LogImportFailedAsync(uploadId, integrityResult.ErrorMessage!, null, cancellationToken);
                await FailImportAsync(uploadId, sqlitePath, integrityResult.ErrorMessage!, cancellationToken);
                throw new InvalidOperationException($"Database integrity check failed: {integrityResult.ErrorMessage}");
            }

            // Run the import
            var connectionString = _sqlSettings.BuildConnectionString();

            var statistics = await _importer.ImportAllTablesAsync(
                sqlitePath,
                connectionString,
                uploadId,
                async progress =>
                {
                    await _uploadRepository.UpdateStatusAsync(
                        uploadId,
                        "Importing",
                        progress.Message,
                        progress.PercentComplete,
                        progress.CurrentTable,
                        cancellationToken);

                    await NotifyProgressAsync(
                        uploadId,
                        progress.Phase,
                        progress.CurrentTable ?? "",
                        progress.PercentComplete,
                        progress.Message);
                },
                cancellationToken);

            // Save statistics
            var statEntities = statistics.TableStatistics.Select(s => new Data.Entities.ImportStatistic
            {
                UploadId = uploadId,
                InventoryId = s.InventoryId,
                TableName = s.TableName,
                RecordsImported = s.RecordsImported,
                DurationMs = s.DurationMs
            });

            await _uploadRepository.AddImportStatisticsAsync(uploadId, statEntities, cancellationToken);

            // Clear SQLite connection pool to release file lock before moving
            Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();

            // Small delay to ensure file handle is released
            await Task.Delay(100, cancellationToken);

            // Move file to completed folder
            var completedPath = MoveToCompleted(sqlitePath, uploadId);

            // Update status to completed
            await _uploadRepository.UpdateStatusAsync(
                uploadId, "Completed",
                $"Import completed. {statistics.TotalRecordsImported:N0} records imported.",
                100, "Complete",
                cancellationToken);

            // Update file path
            var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
            if (upload != null)
            {
                upload.FilePath = completedPath;
                await _uploadRepository.UpdateAsync(upload, cancellationToken);
            }

            await NotifyProgressAsync(uploadId, "Complete", "", 100,
                $"Import completed. {statistics.TotalRecordsImported:N0} records imported.");

            // Log import complete
            await _appLogService.LogImportCompleteAsync(uploadId, statistics.TotalRecordsImported, statistics.Duration, cancellationToken);

            _logger.LogInformation("Import job completed for upload {UploadId}. {Records:N0} records imported.",
                uploadId, statistics.TotalRecordsImported);
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("Import job cancelled for upload {UploadId}", uploadId);
            await _uploadRepository.UpdateStatusAsync(uploadId, "Cancelled", "Import was cancelled.", null, null, CancellationToken.None);
            await NotifyProgressAsync(uploadId, "Cancelled", "", 0, "Import was cancelled.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Import job failed for upload {UploadId}", uploadId);
            await _appLogService.LogImportFailedAsync(uploadId, ex.Message, ex.ToString(), CancellationToken.None);
            await FailImportAsync(uploadId, sqlitePath, ex.Message, CancellationToken.None);

            // Re-throw so Hangfire marks the job as failed
            throw;
        }
    }

    private async Task FailImportAsync(Guid uploadId, string sqlitePath, string errorMessage, CancellationToken cancellationToken)
    {
        // Clear SQLite connection pool to release file lock before moving
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
        await Task.Delay(100, CancellationToken.None);

        // Move file to errors folder
        var errorPath = MoveToErrors(sqlitePath, uploadId, errorMessage);

        // Update status
        await _uploadRepository.UpdateStatusAsync(uploadId, "Failed", errorMessage, null, null, cancellationToken);

        // Update file path and error details
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload != null)
        {
            upload.FilePath = errorPath;
            upload.ErrorDetails = errorMessage;
            await _uploadRepository.UpdateAsync(upload, cancellationToken);
        }

        await NotifyProgressAsync(uploadId, "Failed", "", 0, errorMessage);
    }

    private string MoveToCompleted(string sourcePath, Guid uploadId)
    {
        var completedDir = _storageSettings.GetCompletedPath();
        Directory.CreateDirectory(completedDir);

        var fileName = $"{uploadId}_{Path.GetFileName(sourcePath)}";
        var destPath = Path.Combine(completedDir, fileName);

        MoveFileWithRetry(sourcePath, destPath);

        // Create metadata file
        CreateMetadataFile(destPath, uploadId, null);

        return destPath;
    }

    private string MoveToErrors(string sourcePath, Guid uploadId, string errorMessage)
    {
        var errorsDir = _storageSettings.GetErrorsPath();
        Directory.CreateDirectory(errorsDir);

        var fileName = $"{uploadId}_{Path.GetFileName(sourcePath)}";
        var destPath = Path.Combine(errorsDir, fileName);

        MoveFileWithRetry(sourcePath, destPath);

        // Create metadata file
        CreateMetadataFile(destPath, uploadId, errorMessage);

        return destPath;
    }

    private void MoveFileWithRetry(string sourcePath, string destPath, int maxRetries = 5)
    {
        if (!File.Exists(sourcePath))
        {
            _logger.LogWarning("Source file does not exist: {Path}", sourcePath);
            return;
        }

        for (int attempt = 1; attempt <= maxRetries; attempt++)
        {
            try
            {
                File.Move(sourcePath, destPath, overwrite: true);
                _logger.LogInformation("Moved file to {DestPath}", destPath);
                return;
            }
            catch (IOException ex) when (attempt < maxRetries)
            {
                _logger.LogWarning("File move attempt {Attempt}/{MaxRetries} failed: {Error}. Retrying...",
                    attempt, maxRetries, ex.Message);
                Thread.Sleep(200 * attempt); // Exponential backoff: 200ms, 400ms, 600ms, 800ms
            }
        }

        // Final attempt - let it throw if it fails
        File.Move(sourcePath, destPath, overwrite: true);
    }

    private void CreateMetadataFile(string dbPath, Guid uploadId, string? errorMessage)
    {
        var metadataPath = dbPath + ".meta";
        var metadata = new Dictionary<string, object?>
        {
            ["UploadId"] = uploadId,
            ["Timestamp"] = DateTime.UtcNow,
            ["ErrorMessage"] = errorMessage
        };

        var json = System.Text.Json.JsonSerializer.Serialize(metadata, new System.Text.Json.JsonSerializerOptions
        {
            WriteIndented = true
        });

        File.WriteAllText(metadataPath, json);
    }

    private async Task NotifyProgressAsync(Guid uploadId, string phase, string currentTable, int percent, string message)
    {
        if (_hubNotifier != null)
        {
            await _hubNotifier.SendProgressAsync(uploadId, phase, currentTable, percent, message);
        }
    }
}

/// <summary>
/// Interface for SignalR hub notifications.
/// </summary>
public interface IHubNotifier
{
    Task SendProgressAsync(Guid uploadId, string phase, string currentTable, int percent, string message);
}
