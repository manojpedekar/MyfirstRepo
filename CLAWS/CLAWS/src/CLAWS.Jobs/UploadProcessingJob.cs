using System.Data;
using System.IO.Compression;
using Hangfire;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Jobs.Filters;
using CLAWS.Core.Import;
using CLAWS.Core.Models;
using CLAWS.Core.Services;
using CLAWS.Core.Validation;
using CLAWS.Data.Repositories;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for processing uploads: extraction, validation, and import.
/// Uses DisableConcurrentExecution to ensure only one upload processes at a time,
/// preventing disk I/O contention when multiple large files are uploaded.
/// </summary>
public interface IUploadProcessingJob
{
    /// <summary>
    /// Processes an uploaded file: extracts ZIP, validates, and imports to SQL Server.
    /// </summary>
    /// <param name="uploadId">The upload ID.</param>
    /// <param name="zipFilePath">Path to the uploaded ZIP file.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    [JobDisplayName("Process Upload: {0}")]
    [AutomaticRetry(Attempts = 0)]
    [Queue("upload-processing")]
    [ConfigurableDisableConcurrentExecution] // Timeout configured via AppSettings.JobTimeouts.UploadProcessingMinutes
    Task ExecuteAsync(Guid uploadId, string zipFilePath, CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of the upload processing job.
/// Handles the complete upload workflow: extraction → validation → import.
/// Optionally performs automatic validation and merge based on configuration.
/// </summary>
public class UploadProcessingJob : IUploadProcessingJob
{
    private readonly ILogger<UploadProcessingJob> _logger;
    private readonly IUploadRepository _uploadRepository;
    private readonly IZipValidator _zipValidator;
    private readonly IDatabaseValidator _dbValidator;
    private readonly IUploadTypeDetector _typeDetector;
    private readonly ISqliteImporter _importer;
    private readonly IVersionService _versionService;
    private readonly IAppLogService _appLogService;
    private readonly IMigrationService _migrationService;
    private readonly SqlServerSettings _sqlSettings;
    private readonly StorageSettings _storageSettings;
    private readonly ImportSettings _importSettings;
    private readonly IHubNotifier? _hubNotifier;

    public UploadProcessingJob(
        ILogger<UploadProcessingJob> logger,
        IUploadRepository uploadRepository,
        IZipValidator zipValidator,
        IDatabaseValidator dbValidator,
        IUploadTypeDetector typeDetector,
        ISqliteImporter importer,
        IVersionService versionService,
        IAppLogService appLogService,
        IMigrationService migrationService,
        SqlServerSettings sqlSettings,
        StorageSettings storageSettings,
        ImportSettings importSettings,
        IHubNotifier? hubNotifier = null)
    {
        _logger = logger;
        _uploadRepository = uploadRepository;
        _zipValidator = zipValidator;
        _dbValidator = dbValidator;
        _typeDetector = typeDetector;
        _importer = importer;
        _versionService = versionService;
        _appLogService = appLogService;
        _migrationService = migrationService;
        _sqlSettings = sqlSettings;
        _storageSettings = storageSettings;
        _importSettings = importSettings;
        _hubNotifier = hubNotifier;
    }

    /// <inheritdoc/>
    public async Task ExecuteAsync(Guid uploadId, string zipFilePath, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting upload processing job for {UploadId}", uploadId);

        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null)
        {
            _logger.LogError("Upload {UploadId} not found", uploadId);
            return;
        }

        // Cache original upload values for logging (upload may be reassigned during processing)
        var originalFilename = upload.OriginalFilename;
        var uploadedBy = upload.UploadedBy;

        string? extractedPath = null;
        var extractionPath = Path.Combine(_storageSettings.GetExtractionPath(), uploadId.ToString());

        try
        {
            // ═══════════════════════════════════════════════════════════════════
            // Phase 1: ZIP Extraction and Validation
            // ═══════════════════════════════════════════════════════════════════

            await UpdateStatusAsync(uploadId, "Processing", "Extracting ZIP file...", 5, "Extracting");
            await NotifyProgressAsync(uploadId, "Extracting", "", 5, "Extracting ZIP file...");

            var zipResult = await _zipValidator.ValidateAndExtractAsync(zipFilePath, extractionPath, cancellationToken);

            if (!zipResult.IsValid)
            {
                await FailUploadWithZipAsync(uploadId, zipFilePath, extractionPath, zipResult.ErrorMessage!, cancellationToken);
                await _appLogService.LogValidationFailAsync(uploadId, $"ZIP: {zipResult.ErrorMessage}", cancellationToken);
                await _appLogService.LogUploadFailedAsync(uploadId, upload.OriginalFilename, zipResult.ErrorMessage!, upload.UploadedBy, cancellationToken);
                return;
            }

            extractedPath = zipResult.Details?["ExtractedPath"]?.ToString();

            // NOTE: Don't delete ZIP file yet - we need it if duplicate check fails

            // ═══════════════════════════════════════════════════════════════════
            // Phase 1.5: Detect Upload Type
            // ═══════════════════════════════════════════════════════════════════

            await UpdateStatusAsync(uploadId, "Processing", "Detecting database type...", 10, "TypeDetection");
            await NotifyProgressAsync(uploadId, "TypeDetection", "", 10, "Detecting database type...");

            var typeDetectionResult = await _typeDetector.DetectTypeWithDetailsAsync(extractedPath!, cancellationToken);
            var uploadType = typeDetectionResult.UploadType;

            if (!typeDetectionResult.Success || uploadType == UploadType.Unknown)
            {
                var errorMsg = typeDetectionResult.ErrorMessage ?? "Unable to detect database type. Expected NTFSPermissions or ADInventory database.";
                await FailUploadWithZipAsync(uploadId, zipFilePath, extractionPath, errorMsg, cancellationToken);
                await _appLogService.LogValidationFailAsync(uploadId, $"Type detection: {errorMsg}", cancellationToken);
                await _appLogService.LogUploadFailedAsync(uploadId, upload.OriginalFilename, errorMsg, upload.UploadedBy, cancellationToken);
                return;
            }

            _logger.LogInformation("Detected upload type: {UploadType} (version: {Version})", uploadType, typeDetectionResult.DbVersion);

            // Store upload type in entity
            upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
            if (upload != null)
            {
                upload.UploadType = uploadType.ToString();
                await _uploadRepository.UpdateAsync(upload, cancellationToken);
            }

            // ═══════════════════════════════════════════════════════════════════
            // Phase 2: Database Validation
            // ═══════════════════════════════════════════════════════════════════

            await UpdateStatusAsync(uploadId, "Processing", $"Validating {uploadType.GetDisplayName()} database...", 12, "Validating");
            await NotifyProgressAsync(uploadId, "Validating", "", 12, $"Validating {uploadType.GetDisplayName()} database...");

            // Get version requirements from SQL Server for this upload type
            var connectionString = _sqlSettings.BuildConnectionString();
            var requiredDbVersion = await _versionService.GetRequiredDbVersionAsync(connectionString, uploadType, cancellationToken);
            var requiredAppVersion = await _versionService.GetRequiredAppVersionAsync(connectionString, uploadType, cancellationToken);

            var dbResult = await _dbValidator.ValidateAsync(
                extractedPath!,
                uploadType,
                requiredDbVersion ?? "1.0.0",
                requiredAppVersion,
                cancellationToken);

            if (!dbResult.IsValid)
            {
                await FailUploadWithZipAsync(uploadId, zipFilePath, extractionPath, dbResult.ErrorMessage!, cancellationToken);
                await _appLogService.LogValidationFailAsync(uploadId, $"Database: {dbResult.ErrorMessage}", cancellationToken);
                await _appLogService.LogUploadFailedAsync(uploadId, originalFilename, dbResult.ErrorMessage!, uploadedBy, cancellationToken);

                // Update with validation result details
                upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
                if (upload != null)
                {
                    upload.ValidationResult = System.Text.Json.JsonSerializer.Serialize(dbResult);
                    await _uploadRepository.UpdateAsync(upload, cancellationToken);
                }
                return;
            }

            // ═══════════════════════════════════════════════════════════════════
            // Phase 2.5: Duplicate InventoryID Check
            // ═══════════════════════════════════════════════════════════════════

            await UpdateStatusAsync(uploadId, "Processing", "Checking for duplicate data...", 15, "DuplicateCheck");
            await NotifyProgressAsync(uploadId, "DuplicateCheck", "", 15, "Checking for duplicate InventoryIDs...");

            var duplicateResult = await _dbValidator.CheckForDuplicateInventoriesAsync(
                extractedPath!,
                connectionString,
                uploadType,
                cancellationToken);

            if (!duplicateResult.IsValid)
            {
                // Duplicate found - this is a hard failure
                _logger.LogWarning("Duplicate InventoryID(s) detected for upload {UploadId}: {Message}",
                    uploadId, duplicateResult.ErrorMessage);

                await FailUploadWithZipAsync(uploadId, zipFilePath, extractionPath, duplicateResult.ErrorMessage!, cancellationToken);
                await _appLogService.LogValidationFailAsync(uploadId, $"Duplicate: {duplicateResult.ErrorMessage}", cancellationToken);
                await _appLogService.LogUploadFailedAsync(uploadId, originalFilename, duplicateResult.ErrorMessage!, uploadedBy, cancellationToken);

                // Update with duplicate details for display
                upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
                if (upload != null)
                {
                    // Include duplicate info in validation result
                    var combinedResult = new
                    {
                        dbResult.DbVersion,
                        dbResult.RequiredDbVersion,
                        dbResult.Collections,
                        DuplicateCheck = new
                        {
                            duplicateResult.ErrorCode,
                            duplicateResult.ErrorMessage,
                            duplicateResult.Duplicates
                        }
                    };
                    upload.ValidationResult = System.Text.Json.JsonSerializer.Serialize(combinedResult);
                    await _uploadRepository.UpdateAsync(upload, cancellationToken);
                }
                return;
            }

            // Log validation pass (both structure and duplicate check passed)
            await _appLogService.LogValidationPassAsync(uploadId, cancellationToken);

            // NOTE: Keep ZIP file - we'll move it to Completed/Errors folder instead of re-compressing
            // This optimization reduces disk I/O by ~50% since we avoid re-compressing the database

            // Update file path to extracted database
            upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
            if (upload != null)
            {
                upload.FilePath = extractedPath;
                upload.ValidationResult = System.Text.Json.JsonSerializer.Serialize(dbResult);
                await _uploadRepository.UpdateAsync(upload, cancellationToken);
            }

            // ═══════════════════════════════════════════════════════════════════
            // Phase 3: Database Integrity Check
            // ═══════════════════════════════════════════════════════════════════

            await UpdateStatusAsync(uploadId, "Processing", "Checking database integrity...", 20, "IntegrityCheck");
            await NotifyProgressAsync(uploadId, "IntegrityCheck", "", 20, "Checking database integrity...");

            // Log import start
            await _appLogService.LogImportStartAsync(uploadId, cancellationToken);

            // Extract InventoryIDs FIRST for early registration (enables cleanup if import fails)
            _logger.LogInformation("Extracting InventoryIDs from SQLite for early registration ({UploadType})...", uploadType);
            var inventoryIds = await _importer.GetInventoryIdsFromSqliteAsync(extractedPath!, uploadType, cancellationToken);

            if (inventoryIds.Count > 0)
            {
                var placeholderStats = inventoryIds.Select(id => new Data.Entities.ImportStatistic
                {
                    UploadId = uploadId,
                    InventoryId = id,
                    TableName = "_InventoryLink",
                    RecordsImported = 0,
                    DurationMs = 0
                });

                await _uploadRepository.AddImportStatisticsAsync(uploadId, placeholderStats, cancellationToken);
                _logger.LogInformation("Registered {Count} InventoryID(s) for upload {UploadId}", inventoryIds.Count, uploadId);
            }

            // Run integrity check
            var integrityResult = await _dbValidator.RunIntegrityCheckAsync(extractedPath!, cancellationToken);
            if (!integrityResult.IsValid)
            {
                await FailImportAsync(uploadId, extractedPath!, zipFilePath, integrityResult.ErrorMessage!, cancellationToken);
                await _appLogService.LogImportFailedAsync(uploadId, integrityResult.ErrorMessage!, null, cancellationToken);
                return;
            }

            // ═══════════════════════════════════════════════════════════════════
            // Phase 4: Import to SQL Server
            // ═══════════════════════════════════════════════════════════════════

            await UpdateStatusAsync(uploadId, "Importing", $"Starting {uploadType.GetDisplayName()} import...", 25, "Importing");
            await NotifyProgressAsync(uploadId, "Importing", "", 25, $"Starting {uploadType.GetDisplayName()} import...");

            var statistics = await _importer.ImportAllTablesAsync(
                extractedPath!,
                connectionString,
                uploadId,
                uploadType,
                async progress =>
                {
                    // Scale progress from 25-95%
                    var scaledPercent = 25 + (int)(progress.PercentComplete * 0.70);

                    // Use detailed progress update for real-time tracking
                    await _uploadRepository.UpdateProgressAsync(
                        uploadId,
                        scaledPercent,
                        progress.CurrentTable,
                        progress.RowsProcessed,
                        progress.TotalRows,
                        progress.Message,
                        CancellationToken.None);

                    await NotifyProgressAsync(uploadId, "Importing", progress.CurrentTable ?? "", scaledPercent, progress.Message);
                },
                cancellationToken);

            // Save import statistics
            var statEntities = statistics.TableStatistics.Select(s => new Data.Entities.ImportStatistic
            {
                UploadId = uploadId,
                InventoryId = s.InventoryId,
                TableName = s.TableName,
                RecordsImported = s.RecordsImported,
                DurationMs = s.DurationMs
            });

            await _uploadRepository.AddImportStatisticsAsync(uploadId, statEntities, cancellationToken);

            // Compute TableCounts statistics for each imported inventory (NTFSPermissions only)
            if (uploadType == UploadType.NTFSPermissions && inventoryIds.Count > 0)
            {
                _logger.LogInformation("Computing TableCounts stats for {Count} inventory(s)...", inventoryIds.Count);

                foreach (var inventoryId in inventoryIds)
                {
                    try
                    {
                        await using var statsConnection = new SqlConnection(connectionString);
                        await statsConnection.OpenAsync(cancellationToken);

                        await using var statsCommand = new SqlCommand("dbo.usp_ComputeStats_TableCounts", statsConnection)
                        {
                            CommandType = CommandType.StoredProcedure,
                            CommandTimeout = 60 // 1 minute should be sufficient
                        };
                        statsCommand.Parameters.AddWithValue("@InventoryID", inventoryId);

                        await statsCommand.ExecuteNonQueryAsync(cancellationToken);
                        _logger.LogDebug("Computed TableCounts stats for inventory {InventoryId}", inventoryId);
                    }
                    catch (Exception ex)
                    {
                        // Log but don't fail the import - stats computation is non-critical
                        _logger.LogWarning(ex, "Failed to compute TableCounts stats for inventory {InventoryId}", inventoryId);
                    }
                }

                _logger.LogInformation("TableCounts stats computation completed for {Count} inventory(s)", inventoryIds.Count);
            }

            // ═══════════════════════════════════════════════════════════════════
            // Phase 5: Finalization
            // ═══════════════════════════════════════════════════════════════════

            await UpdateStatusAsync(uploadId, "Importing", "Finalizing...", 98, "Finalizing");

            // Clear SQLite connection pool to release file lock
            Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
            await Task.Delay(100, cancellationToken);

            // Move original ZIP to completed folder (avoids re-compression)
            var completedPath = MoveToCompleted(extractedPath!, uploadId, zipFilePath);

            // Update final status
            await UpdateStatusAsync(uploadId, "Completed",
                $"Import completed. {statistics.TotalRecordsImported:N0} records imported.",
                100, "Complete");

            // Update file path
            upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
            if (upload != null)
            {
                upload.FilePath = completedPath;
                await _uploadRepository.UpdateAsync(upload, cancellationToken);
            }

            await NotifyProgressAsync(uploadId, "Complete", "", 100,
                $"Import completed. {statistics.TotalRecordsImported:N0} records imported.");

            // Log completion
            await _appLogService.LogImportCompleteAsync(uploadId, statistics.TotalRecordsImported, statistics.Duration, cancellationToken);

            _logger.LogInformation("Upload processing completed for {UploadId}. {Records:N0} records imported.",
                uploadId, statistics.TotalRecordsImported);

            // ═══════════════════════════════════════════════════════════════════
            // Phase 6: Automatic Validation and Merge (if configured)
            // ═══════════════════════════════════════════════════════════════════

            if (upload != null)
            {
                await PerformAutomaticProcessingAsync(uploadId, upload, cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("Upload processing cancelled for {UploadId}", uploadId);
            await UpdateStatusAsync(uploadId, "Cancelled", "Processing was cancelled.", null, null);
            await NotifyProgressAsync(uploadId, "Cancelled", "", 0, "Processing was cancelled.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Upload processing failed for {UploadId}", uploadId);
            await _appLogService.LogImportFailedAsync(uploadId, ex.Message, ex.ToString(), CancellationToken.None);

            if (extractedPath != null)
            {
                await FailImportAsync(uploadId, extractedPath, zipFilePath, ex.Message, CancellationToken.None);
            }
            else
            {
                await FailUploadAsync(uploadId, zipFilePath, extractionPath, ex.Message, CancellationToken.None);
            }

            throw; // Re-throw so Hangfire marks the job as failed
        }
    }

    private async Task UpdateStatusAsync(Guid uploadId, string status, string? message, int? progress, string? phase)
    {
        await _uploadRepository.UpdateStatusAsync(uploadId, status, message, progress, phase, CancellationToken.None);
    }

    private async Task FailUploadAsync(Guid uploadId, string? zipFilePath, string? extractionPath, string errorMessage, CancellationToken cancellationToken)
    {
        _logger.LogWarning("Upload {UploadId} failed: {Error}", uploadId, errorMessage);

        // Clean up files
        if (!string.IsNullOrEmpty(zipFilePath) && File.Exists(zipFilePath))
        {
            try { File.Delete(zipFilePath); }
            catch { /* Best effort */ }
        }

        if (!string.IsNullOrEmpty(extractionPath) && Directory.Exists(extractionPath))
        {
            try { Directory.Delete(extractionPath, true); }
            catch { /* Best effort */ }
        }

        await UpdateStatusAsync(uploadId, "Failed", errorMessage, null, null);
        await NotifyProgressAsync(uploadId, "Failed", "", 0, errorMessage);
    }

    /// <summary>
    /// Fails an upload and moves the ZIP file to the Errors folder for investigation.
    /// Used when validation fails but we want to keep the original file.
    /// </summary>
    private async Task FailUploadWithZipAsync(Guid uploadId, string? zipFilePath, string? extractionPath, string errorMessage, CancellationToken cancellationToken)
    {
        _logger.LogWarning("Upload {UploadId} failed (keeping ZIP): {Error}", uploadId, errorMessage);

        string? errorZipPath = null;

        // Move ZIP to errors folder (if it exists)
        if (!string.IsNullOrEmpty(zipFilePath) && File.Exists(zipFilePath))
        {
            try
            {
                var errorsDir = _storageSettings.GetErrorsPath();
                Directory.CreateDirectory(errorsDir);

                var fileName = $"{uploadId}_{Path.GetFileName(zipFilePath)}";
                errorZipPath = Path.Combine(errorsDir, fileName);

                File.Move(zipFilePath, errorZipPath, overwrite: true);
                CreateMetadataFile(errorZipPath, uploadId, errorMessage);

                _logger.LogInformation("Moved failed upload ZIP to {Path}", errorZipPath);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to move ZIP to errors folder: {Path}", zipFilePath);
                // Try to delete the ZIP if move failed
                try { File.Delete(zipFilePath); }
                catch { /* Best effort */ }
            }
        }

        // Clean up extraction folder
        if (!string.IsNullOrEmpty(extractionPath) && Directory.Exists(extractionPath))
        {
            // Clear SQLite connection pool to release file lock
            Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();

            try { Directory.Delete(extractionPath, true); }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to delete extraction folder: {Path}", extractionPath);
            }
        }

        // Update status
        await UpdateStatusAsync(uploadId, "Failed", errorMessage, null, null);

        // Update file path to error location
        if (!string.IsNullOrEmpty(errorZipPath))
        {
            var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
            if (upload != null)
            {
                upload.FilePath = errorZipPath;
                upload.ErrorDetails = errorMessage;
                await _uploadRepository.UpdateAsync(upload, cancellationToken);
            }
        }

        await NotifyProgressAsync(uploadId, "Failed", "", 0, errorMessage);
    }

    private async Task FailImportAsync(Guid uploadId, string sqlitePath, string originalZipPath, string errorMessage, CancellationToken cancellationToken)
    {
        _logger.LogWarning("Import for {UploadId} failed: {Error}", uploadId, errorMessage);

        // Clear SQLite connection pool to release file lock
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
        await Task.Delay(100, CancellationToken.None);

        // Move original ZIP to errors folder (avoids re-compression)
        var errorPath = MoveToErrors(sqlitePath, uploadId, originalZipPath, errorMessage);

        // Update status
        await UpdateStatusAsync(uploadId, "Failed", errorMessage, null, null);

        // Update file path
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload != null)
        {
            upload.FilePath = errorPath;
            upload.ErrorDetails = errorMessage;
            await _uploadRepository.UpdateAsync(upload, cancellationToken);
        }

        await NotifyProgressAsync(uploadId, "Failed", "", 0, errorMessage);
    }

    private string MoveToCompleted(string sourcePath, Guid uploadId, string originalZipPath)
    {
        var completedDir = _storageSettings.GetCompletedPath();
        Directory.CreateDirectory(completedDir);

        var originalFileName = Path.GetFileName(sourcePath);
        var zipFileName = $"{uploadId}_{Path.GetFileNameWithoutExtension(originalFileName)}.zip";
        var zipPath = Path.Combine(completedDir, zipFileName);

        // Optimization: Move original ZIP instead of re-compressing the extracted database
        // This reduces disk I/O by ~50% since we avoid the compression operation
        if (!string.IsNullOrEmpty(originalZipPath) && File.Exists(originalZipPath))
        {
            try
            {
                MoveFileWithRetry(originalZipPath, zipPath);

                // Move original metadata file if it exists, otherwise create new one
                var originalMetaPath = originalZipPath + ".meta";
                var newMetaPath = zipPath + ".meta";
                if (File.Exists(originalMetaPath))
                {
                    MoveFileWithRetry(originalMetaPath, newMetaPath);
                    _logger.LogDebug("Moved original metadata file to {MetaPath}", newMetaPath);
                }
                else
                {
                    CreateMetadataFile(zipPath, uploadId, null);
                }

                _logger.LogInformation("Moved original ZIP to completed: {ZipPath} (avoided re-compression)", zipPath);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to move original ZIP, falling back to re-compression");
                // Fallback: Compress the database file if move fails
                CompressFileToZip(sourcePath, zipPath, originalFileName);
                CreateMetadataFile(zipPath, uploadId, null);
                _logger.LogInformation("Compressed completed file to {ZipPath} (fallback)", zipPath);
            }
        }
        else
        {
            // Fallback: Original ZIP not available, compress the extracted database
            _logger.LogWarning("Original ZIP not found at {Path}, falling back to re-compression", originalZipPath);
            CompressFileToZip(sourcePath, zipPath, originalFileName);
            CreateMetadataFile(zipPath, uploadId, null);
            _logger.LogInformation("Compressed completed file to {ZipPath}", zipPath);
        }

        // Clean up the extraction folder (includes .db, .db-shm, .db-wal files)
        CleanupExtractionFolder(sourcePath);

        return zipPath;
    }

    private string MoveToErrors(string sourcePath, Guid uploadId, string originalZipPath, string errorMessage)
    {
        var errorsDir = _storageSettings.GetErrorsPath();
        Directory.CreateDirectory(errorsDir);

        var originalFileName = Path.GetFileName(sourcePath);
        var zipFileName = $"{uploadId}_{Path.GetFileNameWithoutExtension(originalFileName)}.zip";
        var zipPath = Path.Combine(errorsDir, zipFileName);

        // Optimization: Move original ZIP instead of re-compressing the extracted database
        // This reduces disk I/O by ~50% since we avoid the compression operation
        if (!string.IsNullOrEmpty(originalZipPath) && File.Exists(originalZipPath))
        {
            try
            {
                MoveFileWithRetry(originalZipPath, zipPath);

                // Create metadata file with error info (don't move original, need error details)
                CreateMetadataFile(zipPath, uploadId, errorMessage);

                // Delete original metadata file if it exists
                var originalMetaPath = originalZipPath + ".meta";
                if (File.Exists(originalMetaPath))
                {
                    try { File.Delete(originalMetaPath); }
                    catch { /* Best effort */ }
                }

                _logger.LogInformation("Moved original ZIP to errors: {ZipPath} (avoided re-compression)", zipPath);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to move original ZIP, falling back to re-compression");
                // Fallback: Compress the database file if move fails
                CompressFileToZip(sourcePath, zipPath, originalFileName);
                CreateMetadataFile(zipPath, uploadId, errorMessage);
                _logger.LogInformation("Compressed error file to {ZipPath} (fallback)", zipPath);
            }
        }
        else
        {
            // Fallback: Original ZIP not available, compress the extracted database
            _logger.LogWarning("Original ZIP not found at {Path}, falling back to re-compression", originalZipPath);
            CompressFileToZip(sourcePath, zipPath, originalFileName);
            CreateMetadataFile(zipPath, uploadId, errorMessage);
            _logger.LogInformation("Compressed error file to {ZipPath}", zipPath);
        }

        // Clean up the extraction folder (includes .db, .db-shm, .db-wal files)
        CleanupExtractionFolder(sourcePath);

        return zipPath;
    }

    /// <summary>
    /// Cleans up the extraction folder after compression, including SQLite WAL files.
    /// </summary>
    private void CleanupExtractionFolder(string dbFilePath)
    {
        // Delete the main database file
        DeleteFileWithRetry(dbFilePath);

        // Delete SQLite WAL (Write-Ahead Logging) files if they exist
        var walFile = dbFilePath + "-wal";
        var shmFile = dbFilePath + "-shm";
        var journalFile = dbFilePath + "-journal";

        if (File.Exists(walFile))
        {
            DeleteFileWithRetry(walFile);
            _logger.LogDebug("Deleted WAL file: {Path}", walFile);
        }

        if (File.Exists(shmFile))
        {
            DeleteFileWithRetry(shmFile);
            _logger.LogDebug("Deleted SHM file: {Path}", shmFile);
        }

        if (File.Exists(journalFile))
        {
            DeleteFileWithRetry(journalFile);
            _logger.LogDebug("Deleted journal file: {Path}", journalFile);
        }

        // Delete the parent extraction folder if it's empty (the GUID folder)
        var extractionFolder = Path.GetDirectoryName(dbFilePath);
        if (!string.IsNullOrEmpty(extractionFolder) && Directory.Exists(extractionFolder))
        {
            try
            {
                // Check if the folder is within our extraction path before deleting
                var extractionBasePath = _storageSettings.GetExtractionPath();
                if (extractionFolder.StartsWith(extractionBasePath, StringComparison.OrdinalIgnoreCase))
                {
                    // Delete the folder and any remaining files
                    Directory.Delete(extractionFolder, recursive: true);
                    _logger.LogDebug("Deleted extraction folder: {Path}", extractionFolder);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to delete extraction folder: {Path}", extractionFolder);
            }
        }
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
                Thread.Sleep(200 * attempt);
            }
        }

        File.Move(sourcePath, destPath, overwrite: true);
    }

