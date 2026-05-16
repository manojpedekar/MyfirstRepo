using Microsoft.Data.SqlClient;
using CLAWS.Core.Configuration;
using CLAWS.Core.Models;
using CLAWS.Core.Services;
using CLAWS.Data.Repositories;
using System.Data;

namespace CLAWS.Web.Services;

/// <summary>
/// Implementation of migration service.
/// </summary>
public class MigrationService : IMigrationService
{
    private readonly ILogger<MigrationService> _logger;
    private readonly IUploadRepository _uploadRepository;
    private readonly SqlServerSettings _sqlSettings;
    private readonly DatabasePerformanceSettings _perfSettings;
    private readonly IAppLogService _appLogService;

    public MigrationService(
        ILogger<MigrationService> logger,
        IUploadRepository uploadRepository,
        SqlServerSettings sqlSettings,
        DatabasePerformanceSettings perfSettings,
        IAppLogService appLogService)
    {
        _logger = logger;
        _uploadRepository = uploadRepository;
        _sqlSettings = sqlSettings;
        _perfSettings = perfSettings;
        _appLogService = appLogService;
    }

    /// <summary>
    /// Updates validation status with retry logic and fresh connection fallback.
    /// After long-running operations, the scoped DbContext connection may be stale.
    /// </summary>
    private async Task UpdateValidationStatusWithRetryAsync(
        Guid uploadId,
        string status,
        string message,
        CancellationToken cancellationToken)
    {
        const int maxRetries = 3;
        Exception? lastException = null;

        // Try using the repository first (may work if connection is still good)
        for (int attempt = 1; attempt <= maxRetries; attempt++)
        {
            try
            {
                var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
                if (upload != null)
                {
                    upload.ValidationStatus = status;
                    upload.ValidationMessage = message;
                    upload.ValidationCompletedAt = DateTime.UtcNow;
                    await _uploadRepository.UpdateAsync(upload, cancellationToken);
                    _logger.LogDebug("Updated validation status via repository on attempt {Attempt}", attempt);
                    return;
                }
            }
            catch (Exception ex)
            {
                lastException = ex;
                _logger.LogWarning(ex, "Repository update failed on attempt {Attempt}/{MaxRetries}", attempt, maxRetries);
                if (attempt < maxRetries)
                    await Task.Delay(TimeSpan.FromSeconds(attempt), cancellationToken);
            }
        }

        // Fallback: Use direct SQL with fresh connection
        _logger.LogInformation("Falling back to direct SQL update for validation status");
        try
        {
            var connectionString = _sqlSettings.BuildConnectionString();
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            const string sql = @"
                UPDATE app.Uploads
                SET ValidationStatus = @Status,
                    ValidationMessage = @Message,
                    ValidationCompletedAt = @CompletedAt
                WHERE UploadId = @UploadId";

            await using var command = new SqlCommand(sql, connection);
            command.Parameters.AddWithValue("@UploadId", uploadId);
            command.Parameters.AddWithValue("@Status", status);
            command.Parameters.AddWithValue("@Message", message);
            command.Parameters.AddWithValue("@CompletedAt", DateTime.UtcNow);

            var rowsAffected = await command.ExecuteNonQueryAsync(cancellationToken);
            _logger.LogInformation("Direct SQL update succeeded, {RowsAffected} row(s) affected", rowsAffected);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Direct SQL update also failed for upload {UploadId}", uploadId);
            throw new AggregateException("Failed to update validation status after all retries", lastException!, ex);
        }
    }

    /// <summary>
    /// Updates merge status with retry logic and fresh connection fallback.
    /// </summary>
    private async Task UpdateMergeStatusWithRetryAsync(
        Guid uploadId,
        string status,
        string message,
        CancellationToken cancellationToken)
    {
        const int maxRetries = 3;
        Exception? lastException = null;

        for (int attempt = 1; attempt <= maxRetries; attempt++)
        {
            try
            {
                var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
                if (upload != null)
                {
                    upload.MergeStatus = status;
                    upload.MergeMessage = message;
                    upload.MergeCompletedAt = DateTime.UtcNow;
                    await _uploadRepository.UpdateAsync(upload, cancellationToken);
                    _logger.LogDebug("Updated merge status via repository on attempt {Attempt}", attempt);
                    return;
                }
            }
            catch (Exception ex)
            {
                lastException = ex;
                _logger.LogWarning(ex, "Repository update failed on attempt {Attempt}/{MaxRetries}", attempt, maxRetries);
                if (attempt < maxRetries)
                    await Task.Delay(TimeSpan.FromSeconds(attempt), cancellationToken);
            }
        }

        // Fallback: Use direct SQL with fresh connection
        _logger.LogInformation("Falling back to direct SQL update for merge status");
        try
        {
            var connectionString = _sqlSettings.BuildConnectionString();
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            const string sql = @"
                UPDATE app.Uploads
                SET MergeStatus = @Status,
                    MergeMessage = @Message,
                    MergeCompletedAt = @CompletedAt
                WHERE UploadId = @UploadId";

            await using var command = new SqlCommand(sql, connection);
            command.Parameters.AddWithValue("@UploadId", uploadId);
            command.Parameters.AddWithValue("@Status", status);
            command.Parameters.AddWithValue("@Message", message);
            command.Parameters.AddWithValue("@CompletedAt", DateTime.UtcNow);

            var rowsAffected = await command.ExecuteNonQueryAsync(cancellationToken);
            _logger.LogInformation("Direct SQL update succeeded, {RowsAffected} row(s) affected", rowsAffected);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Direct SQL update also failed for upload {UploadId}", uploadId);
            throw new AggregateException("Failed to update merge status after all retries", lastException!, ex);
        }
    }

