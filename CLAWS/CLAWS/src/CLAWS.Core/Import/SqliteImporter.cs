using System.Data;
using System.Runtime.Versioning;
using Microsoft.Data.SqlClient;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Core.Models;

namespace CLAWS.Core.Import;

/// <summary>
/// Progress callback for import operations.
/// </summary>
public delegate Task ImportProgressCallbackAsync(ImportProgress progress);

/// <summary>
/// Imports data from SQLite databases to SQL Server.
/// </summary>
public interface ISqliteImporter
{
    /// <summary>
    /// Imports all tables from a SQLite database to SQL Server (legacy - assumes NTFSPermissions).
    /// </summary>
    /// <param name="sqlitePath">Path to the SQLite database.</param>
    /// <param name="sqlConnectionString">SQL Server connection string.</param>
    /// <param name="uploadId">Upload ID for progress tracking.</param>
    /// <param name="progressCallback">Optional async callback for progress updates.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Import statistics.</returns>
    Task<ImportStatistics> ImportAllTablesAsync(
        string sqlitePath,
        string sqlConnectionString,
        Guid uploadId,
        ImportProgressCallbackAsync? progressCallback = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Imports all tables from a SQLite database to SQL Server for a specific upload type.
    /// </summary>
    /// <param name="sqlitePath">Path to the SQLite database.</param>
    /// <param name="sqlConnectionString">SQL Server connection string.</param>
    /// <param name="uploadId">Upload ID for progress tracking.</param>
    /// <param name="uploadType">Type of upload determining table mappings and value conversion.</param>
    /// <param name="progressCallback">Optional async callback for progress updates.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Import statistics.</returns>
    Task<ImportStatistics> ImportAllTablesAsync(
        string sqlitePath,
        string sqlConnectionString,
        Guid uploadId,
        UploadType uploadType,
        ImportProgressCallbackAsync? progressCallback = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Checks for existing collections in the target database.
    /// </summary>
    /// <param name="sqlitePath">Path to the SQLite database.</param>
    /// <param name="sqlConnectionString">SQL Server connection string.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>List of InventoryIDs that already exist in the target.</returns>
    Task<List<Guid>> CheckExistingCollectionsAsync(
        string sqlitePath,
        string sqlConnectionString,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all InventoryIDs from the SQLite database (legacy - assumes NTFSPermissions).
    /// </summary>
    /// <param name="sqlitePath">Path to the SQLite database.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>List of InventoryIDs found in the SQLite database.</returns>
    Task<List<Guid>> GetInventoryIdsFromSqliteAsync(
        string sqlitePath,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all InventoryIDs from the SQLite database for a specific upload type.
    /// </summary>
    /// <param name="sqlitePath">Path to the SQLite database.</param>
    /// <param name="uploadType">Type of upload to determine the correct table to query.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>List of InventoryIDs found in the SQLite database.</returns>
    Task<List<Guid>> GetInventoryIdsFromSqliteAsync(
        string sqlitePath,
        UploadType uploadType,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Implementation of SQLite to SQL Server data import.
/// </summary>
[SupportedOSPlatform("windows")]
public class SqliteImporter : ISqliteImporter
{
    private readonly ILogger<SqliteImporter> _logger;
    private readonly ImportSettings _importSettings;
    private readonly DatabasePerformanceSettings _performanceSettings;
    private readonly IValueConverterFactory _converterFactory;

    public SqliteImporter(ILogger<SqliteImporter> logger, ImportSettings importSettings, DatabasePerformanceSettings performanceSettings)
        : this(logger, importSettings, performanceSettings, new ValueConverterFactory())
    {
    }

    public SqliteImporter(ILogger<SqliteImporter> logger, ImportSettings importSettings, DatabasePerformanceSettings performanceSettings, IValueConverterFactory converterFactory)
    {
        _logger = logger;
        _importSettings = importSettings;
        _performanceSettings = performanceSettings;
        _converterFactory = converterFactory;
    }

    /// <inheritdoc/>
    public async Task<List<Guid>> CheckExistingCollectionsAsync(
        string sqlitePath,
        string sqlConnectionString,
        CancellationToken cancellationToken = default)
    {
        var existingIds = new List<Guid>();

        // Get InventoryIDs from SQLite
        var sqliteIds = new List<Guid>();
        var sqliteConnStr = new SqliteConnectionStringBuilder
        {
            DataSource = sqlitePath,
            Mode = SqliteOpenMode.ReadOnly
        }.ConnectionString;

        await using (var sqliteConn = new SqliteConnection(sqliteConnStr))
        {
            await sqliteConn.OpenAsync(cancellationToken);
            await using var cmd = sqliteConn.CreateCommand();
            cmd.CommandText = "SELECT InventoryID FROM app__CollectionInfo";
            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                sqliteIds.Add(Guid.Parse(reader.GetString(0)));
            }
        }

        // Check which ones exist in SQL Server
        await using (var sqlConn = new SqlConnection(sqlConnectionString))
        {
            await sqlConn.OpenAsync(cancellationToken);
            foreach (var id in sqliteIds)
            {
                await using var cmd = sqlConn.CreateCommand();
                cmd.CommandText = "SELECT COUNT(*) FROM [fssimport].[CollectionInfo] WHERE InventoryID = @id";
                cmd.Parameters.AddWithValue("@id", id);
                var count = (int)(await cmd.ExecuteScalarAsync(cancellationToken) ?? 0);
                if (count > 0)
                {
                    existingIds.Add(id);
                }
            }
        }

        return existingIds;
    }

    /// <inheritdoc/>
    public Task<List<Guid>> GetInventoryIdsFromSqliteAsync(
        string sqlitePath,
        CancellationToken cancellationToken = default)
    {
        // Legacy method - assumes NTFSPermissions
        return GetInventoryIdsFromSqliteAsync(sqlitePath, UploadType.NTFSPermissions, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<List<Guid>> GetInventoryIdsFromSqliteAsync(
        string sqlitePath,
        UploadType uploadType,
        CancellationToken cancellationToken = default)
    {
        var inventoryIds = new List<Guid>();

        var sqliteConnStr = new SqliteConnectionStringBuilder
        {
            DataSource = sqlitePath,
            Mode = SqliteOpenMode.ReadOnly
        }.ConnectionString;

        await using var sqliteConn = new SqliteConnection(sqliteConnStr);
        await sqliteConn.OpenAsync(cancellationToken);

        await using var cmd = sqliteConn.CreateCommand();

        // Type-specific query
        cmd.CommandText = uploadType switch
        {
            UploadType.ADInventory => "SELECT InventoryID FROM AD_CollectionInfo",
            _ => "SELECT InventoryID FROM app__CollectionInfo"
        };

        await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            if (!reader.IsDBNull(0) && Guid.TryParse(reader.GetString(0), out var id))
            {
                inventoryIds.Add(id);
            }
        }

        _logger.LogInformation("Found {Count} InventoryID(s) in SQLite database ({Type}): {Ids}",
            inventoryIds.Count, uploadType, string.Join(", ", inventoryIds.Select(id => id.ToString().Substring(0, 8))));

        return inventoryIds;
    }

    /// <inheritdoc/>
    public Task<ImportStatistics> ImportAllTablesAsync(
        string sqlitePath,
        string sqlConnectionString,
        Guid uploadId,
        ImportProgressCallbackAsync? progressCallback = null,
        CancellationToken cancellationToken = default)
    {
        // Legacy method - assumes NTFSPermissions
        return ImportAllTablesAsync(sqlitePath, sqlConnectionString, uploadId, UploadType.NTFSPermissions, progressCallback, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<ImportStatistics> ImportAllTablesAsync(
        string sqlitePath,
        string sqlConnectionString,
        Guid uploadId,
        UploadType uploadType,
        ImportProgressCallbackAsync? progressCallback = null,
        CancellationToken cancellationToken = default)
    {
        var statistics = new ImportStatistics
        {
            UploadId = uploadId,
            StartedAt = DateTime.UtcNow
        };

        var sqliteConnStr = new SqliteConnectionStringBuilder
        {
            DataSource = sqlitePath,
            Mode = SqliteOpenMode.ReadOnly
        }.ConnectionString;

        _logger.LogInformation("Starting import from {SqlitePath} (Type: {UploadType})", sqlitePath, uploadType);

        await using var sqliteConn = new SqliteConnection(sqliteConnStr);
        await sqliteConn.OpenAsync(cancellationToken);

        await using var sqlConn = new SqlConnection(sqlConnectionString);
        await sqlConn.OpenAsync(cancellationToken);

        // Prepare partitions if partitioning is enabled
        if (_performanceSettings.PartitioningEnabled && _performanceSettings.AutoPreparePartitions)
        {
            await PreparePartitionsForImportAsync(sqliteConn, sqlConn, uploadType, cancellationToken);
        }

        // Try to load pre-computed table counts (optimization for large databases)
        var preComputedCounts = await GetPreComputedCountsAsync(sqliteConn, cancellationToken);
        if (preComputedCounts != null)
        {
            _logger.LogInformation("Using pre-computed table counts for import progress tracking");
        }
        else
        {
            _logger.LogInformation("Pre-computed counts not available, will use COUNT(*) queries for progress");
        }

        // Get type-specific table mappings
        var tableMappings = TableMappings.GetImportOrder(uploadType).ToList();
        var totalTables = tableMappings.Count;
        var currentTable = 0;

        // Create type-specific value converter
        var valueConverter = _converterFactory.CreateConverter(uploadType);

        foreach (var mapping in tableMappings)
        {
            currentTable++;
            cancellationToken.ThrowIfCancellationRequested();

            var progress = new ImportProgress
            {
                UploadId = uploadId,
                Phase = "Importing",
                CurrentTable = mapping.DisplayName,
                PercentComplete = (int)((currentTable - 1) * 100.0 / totalTables),
                Message = $"Importing {mapping.DisplayName}..."
            };
            if (progressCallback != null) await progressCallback(progress);

            _logger.LogInformation("Importing table {Table} ({Current}/{Total})",
                mapping.DisplayName, currentTable, totalTables);

            var tableStats = await ImportTableAsync(
                sqliteConn,
                sqlConn,
                mapping,
                uploadId,
                uploadType,
                valueConverter,
                preComputedCounts,
                progressCallback,
                cancellationToken);

            statistics.TableStatistics.AddRange(tableStats);
        }

        statistics.CompletedAt = DateTime.UtcNow;

        var finalProgress = new ImportProgress
        {
            UploadId = uploadId,
            Phase = "Complete",
            PercentComplete = 100,
            Message = $"Import complete. {statistics.TotalRecordsImported:N0} records imported.",
            RowsProcessed = statistics.TotalRecordsImported
        };
        if (progressCallback != null) await progressCallback(finalProgress);

        _logger.LogInformation("Import complete ({UploadType}). {TotalRecords:N0} records imported in {Duration}",
            uploadType, statistics.TotalRecordsImported, statistics.Duration);

        return statistics;
    }

    private async Task<List<TableImportStatistic>> ImportTableAsync(
        SqliteConnection sqliteConn,
        SqlConnection sqlConn,
        TableMapping mapping,
        Guid uploadId,
        UploadType uploadType,
        IValueConverter valueConverter,
        Dictionary<string, long>? preComputedCounts,
        ImportProgressCallbackAsync? progressCallback,
        CancellationToken cancellationToken)
    {
        var stats = new List<TableImportStatistic>();
        var startTime = DateTime.UtcNow;

        // Get column info from SQLite
        var columns = await GetTableColumnsAsync(sqliteConn, mapping.GetSqliteTableName(), cancellationToken);
        if (columns.Count == 0)
        {
            _logger.LogWarning("No columns found for table {Table}, skipping", mapping.SqliteTable);
            return stats;
        }

        // Find InventoryID column index for per-inventory counting
        var inventoryIdColumnIndex = columns.FindIndex(c =>
            c.Name.Equals("InventoryID", StringComparison.OrdinalIgnoreCase));

        // For ADInventory tables that don't have InventoryID, try CollectionID
        var collectionIdColumnIndex = inventoryIdColumnIndex < 0
            ? columns.FindIndex(c => c.Name.Equals("CollectionID", StringComparison.OrdinalIgnoreCase))
            : -1;

        // Dictionary to track actual per-inventory record counts
        var perInventoryCounts = new Dictionary<Guid, long>();

        // Get row count for progress (uses pre-computed if available)
        var totalRows = await GetRowCountWithFallbackAsync(sqliteConn, mapping.GetSqliteTableName(), preComputedCounts, cancellationToken);
        _logger.LogInformation("Table {Table} has {RowCount:N0} rows", mapping.DisplayName, totalRows);

        if (totalRows == 0)
        {
            return stats;
        }

        // Build SELECT query
        var columnList = string.Join(", ", columns.Select(c => $"[{c.Name}]"));
        var selectQuery = $"SELECT {columnList} FROM [{mapping.GetSqliteTableName()}]";

        // Build INSERT query for SQL Server
        var paramList = string.Join(", ", columns.Select((c, i) => $"@p{i}"));
        var insertQuery = $"INSERT INTO {mapping.GetMssqlTableName()} ({columnList}) VALUES ({paramList})";

        await using var selectCmd = sqliteConn.CreateCommand();
        selectCmd.CommandText = selectQuery;

        await using var reader = await selectCmd.ExecuteReaderAsync(cancellationToken);

        long rowsProcessed = 0;
        var batchRows = new List<object?[]>();

        using var transaction = _importSettings.TransactionMode == TransactionMode.PerTable
            ? sqlConn.BeginTransaction()
            : null;

        try
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                var values = new object?[columns.Count];
                for (int i = 0; i < columns.Count; i++)
                {
                    // Use the value converter for type-specific conversions
                    values[i] = reader.IsDBNull(i) ? null : valueConverter.Convert(reader.GetValue(i), columns[i]);
                }
                batchRows.Add(values);

                // Track per-inventory count if table has InventoryID column
                if (inventoryIdColumnIndex >= 0 && !reader.IsDBNull(inventoryIdColumnIndex))
                {
                    var inventoryIdStr = reader.GetString(inventoryIdColumnIndex);
                    if (Guid.TryParse(inventoryIdStr, out var inventoryId))
                    {
                        if (!perInventoryCounts.ContainsKey(inventoryId))
                        {
                            perInventoryCounts[inventoryId] = 0;
                        }
                        perInventoryCounts[inventoryId]++;
                    }
                }
                // For ADInventory tables with CollectionID, use that for tracking
                // CollectionID is stored as TEXT (GUID string) in SQLite
                else if (collectionIdColumnIndex >= 0 && !reader.IsDBNull(collectionIdColumnIndex))
                {
                    var collectionIdStr = reader.GetString(collectionIdColumnIndex);
                    if (Guid.TryParse(collectionIdStr, out var trackingId))
                    {
                        if (!perInventoryCounts.ContainsKey(trackingId))
                        {
                            perInventoryCounts[trackingId] = 0;
                        }
                        perInventoryCounts[trackingId]++;
                    }
                }

                if (batchRows.Count >= _performanceSettings.ImportBatchSize)
                {
                    await InsertBatchAsync(sqlConn, transaction, insertQuery, columns, batchRows, cancellationToken);
                    rowsProcessed += batchRows.Count;
                    batchRows.Clear();

                    // Report progress
                    var percent = (int)(rowsProcessed * 100.0 / totalRows);
                    if (progressCallback != null)
                    {
                        await progressCallback(new ImportProgress
                        {
                            UploadId = uploadId,
                            Phase = "Importing",
                            CurrentTable = mapping.DisplayName,
                            PercentComplete = percent,
                            RowsProcessed = rowsProcessed,
                            TotalRows = totalRows,
                            Message = $"Importing {mapping.DisplayName}: {rowsProcessed:N0} / {totalRows:N0} rows"
                        });
                    }
                }
            }

            // Insert remaining rows
            if (batchRows.Count > 0)
            {
                _logger.LogInformation("Inserting final batch of {Count} rows for {Table}",
                    batchRows.Count, mapping.DisplayName);
                await InsertBatchAsync(sqlConn, transaction, insertQuery, columns, batchRows, cancellationToken);
                rowsProcessed += batchRows.Count;
                _logger.LogInformation("Final batch inserted for {Table}. Total rows: {Total}",
                    mapping.DisplayName, rowsProcessed);
            }

            _logger.LogInformation("Committing transaction for {Table}", mapping.DisplayName);
            transaction?.Commit();
            _logger.LogInformation("Transaction committed for {Table}", mapping.DisplayName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error importing table {Table}. Rolling back transaction.", mapping.DisplayName);
            transaction?.Rollback();
            throw;
        }

        var duration = DateTime.UtcNow - startTime;

        // Create statistics with actual per-inventory counts
        if (perInventoryCounts.Count > 0)
        {
            // Use actual per-inventory counts tracked during import
            foreach (var kvp in perInventoryCounts)
            {
                // Calculate proportional duration based on record count
                var proportionalDuration = rowsProcessed > 0
                    ? (long)(duration.TotalMilliseconds * kvp.Value / rowsProcessed)
                    : (long)duration.TotalMilliseconds / perInventoryCounts.Count;

                stats.Add(new TableImportStatistic
                {
                    InventoryId = kvp.Key,
                    TableName = mapping.MssqlTable,
                    RecordsImported = kvp.Value,
                    DurationMs = proportionalDuration
                });
            }

            _logger.LogDebug("Per-inventory counts for {Table}: {Counts}",
                mapping.DisplayName,
                string.Join(", ", perInventoryCounts.Select(kvp =>
                    $"{kvp.Key.ToString().Substring(0, 8)}={kvp.Value:N0}")));
        }
        else
        {
            // Table doesn't have InventoryID column - use a single stat with Guid.Empty
            stats.Add(new TableImportStatistic
            {
                InventoryId = Guid.Empty,
                TableName = mapping.MssqlTable,
                RecordsImported = rowsProcessed,
                DurationMs = (long)duration.TotalMilliseconds
            });
        }

        _logger.LogInformation("Imported {RowCount:N0} rows to {Table} in {Duration}",
            rowsProcessed, mapping.DisplayName, duration);

        return stats;
    }

    private async Task<List<ColumnInfo>> GetTableColumnsAsync(
        SqliteConnection connection,
        string tableName,
        CancellationToken cancellationToken)
    {
        var columns = new List<ColumnInfo>();
        await using var cmd = connection.CreateCommand();
        cmd.CommandText = $"PRAGMA table_info([{tableName}])";

        await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            columns.Add(new ColumnInfo
            {
                Name = reader.GetString(1),
                Type = reader.GetString(2).ToUpperInvariant(),
                IsNullable = reader.GetInt32(3) == 0,
                IsPrimaryKey = reader.GetInt32(5) == 1
            });
        }

        return columns;
    }

    private async Task<long> GetRowCountAsync(
        SqliteConnection connection,
        string tableName,
        CancellationToken cancellationToken)
    {
        await using var cmd = connection.CreateCommand();
        cmd.CommandText = $"SELECT COUNT(*) FROM [{tableName}]";
        var result = await cmd.ExecuteScalarAsync(cancellationToken);
        return Convert.ToInt64(result);
    }

    /// <summary>
    /// Reads pre-computed table row counts from the SQLite database if available.
    /// This optimization avoids expensive COUNT(*) queries during import.
    /// </summary>
    /// <param name="connection">Open SQLite connection.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Dictionary of table name to row count, or null if pre-computed counts are not available.</returns>
    private async Task<Dictionary<string, long>?> GetPreComputedCountsAsync(
        SqliteConnection connection,
        CancellationToken cancellationToken)
    {
        try
        {
            // Check if the app__TableCounts table exists
            await using var checkCmd = connection.CreateCommand();
            checkCmd.CommandText = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='app__TableCounts'";
            var tableExists = Convert.ToInt32(await checkCmd.ExecuteScalarAsync(cancellationToken)) > 0;

            if (!tableExists)
            {
                _logger.LogDebug("Pre-computed table counts not available (app__TableCounts table not found)");
                return null;
            }

            // Read all counts into dictionary
            var counts = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
            await using var cmd = connection.CreateCommand();
            cmd.CommandText = "SELECT TableName, RowCount FROM app__TableCounts";

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var tableName = reader.GetString(0);
                var rowCount = reader.GetInt64(1);
                counts[tableName] = rowCount;
            }

            if (counts.Count > 0)
            {
                _logger.LogInformation("Loaded {Count} pre-computed table counts from SQLite", counts.Count);
            }

            return counts.Count > 0 ? counts : null;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to read pre-computed table counts, will use COUNT(*) queries");
            return null;
        }
    }

    /// <summary>
    /// Gets the row count for a table, using pre-computed count if available.
    /// </summary>
    private async Task<long> GetRowCountWithFallbackAsync(
        SqliteConnection connection,
        string tableName,
        Dictionary<string, long>? preComputedCounts,
        CancellationToken cancellationToken)
    {
        // Try to get pre-computed count first
        if (preComputedCounts != null)
        {
            // Try exact match first
            if (preComputedCounts.TryGetValue(tableName, out var count))
            {
                _logger.LogDebug("Using pre-computed row count for {Table}: {Count:N0}", tableName, count);
                return count;
            }

            // Try without app__ prefix (SQLite uses app__Folders, SQL uses Folders)
            var shortName = tableName.StartsWith("app__", StringComparison.OrdinalIgnoreCase)
                ? tableName.Substring(5)
                : tableName;

            if (preComputedCounts.TryGetValue(shortName, out count))
            {
                _logger.LogDebug("Using pre-computed row count for {Table}: {Count:N0}", tableName, count);
                return count;
            }

            // Try with app__ prefix
            if (preComputedCounts.TryGetValue("app__" + tableName, out count))
            {
                _logger.LogDebug("Using pre-computed row count for {Table}: {Count:N0}", tableName, count);
                return count;
            }
        }

        // Fall back to COUNT(*) query
        _logger.LogDebug("Computing row count for {Table} via COUNT(*)", tableName);
        return await GetRowCountAsync(connection, tableName, cancellationToken);
    }

    private async Task<List<Guid>> GetInventoryIdsAsync(
        SqliteConnection connection,
        string tableName,
        CancellationToken cancellationToken)
    {
        var ids = new List<Guid>();
        try
        {
            await using var cmd = connection.CreateCommand();
            cmd.CommandText = $"SELECT DISTINCT InventoryID FROM [{tableName}]";
            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                if (!reader.IsDBNull(0) && Guid.TryParse(reader.GetString(0), out var id))
                {
                    ids.Add(id);
                }
            }
        }
        catch
        {
            // Table might not have InventoryID column
        }
        return ids.Count > 0 ? ids : new List<Guid> { Guid.Empty };
    }

    private async Task InsertBatchAsync(
        SqlConnection connection,
        SqlTransaction? transaction,
        string insertQuery,
        List<ColumnInfo> columns,
        List<object?[]> rows,
        CancellationToken cancellationToken)
    {
        if (rows.Count == 0) return;

        // Use SqlBulkCopy for efficient bulk inserts
        // Extract table name from insert query: INSERT INTO [schema].[table] (...)
        var tableNameMatch = System.Text.RegularExpressions.Regex.Match(
            insertQuery, @"INSERT INTO (\[?\w+\]?\.\[?\w+\]?)");

        if (!tableNameMatch.Success)
        {
            _logger.LogWarning("Could not parse table name from query, falling back to individual inserts");
            await InsertBatchIndividualAsync(connection, transaction, insertQuery, columns, rows, cancellationToken);
            return;
        }

        var tableName = tableNameMatch.Groups[1].Value;

        try
        {
            // Create a DataTable for bulk copy - use object type to avoid type conversion issues
            using var dataTable = new DataTable();
            foreach (var col in columns)
            {
                // Use object type for flexibility - SqlBulkCopy will handle conversion
                dataTable.Columns.Add(col.Name, typeof(object));
            }

            // Add rows to DataTable
            foreach (var row in rows)
            {
                var dataRow = dataTable.NewRow();
                for (int i = 0; i < columns.Count; i++)
                {
                    dataRow[i] = row[i] ?? DBNull.Value;
                }
                dataTable.Rows.Add(dataRow);
            }

            // Perform bulk copy
            using var bulkCopy = new SqlBulkCopy(connection, SqlBulkCopyOptions.Default, transaction)
            {
                DestinationTableName = tableName,
                BatchSize = rows.Count,
                BulkCopyTimeout = _performanceSettings.BulkCopyTimeoutSeconds
            };

            // Map columns by name
            foreach (var col in columns)
            {
                bulkCopy.ColumnMappings.Add(col.Name, col.Name);
            }

            _logger.LogDebug("Bulk copying {RowCount} rows to {Table}", rows.Count, tableName);
            await bulkCopy.WriteToServerAsync(dataTable, cancellationToken);
            _logger.LogDebug("Bulk copy completed for {Table}", tableName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "SqlBulkCopy failed for table {Table} with {RowCount} rows. Falling back to individual inserts.",
                tableName, rows.Count);

            // Fallback to individual inserts
            await InsertBatchIndividualAsync(connection, transaction, insertQuery, columns, rows, cancellationToken);
        }
    }


    private async Task InsertBatchIndividualAsync(
        SqlConnection connection,
        SqlTransaction? transaction,
        string insertQuery,
        List<ColumnInfo> columns,
        List<object?[]> rows,
        CancellationToken cancellationToken)
    {
        // Fallback: individual inserts (slow, but works if bulk copy fails)
        foreach (var row in rows)
        {
            await using var cmd = connection.CreateCommand();
            cmd.CommandText = insertQuery;
            cmd.Transaction = transaction;

            for (int i = 0; i < columns.Count; i++)
            {
                var param = cmd.Parameters.AddWithValue($"@p{i}", row[i] ?? DBNull.Value);

                // Set appropriate SQL types
                if (columns[i].Name.Equals("InventoryID", StringComparison.OrdinalIgnoreCase))
                {
                    param.SqlDbType = SqlDbType.UniqueIdentifier;
                }
            }

            await cmd.ExecuteNonQueryAsync(cancellationToken);
        }
    }

    /// <summary>
    /// Prepares database partitions for the collections being imported.
    /// This ensures partition boundaries exist before bulk importing data.
    /// </summary>
    private async Task PreparePartitionsForImportAsync(
        SqliteConnection sqliteConn,
        SqlConnection sqlConn,
        UploadType uploadType,
        CancellationToken cancellationToken)
    {
        try
        {
            if (uploadType == UploadType.ADInventory)
            {
                // For AD Inventory, get CollectionIDs and prepare partitions
                var collectionIds = await GetCollectionIdsFromSqliteAsync(sqliteConn, cancellationToken);
                foreach (var collectionId in collectionIds)
                {
                    await using var cmd = sqlConn.CreateCommand();
                    cmd.CommandText = "dbo.usp_PreparePartitionForImport";
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 60;
                    cmd.Parameters.AddWithValue("@CollectionID", collectionId);

                    await cmd.ExecuteNonQueryAsync(cancellationToken);
                    _logger.LogDebug("Prepared partition for CollectionID {CollectionId}", collectionId);
                }

                _logger.LogInformation("Prepared {Count} partitions for AD Inventory import", collectionIds.Count);
            }
            else
            {
                // For NTFS Permissions, get InventoryIDs and prepare partitions
                var inventoryIds = await GetInventoryIdsFromSqliteInternalAsync(sqliteConn, cancellationToken);
                foreach (var inventoryId in inventoryIds)
                {
                    await using var cmd = sqlConn.CreateCommand();
                    cmd.CommandText = "dbo.usp_PreparePartitionForImport";
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 60;
                    cmd.Parameters.AddWithValue("@InventoryID", inventoryId);

                    await cmd.ExecuteNonQueryAsync(cancellationToken);
                    _logger.LogDebug("Prepared partition for InventoryID {InventoryId}", inventoryId);
                }

                _logger.LogInformation("Prepared {Count} partitions for NTFS Permissions import", inventoryIds.Count);
            }
        }
        catch (SqlException ex) when (ex.Number == 2812) // Stored procedure not found
        {
            _logger.LogWarning("Partition preparation skipped: usp_PreparePartitionForImport not found. " +
                "Ensure partitioning SQL scripts have been applied to the database.");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error preparing partitions for import. Import will continue without partition preparation.");
        }
    }

    /// <summary>
    /// Gets InventoryIDs from the SQLite database (internal method for partition preparation).
    /// </summary>
    private async Task<List<Guid>> GetInventoryIdsFromSqliteInternalAsync(
        SqliteConnection connection,
        CancellationToken cancellationToken)
    {
        var ids = new List<Guid>();
        await using var cmd = connection.CreateCommand();
        cmd.CommandText = "SELECT DISTINCT InventoryID FROM app__CollectionInfo";
        await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            if (!reader.IsDBNull(0) && Guid.TryParse(reader.GetString(0), out var id))
            {
                ids.Add(id);
            }
        }
        return ids;
    }

    /// <summary>
    /// Gets CollectionIDs from the SQLite database for AD Inventory imports.
    /// CollectionID is stored as TEXT (GUID string) in SQLite.
    /// </summary>
    private async Task<List<Guid>> GetCollectionIdsFromSqliteAsync(
        SqliteConnection connection,
        CancellationToken cancellationToken)
    {
        var ids = new List<Guid>();
        await using var cmd = connection.CreateCommand();
        cmd.CommandText = "SELECT DISTINCT CollectionID FROM AD_CollectionInfo";
        await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            if (!reader.IsDBNull(0))
            {
                // CollectionID is stored as TEXT in SQLite - parse to Guid
                if (Guid.TryParse(reader.GetString(0), out var id))
                    ids.Add(id);
            }
        }
        return ids;
    }

}
