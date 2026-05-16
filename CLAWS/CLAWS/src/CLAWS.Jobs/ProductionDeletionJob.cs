using Hangfire;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Jobs.Filters;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for deleting production collections with progress reporting.
/// </summary>
public interface IProductionDeletionJob
{
    /// <summary>
    /// Deletes an NTFS collection from fsapp schema with progress reporting.
    /// </summary>
    [JobDisplayName("Delete NTFS Collection: {0}")]
    [AutomaticRetry(Attempts = 0)]
    [Queue("deletion")]
    [ConfigurableDisableConcurrentExecution] // Timeout configured via AppSettings.JobTimeouts.DeletionMinutes
    Task DeleteNtfsCollectionAsync(Guid inventoryId, string initiatedBy, CancellationToken cancellationToken);

    /// <summary>
    /// Deletes an AD collection from ADData schema with progress reporting.
    /// </summary>
    [JobDisplayName("Delete AD Collection: {0}")]
    [AutomaticRetry(Attempts = 0)]
    [Queue("ad-deletion")]
    [ConfigurableDisableConcurrentExecution] // Timeout configured via AppSettings.JobTimeouts.DeletionMinutes
    Task DeleteAdCollectionAsync(Guid collectionId, string initiatedBy, CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of production deletion job with batch processing and progress reporting.
/// </summary>
public class ProductionDeletionJob : IProductionDeletionJob
{
    private readonly ILogger<ProductionDeletionJob> _logger;
    private readonly SqlServerSettings _sqlSettings;
    private readonly DatabasePerformanceSettings _perfSettings;
    private readonly IHubNotifier? _hubNotifier;

    // NTFS tables in deletion order (children first)
    private static readonly string[] NtfsTablesToDelete = new[]
    {
        "fsapp.EventLog",
        "fsapp.SMBShareAccess",
        "fsapp.SMBShares",
        "fsapp.ACE",
        "fsapp.ACL",
        "fsapp.Folders",
        "fsapp.Partitions",
        "fsapp.VolumeExtents",
        "fsapp.VolumeMounts",
        "fsapp.Volumes",
        "fsapp.Disks",
        "fsapp.SIDs",
        "fsapp.CollectionInfo"
    };

    // Tables to count for progress reporting
    private static readonly string[] AdTablesToCount = new[]
    {
        "ADData.AD_ExecutionTime",
        "ADData.AD_Log",
        "ADData.AD_Forest",
        "ADData.AD_Domain",
        "ADData.AD_Trust",
        "ADData.AD_ForeignSecurityPrincipal",
        "ADData.AD_FlattenStats",
        "ADData.AD_GroupMember_Flat",
        "ADData.AD_GroupMembership",
        "ADData.AD_Object",
        "ADData.CollectionInfo"
    };

    // Tables to delete in order (child tables first, then parent)
    // Explicit deletion is more reliable than CASCADE which may not work with partitioned tables
    private static readonly string[] AdTablesToDelete = new[]
    {
        "ADData.AD_ExecutionTime",
        "ADData.AD_Log",
        "ADData.AD_FlattenStats",
        "ADData.AD_GroupMember_Flat",
        "ADData.AD_GroupMembership",
        "ADData.AD_ForeignSecurityPrincipal",
        "ADData.AD_Trust",
        "ADData.AD_Forest",
        "ADData.AD_Domain",
        "ADData.AD_Object",
        "ADData.CollectionInfo"  // Parent table last
    };

    public ProductionDeletionJob(
        ILogger<ProductionDeletionJob> logger,
        SqlServerSettings sqlSettings,
        DatabasePerformanceSettings perfSettings,
        IHubNotifier? hubNotifier = null)
    {
        _logger = logger;
        _sqlSettings = sqlSettings;
        _perfSettings = perfSettings;
        _hubNotifier = hubNotifier;
    }

    /// <inheritdoc/>
    public async Task DeleteNtfsCollectionAsync(Guid inventoryId, string initiatedBy, CancellationToken cancellationToken)
    {
        _logger.LogWarning("Starting NTFS collection deletion job for {InventoryId} initiated by {User}",
            inventoryId, initiatedBy);

        await SendProgressAsync(inventoryId, "Starting", "", 0, "Initializing deletion...");

        var connectionString = _sqlSettings.BuildConnectionString();
        var totalDeleted = 0L;

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Use partition-aware deletion if partitioning is enabled
            if (_perfSettings.PartitioningEnabled)
            {
                await DeleteNtfsCollectionWithPartitioningAsync(connection, inventoryId, cancellationToken);
                return;
            }

            // Fall back to batched deletion when partitioning is not enabled
            var tableIndex = 0;
            var totalTables = NtfsTablesToDelete.Length;

            // Delete table by table WITHOUT a transaction
            // This is more resilient for large datasets - if it fails partway through,
            // re-running the job will continue from where it left off
            foreach (var table in NtfsTablesToDelete)
            {
                tableIndex++;
                var basePercent = (int)((tableIndex - 1) * 100.0 / totalTables);

                await SendProgressAsync(inventoryId, "Deleting", table, basePercent,
                    $"Deleting from {table}...");

                // Delete in batches to avoid lock escalation and timeout issues
                var batchSize = _perfSettings.DeletionBatchSize;
                var deletedFromTable = 0L;
                int deletedInBatch;

                // Special handling for self-referential Folders table
                // Must delete leaf nodes (folders with no children) first
                var isFoldersTable = table.Equals("fsapp.Folders", StringComparison.OrdinalIgnoreCase);

                do
                {
                    cancellationToken.ThrowIfCancellationRequested();

                    string deleteQuery;
                    if (isFoldersTable)
                    {
                        // Delete only folders that have no child folders (leaf nodes first)
                        // This respects the self-referential FK constraint
                        // FK references: (InventoryID, ParentFolderID) -> (InventoryID, LocalFolderID)
                        deleteQuery = $@"
                            DELETE TOP ({batchSize}) f FROM fsapp.Folders f
                            WHERE f.InventoryID = @InventoryId
                            AND NOT EXISTS (
                                SELECT 1 FROM fsapp.Folders child
                                WHERE child.ParentFolderID = f.LocalFolderID
                                AND child.InventoryID = @InventoryId
                            )";
                    }
                    else
                    {
                        deleteQuery = $@"
                            DELETE TOP ({batchSize}) FROM {table}
                            WHERE InventoryID = @InventoryId";
                    }

                    await using var cmd = new SqlCommand(deleteQuery, connection);
                    cmd.CommandTimeout = 300; // 5 minutes per batch should be plenty
                    cmd.Parameters.AddWithValue("@InventoryId", inventoryId);

                    deletedInBatch = await cmd.ExecuteNonQueryAsync(cancellationToken);
                    deletedFromTable += deletedInBatch;
                    totalDeleted += deletedInBatch;

                    if (deletedInBatch > 0)
                    {
                        // Calculate progress within this table
                        var tableProgressPercent = basePercent + (int)((tableIndex * 100.0 / totalTables) - basePercent) / 2;
                        await SendProgressAsync(inventoryId, "Deleting", table, Math.Min(99, tableProgressPercent),
                            $"Deleted {deletedFromTable:N0} rows from {table}...");
                    }

                    // For self-referential Folders table, continue while ANY rows are deleted
                    // (leaf-node query returns varying counts as hierarchy is traversed)
                    // For other tables, continue while batch is full
                } while (isFoldersTable ? deletedInBatch > 0 : deletedInBatch == batchSize);

                if (deletedFromTable > 0)
                {
                    _logger.LogDebug("Deleted {Count} rows from {Table}", deletedFromTable, table);
                }
            }

            await SendProgressAsync(inventoryId, "Completed", "", 100,
                $"Successfully deleted {totalDeleted:N0} records");

            _logger.LogInformation(
                "Successfully deleted NTFS collection {InventoryId}: {TotalDeleted} total rows",
                inventoryId, totalDeleted);
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("NTFS collection deletion cancelled for {InventoryId}. Deleted {TotalDeleted} rows before cancellation.",
                inventoryId, totalDeleted);
            await SendProgressAsync(inventoryId, "Failed", "", 0, $"Cancelled after deleting {totalDeleted:N0} records");
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting NTFS collection {InventoryId}. Deleted {TotalDeleted} rows before error.",
                inventoryId, totalDeleted);
            await SendProgressAsync(inventoryId, "Failed", "", 0, $"Error after {totalDeleted:N0} records: {ex.Message}");
            throw;
        }
    }