    /// <summary>
    /// Compresses a file into a ZIP archive for efficient disk storage.
    /// SQLite databases typically achieve 10:1 or better compression ratios.
    /// </summary>
    private void CompressFileToZip(string sourcePath, string zipPath, string entryName)
    {
        if (!File.Exists(sourcePath))
        {
            _logger.LogWarning("Source file does not exist for compression: {Path}", sourcePath);
            return;
        }

        // Delete existing ZIP if it exists
        if (File.Exists(zipPath))
        {
            File.Delete(zipPath);
        }

        using var zipArchive = ZipFile.Open(zipPath, ZipArchiveMode.Create);
        zipArchive.CreateEntryFromFile(sourcePath, entryName, CompressionLevel.Optimal);

        // Log compression statistics
        var originalSize = new FileInfo(sourcePath).Length;
        var compressedSize = new FileInfo(zipPath).Length;
        var ratio = originalSize > 0 ? (double)originalSize / compressedSize : 0;

        _logger.LogInformation(
            "Compressed {SourceFile}: {OriginalSize:N0} bytes → {CompressedSize:N0} bytes ({Ratio:F1}:1 ratio)",
            Path.GetFileName(sourcePath), originalSize, compressedSize, ratio);
    }

    /// <summary>
    /// Deletes a ZIP file with retry logic and exponential backoff.
    /// Handles transient file locks from antivirus or Windows file system.
    /// </summary>
    private async Task DeleteZipWithRetryAsync(string path, int maxRetries = 3, int baseDelayMs = 500)
    {
        for (int i = 0; i < maxRetries; i++)
        {
            try
            {
                if (File.Exists(path))
                {
                    File.Delete(path);
                    _logger.LogDebug("Deleted ZIP file: {Path}", path);
                    return;
                }
                return; // File doesn't exist, nothing to do
            }
            catch (IOException) when (i < maxRetries - 1)
            {
                var delay = baseDelayMs * (i + 1); // Exponential backoff: 500, 1000, 1500ms
                _logger.LogDebug("Retry {Attempt}/{Max} deleting ZIP (waiting {Delay}ms): {Path}",
                    i + 1, maxRetries, delay, path);
                await Task.Delay(delay);
            }
        }

        // Final attempt - log warning if it still fails
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
                _logger.LogDebug("Deleted ZIP file on final attempt: {Path}", path);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to delete ZIP after {Retries} retries: {Path}", maxRetries, path);
        }
    }

    /// <summary>
    /// Deletes a file with retry logic for handling temporary locks.
    /// </summary>
    private void DeleteFileWithRetry(string filePath, int maxRetries = 5)
    {
        if (!File.Exists(filePath))
        {
            return;
        }

        for (int attempt = 1; attempt <= maxRetries; attempt++)
        {
            try
            {
                File.Delete(filePath);
                return;
            }
            catch (IOException ex) when (attempt < maxRetries)
            {
                _logger.LogWarning("File delete attempt {Attempt}/{MaxRetries} failed: {Error}. Retrying...",
                    attempt, maxRetries, ex.Message);
                Thread.Sleep(200 * attempt);
            }
        }

        // Final attempt
        try
        {
            File.Delete(filePath);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to delete file after compression: {Path}", filePath);
        }
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

    /// <summary>
    /// Performs automatic validation and merge based on configuration and per-upload override.
    /// </summary>
    private async Task PerformAutomaticProcessingAsync(Guid uploadId, Data.Entities.Upload upload, CancellationToken cancellationToken)
    {
        // Determine effective auto-processing settings
        var (shouldValidate, shouldMerge) = DetermineAutoProcessingBehavior(upload.AutoProcessingOverride);

        if (!shouldValidate && !shouldMerge)
        {
            _logger.LogInformation("AutoProcess: Auto-processing disabled for upload {UploadId}", uploadId);
            return;
        }

        _logger.LogInformation("AutoProcess: Starting automatic processing for upload {UploadId}. AutoValidate={Validate}, AutoMerge={Merge}",
            uploadId, shouldValidate, shouldMerge);

        // Perform automatic validation
        if (shouldValidate)
        {
            try
            {
                _logger.LogInformation("AutoProcess: Running automatic validation for upload {UploadId}", uploadId);
                await _appLogService.LogAsync(uploadId, "AutoProcess", "INFO",
                    "Starting automatic validation", null, null, cancellationToken);

                var validationResult = await _migrationService.ValidateAsync(uploadId, cancellationToken);

                if (validationResult.Success)
                {
                    _logger.LogInformation("AutoProcess: Automatic validation passed for upload {UploadId}", uploadId);
                    await _appLogService.LogAsync(uploadId, "AutoProcess", "INFO",
                        "Automatic validation completed successfully", null, null, cancellationToken);

                    // Proceed to merge if enabled and validation passed
                    if (shouldMerge)
                    {
                        await PerformAutomaticMergeAsync(uploadId, cancellationToken);
                    }
                }
                else
                {
                    _logger.LogWarning("AutoProcess: Automatic validation failed for upload {UploadId}: {Message}",
                        uploadId, validationResult.Message);
                    await _appLogService.LogAsync(uploadId, "AutoProcess", "WARNING",
                        $"Automatic validation failed: {validationResult.Message}", null, null, cancellationToken);

                    // Do NOT proceed to merge if validation failed
                    if (shouldMerge)
                    {
                        _logger.LogInformation("AutoProcess: Automatic merge skipped due to validation failure for upload {UploadId}", uploadId);
                        await _appLogService.LogAsync(uploadId, "AutoProcess", "INFO",
                            "Automatic merge skipped: validation failed", null, null, cancellationToken);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "AutoProcess: Error during automatic validation for upload {UploadId}", uploadId);
                await _appLogService.LogAsync(uploadId, "AutoProcess", "ERROR",
                    $"Error during automatic validation: {ex.Message}", null, null, cancellationToken);
            }
        }
    }

    /// <summary>
    /// Performs automatic merge after successful validation.
    /// </summary>
    private async Task PerformAutomaticMergeAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        try
        {
            _logger.LogInformation("AutoProcess: Running automatic merge for upload {UploadId}", uploadId);
            await _appLogService.LogAsync(uploadId, "AutoProcess", "INFO",
                "Starting automatic merge", null, null, cancellationToken);

            var mergeResult = await _migrationService.MigrateAsync(uploadId, cancellationToken);

            if (mergeResult.Success)
            {
                _logger.LogInformation("AutoProcess: Automatic merge completed for upload {UploadId}", uploadId);
                await _appLogService.LogAsync(uploadId, "AutoProcess", "INFO",
                    "Automatic merge completed successfully", null, null, cancellationToken);
            }
            else
            {
                _logger.LogWarning("AutoProcess: Automatic merge failed for upload {UploadId}: {Message}",
                    uploadId, mergeResult.Message);
                await _appLogService.LogAsync(uploadId, "AutoProcess", "WARNING",
                    $"Automatic merge failed: {mergeResult.Message}", null, null, cancellationToken);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AutoProcess: Error during automatic merge for upload {UploadId}", uploadId);
            await _appLogService.LogAsync(uploadId, "AutoProcess", "ERROR",
                $"Error during automatic merge: {ex.Message}", null, null, cancellationToken);
        }
    }

    /// <summary>
    /// Determines whether to perform automatic validation and merge based on
    /// global settings and per-upload override.
    /// </summary>
    private (bool shouldValidate, bool shouldMerge) DetermineAutoProcessingBehavior(string? uploadOverride)
    {
        // Per-upload override takes precedence over global settings
        if (!string.IsNullOrEmpty(uploadOverride))
        {
            return uploadOverride switch
            {
                "ValidateOnly" => (true, false),
                "ValidateAndMerge" => (true, true),
                "Manual" => (false, false),
                _ => (_importSettings.EnableAutomaticValidation, _importSettings.EnableAutomaticMerge)
            };
        }

        // Use global settings
        return (_importSettings.EnableAutomaticValidation, _importSettings.EnableAutomaticMerge);
    }
}