    /// <summary>
    /// Gets the upload type for an upload, defaulting to NTFSPermissions for backward compatibility.
    /// </summary>
    private async Task<UploadType> GetUploadTypeAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload?.UploadType == null)
            return UploadType.NTFSPermissions;

        return Enum.TryParse<UploadType>(upload.UploadType, ignoreCase: true, out var uploadType)
            ? uploadType
            : UploadType.NTFSPermissions;
    }

    /// <inheritdoc/>
    public async Task<List<Guid>> GetInventoryIdsAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload?.ImportStatistics == null)
            return new List<Guid>();

        return upload.ImportStatistics
            .Select(s => s.InventoryId)
            .Distinct()
            .ToList();
    }

    /// <inheritdoc/>
    public async Task<List<InventoryInfo>> GetInventoryInfoAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var inventoryIds = await GetInventoryIdsAsync(uploadId, cancellationToken);
        var results = new List<InventoryInfo>();

        if (inventoryIds.Count == 0)
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        // Load upload with statistics once (not per inventory)
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);

        foreach (var inventoryId in inventoryIds)
        {
            var info = new InventoryInfo { InventoryId = inventoryId };

            try
            {
                await using var connection = new SqlConnection(connectionString);
                await connection.OpenAsync(cancellationToken);

                // Try to get info from fssimport.CollectionInfo first, then fsapp.CollectionInfo
                var query = @"
                    SELECT TOP 1 ComputerName, ScanPath, CollectionDateTime
                    FROM fssimport.CollectionInfo
                    WHERE InventoryID = @InventoryId
                    UNION ALL
                    SELECT TOP 1 ComputerName, ScanPath, CollectionDateTime
                    FROM fsapp.CollectionInfo
                    WHERE InventoryID = @InventoryId";

                await using var command = new SqlCommand(query, connection);
                command.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                command.Parameters.AddWithValue("@InventoryId", inventoryId);

                await using var reader = await command.ExecuteReaderAsync(cancellationToken);
                if (await reader.ReadAsync(cancellationToken))
                {
                    info.ComputerName = reader.IsDBNull(0) ? null : reader.GetString(0);
                    info.ScanPath = reader.IsDBNull(1) ? null : reader.GetString(1);
                    // Handle both DateTime and DateTimeOffset column types
                    if (!reader.IsDBNull(2))
                    {
                        var value = reader.GetValue(2);
                        info.CollectionDateTime = value switch
                        {
                            DateTime dt => dt,
                            DateTimeOffset dto => dto.DateTime,
                            _ => null
                        };
                    }
                }
            }
            catch (OperationCanceledException)
            {
                // Request was cancelled (e.g., page refresh) - this is expected behavior
                _logger.LogDebug("Request cancelled while getting info for inventory {InventoryId}", inventoryId);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Could not get info for inventory {InventoryId}", inventoryId);
            }

            // Get record count - prefer stored ImportStatistics for performance
            // (avoids running 13 COUNT queries on large tables every page view)
            if (upload?.ImportStatistics != null && upload.ImportStatistics.Any(s => s.InventoryId == inventoryId))
            {
                // Use stored statistics (fast - already calculated during import)
                info.TotalRecords = upload.ImportStatistics
                    .Where(s => s.InventoryId == inventoryId && s.TableName != "_InventoryLink")
                    .Sum(s => s.RecordsImported);
            }
            else
            {
                // Fall back to COUNT query if statistics not available
                // (e.g., for uploads imported before statistics were tracked)
                try
                {
                    await using var connection = new SqlConnection(connectionString);
                    await connection.OpenAsync(cancellationToken);

                    var countQuery = @"
                        SELECT
                            (SELECT COUNT(*) FROM fssimport.SIDs WHERE InventoryID = @InventoryId) +
                            (SELECT COUNT(*) FROM fssimport.CollectionInfo WHERE InventoryID = @InventoryId) +
                            (SELECT COUNT(*) FROM fssimport.Disks WHERE InventoryID = @InventoryId) +
                            (SELECT COUNT(*) FROM fssimport.Volumes WHERE InventoryID = @InventoryId) +
                            (SELECT COUNT(*) FROM fssimport.VolumeMounts WHERE InventoryID = @InventoryId) +
                            (SELECT COUNT(*) FROM fssimport.VolumeExtents WHERE InventoryID = @InventoryId) +
                            (SELECT COUNT(*) FROM fssimport.Partitions WHERE InventoryID = @InventoryId) +
                            (SELECT COUNT(*) FROM fssimport.Folders WHERE InventoryID = @InventoryId) +
                            (SELECT COUNT(*) FROM fssimport.ACL WHERE InventoryID = @InventoryId) +
                            (SELECT COUNT(*) FROM fssimport.ACE WHERE InventoryID = @InventoryId) +
                            (SELECT COUNT(*) FROM fssimport.SMBShares WHERE InventoryID = @InventoryId) +
                            (SELECT COUNT(*) FROM fssimport.SMBShareAccess WHERE InventoryID = @InventoryId) +
                            (SELECT COUNT(*) FROM fssimport.EventLog WHERE InventoryID = @InventoryId)
                        AS TotalRecords";

                    await using var countCmd = new SqlCommand(countQuery, connection);
                    countCmd.Parameters.AddWithValue("@InventoryId", inventoryId);
                    countCmd.CommandTimeout = 120; // 2 minutes for large datasets

                    var countResult = await countCmd.ExecuteScalarAsync(cancellationToken);
                    if (countResult != null && countResult != DBNull.Value)
                    {
                        info.TotalRecords = Convert.ToInt64(countResult);
                    }
                }
                catch (OperationCanceledException)
                {
                    // Request was cancelled (e.g., page refresh) - this is expected behavior
                    _logger.LogDebug("Request cancelled while getting record count for inventory {InventoryId}", inventoryId);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Could not get record count for inventory {InventoryId}", inventoryId);
                }
            }

            results.Add(info);
        }

        // Sort by CollectionDateTime
        return results.OrderBy(r => r.CollectionDateTime).ToList();
    }

    /// <inheritdoc/>
    public async Task<List<ADInventoryDomainInfo>> GetADInventoryDomainInfoAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var results = new List<ADInventoryDomainInfo>();

        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null || upload.UploadType != "ADInventory")
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Determine schema based on merge status
            var schema = upload.MergeStatus == "Merged" ? "ADData" : "ADImport";

            // Get domain info with record counts from CollectionInfo
            // Join with AD_Object to get record counts per domain
            var query = $@"
                SELECT
                    ci.CollectionID,
                    ci.InventoryID,
                    COALESCE(ci.DomainName, ci.ComputerName) AS DomainName,
                    ci.CollectionDateTime,
                    ISNULL(ao.ObjectCount, 0) +
                    ISNULL(gm.MembershipCount, 0) +
                    ISNULL(fsp.FspCount, 0) +
                    ISNULL(tr.TrustCount, 0) AS TotalRecords
                FROM [{schema}].[CollectionInfo] ci
                LEFT JOIN (
                    SELECT CollectionID, COUNT(*) AS ObjectCount
                    FROM [{schema}].[AD_Object]
                    GROUP BY CollectionID
                ) ao ON ci.CollectionID = ao.CollectionID
                LEFT JOIN (
                    SELECT CollectionID, COUNT(*) AS MembershipCount
                    FROM [{schema}].[AD_GroupMembership]
                    GROUP BY CollectionID
                ) gm ON ci.CollectionID = gm.CollectionID
                LEFT JOIN (
                    SELECT CollectionID, COUNT(*) AS FspCount
                    FROM [{schema}].[AD_ForeignSecurityPrincipal]
                    GROUP BY CollectionID
                ) fsp ON ci.CollectionID = fsp.CollectionID
                LEFT JOIN (
                    SELECT CollectionID, COUNT(*) AS TrustCount
                    FROM [{schema}].[AD_Trust]
                    GROUP BY CollectionID
                ) tr ON ci.CollectionID = tr.CollectionID
                WHERE ci.InventoryID IN (
                    SELECT DISTINCT InventoryId
                    FROM app.ImportStatistics
                    WHERE UploadId = @UploadId
                )
                ORDER BY DomainName";

            await using var command = new SqlCommand(query, connection);
            command.Parameters.AddWithValue("@UploadId", uploadId);
            command.CommandTimeout = 120;

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var info = new ADInventoryDomainInfo
                {
                    CollectionId = reader.GetGuid(0),
                    DomainName = reader.IsDBNull(2) ? "" : reader.GetString(2),
                    TotalRecords = reader.IsDBNull(4) ? 0 : Convert.ToInt64(reader.GetValue(4))
                };

                // Handle InventoryID (may be string or GUID)
                if (!reader.IsDBNull(1))
                {
                    var inventoryIdValue = reader.GetValue(1);
                    if (inventoryIdValue is Guid guid)
                        info.InventoryId = guid;
                    else if (Guid.TryParse(inventoryIdValue.ToString(), out var parsedGuid))
                        info.InventoryId = parsedGuid;
                }

                // Handle CollectionDateTime (may be DateTime or DateTimeOffset)
                if (!reader.IsDBNull(3))
                {
                    var dateValue = reader.GetValue(3);
                    info.CollectionDateTime = dateValue switch
                    {
                        DateTime dt => dt,
                        DateTimeOffset dto => dto.DateTime,
                        _ => null
                    };
                }

                results.Add(info);
            }

            _logger.LogDebug("Retrieved {Count} domains from {Schema}.CollectionInfo for upload {UploadId}",
                results.Count, schema, uploadId);
        }
        catch (OperationCanceledException)
        {
            // Request was cancelled (e.g., page refresh) - this is expected behavior
            _logger.LogDebug("Request cancelled while getting ADInventory domain info for upload {UploadId}", uploadId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting ADInventory domain info for upload {UploadId}", uploadId);
        }

        return results;
    }

    /// <inheritdoc/>
    public async Task<MigrationResult> ValidateAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var result = new MigrationResult();
        var inventoryIds = await GetInventoryIdsAsync(uploadId, cancellationToken);

        if (inventoryIds.Count == 0)
        {
            result.Success = false;
            result.Message = "No inventory data found for this upload.";
            return result;
        }

        // Get upload type to determine which stored procedure to use
        var uploadType = await GetUploadTypeAsync(uploadId, cancellationToken);
        var validationProc = uploadType.GetValidationProcedure();

        // For ADInventory, use only the real InventoryID (not CollectionIDs)
        // CollectionIDs are for partitioning, validation runs on InventoryID only
        if (uploadType == UploadType.ADInventory)
        {
            _logger.LogDebug("ADInventory upload - filtering to real InventoryIDs only (excluding CollectionIDs)");
            inventoryIds = await GetRealADInventoryIdsAsync(uploadId, cancellationToken);

            if (inventoryIds.Count == 0)
            {
                result.Success = false;
                result.Message = "No valid ADInventory InventoryIDs found for validation.";
                return result;
            }
        }

        _logger.LogInformation("Validation STARTED for upload {UploadId} - validating {Count} inventory(s) (Type: {UploadType})",
            uploadId, inventoryIds.Count, uploadType);

        // Log validation start to app.Logs (visible in Admin page)
        await _appLogService.LogAsync(uploadId, "Validation", "INFO",
            $"Validation started for {inventoryIds.Count} inventory(s) ({uploadType})",
            cancellationToken: CancellationToken.None);

        // Set "InProgress" status at the start so users can see validation is running
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload != null)
        {
            upload.ValidationStatus = "InProgress";
            upload.ValidationMessage = $"Validating {inventoryIds.Count} inventory(s)...";
            await _uploadRepository.UpdateAsync(upload, cancellationToken);
        }

        var connectionString = _sqlSettings.BuildConnectionString();

        // Use a timeout-based cancellation token for SQL operations instead of HTTP request token.
        // This ensures validation completes even if user navigates away from the page.
        var timeoutMinutes = _perfSettings.CommandTimeoutMinutes;
        using var sqlCts = new CancellationTokenSource(TimeSpan.FromMinutes(timeoutMinutes + 5)); // Add 5 min buffer
        var sqlToken = sqlCts.Token;

        foreach (var inventoryId in inventoryIds)
        {
            var inventoryResult = new InventoryMigrationResult { InventoryId = inventoryId };

            try
            {
                await using var connection = new SqlConnection(connectionString);
                await connection.OpenAsync(sqlToken);

                await using var command = new SqlCommand(validationProc, connection)
                {
                    CommandType = CommandType.StoredProcedure,
                    CommandTimeout = _perfSettings.CommandTimeoutSeconds
                };

                command.Parameters.AddWithValue("@InventoryID", inventoryId);
                command.Parameters.AddWithValue("@VerboseOutput", true); // Enable verbose to get error details

                var hasErrorsParam = new SqlParameter("@HasErrors", SqlDbType.Bit) { Direction = ParameterDirection.Output };
                var errorCountParam = new SqlParameter("@TotalErrorCount", SqlDbType.Int) { Direction = ParameterDirection.Output };

                command.Parameters.Add(hasErrorsParam);
                command.Parameters.Add(errorCountParam);

                // Use ExecuteReaderAsync to capture the verbose output result set
                await using var reader = await command.ExecuteReaderAsync(sqlToken);

                // Read validation error details from result set
                while (await reader.ReadAsync(sqlToken))
                {
                    var errorDetail = new ValidationErrorDetail
                    {
                        Category = reader.IsDBNull(0) ? "" : reader.GetString(0),
                        Severity = reader.IsDBNull(1) ? "" : reader.GetString(1),
                        TableName = reader.IsDBNull(2) ? "" : reader.GetString(2),
                        ErrorMessage = reader.IsDBNull(3) ? "" : reader.GetString(3),
                        AffectedCount = reader.IsDBNull(4) ? 0 : reader.GetInt32(4)
                    };
                    inventoryResult.ValidationErrors.Add(errorDetail);
                }

                // Close the reader to access output parameters
                await reader.CloseAsync();

                var hasErrors = hasErrorsParam.Value != DBNull.Value && (bool)hasErrorsParam.Value;
                var errorCount = errorCountParam.Value != DBNull.Value ? (int)errorCountParam.Value : 0;

                inventoryResult.ValidationPassed = !hasErrors;
                inventoryResult.ValidationErrorCount = errorCount;

                if (hasErrors)
                {
                    inventoryResult.ErrorMessage = $"Validation found {errorCount} error(s)";
                    result.TotalErrorCount += errorCount;

                    // Log each validation error category with details to both web log and Admin Logs
                    foreach (var error in inventoryResult.ValidationErrors.Where(e => e.Severity == "ERROR"))
                    {
                        _logger.LogWarning("Validation error for inventory {InventoryId}: [{Category}] {TableName} - {ErrorMessage} (Affected: {AffectedCount})",
                            inventoryId, error.Category, error.TableName, error.ErrorMessage, error.AffectedCount);

                        // Log to Admin Logs page (app.Logs table)
                        await _appLogService.LogAsync(uploadId, "Validation", "WARNING",
                            $"[{error.Category}] {error.TableName}: {error.ErrorMessage} ({error.AffectedCount:N0} records)",
                            cancellationToken: CancellationToken.None);
                    }

                    // Log warnings at debug level (web log only - too verbose for Admin Logs)
                    foreach (var warning in inventoryResult.ValidationErrors.Where(e => e.Severity == "WARNING"))
                    {
                        _logger.LogDebug("Validation warning for inventory {InventoryId}: [{Category}] {TableName} - {ErrorMessage} (Affected: {AffectedCount})",
                            inventoryId, warning.Category, warning.TableName, warning.ErrorMessage, warning.AffectedCount);
                    }
                }

                _logger.LogInformation("Validation for inventory {InventoryId}: {Status} ({ErrorCount} errors, {WarningCount} warnings)",
                    inventoryId, hasErrors ? "FAILED" : "PASSED", errorCount,
                    inventoryResult.ValidationErrors.Count(e => e.Severity == "WARNING"));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error validating inventory {InventoryId}", inventoryId);
                inventoryResult.ValidationPassed = false;
                inventoryResult.ErrorMessage = ex.Message;
            }

            result.InventoryResults.Add(inventoryResult);
        }

        result.Success = result.InventoryResults.All(r => r.ValidationPassed);

        // Build detailed message including error breakdown
        var failedCount = result.InventoryResults.Count(r => !r.ValidationPassed);
        if (result.Success)
        {
            result.Message = $"Validation passed for all {inventoryIds.Count} inventory(s).";
        }
        else
        {
            var errorBreakdown = result.InventoryResults
                .Where(r => !r.ValidationPassed)
                .SelectMany(r => r.ValidationErrors.Where(e => e.Severity == "ERROR"))
                .GroupBy(e => e.ErrorMessage)
                .Select(g => $"{g.Key}: {g.Sum(e => e.AffectedCount)}")
                .Take(5) // Limit to top 5 error types
                .ToList();

            result.Message = $"Validation failed for {failedCount} of {inventoryIds.Count} inventory(s). Total errors: {result.TotalErrorCount}";
            if (errorBreakdown.Any())
            {
                result.Message += $" Top issues: {string.Join("; ", errorBreakdown)}";
            }
        }

        _logger.LogInformation("Validation COMPLETED for upload {UploadId}: {Status} - {Message}",
            uploadId, result.Success ? "PASSED" : "FAILED", result.Message);

        // Log validation result to app.Logs (visible in Admin page)
        if (result.Success)
        {
            await _appLogService.LogValidationPassAsync(uploadId, CancellationToken.None);
        }
        else
        {
            await _appLogService.LogValidationFailAsync(uploadId, result.Message, CancellationToken.None);
        }

        // Update final status with retry logic (connection may be stale after long validation)
        // Use CancellationToken.None - we want this to complete even if HTTP request is canceled
        await UpdateValidationStatusWithRetryAsync(
            uploadId,
            result.Success ? "Passed" : "Failed",
            result.Message,
            CancellationToken.None);

        return result;
    }

    /// <inheritdoc/>
    public async Task<MigrationResult> MigrateAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var result = new MigrationResult();
        var inventoryIds = await GetInventoryIdsAsync(uploadId, cancellationToken);

        if (inventoryIds.Count == 0)
        {
            result.Success = false;
            result.Message = "No inventory data found for this upload.";
            return result;
        }

        // Get upload type to determine which stored procedure to use
        var uploadType = await GetUploadTypeAsync(uploadId, cancellationToken);

        // For ADInventory, use only the real InventoryID (not CollectionIDs)
        // CollectionIDs are for partitioning, migration runs on InventoryID only
        if (uploadType == UploadType.ADInventory)
        {
            _logger.LogDebug("ADInventory upload - filtering to real InventoryIDs only (excluding CollectionIDs)");
            inventoryIds = await GetRealADInventoryIdsAsync(uploadId, cancellationToken);

            if (inventoryIds.Count == 0)
            {
                result.Success = false;
                result.Message = "No valid ADInventory InventoryIDs found for merge.";
                return result;
            }
        }
        var migrationProc = uploadType.GetMigrationProcedure();
        var productionSchema = uploadType.GetProductionSchema();

        _logger.LogInformation("Migrating {Count} inventories for upload {UploadId} (Type: {UploadType})",
            inventoryIds.Count, uploadId, uploadType);

        // Log merge start to app.Logs (visible in Admin page)
        await _appLogService.LogMergeStartAsync(uploadId, CancellationToken.None);

        // Set "InProgress" status at the start so users can see merge is running
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload != null)
        {
            upload.MergeStatus = "InProgress";
            upload.MergeMessage = $"Merging {inventoryIds.Count} inventory(s)...";
            await _uploadRepository.UpdateAsync(upload, cancellationToken);
        }

        var connectionString = _sqlSettings.BuildConnectionString();

        // Use a timeout-based cancellation token for SQL operations instead of HTTP request token.
        // This ensures migration completes even if user navigates away from the page.
        var timeoutMinutes = _perfSettings.CommandTimeoutMinutes;
        using var sqlCts = new CancellationTokenSource(TimeSpan.FromMinutes(timeoutMinutes + 5)); // Add 5 min buffer
        var sqlToken = sqlCts.Token;

        // ADInventory uses CollectionID, NTFS uses InventoryID
        if (uploadType == UploadType.ADInventory)
        {
            // For ADInventory, get all CollectionIDs for this InventoryID and transfer each
            foreach (var inventoryId in inventoryIds)
            {
                var inventoryResult = new InventoryMigrationResult
                {
                    InventoryId = inventoryId,
                    ValidationPassed = true
                };

                try
                {
                    // Get CollectionIDs for this InventoryID
                    var collectionIds = await GetCollectionIdsForInventoryAsync(inventoryId, connectionString, sqlToken);

                    if (collectionIds.Count == 0)
                    {
                        inventoryResult.MigrationSuccess = false;
                        inventoryResult.ErrorMessage = "No CollectionIDs found for this InventoryID in ADImport";
                        result.InventoryResults.Add(inventoryResult);
                        continue;
                    }

                    _logger.LogInformation("Migrating {Count} CollectionIDs for InventoryID {InventoryId}",
                        collectionIds.Count, inventoryId);

                    var allSucceeded = true;
                    var errors = new List<string>();
                    var migratedCount = 0;
                    var totalCount = collectionIds.Count;

                    // Update initial status with collection count
                    await UpdateMergeProgressAsync(uploadId, migratedCount, totalCount, CancellationToken.None);

                    foreach (var collectionId in collectionIds)
                    {
                        await using var connection = new SqlConnection(connectionString);
                        await connection.OpenAsync(sqlToken);

                        // usp_ADInventory_TransferData uses different parameters:
                        // @CollectionID INT, @DeleteFromStaging BIT, @ComputeFlatMemberships BIT, @MaxRecursionDepth INT
                        await using var command = new SqlCommand(migrationProc, connection)
                        {
                            CommandType = CommandType.StoredProcedure,
                            CommandTimeout = _perfSettings.CommandTimeoutSeconds
                        };

                        command.Parameters.AddWithValue("@CollectionID", collectionId);
                        command.Parameters.AddWithValue("@DeleteFromStaging", true);
                        command.Parameters.AddWithValue("@ComputeFlatMemberships", true);
                        command.Parameters.AddWithValue("@MaxRecursionDepth", 50);

                        await command.ExecuteNonQueryAsync(sqlToken);

                        migratedCount++;
                        _logger.LogInformation("Migration for CollectionID {CollectionId}: SUCCESS ({Migrated} of {Total})",
                            collectionId, migratedCount, totalCount);

                        // Update progress after each collection (use CancellationToken.None to ensure it completes)
                        await UpdateMergeProgressAsync(uploadId, migratedCount, totalCount, CancellationToken.None);
                    }

                    // Compute collection statistics for all migrated collections (fast page rendering)
                    if (migratedCount > 0)
                    {
                        await ComputeAdCollectionStatsAsync(collectionIds, connectionString, sqlToken);
                    }

                    inventoryResult.MigrationSuccess = allSucceeded;
                    if (!allSucceeded)
                    {
                        inventoryResult.ErrorMessage = string.Join("; ", errors);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error migrating ADInventory {InventoryId}", inventoryId);
                    inventoryResult.MigrationSuccess = false;
                    inventoryResult.ErrorMessage = ex.Message;
                }

                result.InventoryResults.Add(inventoryResult);
            }
        }
        else
        {
            // NTFS Permissions - use InventoryID-based migration
            foreach (var inventoryId in inventoryIds)
            {
                var inventoryResult = new InventoryMigrationResult
                {
                    InventoryId = inventoryId,
                    ValidationPassed = true // Assuming validation was done separately
                };

                try
                {
                    await using var connection = new SqlConnection(connectionString);
                    await connection.OpenAsync(sqlToken);

                    await using var command = new SqlCommand(migrationProc, connection)
                    {
                        CommandType = CommandType.StoredProcedure,
                        CommandTimeout = _perfSettings.CommandTimeoutSeconds
                    };

                    command.Parameters.AddWithValue("@InventoryID", inventoryId);
                    command.Parameters.AddWithValue("@CleanupImport", true);
                    command.Parameters.AddWithValue("@UsePartitionedCleanup", _perfSettings.PartitioningEnabled);

                    var errorMessageParam = new SqlParameter("@ErrorMessage", SqlDbType.NVarChar, 4000)
                    {
                        Direction = ParameterDirection.Output
                    };
                    command.Parameters.Add(errorMessageParam);

                    var returnParam = new SqlParameter("@ReturnValue", SqlDbType.Int)
                    {
                        Direction = ParameterDirection.ReturnValue
                    };
                    command.Parameters.Add(returnParam);

                    await command.ExecuteNonQueryAsync(sqlToken);

                    var returnCode = returnParam.Value != DBNull.Value ? (int)returnParam.Value : -1;
                    var errorMessage = errorMessageParam.Value != DBNull.Value
                        ? errorMessageParam.Value.ToString()
                        : null;

                    inventoryResult.MigrationSuccess = returnCode == 0;
                    if (returnCode != 0)
                    {
                        inventoryResult.ErrorMessage = returnCode switch
                        {
                            1 => "InventoryID not found in import schema",
                            2 => $"InventoryID already migrated to {productionSchema} schema",
                            3 => "No InventoryID available to migrate",
                            2627 => "Data already exists in target tables (primary key violation). This collection may have already been merged.",
                            _ => errorMessage ?? $"Migration failed with code {returnCode}"
                        };
                    }
                    else
                    {
                        // Compute collection statistics for fast page rendering
                        await ComputeNtfsCollectionStatsAsync(inventoryId, connectionString, sqlToken);
                    }

                    _logger.LogInformation("Migration for inventory {InventoryId}: {Status} (code: {ReturnCode})",
                        inventoryId, returnCode == 0 ? "SUCCESS" : "FAILED", returnCode);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error migrating inventory {InventoryId}", inventoryId);
                    inventoryResult.MigrationSuccess = false;
                    inventoryResult.ErrorMessage = ex.Message;
                }

                result.InventoryResults.Add(inventoryResult);
            }
        }

        result.Success = result.InventoryResults.All(r => r.MigrationSuccess);
        var succeeded = result.InventoryResults.Count(r => r.MigrationSuccess);
        var failed = result.InventoryResults.Count(r => !r.MigrationSuccess);

        result.Message = result.Success
            ? $"Successfully migrated {succeeded} inventory(s) to {productionSchema} schema."
            : $"Migration completed: {succeeded} succeeded, {failed} failed.";

        // Determine final status
        string mergeStatus;
        if (result.Success)
            mergeStatus = "Merged";
        else if (succeeded > 0)
            mergeStatus = "PartiallyMerged";
        else
            mergeStatus = "Failed";

        // Log merge result to app.Logs (visible in Admin page)
        if (result.Success)
        {
            await _appLogService.LogMergeCompleteAsync(uploadId, CancellationToken.None);
        }
        else
        {
            await _appLogService.LogMergeFailedAsync(uploadId, result.Message, CancellationToken.None);
        }

        // Update final status with retry logic (connection may be stale after long migration)
        // Use CancellationToken.None - we want this to complete even if HTTP request is canceled
        await UpdateMergeStatusWithRetryAsync(
            uploadId,
            mergeStatus,
            result.Message,
            CancellationToken.None);

        return result;
    }

    /// <inheritdoc/>
    public async Task<MigrationResult> ValidateAndMigrateAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        // First validate
        var validationResult = await ValidateAsync(uploadId, cancellationToken);

        if (!validationResult.Success)
        {
            validationResult.Message = "Migration aborted: " + validationResult.Message;
            return validationResult;
        }

        // Then migrate
        var migrationResult = await MigrateAsync(uploadId, cancellationToken);

        // Combine results
        migrationResult.Message = $"Validation passed. {migrationResult.Message}";

        return migrationResult;
    }

    /// <inheritdoc/>
    public async Task<(bool Success, string Message)> CleanupImportDataAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        // Get the upload type to determine which cleanup path to use
        var uploadType = await GetUploadTypeAsync(uploadId, cancellationToken);

        if (uploadType == UploadType.ADInventory)
        {
            return await CleanupADInventoryDataAsync(uploadId, cancellationToken);
        }

        // NTFSPermissions cleanup (original logic)
        return await CleanupNTFSPermissionsDataAsync(uploadId, cancellationToken);
    }

    /// <summary>
    /// Cleans up ADInventory data from the ADImport schema.
    /// </summary>
    private async Task<(bool Success, string Message)> CleanupADInventoryDataAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        // For ADInventory, we need to get the real InventoryID and find all CollectionIDs
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload?.ImportStatistics == null || upload.ImportStatistics.Count == 0)
        {
            return (true, "No ADInventory data to clean up.");
        }

        // Get the InventoryID from the upload statistics
        var realInventoryId = upload.ImportStatistics
            .Select(s => s.InventoryId)
            .FirstOrDefault();

        if (realInventoryId == Guid.Empty)
        {
            return (true, "No valid InventoryID found for ADInventory cleanup.");
        }

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // First, find all CollectionIDs for this InventoryID in ADImport
            // CollectionID is now UNIQUEIDENTIFIER
            var collectionIds = new List<Guid>();
            var findCollectionsSql = @"
                SELECT CollectionID
                FROM [ADImport].[CollectionInfo]
                WHERE InventoryID = @InventoryId";

            await using (var findCmd = new SqlCommand(findCollectionsSql, connection))
            {
                findCmd.Parameters.AddWithValue("@InventoryId", realInventoryId);
                await using var reader = await findCmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    collectionIds.Add(reader.GetGuid(0));
                }
            }

            if (collectionIds.Count == 0)
            {
                _logger.LogInformation("No ADImport data found for InventoryID {InventoryId}", realInventoryId);
                return (true, "No ADInventory data found in ADImport schema (already cleaned or never imported).");
            }

            _logger.LogInformation("Cleaning up {Count} CollectionIDs from ADImport schema for upload {UploadId}",
                collectionIds.Count, uploadId);

            // Build the IN clause for collection IDs
            var collectionIdParams = string.Join(",", collectionIds.Select((id, i) => $"@cid{i}"));

            // Delete from all ADImport tables in order (no FK constraints, but delete data tables first)
            var tablesToClean = new[]
            {
                "[ADImport].[AD_ExecutionTime]",
                "[ADImport].[AD_Log]",
                "[ADImport].[AD_GroupMember_Flat]",
                "[ADImport].[AD_GroupMembership]",
                "[ADImport].[AD_ForeignSecurityPrincipal]",
                "[ADImport].[AD_Trust]",
                "[ADImport].[AD_Forest]",
                "[ADImport].[AD_Domain]",
                "[ADImport].[AD_Object]",
                "[ADImport].[CollectionInfo]"
            };

            var totalDeleted = 0;
            foreach (var table in tablesToClean)
            {
                var deleteSql = $"DELETE FROM {table} WHERE CollectionID IN ({collectionIdParams})";
                await using var deleteCmd = new SqlCommand(deleteSql, connection);
                deleteCmd.CommandTimeout = 300; // 5 minutes

                for (int i = 0; i < collectionIds.Count; i++)
                {
                    deleteCmd.Parameters.AddWithValue($"@cid{i}", collectionIds[i]);
                }

                var deleted = await deleteCmd.ExecuteNonQueryAsync(cancellationToken);
                if (deleted > 0)
                {
                    _logger.LogDebug("Deleted {Count} rows from {Table}", deleted, table);
                    totalDeleted += deleted;
                }
            }

            _logger.LogInformation("Cleaned up ADImport data for upload {UploadId}: {TotalDeleted} total rows deleted across {CollectionCount} collections",
                uploadId, totalDeleted, collectionIds.Count);

            return (true, $"Successfully cleaned up {collectionIds.Count} collection(s) from ADImport schema ({totalDeleted} total rows).");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error cleaning up ADImport data for upload {UploadId}", uploadId);
            return (false, $"Failed to clean up ADInventory data: {ex.Message}");
        }
    }

    /// <summary>
    /// Gets the real InventoryIDs for an ADInventory upload by querying ADImport.CollectionInfo directly.
    /// With GUID-based CollectionIDs, this queries based on all InventoryIDs from ImportStatistics.
    /// </summary>
    private async Task<List<Guid>> GetRealADInventoryIdsAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var results = new List<Guid>();
        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
            if (upload?.ImportStatistics == null || upload.ImportStatistics.Count == 0)
                return results;

            // Get all InventoryIDs from ImportStatistics
            var inventoryIds = upload.ImportStatistics
                .Select(s => s.InventoryId)
                .Where(id => id != Guid.Empty)
                .Distinct()
                .ToList();

            if (inventoryIds.Count == 0)
                return results;

            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Query InventoryIDs that exist in ADImport.CollectionInfo
            var inventoryIdParams = string.Join(",", inventoryIds.Select((_, i) => $"@iid{i}"));
            var query = $@"
                SELECT DISTINCT InventoryID
                FROM [ADImport].[CollectionInfo]
                WHERE InventoryID IN ({inventoryIdParams})";

            await using var command = new SqlCommand(query, connection);
            for (int i = 0; i < inventoryIds.Count; i++)
            {
                command.Parameters.AddWithValue($"@iid{i}", inventoryIds[i]);
            }

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                if (!reader.IsDBNull(0))
                {
                    results.Add(reader.GetGuid(0));
                }
            }

            _logger.LogInformation("Retrieved {Count} InventoryID(s) from ADImport.CollectionInfo for upload {UploadId}",
                results.Count, uploadId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving ADInventory InventoryIDs for upload {UploadId}", uploadId);
        }

        return results;
    }

    /// <summary>
    /// Updates the merge progress message for an upload.
    /// </summary>
    private async Task UpdateMergeProgressAsync(Guid uploadId, int migratedCount, int totalCount, CancellationToken cancellationToken)
    {
        try
        {
            var message = migratedCount == 0
                ? $"Starting merge of {totalCount} collection(s)..."
                : $"Merged {migratedCount} of {totalCount} collection(s)...";

            // Use direct SQL for reliability during long-running operations
            var connectionString = _sqlSettings.BuildConnectionString();
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                UPDATE app.Uploads
                SET MergeMessage = @Message
                WHERE UploadId = @UploadId";

            await using var command = new SqlCommand(query, connection);
            command.Parameters.AddWithValue("@UploadId", uploadId);
            command.Parameters.AddWithValue("@Message", message);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            // Log but don't fail - progress updates are nice-to-have
            _logger.LogWarning(ex, "Failed to update merge progress for upload {UploadId}", uploadId);
        }
    }

    /// <summary>
    /// Gets all CollectionIDs for an ADInventory InventoryID from ADImport.CollectionInfo.
    /// Both CollectionID and InventoryID are now UNIQUEIDENTIFIER.
    /// </summary>
    private async Task<List<Guid>> GetCollectionIdsForInventoryAsync(Guid inventoryId, string connectionString, CancellationToken cancellationToken)
    {
        var results = new List<Guid>();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                SELECT CollectionID
                FROM [ADImport].[CollectionInfo]
                WHERE InventoryID = @InventoryId
                ORDER BY CollectionID";

            await using var command = new SqlCommand(query, connection);
            command.Parameters.AddWithValue("@InventoryId", inventoryId);

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add(reader.GetGuid(0));
            }

            _logger.LogDebug("Found {Count} CollectionID(s) for InventoryID {InventoryId} in ADImport.CollectionInfo",
                results.Count, inventoryId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving CollectionIDs for InventoryID {InventoryId}", inventoryId);
        }

        return results;
    }

    /// <summary>
    /// Cleans up NTFSPermissions data from the fssimport schema.
    /// Uses partition-aware cleanup if partitioning is enabled for faster deletion.
    /// </summary>
    private async Task<(bool Success, string Message)> CleanupNTFSPermissionsDataAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var inventoryIds = await GetInventoryIdsAsync(uploadId, cancellationToken);

        if (inventoryIds.Count == 0)
        {
            return (true, "No inventory data to clean up.");
        }

        _logger.LogInformation("Cleaning up {Count} inventories from fssimport schema for upload {UploadId} (Partitioning: {PartitioningEnabled})",
            inventoryIds.Count, uploadId, _perfSettings.PartitioningEnabled);

        var connectionString = _sqlSettings.BuildConnectionString();
        var successCount = 0;
        var failedCount = 0;
        var errors = new List<string>();

        // Choose the appropriate stored procedure based on partitioning configuration
        var cleanupProc = _perfSettings.PartitioningEnabled
            ? "dbo.usp_CleanupImportedCollection_Partitioned"
            : "dbo.usp_CleanupImportedCollection";

        foreach (var inventoryId in inventoryIds)
        {
            try
            {
                await using var connection = new SqlConnection(connectionString);
                await connection.OpenAsync(cancellationToken);

                await using var command = new SqlCommand(cleanupProc, connection)
                {
                    CommandType = CommandType.StoredProcedure,
                    CommandTimeout = 300 // 5 minutes
                };

                command.Parameters.AddWithValue("@InventoryID", inventoryId);
                command.Parameters.AddWithValue("@Force", true); // Force cleanup even if not migrated

                var errorMessageParam = new SqlParameter("@ErrorMessage", SqlDbType.NVarChar, 4000)
                {
                    Direction = ParameterDirection.Output
                };
                command.Parameters.Add(errorMessageParam);

                var returnParam = new SqlParameter("@ReturnValue", SqlDbType.Int)
                {
                    Direction = ParameterDirection.ReturnValue
                };
                command.Parameters.Add(returnParam);

                await command.ExecuteNonQueryAsync(cancellationToken);

                var returnCode = returnParam.Value != DBNull.Value ? (int)returnParam.Value : -1;
                var errorMessage = errorMessageParam.Value != DBNull.Value
                    ? errorMessageParam.Value.ToString()
                    : null;

                if (returnCode == 0)
                {
                    successCount++;
                    _logger.LogInformation("Cleaned up import data for inventory {InventoryId}", inventoryId);
                }
                else if (returnCode == 1)
                {
                    // Not found in fssimport - already cleaned or never imported
                    successCount++;
                    _logger.LogInformation("Inventory {InventoryId} not found in fssimport (already cleaned)", inventoryId);
                }
                else
                {
                    failedCount++;
                    var error = $"Inventory {inventoryId}: {errorMessage ?? $"Error code {returnCode}"}";
                    errors.Add(error);
                    _logger.LogWarning("Failed to cleanup inventory {InventoryId}: {Error}", inventoryId, errorMessage);
                }
            }
            catch (SqlException ex) when (ex.Number == 2812 && _perfSettings.PartitioningEnabled)
            {
                // Partitioned proc not found, fall back to non-partitioned
                _logger.LogWarning("Partitioned cleanup proc not found, falling back to standard cleanup for {InventoryId}", inventoryId);
                var fallbackResult = await CleanupInventoryWithFallbackAsync(inventoryId, connectionString, cancellationToken);
                if (fallbackResult.Success)
                    successCount++;
                else
                {
                    failedCount++;
                    errors.Add($"Inventory {inventoryId}: {fallbackResult.Message}");
                }
            }
            catch (Exception ex)
            {
                failedCount++;
                errors.Add($"Inventory {inventoryId}: {ex.Message}");
                _logger.LogError(ex, "Error cleaning up inventory {InventoryId}", inventoryId);
            }
        }

        if (failedCount == 0)
        {
            return (true, $"Successfully cleaned up {successCount} inventory(s) from fssimport schema.");
        }
        else if (successCount > 0)
        {
            return (false, $"Partially cleaned up: {successCount} succeeded, {failedCount} failed. Errors: {string.Join("; ", errors)}");
        }
        else
        {
            return (false, $"Failed to clean up import data: {string.Join("; ", errors)}");
        }
    }

    /// <summary>
    /// Fallback cleanup method using non-partitioned stored procedure.
    /// </summary>
    private async Task<(bool Success, string Message)> CleanupInventoryWithFallbackAsync(
        Guid inventoryId,
        string connectionString,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = new SqlCommand("dbo.usp_CleanupImportedCollection", connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 300
            };

            command.Parameters.AddWithValue("@InventoryID", inventoryId);
            command.Parameters.AddWithValue("@Force", true);

            var errorMessageParam = new SqlParameter("@ErrorMessage", SqlDbType.NVarChar, 4000)
            {
                Direction = ParameterDirection.Output
            };
            command.Parameters.Add(errorMessageParam);

            var returnParam = new SqlParameter("@ReturnValue", SqlDbType.Int)
            {
                Direction = ParameterDirection.ReturnValue
            };
            command.Parameters.Add(returnParam);

            await command.ExecuteNonQueryAsync(cancellationToken);

            var returnCode = returnParam.Value != DBNull.Value ? (int)returnParam.Value : -1;
            var errorMessage = errorMessageParam.Value != DBNull.Value
                ? errorMessageParam.Value.ToString()
                : null;

            if (returnCode == 0 || returnCode == 1)
            {
                return (true, "Cleaned successfully");
            }
            return (false, errorMessage ?? $"Error code {returnCode}");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }

    /// <inheritdoc/>
    public async Task<List<OrphanedInventoryInfo>> GetOrphanedInventoriesAsync(CancellationToken cancellationToken)
    {
        var results = new List<OrphanedInventoryInfo>();

        if (!_sqlSettings.IsConfigured)
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Find inventories in fssimport.CollectionInfo that don't have a matching record in app.ImportStatistics
            var query = @"
                SELECT
                    c.InventoryID,
                    c.ComputerName,
                    c.ScanPath,
                    c.CollectionDateTime,
                    (SELECT COUNT(*) FROM fssimport.Folders f WHERE f.InventoryID = c.InventoryID) AS FoldersCount,
                    (SELECT COUNT(*) FROM fssimport.ACL acl WHERE acl.InventoryID = c.InventoryID) AS FilesCount,
                    (SELECT COUNT(*) FROM fssimport.ACE ace WHERE ace.InventoryID = c.InventoryID) AS PermissionsCount
                FROM fssimport.CollectionInfo c
                WHERE NOT EXISTS (
                    SELECT 1 FROM app.ImportStatistics s WHERE s.InventoryId = c.InventoryID
                )
                ORDER BY c.CollectionDateTime DESC";

            await using var command = new SqlCommand(query, connection);
            command.CommandTimeout = 120;

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var info = new OrphanedInventoryInfo
                {
                    InventoryId = reader.GetGuid(0),
                    ComputerName = reader.IsDBNull(1) ? null : reader.GetString(1),
                    ScanPath = reader.IsDBNull(2) ? null : reader.GetString(2),
                    FoldersCount = reader.IsDBNull(4) ? 0 : reader.GetInt32(4),
                    FilesCount = reader.IsDBNull(5) ? 0 : reader.GetInt32(5),
                    PermissionsCount = reader.IsDBNull(6) ? 0 : reader.GetInt32(6)
                };

                // Handle DateTimeOffset
                if (!reader.IsDBNull(3))
                {
                    var value = reader.GetValue(3);
                    info.CollectionDateTime = value switch
                    {
                        DateTime dt => dt,
                        DateTimeOffset dto => dto.DateTime,
                        _ => null
                    };
                }

                results.Add(info);
            }

            _logger.LogInformation("Found {Count} orphaned inventories in fssimport schema", results.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error querying for orphaned inventories");
        }

        return results;
    }

    /// <inheritdoc/>
    public async Task<(bool Success, string Message)> CleanupOrphanedInventoryAsync(Guid inventoryId, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Cleaning up orphaned inventory {InventoryId} from fssimport schema (Partitioning: {PartitioningEnabled})",
            inventoryId, _perfSettings.PartitioningEnabled);

        var connectionString = _sqlSettings.BuildConnectionString();

        // Choose the appropriate stored procedure based on partitioning configuration
        var cleanupProc = _perfSettings.PartitioningEnabled
            ? "dbo.usp_CleanupImportedCollection_Partitioned"
            : "dbo.usp_CleanupImportedCollection";

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = new SqlCommand(cleanupProc, connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 300
            };

            command.Parameters.AddWithValue("@InventoryID", inventoryId);
            command.Parameters.AddWithValue("@Force", true);

            var errorMessageParam = new SqlParameter("@ErrorMessage", SqlDbType.NVarChar, 4000)
            {
                Direction = ParameterDirection.Output
            };
            command.Parameters.Add(errorMessageParam);

            var returnParam = new SqlParameter("@ReturnValue", SqlDbType.Int)
            {
                Direction = ParameterDirection.ReturnValue
            };
            command.Parameters.Add(returnParam);

            await command.ExecuteNonQueryAsync(cancellationToken);

            var returnCode = returnParam.Value != DBNull.Value ? (int)returnParam.Value : -1;
            var errorMessage = errorMessageParam.Value != DBNull.Value
                ? errorMessageParam.Value.ToString()
                : null;

            if (returnCode == 0 || returnCode == 1)
            {
                _logger.LogInformation("Successfully cleaned up orphaned inventory {InventoryId}", inventoryId);
                return (true, $"Successfully cleaned up orphaned inventory data.");
            }
            else
            {
                _logger.LogWarning("Failed to cleanup orphaned inventory {InventoryId}: {Error}", inventoryId, errorMessage);
                return (false, errorMessage ?? $"Cleanup failed with code {returnCode}");
            }
        }
        catch (SqlException ex) when (ex.Number == 2812 && _perfSettings.PartitioningEnabled)
        {
            // Partitioned proc not found, fall back to non-partitioned
            _logger.LogWarning("Partitioned cleanup proc not found, falling back to standard cleanup for orphaned inventory {InventoryId}", inventoryId);
            return await CleanupInventoryWithFallbackAsync(inventoryId, connectionString, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error cleaning up orphaned inventory {InventoryId}", inventoryId);
            return (false, ex.Message);
        }
    }

    /// <inheritdoc/>
    public async Task<(int Cleaned, int Failed, string Message)> CleanupAllOrphanedInventoriesAsync(CancellationToken cancellationToken)
    {
        var orphaned = await GetOrphanedInventoriesAsync(cancellationToken);

        if (orphaned.Count == 0)
        {
            return (0, 0, "No orphaned inventories found.");
        }

        _logger.LogInformation("Cleaning up {Count} orphaned inventories", orphaned.Count);

        var cleaned = 0;
        var failed = 0;
        var errors = new List<string>();

        foreach (var inventory in orphaned)
        {
            var (success, message) = await CleanupOrphanedInventoryAsync(inventory.InventoryId, cancellationToken);
            if (success)
            {
                cleaned++;
            }
            else
            {
                failed++;
                errors.Add($"{inventory.InventoryId}: {message}");
            }
        }

        var resultMessage = failed == 0
            ? $"Successfully cleaned up {cleaned} orphaned inventory(s)."
            : $"Cleaned {cleaned}, failed {failed}. Errors: {string.Join("; ", errors.Take(3))}";

        return (cleaned, failed, resultMessage);
    }

    /// <summary>
    /// Computes collection statistics for an NTFS collection after successful migration.
    /// This updates the fsapp.CollectionStats table for fast page rendering.
    /// </summary>
    private async Task ComputeNtfsCollectionStatsAsync(Guid inventoryId, string connectionString, CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = new SqlCommand("dbo.usp_fsapp_ComputeCollectionStats", connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 120 // 2 minutes should be sufficient for stats computation
            };

            command.Parameters.AddWithValue("@InventoryID", inventoryId);
            command.Parameters.AddWithValue("@ForceRecalculate", false); // Only compute if missing

            await command.ExecuteNonQueryAsync(cancellationToken);

            _logger.LogDebug("Computed NTFS collection stats for InventoryID {InventoryId}", inventoryId);
        }
        catch (SqlException ex) when (ex.Number == 2812)
        {
            // Stored procedure doesn't exist yet (migration 015 not applied)
            _logger.LogDebug("usp_fsapp_ComputeCollectionStats not found - stats computation skipped for {InventoryId}", inventoryId);
        }
        catch (Exception ex)
        {
            // Log but don't fail the migration - stats are nice-to-have
            _logger.LogWarning(ex, "Failed to compute NTFS collection stats for {InventoryId}", inventoryId);
        }
    }

    /// <summary>
    /// Computes collection statistics for AD collections after successful migration.
    /// This updates the ADData.CollectionStats table for fast page rendering.
    /// </summary>
    private async Task ComputeAdCollectionStatsAsync(IEnumerable<Guid> collectionIds, string connectionString, CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            foreach (var collectionId in collectionIds)
            {
                await using var command = new SqlCommand("dbo.usp_ADData_ComputeCollectionStats", connection)
                {
                    CommandType = CommandType.StoredProcedure,
                    CommandTimeout = 120 // 2 minutes should be sufficient for stats computation
                };

                command.Parameters.AddWithValue("@CollectionID", collectionId);
                command.Parameters.AddWithValue("@ForceRecalculate", false); // Only compute if missing

                await command.ExecuteNonQueryAsync(cancellationToken);

                _logger.LogDebug("Computed AD collection stats for CollectionID {CollectionId}", collectionId);
            }
        }
        catch (SqlException ex) when (ex.Number == 2812)
        {
            // Stored procedure doesn't exist yet (migration 015 not applied)
            _logger.LogDebug("usp_ADData_ComputeCollectionStats not found - stats computation skipped");
        }
        catch (Exception ex)
        {
            // Log but don't fail the migration - stats are nice-to-have
            _logger.LogWarning(ex, "Failed to compute AD collection stats");
        }
    }
}