    /// <inheritdoc/>
    public async Task DeleteAdCollectionAsync(Guid collectionId, string initiatedBy, CancellationToken cancellationToken)
    {
        _logger.LogWarning("Starting AD collection deletion job for {CollectionId} initiated by {User}",
            collectionId, initiatedBy);

        // CollectionID is now a GUID, use it directly for progress tracking
        var progressId = collectionId;

        await SendProgressAsync(progressId, "Starting", "", 0, "Initializing deletion...");

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // NOTE: ADData tables use pf_CollectionID/ps_CollectionID, but the partition deletion
            // stored procedure (usp_Partition_DeleteCollection_Fast) is hardcoded for pf_InventoryID.
            // Until the SP is updated, we use explicit table-by-table DELETE for AD collections.
            // TODO: Update usp_Partition_DeleteCollection_Fast to accept partition function/scheme names
            // Count records first for progress reporting
            await SendProgressAsync(progressId, "Counting", "", 5, "Counting records...");

            var totalRecords = 0L;
            foreach (var table in AdTablesToCount)
            {
                var countQuery = table == "ADData.CollectionInfo"
                    ? $"SELECT COUNT(*) FROM {table} WHERE CollectionID = @CollectionId"
                    : $"SELECT COUNT(*) FROM {table} WHERE CollectionID = @CollectionId";

                await using var countCmd = new SqlCommand(countQuery, connection);
                countCmd.CommandTimeout = 120;
                countCmd.Parameters.AddWithValue("@CollectionId", collectionId);
                totalRecords += Convert.ToInt64(await countCmd.ExecuteScalarAsync(cancellationToken));
            }

            // Delete from all tables explicitly (child tables first, then parent)
            // This is more reliable than CASCADE which may not work with partitioned tables
            var deletedTotal = 0L;
            var tableIndex = 0;
            foreach (var table in AdTablesToDelete)
            {
                tableIndex++;
                var progress = 10 + (tableIndex * 70 / AdTablesToDelete.Length);
                await SendProgressAsync(progressId, "Deleting", table, progress,
                    $"Deleting from {table}...");

                var deleteQuery = $"DELETE FROM {table} WHERE CollectionID = @CollectionId";
                await using var deleteCmd = new SqlCommand(deleteQuery, connection);
                deleteCmd.CommandTimeout = 600; // 10 minutes per table
                deleteCmd.Parameters.AddWithValue("@CollectionId", collectionId);

                var deleted = await deleteCmd.ExecuteNonQueryAsync(cancellationToken);
                deletedTotal += deleted;

                _logger.LogDebug("Deleted {Count} records from {Table}", deleted, table);
            }

            if (deletedTotal > 0)
            {
                // Merge the empty partition after successful deletion
                await SendProgressAsync(progressId, "Cleanup", "", 90, "Merging empty partition...");
                await MergeEmptyPartitionAsync(connection, collectionId, cancellationToken);

                await SendProgressAsync(progressId, "Completed", "", 100,
                    $"Successfully deleted {totalRecords:N0} records from {AdTablesToDelete.Length} tables");

                _logger.LogInformation(
                    "Successfully deleted AD collection {CollectionId}: {TotalRecords} total records from {TableCount} tables",
                    collectionId, totalRecords, AdTablesToDelete.Length);
            }
            else
            {
                await SendProgressAsync(progressId, "Failed", "", 0, $"Collection {collectionId} not found");
                _logger.LogWarning("AD collection {CollectionId} not found", collectionId);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting AD collection {CollectionId}", collectionId);
            await SendProgressAsync(progressId, "Failed", "", 0, $"Deletion failed: {ex.Message}");
            throw;
        }
    }

