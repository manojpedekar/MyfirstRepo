using Hangfire;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Jobs.Filters;
using System.Data;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for cleaning up orphaned data from fssimport schema.
/// </summary>
public interface IOrphanedDataCleanupJob
{
    /// <summary>
    /// Cleans up a single orphaned inventory from fssimport schema with progress reporting.
    /// </summary>
    [JobDisplayName("Cleanup Orphaned Inventory: {0}")]
    [AutomaticRetry(Attempts = 0)]
    [Queue("deletion")]
    Task CleanupOrphanedInventoryAsync(Guid inventoryId, string initiatedBy, CancellationToken cancellationToken);

    /// <summary>
    /// Cleans up all orphaned inventories from fssimport schema with progress reporting.
    /// </summary>
    [JobDisplayName("Cleanup All Orphaned Inventories")]
    [AutomaticRetry(Attempts = 0)]
    [Queue("deletion")]
    [ConfigurableDisableConcurrentExecution] // Timeout configured via AppSettings.JobTimeouts.OrphanedCleanupMinutes
    Task CleanupAllOrphanedInventoriesAsync(string initiatedBy, CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of orphaned data cleanup job with progress reporting.
/// </summary>
public class OrphanedDataCleanupJob : IOrphanedDataCleanupJob
{
    private readonly ILogger<OrphanedDataCleanupJob> _logger;
    private readonly SqlServerSettings _sqlSettings;
    private readonly DatabasePerformanceSettings _perfSettings;
    private readonly IHubNotifier? _hubNotifier;

    // Stable GUID prefix for "cleanup all" progress tracking
    private static readonly Guid AllOrphanedProgressId = new Guid("00000000-0000-0000-0001-000000000001");

    public OrphanedDataCleanupJob(
        ILogger<OrphanedDataCleanupJob> logger,
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
    public async Task CleanupOrphanedInventoryAsync(Guid inventoryId, string initiatedBy, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting orphaned inventory cleanup for {InventoryId} initiated by {User}",
            inventoryId, initiatedBy);

        await SendProgressAsync(inventoryId, "Starting", "", 0, "Initializing cleanup...");

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await SendProgressAsync(inventoryId, "Cleaning", "", 30, "Executing cleanup stored procedure...");

            await using var command = new SqlCommand("dbo.usp_CleanupImportedCollection", connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 600 // 10 minutes for large inventories
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

            if (returnCode == 0 || returnCode == 1)
            {
                await SendProgressAsync(inventoryId, "Completed", "", 100,
                    "Successfully cleaned up orphaned inventory data");
                _logger.LogInformation("Successfully cleaned up orphaned inventory {InventoryId}", inventoryId);
            }
            else
            {
                await SendProgressAsync(inventoryId, "Failed", "", 0,
                    $"Cleanup failed: {errorMessage ?? $"Error code {returnCode}"}");
                _logger.LogWarning("Failed to cleanup orphaned inventory {InventoryId}: {Error}",
                    inventoryId, errorMessage ?? $"Error code {returnCode}");
                throw new InvalidOperationException(errorMessage ?? $"Cleanup failed with code {returnCode}");
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("Orphaned inventory cleanup cancelled for {InventoryId}", inventoryId);
            await SendProgressAsync(inventoryId, "Failed", "", 0, "Cleanup cancelled");
            throw;
        }
        catch (Exception ex) when (ex is not InvalidOperationException)
        {
            _logger.LogError(ex, "Error cleaning up orphaned inventory {InventoryId}", inventoryId);
            await SendProgressAsync(inventoryId, "Failed", "", 0, $"Error: {ex.Message}");
            throw;
        }
    }

    /// <inheritdoc/>
    public async Task CleanupAllOrphanedInventoriesAsync(string initiatedBy, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting cleanup of all orphaned inventories initiated by {User}", initiatedBy);

        await SendProgressAsync(AllOrphanedProgressId, "Starting", "", 0, "Finding orphaned inventories...");

        var connectionString = _sqlSettings.BuildConnectionString();
        var orphanedIds = new List<Guid>();

        try
        {
            // First, find all orphaned inventories
            await using (var connection = new SqlConnection(connectionString))
            {
                await connection.OpenAsync(cancellationToken);

                var query = @"
                    SELECT c.InventoryID
                    FROM fssimport.CollectionInfo c
                    WHERE NOT EXISTS (
                        SELECT 1 FROM app.ImportStatistics s WHERE s.InventoryId = c.InventoryID
                    )";

                await using var command = new SqlCommand(query, connection);
                command.CommandTimeout = 120;

                await using var reader = await command.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    orphanedIds.Add(reader.GetGuid(0));
                }
            }

            if (orphanedIds.Count == 0)
            {
                await SendProgressAsync(AllOrphanedProgressId, "Completed", "", 100, "No orphaned inventories found");
                _logger.LogInformation("No orphaned inventories found to clean up");
                return;
            }

            _logger.LogInformation("Found {Count} orphaned inventories to clean up", orphanedIds.Count);
            await SendProgressAsync(AllOrphanedProgressId, "Cleaning", "", 10,
                $"Found {orphanedIds.Count} orphaned inventories. Starting cleanup...");

            var cleaned = 0;
            var failed = 0;
            var errors = new List<string>();

            for (int i = 0; i < orphanedIds.Count; i++)
            {
                cancellationToken.ThrowIfCancellationRequested();

                var inventoryId = orphanedIds[i];
                var progress = 10 + (int)((i + 1) * 85.0 / orphanedIds.Count);

                await SendProgressAsync(AllOrphanedProgressId, "Cleaning", inventoryId.ToString(),
                    Math.Min(95, progress), $"Cleaning inventory {i + 1} of {orphanedIds.Count}...");

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

                    if (returnCode == 0 || returnCode == 1)
                    {
                        cleaned++;
                        _logger.LogDebug("Cleaned orphaned inventory {InventoryId}", inventoryId);
                    }
                    else
                    {
                        var errMsg = errorMessageParam.Value != DBNull.Value
                            ? errorMessageParam.Value.ToString()
                            : $"Error code {returnCode}";
                        failed++;
                        errors.Add($"{inventoryId}: {errMsg}");
                        _logger.LogWarning("Failed to cleanup orphaned inventory {InventoryId}: {Error}",
                            inventoryId, errMsg);
                    }
                }
                catch (Exception ex)
                {
                    failed++;
                    errors.Add($"{inventoryId}: {ex.Message}");
                    _logger.LogError(ex, "Error cleaning up orphaned inventory {InventoryId}", inventoryId);
                }
            }

            var finalMessage = failed == 0
                ? $"Successfully cleaned up {cleaned} orphaned inventory(s)"
                : $"Cleaned {cleaned}, failed {failed}. Errors: {string.Join("; ", errors.Take(3))}";

            if (failed == 0)
            {
                await SendProgressAsync(AllOrphanedProgressId, "Completed", "", 100, finalMessage);
            }
            else
            {
                await SendProgressAsync(AllOrphanedProgressId, "Completed", "", 100, finalMessage);
            }

            _logger.LogInformation("Orphaned inventory cleanup completed: {Cleaned} cleaned, {Failed} failed",
                cleaned, failed);
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("Orphaned inventory cleanup cancelled");
            await SendProgressAsync(AllOrphanedProgressId, "Failed", "", 0, "Cleanup cancelled");
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during orphaned inventory cleanup");
            await SendProgressAsync(AllOrphanedProgressId, "Failed", "", 0, $"Error: {ex.Message}");
            throw;
        }
    }

    /// <summary>
    /// Gets the progress ID for the "cleanup all" operation.
    /// </summary>
    public static Guid GetAllOrphanedProgressId() => AllOrphanedProgressId;

    private async Task SendProgressAsync(Guid id, string phase, string currentTable, int percent, string message)
    {
        if (_hubNotifier != null)
        {
            await _hubNotifier.SendProgressAsync(id, phase, currentTable, percent, message);
        }
    }
}
