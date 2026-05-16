using System.Text.RegularExpressions;
using Hangfire;
using Hangfire.Common;
using Hangfire.Storage;
using Microsoft.Data.SqlClient;
using CLAWS.Core.Configuration;
using CLAWS.Web.Models;

namespace CLAWS.Web.Services;

/// <summary>
/// Implementation of production data management service.
/// </summary>
public class ProductionDataService : IProductionDataService
{
    private readonly ILogger<ProductionDataService> _logger;
    private readonly SqlServerSettings _sqlSettings;
    private readonly DatabasePerformanceSettings _perfSettings;

    public ProductionDataService(
        ILogger<ProductionDataService> logger,
        SqlServerSettings sqlSettings,
        DatabasePerformanceSettings perfSettings)
    {
        _logger = logger;
        _sqlSettings = sqlSettings;
        _perfSettings = perfSettings;
    }

    /// <inheritdoc/>
    public async Task<List<NtfsProductionCollectionItem>> GetNtfsCollectionsAsync(CancellationToken cancellationToken)
    {
        var results = new List<NtfsProductionCollectionItem>();

        if (!_sqlSettings.IsConfigured)
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Query pre-computed statistics from fsapp.vw_CollectionStatsWithInfo
            // Stats are computed by usp_fsapp_ComputeCollectionStats after imports
            var query = @"
                SELECT
                    InventoryID,
                    ComputerName,
                    ScanPath,
                    CollectionDateTime,
                    ApplicationVersion,
                    FoldersCount,
                    AclCount,
                    AceCount,
                    SidsCount,
                    SmbSharesCount
                FROM fsapp.vw_CollectionStatsWithInfo
                ORDER BY CollectionDateTime DESC";

            await using var command = new SqlCommand(query, connection);
            command.CommandTimeout = _perfSettings.CommandTimeoutSeconds;

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var item = new NtfsProductionCollectionItem
                {
                    InventoryId = reader.GetGuid(0),
                    ComputerName = reader.IsDBNull(1) ? null : reader.GetString(1),
                    ScanPath = reader.IsDBNull(2) ? null : reader.GetString(2),
                    ExeVersion = reader.IsDBNull(4) ? null : reader.GetString(4),
                    FoldersCount = reader.IsDBNull(5) ? 0 : Convert.ToInt64(reader.GetValue(5)),
                    AclCount = reader.IsDBNull(6) ? 0 : Convert.ToInt64(reader.GetValue(6)),
                    AceCount = reader.IsDBNull(7) ? 0 : Convert.ToInt64(reader.GetValue(7)),
                    SidsCount = reader.IsDBNull(8) ? 0 : Convert.ToInt64(reader.GetValue(8)),
                    SmbSharesCount = reader.IsDBNull(9) ? 0 : Convert.ToInt64(reader.GetValue(9))
                };

                // Handle CollectionDateTime (may be DateTime or DateTimeOffset)
                if (!reader.IsDBNull(3))
                {
                    var dateValue = reader.GetValue(3);
                    item.CollectionDateTime = dateValue switch
                    {
                        DateTime dt => dt,
                        DateTimeOffset dto => dto.DateTime,
                        _ => null
                    };
                }

                results.Add(item);
            }

            _logger.LogDebug("Retrieved {Count} NTFS collections from fsapp.CollectionInfo", results.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error querying NTFS production collections");
        }

