using Hangfire;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Jobs.Filters;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for truncating entire database schemas with progress reporting.
/// </summary>
public interface ISchemaTruncateJob
{
    /// <summary>
    /// Truncates all tables in a schema with batched deletes and progress reporting.
    /// </summary>
    [JobDisplayName("Truncate Schema: {0}")]
    [AutomaticRetry(Attempts = 0)]
    [Queue("deletion")]
    [ConfigurableDisableConcurrentExecution] // Timeout configured via AppSettings.JobTimeouts.SchemaTruncateMinutes
    Task TruncateSchemaAsync(string schemaName, string initiatedBy, CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of schema truncation job with batch processing and progress reporting.
/// </summary>
public class SchemaTruncateJob : ISchemaTruncateJob
{
    private readonly ILogger<SchemaTruncateJob> _logger;
    private readonly SqlServerSettings _sqlSettings;
    private readonly DatabasePerformanceSettings _perfSettings;
    private readonly IHubNotifier? _hubNotifier;

    // ADData tables in deletion order (children first, respecting FK relationships)
    private static readonly string[] AdDataTablesToDelete = new[]
    {
        "ADData.AD_ExecutionTime",
        "ADData.AD_Log",
        "ADData.AD_FlattenStats",
        "ADData.AD_GroupMember_Flat",
        "ADData.AD_GroupMembership",
        "ADData.AD_ForeignSecurityPrincipal",
        "ADData.AD_Trust",
        "ADData.AD_Object",
        "ADData.AD_Domain",
        "ADData.AD_Forest",
        "ADData.CollectionInfo"
    };

    // ADImport tables (same structure as ADData)
    private static readonly string[] AdImportTablesToDelete = new[]
    {
        "ADImport.AD_ExecutionTime",
        "ADImport.AD_Log",
        "ADImport.AD_FlattenStats",
        "ADImport.AD_GroupMember_Flat",
        "ADImport.AD_GroupMembership",
        "ADImport.AD_ForeignSecurityPrincipal",
        "ADImport.AD_Trust",
        "ADImport.AD_Object",
        "ADImport.AD_Domain",
        "ADImport.AD_Forest",
        "ADImport.CollectionInfo"
    };

    // fsapp tables in deletion order (children first)
    private static readonly string[] FsappTablesToDelete = new[]
    {
        "fsapp.EventLog",
        "fsapp.SMBShareAccess",
        "fsapp.SMBShares",
        "fsapp.ACE",
        "fsapp.ACL",
        "fsapp.Folders",  // Self-referential - needs special handling
        "fsapp.Partitions",
        "fsapp.VolumeExtents",
        "fsapp.VolumeMounts",
        "fsapp.Volumes",
        "fsapp.Disks",
        "fsapp.SIDs",
        "fsapp.CollectionInfo"
    };

    // fssimport tables (same structure as fsapp)
    private static readonly string[] FssimportTablesToDelete = new[]
    {
        "fssimport.EventLog",
        "fssimport.SMBShareAccess",
        "fssimport.SMBShares",
        "fssimport.ACE",
        "fssimport.ACL",
        "fssimport.Folders",  // Self-referential - needs special handling
        "fssimport.Partitions",
        "fssimport.VolumeExtents",
        "fssimport.VolumeMounts",
        "fssimport.Volumes",
        "fssimport.Disks",
        "fssimport.SIDs",
        "fssimport.CollectionInfo"
    };

    // Allowed schemas for validation
    private static readonly string[] AllowedSchemas = { "ADData", "ADImport", "fsapp", "fssimport" };

    public SchemaTruncateJob(
        ILogger<SchemaTruncateJob> logger,
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
    public async Task TruncateSchemaAsync(string schemaName, string initiatedBy, CancellationToken cancellationToken)
    {
        if (!AllowedSchemas.Contains(schemaName, StringComparer.OrdinalIgnoreCase))
        {
            throw new ArgumentException($"Invalid schema: {schemaName}. Allowed schemas: {string.Join(", ", AllowedSchemas)}");
        }

        _logger.LogWarning("Starting schema truncation job for [{Schema}] initiated by {User}",
            schemaName, initiatedBy);

        // Use schema name as a stable GUID for progress tracking
        var progressId = GenerateSchemaProgressId(schemaName);
        await SendProgressAsync(progressId, "Starting", "", 0, $"Initializing truncation of [{schemaName}]...");

        var connectionString = _sqlSettings.BuildConnectionString();
        var totalDeleted = 0L;
        var tablesTruncated = 0;
        var tablesWithErrors = 0;

        var tablesToDelete = GetTablesForSchema(schemaName);

        try
        {
            // Create a new connection for each major operation to avoid connection timeout issues
            var tableIndex = 0;
            var totalTables = tablesToDelete.Length;

            foreach (var table in tablesToDelete)
            {
                tableIndex++;
                var basePercent = (int)((tableIndex - 1) * 100.0 / totalTables);

                try
                {
                    await SendProgressAsync(progressId, "Counting", table, basePercent,
                        $"Counting rows in {table}...");

                    // Get row count first (for progress reporting)
                    var rowCount = await GetTableRowCountAsync(connectionString, table, cancellationToken);

                    if (rowCount == 0)
                    {
                        _logger.LogDebug("Table {Table} is already empty, skipping", table);
                        tablesTruncated++;
                        continue;
                    }

                    await SendProgressAsync(progressId, "Deleting", table, basePercent,
                        $"Deleting {rowCount:N0} rows from {table}...");

                    // Delete in batches using a fresh connection for resilience
                    var deletedFromTable = await DeleteTableInBatchesAsync(
                        connectionString, table, progressId, basePercent, totalTables, tableIndex, cancellationToken);

                    totalDeleted += deletedFromTable;
                    tablesTruncated++;

                    _logger.LogInformation("Truncated {Count:N0} rows from {Table}", deletedFromTable, table);
                }
                catch (OperationCanceledException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error truncating table {Table}", table);
                    tablesWithErrors++;
                    // Continue with next table - partial progress is better than complete failure
                    await SendProgressAsync(progressId, "Error", table, basePercent,
                        $"Error on {table}: {ex.Message}. Continuing...");
                }
            }

            // Clean up related app schema data
            await CleanupAppSchemaDataAsync(connectionString, schemaName, initiatedBy, cancellationToken);

            var finalMessage = tablesWithErrors == 0
                ? $"Successfully truncated {totalDeleted:N0} records from {tablesTruncated} tables"
                : $"Truncated {totalDeleted:N0} records from {tablesTruncated} tables ({tablesWithErrors} tables had errors)";

            await SendProgressAsync(progressId, "Completed", "", 100, finalMessage);

            _logger.LogInformation(
                "Schema truncation completed for [{Schema}]: {TotalDeleted:N0} rows from {TableCount} tables, {ErrorCount} errors",
                schemaName, totalDeleted, tablesTruncated, tablesWithErrors);
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("Schema truncation cancelled for [{Schema}]. Deleted {TotalDeleted:N0} rows before cancellation.",
                schemaName, totalDeleted);
            await SendProgressAsync(progressId, "Failed", "", 0, $"Cancelled after deleting {totalDeleted:N0} records");
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error truncating schema [{Schema}]. Deleted {TotalDeleted:N0} rows before error.",
                schemaName, totalDeleted);
            await SendProgressAsync(progressId, "Failed", "", 0, $"Error after {totalDeleted:N0} records: {ex.Message}");
            throw;
        }
    }

    private string[] GetTablesForSchema(string schemaName)
    {
        return schemaName.ToUpperInvariant() switch
        {
            "ADDATA" => AdDataTablesToDelete,
            "ADIMPORT" => AdImportTablesToDelete,
            "FSAPP" => FsappTablesToDelete,
            "FSSIMPORT" => FssimportTablesToDelete,
            _ => throw new ArgumentException($"Unknown schema: {schemaName}")
        };
    }

    private static Guid GenerateSchemaProgressId(string schemaName)
    {
        // Generate a stable GUID from schema name for progress tracking
        // Using a simple hash-based approach
        var hash = schemaName.ToUpperInvariant().GetHashCode();
        return new Guid(hash, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1);
    }

    /// <summary>
    /// Gets the progress ID for a schema (for UI to subscribe to progress updates).
    /// </summary>
    public static Guid GetProgressId(string schemaName) => GenerateSchemaProgressId(schemaName);

    private async Task<long> GetTableRowCountAsync(string connectionString, string table, CancellationToken cancellationToken)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var countQuery = $"SELECT COUNT_BIG(*) FROM {table}";
        await using var cmd = new SqlCommand(countQuery, connection);
        cmd.CommandTimeout = 120; // 2 minutes for count

        return Convert.ToInt64(await cmd.ExecuteScalarAsync(cancellationToken));
    }

    private async Task<long> DeleteTableInBatchesAsync(
        string connectionString,
        string table,
        Guid progressId,
        int basePercent,
        int totalTables,
        int tableIndex,
        CancellationToken cancellationToken)
    {
        var batchSize = _perfSettings.DeletionBatchSize;
        var deletedFromTable = 0L;
        int deletedInBatch;

        // Check if this is a self-referential table (Folders)
        var isFoldersTable = table.EndsWith(".Folders", StringComparison.OrdinalIgnoreCase);

        do
        {
            cancellationToken.ThrowIfCancellationRequested();

            // Use a fresh connection for each batch to avoid timeout/closed connection issues
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            string deleteQuery;
            if (isFoldersTable)
            {
                // Delete only folders that have no child folders (leaf nodes first)
                // This respects the self-referential FK constraint
                deleteQuery = $@"
                    DELETE TOP ({batchSize}) f FROM {table} f
                    WHERE NOT EXISTS (
                        SELECT 1 FROM {table} child
                        WHERE child.ParentFolderID = f.LocalFolderID
                        AND child.InventoryID = f.InventoryID
                    )";
            }
            else
            {
                deleteQuery = $"DELETE TOP ({batchSize}) FROM {table}";
            }

            await using var cmd = new SqlCommand(deleteQuery, connection);
            cmd.CommandTimeout = 600; // 10 minutes per batch for very large tables

            deletedInBatch = await cmd.ExecuteNonQueryAsync(cancellationToken);
            deletedFromTable += deletedInBatch;

            if (deletedInBatch > 0)
            {
                // Calculate progress within this table
                var tableProgressPercent = basePercent + (int)((tableIndex * 100.0 / totalTables) - basePercent) / 2;
                await SendProgressAsync(progressId, "Deleting", table, Math.Min(99, tableProgressPercent),
                    $"Deleted {deletedFromTable:N0} rows from {table}...");
            }

            // For self-referential tables, continue while ANY rows are deleted
            // For other tables, continue while batch is full
        } while (isFoldersTable ? deletedInBatch > 0 : deletedInBatch == batchSize);

        return deletedFromTable;
    }

    private async Task CleanupAppSchemaDataAsync(
        string connectionString,
        string schemaName,
        string initiatedBy,
        CancellationToken cancellationToken)
    {
        var isProduction = schemaName.Equals("ADData", StringComparison.OrdinalIgnoreCase) ||
                          schemaName.Equals("fsapp", StringComparison.OrdinalIgnoreCase);
        var uploadType = schemaName.StartsWith("AD", StringComparison.OrdinalIgnoreCase)
            ? "ADInventory"
            : "NTFSPermissions";

        _logger.LogInformation("Cleaning up app schema data related to [{Schema}] (type: {Type}, production: {IsProduction})",
            schemaName, uploadType, isProduction);

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // If we're truncating staging data, delete related upload records
            if (!isProduction)
            {
                var deleteUploadsCmd = @"
                    DELETE FROM app.ImportStatistics WHERE UploadId IN (
                        SELECT UploadId FROM app.Uploads WHERE UploadType = @UploadType AND Status IN ('Completed', 'Queued', 'Importing')
                    );
                    DELETE FROM app.Uploads WHERE UploadType = @UploadType AND Status IN ('Completed', 'Queued', 'Importing');";

                await using var cmd = new SqlCommand(deleteUploadsCmd, connection);
                cmd.Parameters.AddWithValue("@UploadType", uploadType);
                cmd.CommandTimeout = 300;
                var deletedRows = await cmd.ExecuteNonQueryAsync(cancellationToken);
                _logger.LogInformation("Deleted {Count} upload-related records for {UploadType}", deletedRows, uploadType);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error cleaning up app schema data for [{Schema}]", schemaName);
            // Don't throw - this is a best-effort cleanup
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