    /// <summary>
    /// Deletes an NTFS collection using partition-aware deletion (much faster for partitioned tables).
    /// </summary>
    private async Task DeleteNtfsCollectionWithPartitioningAsync(SqlConnection connection, Guid inventoryId, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Using partition-aware deletion for NTFS collection {InventoryId}", inventoryId);

        await SendProgressAsync(inventoryId, "Counting", "", 10, "Counting records in partition...");

        // Count total rows first for progress reporting
        var countQuery = @"
            DECLARE @PartitionNumber INT = $PARTITION.pf_InventoryID(@InventoryId);
            SELECT ISNULL(SUM(p.rows), 0) AS TotalRows
            FROM sys.tables t
            JOIN sys.schemas s ON t.schema_id = s.schema_id
            JOIN sys.indexes i ON t.object_id = i.object_id AND i.index_id <= 1
            JOIN sys.partition_schemes ps ON i.data_space_id = ps.data_space_id
            JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
            WHERE s.name = 'fsapp'
              AND ps.name = 'ps_InventoryID'
              AND p.partition_number = @PartitionNumber";

        await using var countCmd = new SqlCommand(countQuery, connection);
        countCmd.CommandTimeout = 60;
        countCmd.Parameters.AddWithValue("@InventoryId", inventoryId);
        var totalRows = Convert.ToInt64(await countCmd.ExecuteScalarAsync(cancellationToken));

        if (totalRows == 0)
        {
            _logger.LogWarning("No data found in partition for InventoryId {InventoryId}", inventoryId);
            await SendProgressAsync(inventoryId, "Completed", "", 100, "No data found to delete");
            return;
        }

        await SendProgressAsync(inventoryId, "Deleting", "fsapp", 30, $"Deleting {totalRows:N0} records using partition-optimized deletion...");

        // Call the stored procedure for partition-aware deletion
        await using var deleteCmd = new SqlCommand("dbo.usp_Partition_DeleteCollection_Fast", connection);
        deleteCmd.CommandType = System.Data.CommandType.StoredProcedure;
        deleteCmd.CommandTimeout = 1800; // 30 minutes
        deleteCmd.Parameters.AddWithValue("@InventoryID", inventoryId);
        deleteCmd.Parameters.AddWithValue("@Schema", "fsapp");

        var errorMsgParam = new SqlParameter("@ErrorMessage", System.Data.SqlDbType.NVarChar, 4000)
        {
            Direction = System.Data.ParameterDirection.Output
        };
        deleteCmd.Parameters.Add(errorMsgParam);

        var returnValue = new SqlParameter("@ReturnValue", System.Data.SqlDbType.Int)
        {
            Direction = System.Data.ParameterDirection.ReturnValue
        };
        deleteCmd.Parameters.Add(returnValue);

        await deleteCmd.ExecuteNonQueryAsync(cancellationToken);

        var returnCode = (int?)returnValue.Value ?? 0;
        var errorMessage = errorMsgParam.Value as string;

        if (returnCode != 0)
        {
            _logger.LogError("Partition deletion failed for {InventoryId}: {Error}", inventoryId, errorMessage);
            await SendProgressAsync(inventoryId, "Failed", "", 0, $"Deletion failed: {errorMessage}");
            throw new InvalidOperationException($"Partition deletion failed: {errorMessage}");
        }

        // Merge the empty partition after successful deletion
        await SendProgressAsync(inventoryId, "Cleanup", "", 90, "Merging empty partition...");
        await MergeEmptyPartitionAsync(connection, inventoryId, cancellationToken);

        await SendProgressAsync(inventoryId, "Completed", "", 100, $"Successfully deleted {totalRows:N0} records");

        _logger.LogInformation("Successfully deleted NTFS collection {InventoryId} using partition-aware deletion: {TotalRows} rows",
            inventoryId, totalRows);
    }

