using Hangfire;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Data.Repositories;
using System.Data;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for cleaning up import data from staging schemas (fssimport/ADImport).
/// This job cleans up staging data without deleting the upload record or files.
/// </summary>
public interface IImportDataCleanupJob
{
    /// <summary>
    /// Cleans up import data for an upload from staging schema with progress reporting.
    /// </summary>
    [JobDisplayName("Cleanup Import Data: {0}")]
    [AutomaticRetry(Attempts = 0)]
    [Queue("deletion")]
    Task CleanupImportDataAsync(Guid uploadId, string initiatedBy, CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of import data cleanup job with progress reporting.
/// </summary>
public class ImportDataCleanupJob : IImportDataCleanupJob
{
    private readonly ILogger<ImportDataCleanupJob> _logger;
    private readonly IUploadRepository _uploadRepository;
    private readonly SqlServerSettings _sqlSettings;
    private readonly DatabasePerformanceSettings _perfSettings;
    private readonly IHubNotifier? _hubNotifier;

    public ImportDataCleanupJob(
        ILogger<ImportDataCleanupJob> logger,
        IUploadRepository uploadRepository,
        SqlServerSettings sqlSettings,
        DatabasePerformanceSettings perfSettings,
        IHubNotifier? hubNotifier = null)
    {
        _logger = logger;
        _uploadRepository = uploadRepository;
        _sqlSettings = sqlSettings;
        _perfSettings = perfSettings;
        _hubNotifier = hubNotifier;
    }

    /// <inheritdoc/>
    public async Task CleanupImportDataAsync(Guid uploadId, string initiatedBy, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting import data cleanup for {UploadId} initiated by {User}",
            uploadId, initiatedBy);

        await SendProgressAsync(uploadId, "Starting", "", 0, "Initializing cleanup...");

        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null)
        {
            await SendProgressAsync(uploadId, "Failed", "", 0, "Upload not found");
            _logger.LogWarning("Upload {UploadId} not found for import data cleanup", uploadId);
            return;
        }

        // Determine upload type
        var isADInventory = upload.UploadType == "ADInventory";

        try
        {
            if (isADInventory)
            {
                await CleanupADInventoryDataAsync(uploadId, upload, cancellationToken);
            }
            else
            {
                await CleanupNTFSPermissionsDataAsync(uploadId, upload, cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("Import data cleanup cancelled for {UploadId}", uploadId);
            await SendProgressAsync(uploadId, "Failed", "", 0, "Cleanup cancelled");
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error cleaning up import data for {UploadId}", uploadId);
            await SendProgressAsync(uploadId, "Failed", "", 0, $"Error: {ex.Message}");
            throw;
        }
    }

    private async Task CleanupADInventoryDataAsync(Guid uploadId, Data.Entities.Upload upload, CancellationToken cancellationToken)
    {
        await SendProgressAsync(uploadId, "Cleaning", "ADImport", 10, "Finding ADImport collections...");

        if (upload.ImportStatistics == null || upload.ImportStatistics.Count == 0)
        {
            await SendProgressAsync(uploadId, "Completed", "", 100, "No ADInventory data to clean up");
            _logger.LogInformation("No ADInventory data found to clean up for upload {UploadId}", uploadId);
            return;
        }

        // Get the InventoryID from the upload statistics
        var realInventoryId = upload.ImportStatistics
            .Select(s => s.InventoryId)
            .FirstOrDefault();

        if (realInventoryId == Guid.Empty)
        {
            await SendProgressAsync(uploadId, "Completed", "", 100, "No valid InventoryID found for cleanup");
            return;
        }

        var connectionString = _sqlSettings.BuildConnectionString();

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        // Find all CollectionIDs for this InventoryID in ADImport
        var collectionIds = new List<int>();
        var findCollectionsSql = @"
            SELECT CollectionID
            FROM [ADImport].[CollectionInfo]
            WHERE InventoryID = @InventoryId";

        await using (var findCmd = new SqlCommand(findCollectionsSql, connection))
        {
            findCmd.Parameters.AddWithValue("@InventoryId", realInventoryId.ToString());
            await using var reader = await findCmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                collectionIds.Add(reader.GetInt32(0));
            }
        }

        if (collectionIds.Count == 0)
        {
            await SendProgressAsync(uploadId, "Completed", "", 100,
                "No ADImport data found (already cleaned or never imported)");
            _logger.LogInformation("No ADImport data found for InventoryID {InventoryId}", realInventoryId);
            return;
        }

        _logger.LogInformation("Cleaning up {Count} CollectionIDs from ADImport schema for upload {UploadId}",
            collectionIds.Count, uploadId);

        // Build the IN clause for collection IDs
        var collectionIdParams = string.Join(",", collectionIds.Select((id, i) => $"@cid{i}"));

        // ADImport tables to clean in order
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
        var tableIndex = 0;

        foreach (var table in tablesToClean)
        {
            tableIndex++;
            var progress = 20 + (int)(tableIndex * 70.0 / tablesToClean.Length);

            await SendProgressAsync(uploadId, "Cleaning", table, progress,
                $"Cleaning {table}... ({totalDeleted:N0} rows deleted so far)");

            var deleteSql = $"DELETE FROM {table} WHERE CollectionID IN ({collectionIdParams})";
            await using var deleteCmd = new SqlCommand(deleteSql, connection);
            deleteCmd.CommandTimeout = 600; // 10 minutes

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

        await SendProgressAsync(uploadId, "Completed", "", 100,
            $"Successfully cleaned up {collectionIds.Count} collection(s) ({totalDeleted:N0} total rows)");

        _logger.LogInformation("Cleaned up ADImport data for upload {UploadId}: {TotalDeleted} total rows",
            uploadId, totalDeleted);
    }

    private async Task CleanupNTFSPermissionsDataAsync(Guid uploadId, Data.Entities.Upload upload, CancellationToken cancellationToken)
    {
        await SendProgressAsync(uploadId, "Cleaning", "fssimport", 10, "Finding inventories to clean...");

        if (upload.ImportStatistics == null || upload.ImportStatistics.Count == 0)
        {
            await SendProgressAsync(uploadId, "Completed", "", 100, "No NTFS data to clean up");
            _logger.LogInformation("No NTFS data found to clean up for upload {UploadId}", uploadId);
            return;
        }

        var inventoryIds = upload.ImportStatistics
            .Select(s => s.InventoryId)
            .Distinct()
            .ToList();

        if (inventoryIds.Count == 0)
        {
            await SendProgressAsync(uploadId, "Completed", "", 100, "No inventory data found");
            return;
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

        for (int i = 0; i < inventoryIds.Count; i++)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var inventoryId = inventoryIds[i];
            var progress = 20 + (int)((i + 1) * 70.0 / inventoryIds.Count);

            await SendProgressAsync(uploadId, "Cleaning", inventoryId.ToString(), progress,
                $"Cleaning inventory {i + 1} of {inventoryIds.Count}...");

            try
            {
                await using var connection = new SqlConnection(connectionString);
                await connection.OpenAsync(cancellationToken);

                await using var command = new SqlCommand(cleanupProc, connection)
                {
                    CommandType = CommandType.StoredProcedure,
                    CommandTimeout = 600 // 10 minutes
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
                    _logger.LogDebug("Cleaned up import data for inventory {InventoryId}", inventoryId);
                }
                else if (returnCode == 1)
                {
                    // Not found in fssimport - already cleaned or never imported
                    successCount++;
                    _logger.LogDebug("Inventory {InventoryId} not found in fssimport (already cleaned)", inventoryId);
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

        var finalMessage = failedCount == 0
            ? $"Successfully cleaned up {successCount} inventory(s)"
            : $"Cleaned {successCount}, failed {failedCount}. Errors: {string.Join("; ", errors.Take(3))}";

        await SendProgressAsync(uploadId, "Completed", "", 100, finalMessage);

        _logger.LogInformation("Import data cleanup completed for upload {UploadId}: {Success} cleaned, {Failed} failed",
            uploadId, successCount, failedCount);
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
                CommandTimeout = 600
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

    private async Task SendProgressAsync(Guid id, string phase, string currentTable, int percent, string message)
    {
        if (_hubNotifier != null)
        {
            await _hubNotifier.SendProgressAsync(id, phase, currentTable, percent, message);
        }
    }
}