        return results;
    }

    /// <inheritdoc/>
    public async Task<List<AdProductionCollectionItem>> GetAdCollectionsAsync(CancellationToken cancellationToken)
    {
        var results = new List<AdProductionCollectionItem>();

        if (!_sqlSettings.IsConfigured)
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Query pre-computed statistics from ADData.vw_CollectionStatsWithInfo
            // Stats are computed by usp_ADData_ComputeCollectionStats after imports
            var query = @"
                SELECT
                    CollectionID,
                    InventoryID,
                    DomainName,
                    ComputerName,
                    CollectionDateTime,
                    ObjectCount,
                    GroupMembershipCount,
                    FspCount,
                    TrustCount,
                    FlatMembershipCount
                FROM ADData.vw_CollectionStatsWithInfo
                ORDER BY CollectionDateTime DESC";

            await using var command = new SqlCommand(query, connection);
            command.CommandTimeout = _perfSettings.CommandTimeoutSeconds;

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var item = new AdProductionCollectionItem
                {
                    CollectionId = reader.GetGuid(0),
                    DomainName = reader.IsDBNull(2) ? null : reader.GetString(2),
                    ComputerName = reader.IsDBNull(3) ? null : reader.GetString(3),
                    ObjectCount = reader.IsDBNull(5) ? 0 : Convert.ToInt64(reader.GetValue(5)),
                    GroupMembershipCount = reader.IsDBNull(6) ? 0 : Convert.ToInt64(reader.GetValue(6)),
                    FspCount = reader.IsDBNull(7) ? 0 : Convert.ToInt64(reader.GetValue(7)),
                    TrustCount = reader.IsDBNull(8) ? 0 : Convert.ToInt64(reader.GetValue(8)),
                    FlatMembershipCount = reader.IsDBNull(9) ? 0 : Convert.ToInt64(reader.GetValue(9))
                };

                // Handle InventoryID (may be string or GUID)
                if (!reader.IsDBNull(1))
                {
                    var inventoryIdValue = reader.GetValue(1);
                    if (inventoryIdValue is Guid guid)
                        item.InventoryId = guid;
                    else if (Guid.TryParse(inventoryIdValue.ToString(), out var parsedGuid))
                        item.InventoryId = parsedGuid;
                }

                // Handle CollectionDateTime (may be DateTime or DateTimeOffset)
                if (!reader.IsDBNull(4))
                {
                    var dateValue = reader.GetValue(4);
                    item.CollectionDateTime = dateValue switch
                    {
                        DateTime dt => dt,
                        DateTimeOffset dto => dto.DateTime,
                        _ => null
                    };
                }

                results.Add(item);
            }

            _logger.LogDebug("Retrieved {Count} AD collections from ADData.CollectionInfo", results.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error querying AD production collections");
        }

        return results;
    }

    /// <inheritdoc/>
    public async Task<(bool Success, string Message)> DeleteNtfsCollectionAsync(Guid inventoryId, CancellationToken cancellationToken)
    {
        _logger.LogWarning("Deleting NTFS collection {InventoryId} from fsapp schema", inventoryId);

        if (!_sqlSettings.IsConfigured)
            return (false, "Database is not configured.");

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Start transaction for atomic deletion
            await using var transaction = connection.BeginTransaction();

            try
            {
                // Delete from tables in dependency order (children first)
                // Tables with CASCADE: ACL->ACE (ACE has CASCADE from ACL)
                // Tables without CASCADE that need explicit deletion
                var tablesToDelete = new[]
                {
                    // Delete child tables first
                    "fsapp.EventLog",
                    "fsapp.SMBShareAccess",
                    "fsapp.SMBShares",
                    "fsapp.ACE",        // Child of ACL
                    "fsapp.ACL",
                    "fsapp.Folders",
                    "fsapp.Partitions",
                    "fsapp.VolumeExtents",
                    "fsapp.VolumeMounts",
                    "fsapp.Volumes",
                    "fsapp.Disks",
                    "fsapp.SIDs",
                    // Delete parent table last
                    "fsapp.CollectionInfo"
                };

                var totalDeleted = 0;
                foreach (var table in tablesToDelete)
                {
                    var deleteQuery = $"DELETE FROM {table} WHERE InventoryID = @InventoryId";
                    await using var cmd = new SqlCommand(deleteQuery, connection, transaction);
                    cmd.CommandTimeout = 300; // 5 minutes per table
                    cmd.Parameters.AddWithValue("@InventoryId", inventoryId);
                    var deleted = await cmd.ExecuteNonQueryAsync(cancellationToken);
                    if (deleted > 0)
                    {
                        _logger.LogDebug("Deleted {Count} rows from {Table}", deleted, table);
                        totalDeleted += deleted;
                    }
                }

                await transaction.CommitAsync(cancellationToken);

                _logger.LogInformation("Successfully deleted NTFS collection {InventoryId}: {TotalDeleted} total rows",
                    inventoryId, totalDeleted);

                return (true, $"Successfully deleted collection ({totalDeleted:N0} records removed).");
            }
            catch (Exception ex)
            {
                await transaction.RollbackAsync(cancellationToken);
                throw new InvalidOperationException($"Failed to delete collection: {ex.Message}", ex);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting NTFS collection {InventoryId}", inventoryId);
            return (false, $"Failed to delete collection: {ex.Message}");
        }
    }

    /// <inheritdoc/>
    public async Task<(bool Success, string Message)> DeleteAdCollectionAsync(Guid collectionId, CancellationToken cancellationToken)
    {
        _logger.LogWarning("Deleting AD collection {CollectionId} from ADData schema", collectionId);

        if (!_sqlSettings.IsConfigured)
            return (false, "Database is not configured.");

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Count records before deletion for reporting
            var countQuery = @"
                SELECT
                    (SELECT COUNT(*) FROM ADData.AD_Object WHERE CollectionID = @CollectionId) +
                    (SELECT COUNT(*) FROM ADData.AD_GroupMembership WHERE CollectionID = @CollectionId) +
                    (SELECT COUNT(*) FROM ADData.AD_ForeignSecurityPrincipal WHERE CollectionID = @CollectionId) +
                    (SELECT COUNT(*) FROM ADData.AD_Trust WHERE CollectionID = @CollectionId) +
                    (SELECT COUNT(*) FROM ADData.AD_GroupMember_Flat WHERE CollectionID = @CollectionId) +
                    (SELECT COUNT(*) FROM ADData.AD_Domain WHERE CollectionID = @CollectionId) +
                    (SELECT COUNT(*) FROM ADData.AD_Forest WHERE CollectionID = @CollectionId) +
                    (SELECT COUNT(*) FROM ADData.AD_Log WHERE CollectionID = @CollectionId) +
                    (SELECT COUNT(*) FROM ADData.AD_ExecutionTime WHERE CollectionID = @CollectionId) +
                    1  -- CollectionInfo row itself
                AS TotalRecords";

            await using var countCmd = new SqlCommand(countQuery, connection);
            countCmd.CommandTimeout = 120;
            countCmd.Parameters.AddWithValue("@CollectionId", collectionId);
            var totalRecords = Convert.ToInt64(await countCmd.ExecuteScalarAsync(cancellationToken));

            // ADData uses ON DELETE CASCADE, so we only need to delete from CollectionInfo
            var deleteQuery = "DELETE FROM ADData.CollectionInfo WHERE CollectionID = @CollectionId";
            await using var deleteCmd = new SqlCommand(deleteQuery, connection);
            deleteCmd.CommandTimeout = 300; // 5 minutes
            deleteCmd.Parameters.AddWithValue("@CollectionId", collectionId);

            var deleted = await deleteCmd.ExecuteNonQueryAsync(cancellationToken);

            if (deleted > 0)
            {
                _logger.LogInformation("Successfully deleted AD collection {CollectionId}: {TotalRecords} total records via CASCADE",
                    collectionId, totalRecords);
                return (true, $"Successfully deleted collection ({totalRecords:N0} records removed via cascade).");
            }
            else
            {
                return (false, $"Collection {collectionId} not found.");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting AD collection {CollectionId}", collectionId);
            return (false, $"Failed to delete collection: {ex.Message}");
        }
    }

    /// <inheritdoc/>
    public List<string> GetActiveDeletionIds()
    {
        var activeIds = new List<string>();

        try
        {
            var monitor = JobStorage.Current.GetMonitoringApi();

            // Check processing jobs (currently running)
            var processingJobs = monitor.ProcessingJobs(0, 100);
            foreach (var job in processingJobs)
            {
                var id = ExtractCollectionIdFromJob(job.Value.Job);
                if (id != null)
                    activeIds.Add(id);
            }

            // Check enqueued jobs in the deletion queue (waiting to run)
            var enqueuedJobs = monitor.EnqueuedJobs("deletion", 0, 100);
            foreach (var job in enqueuedJobs)
            {
                var id = ExtractCollectionIdFromJob(job.Value.Job);
                if (id != null)
                    activeIds.Add(id);
            }

            // Check enqueued jobs in the AD deletion queue (waiting to run)
            var adEnqueuedJobs = monitor.EnqueuedJobs("ad-deletion", 0, 100);
            foreach (var job in adEnqueuedJobs)
            {
                var id = ExtractCollectionIdFromJob(job.Value.Job);
                if (id != null)
                    activeIds.Add(id);
            }

            // Check scheduled jobs (delayed)
            var scheduledJobs = monitor.ScheduledJobs(0, 100);
            foreach (var job in scheduledJobs)
            {
                var id = ExtractCollectionIdFromJob(job.Value.Job);
                if (id != null)
                    activeIds.Add(id);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error querying Hangfire for active deletion jobs");
        }

        return activeIds.Distinct().ToList();
    }

    /// <summary>
    /// Extracts the collection ID from a Hangfire job if it's a deletion job.
    /// </summary>
    private static string? ExtractCollectionIdFromJob(Job? job)
    {
        if (job == null)
            return null;

        // Check if this is a deletion job by method name
        var methodName = job.Method?.Name;
        if (methodName != "DeleteNtfsCollectionAsync" && methodName != "DeleteAdCollectionAsync")
            return null;

        // The first argument is the collection ID (Guid for NTFS, int for AD)
        var args = job.Args;
        if (args == null || args.Count == 0)
            return null;

        var firstArg = args[0];
        if (firstArg is Guid guid)
            return guid.ToString();

        if (firstArg is int intId)
        {
            // AD uses a pseudo-GUID for SignalR tracking
            var pseudoGuid = new Guid(intId, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
            return pseudoGuid.ToString();
        }

        return firstArg?.ToString();
    }
}
