using Hangfire;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using System.Data;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for cleaning up old AD collections per domain.
/// </summary>
public interface IAdCollectionCleanupJob
{
    /// <summary>
    /// Cleans up old AD collections, keeping only the configured number per domain.
    /// </summary>
    [JobDisplayName("Cleanup: AD Collections")]
    [Queue("ad-deletion")]
    Task CleanupOldCollectionsAsync(CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of the AD collection cleanup job.
/// </summary>
public class AdCollectionCleanupJob : IAdCollectionCleanupJob
{
    private readonly ILogger<AdCollectionCleanupJob> _logger;
    private readonly CleanupSettings _cleanupSettings;
    private readonly SqlServerSettings _sqlSettings;

    public AdCollectionCleanupJob(
        ILogger<AdCollectionCleanupJob> logger,
        CleanupSettings cleanupSettings,
        SqlServerSettings sqlSettings)
    {
        _logger = logger;
        _cleanupSettings = cleanupSettings;
        _sqlSettings = sqlSettings;
    }

    /// <inheritdoc/>
    public async Task CleanupOldCollectionsAsync(CancellationToken cancellationToken)
    {
        if (!_cleanupSettings.AutoPruneAdCollections)
        {
            _logger.LogInformation("AD collection pruning is disabled");
            return;
        }

        if (!_sqlSettings.IsConfigured)
        {
            _logger.LogWarning("SQL Server is not configured, cannot cleanup AD collections");
            return;
        }

        var keepCount = _cleanupSettings.AdCollectionsToKeepPerDomain;
        if (keepCount < 1)
        {
            _logger.LogWarning("AdCollectionsToKeepPerDomain must be at least 1, skipping cleanup");
            return;
        }

        _logger.LogInformation("Starting AD collection cleanup. Keeping {KeepCount} collections per domain", keepCount);

        var connectionString = _sqlSettings.BuildConnectionString();
        var totalDeleted = 0;
        var domainsProcessed = 0;

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Step 1: Get distinct domains with collection counts
            var domains = new List<(string DomainName, int CollectionCount)>();

            var domainQuery = @"
                SELECT
                    COALESCE(DomainName, ComputerName) AS DomainName,
                    COUNT(*) AS CollectionCount
                FROM ADData.CollectionInfo
                GROUP BY COALESCE(DomainName, ComputerName)
                HAVING COUNT(*) > @KeepCount
                ORDER BY DomainName";

            await using (var cmd = new SqlCommand(domainQuery, connection))
            {
                cmd.Parameters.AddWithValue("@KeepCount", keepCount);
                cmd.CommandTimeout = 120;

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    var domainName = reader.GetString(0);
                    var count = reader.GetInt32(1);
                    domains.Add((domainName, count));
                }
            }

            if (domains.Count == 0)
            {
                _logger.LogInformation("No domains have more than {KeepCount} collections, nothing to cleanup", keepCount);
                return;
            }

            _logger.LogInformation("Found {DomainCount} domains with collections to cleanup", domains.Count);

            // Step 2: For each domain, get collections to delete (older than the Nth most recent)
            foreach (var (domainName, collectionCount) in domains)
            {
                cancellationToken.ThrowIfCancellationRequested();

                var collectionsToDelete = new List<Guid>();

                // Get CollectionIDs to delete (all except the N most recent)
                var collectionsQuery = @"
                    SELECT CollectionID
                    FROM ADData.CollectionInfo
                    WHERE COALESCE(DomainName, ComputerName) = @DomainName
                    ORDER BY CollectionDateTime DESC
                    OFFSET @KeepCount ROWS";

                await using (var cmd = new SqlCommand(collectionsQuery, connection))
                {
                    cmd.Parameters.AddWithValue("@DomainName", domainName);
                    cmd.Parameters.AddWithValue("@KeepCount", keepCount);
                    cmd.CommandTimeout = 120;

                    await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                    while (await reader.ReadAsync(cancellationToken))
                    {
                        collectionsToDelete.Add(reader.GetGuid(0));
                    }
                }

                if (collectionsToDelete.Count == 0)
                {
                    continue;
                }

                _logger.LogInformation("Domain '{DomainName}': Deleting {DeleteCount} of {TotalCount} collections",
                    domainName, collectionsToDelete.Count, collectionCount);

                // Step 3: Delete each collection using the stored procedure
                foreach (var collectionId in collectionsToDelete)
                {
                    cancellationToken.ThrowIfCancellationRequested();

                    try
                    {
                        await using var deleteCmd = new SqlCommand("dbo.usp_ADData_DeleteCollection", connection)
                        {
                            CommandType = CommandType.StoredProcedure,
                            CommandTimeout = 300 // 5 minutes per collection
                        };

                        deleteCmd.Parameters.AddWithValue("@CollectionID", collectionId);

                        var returnParam = new SqlParameter("@ReturnValue", SqlDbType.Int)
                        {
                            Direction = ParameterDirection.ReturnValue
                        };
                        deleteCmd.Parameters.Add(returnParam);

                        await deleteCmd.ExecuteNonQueryAsync(cancellationToken);

                        var returnCode = returnParam.Value != DBNull.Value ? (int)returnParam.Value : -1;

                        if (returnCode == 0)
                        {
                            totalDeleted++;
                            _logger.LogDebug("Deleted AD collection {CollectionId} from domain '{DomainName}'",
                                collectionId, domainName);
                        }
                        else
                        {
                            _logger.LogWarning("Failed to delete AD collection {CollectionId}: return code {ReturnCode}",
                                collectionId, returnCode);
                        }
                    }
                    catch (SqlException ex) when (ex.Number == 2812)
                    {
                        // Stored procedure doesn't exist
                        _logger.LogError("Stored procedure dbo.usp_ADData_DeleteCollection not found. Run migration 016 first.");
                        return;
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Error deleting AD collection {CollectionId}", collectionId);
                    }
                }

                domainsProcessed++;
            }

            _logger.LogInformation("AD collection cleanup completed. Deleted {TotalDeleted} collections across {DomainsProcessed} domains",
                totalDeleted, domainsProcessed);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during AD collection cleanup");
            throw;
        }
    }
}