    /// <summary>
    /// Deletes an AD collection using partition-aware deletion (much faster for partitioned tables).
    /// </summary>
    private async Task DeleteAdCollectionWithPartitioningAsync(SqlConnection connection, Guid collectionId, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Using partition-aware deletion for AD collection {CollectionId}", collectionId);

        await SendProgressAsync(collectionId, "Counting", "", 10, "Counting records in partition...");

        // Count total rows first for progress reporting
        // ADData tables use pf_CollectionID/ps_CollectionID (partitioned by CollectionID)
        var countQuery = @"
            DECLARE @PartitionNumber INT = $PARTITION.pf_CollectionID(@CollectionId);
            SELECT ISNULL(SUM(p.rows), 0) AS TotalRows
            FROM sys.tables t
            JOIN sys.schemas s ON t.schema_id = s.schema_id
            JOIN sys.indexes i ON t.object_id = i.object_id AND i.index_id <= 1
            JOIN sys.partition_schemes ps ON i.data_space_id = ps.data_space_id
            JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
            WHERE s.name = 'ADData'
              AND ps.name = 'ps_CollectionID'
              AND p.partition_number = @PartitionNumber";

        await using var countCmd = new SqlCommand(countQuery, connection);
        countCmd.CommandTimeout = 60;
        countCmd.Parameters.AddWithValue("@CollectionId", collectionId);
        var totalRows = Convert.ToInt64(await countCmd.ExecuteScalarAsync(cancellationToken));

        if (totalRows == 0)
        {
            _logger.LogWarning("No data found in partition for CollectionId {CollectionId}", collectionId);
            await SendProgressAsync(collectionId, "Completed", "", 100, "No data found to delete");
            return;
        }

        await SendProgressAsync(collectionId, "Deleting", "ADData", 30, $"Deleting {totalRows:N0} records using partition-optimized deletion...");

        // Call the stored procedure for partition-aware deletion
        await using var deleteCmd = new SqlCommand("dbo.usp_Partition_DeleteCollection_Fast", connection);
        deleteCmd.CommandType = System.Data.CommandType.StoredProcedure;
        deleteCmd.CommandTimeout = 1800; // 30 minutes
        deleteCmd.Parameters.AddWithValue("@InventoryID", collectionId);  // Uses CollectionID as partition key
        deleteCmd.Parameters.AddWithValue("@Schema", "ADData");

        var errorMsgParam = new SqlParameter("@ErrorMessage", System.Data.SqlDbType.NVarChar, 4000)
        {
            Direction = System.Data.ParameterDirection.Output
        };
        deleteCmd.Parameters.Add(errorMsgParam);

        var returnValue = new SqlParameter("@ReturnValue", System.Data.SqlDbType.Int)
        {
            Direction = System.Data.ParameterDirection.ReturnValue
        };
        deleteCmd.Parameters.Add(returnValue);

        await deleteCmd.ExecuteNonQueryAsync(cancellationToken);

        var returnCode = (int?)returnValue.Value ?? 0;
        var errorMessage = errorMsgParam.Value as string;

        if (returnCode != 0)
        {
            _logger.LogError("Partition deletion failed for AD collection {CollectionId}: {Error}", collectionId, errorMessage);
            await SendProgressAsync(collectionId, "Failed", "", 0, $"Deletion failed: {errorMessage}");
            throw new InvalidOperationException($"Partition deletion failed: {errorMessage}");
        }

        // Merge the empty partition after successful deletion
        await SendProgressAsync(collectionId, "Cleanup", "", 90, "Merging empty partition...");
        await MergeEmptyPartitionAsync(connection, collectionId, cancellationToken);

        await SendProgressAsync(collectionId, "Completed", "", 100, $"Successfully deleted {totalRows:N0} records");

        _logger.LogInformation("Successfully deleted AD collection {CollectionId} using partition-aware deletion: {TotalRows} rows",
            collectionId, totalRows);
    }

    /// <summary>
    /// Merges an empty partition after deletion to clean up the partition function.
    /// </summary>
    private async Task MergeEmptyPartitionAsync(SqlConnection connection, Guid partitionKey, CancellationToken cancellationToken)
    {
        try
        {
            await using var mergeCmd = new SqlCommand("dbo.usp_Partition_MergeEmpty", connection);
            mergeCmd.CommandType = System.Data.CommandType.StoredProcedure;
            mergeCmd.CommandTimeout = 300; // 5 minutes for partition merge
            mergeCmd.Parameters.AddWithValue("@InventoryID", partitionKey);

            var errorMsgParam = new SqlParameter("@ErrorMessage", System.Data.SqlDbType.NVarChar, 4000)
            {
                Direction = System.Data.ParameterDirection.Output
            };
            mergeCmd.Parameters.Add(errorMsgParam);

            await mergeCmd.ExecuteNonQueryAsync(cancellationToken);

            var errorMessage = errorMsgParam.Value as string;
            if (!string.IsNullOrEmpty(errorMessage))
            {
                _logger.LogWarning("Partition merge note for {PartitionKey}: {Message}", partitionKey, errorMessage);
            }
            else
            {
                _logger.LogInformation("Successfully merged empty partition for {PartitionKey}", partitionKey);
            }
        }
        catch (Exception ex)
        {
            // Don't fail the deletion if partition merge fails - data is already deleted
            _logger.LogWarning(ex, "Failed to merge partition for {PartitionKey}, but deletion succeeded", partitionKey);
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
