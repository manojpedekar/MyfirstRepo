using Microsoft.Data.SqlClient;
using CLAWS.Core.Configuration;
using CLAWS.Data.Repositories;
using CLAWS.Web.Models;
using System.Data;
using System.Text;

namespace CLAWS.Web.Services;

/// <summary>
/// Service for retrieving collection logs from EventLog tables.
/// Handles schema selection based on upload merge status.
/// </summary>
public class CollectionLogService : ICollectionLogService
{
    private readonly ILogger<CollectionLogService> _logger;
    private readonly IUploadRepository _uploadRepository;
    private readonly SqlServerSettings _sqlSettings;

    // Maximum page size to prevent excessive data loading
    private const int MaxPageSize = 200;

    public CollectionLogService(
        ILogger<CollectionLogService> logger,
        IUploadRepository uploadRepository,
        SqlServerSettings sqlSettings)
    {
        _logger = logger;
        _uploadRepository = uploadRepository;
        _sqlSettings = sqlSettings;
    }

    /// <inheritdoc/>
    public async Task<PagedCollectionLogs> GetLogsForUploadAsync(
        Guid uploadId,
        CollectionLogFilter? filter = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default)
    {
        // Get upload and its inventory IDs
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null)
        {
            return new PagedCollectionLogs
            {
                UploadId = uploadId,
                InventoryLabel = "Upload not found"
            };
        }

        var inventoryIds = upload.ImportStatistics?
            .Select(s => s.InventoryId)
            .Distinct()
            .ToList() ?? new List<Guid>();

        if (inventoryIds.Count == 0)
        {
            return new PagedCollectionLogs
            {
                UploadId = uploadId,
                InventoryLabel = "No inventories found",
                DataSource = DetermineSchema(upload.MergeStatus),
                IsMerged = upload.MergeStatus == "Merged"
            };
        }

        // Determine schema based on merge status
        var schema = DetermineSchema(upload.MergeStatus);
        var isMerged = upload.MergeStatus == "Merged";

        return await QueryLogsAsync(
            uploadId,
            inventoryIds,
            "All Inventories",
            schema,
            isMerged,
            filter,
            page,
            pageSize,
            cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<PagedCollectionLogs> GetLogsForInventoryAsync(
        Guid uploadId,
        Guid inventoryId,
        CollectionLogFilter? filter = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default)
    {
        // Get upload to determine merge status
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null)
        {
            return new PagedCollectionLogs
            {
                UploadId = uploadId,
                InventoryId = inventoryId,
                InventoryLabel = "Upload not found"
            };
        }

        // For partially merged uploads, check which schema has this inventory
        var schema = await DetermineSchemaForInventoryAsync(upload.MergeStatus, inventoryId, cancellationToken);
        var isMerged = schema == "fsapp";

        // Get inventory label
        var inventoryLabel = await GetInventoryLabelAsync(inventoryId, schema, cancellationToken);

        return await QueryLogsAsync(
            uploadId,
            new List<Guid> { inventoryId },
            inventoryLabel,
            schema,
            isMerged,
            filter,
            page,
            pageSize,
            cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<Dictionary<string, int>> GetLogSummaryAsync(
        Guid uploadId,
        Guid? inventoryId = null,
        CancellationToken cancellationToken = default)
    {
        var summary = new Dictionary<string, int>
        {
            ["ERROR"] = 0,
            ["WARNING"] = 0,
            ["INFO"] = 0,
            ["SUCCESS"] = 0,
            ["OTHER"] = 0
        };

        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null)
            return summary;

        var inventoryIds = inventoryId.HasValue
            ? new List<Guid> { inventoryId.Value }
            : upload.ImportStatistics?.Select(s => s.InventoryId).Distinct().ToList() ?? new List<Guid>();

        if (inventoryIds.Count == 0)
            return summary;

        var schema = DetermineSchema(upload.MergeStatus);

        try
        {
            var connectionString = _sqlSettings.BuildConnectionString();
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var sql = $@"
                SELECT Severity, COUNT(*) AS Count
                FROM [{schema}].[EventLog]
                WHERE InventoryID IN ({string.Join(",", inventoryIds.Select((_, i) => $"@id{i}"))})
                GROUP BY Severity";

            await using var command = new SqlCommand(sql, connection);
            command.CommandTimeout = 30;

            for (int i = 0; i < inventoryIds.Count; i++)
            {
                command.Parameters.AddWithValue($"@id{i}", inventoryIds[i]);
            }

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var severity = reader.IsDBNull(0) ? "OTHER" : reader.GetString(0).ToUpperInvariant();
                var count = reader.GetInt32(1);

                if (summary.ContainsKey(severity))
                    summary[severity] = count;
                else
                    summary["OTHER"] += count;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting log summary for upload {UploadId}", uploadId);
        }

        return summary;
    }

    /// <summary>
    /// Determines the schema to query based on merge status.
    /// </summary>
    private static string DetermineSchema(string? mergeStatus)
    {
        return mergeStatus switch
        {
            "Merged" => "fsapp",
            _ => "fssimport"
        };
    }

    /// <summary>
    /// For partially merged uploads, determines which schema contains the specific inventory.
    /// </summary>
    private async Task<string> DetermineSchemaForInventoryAsync(
        string? mergeStatus,
        Guid inventoryId,
        CancellationToken cancellationToken)
    {
        // Simple cases
        if (mergeStatus == "Merged")
            return "fsapp";

        if (mergeStatus != "PartiallyMerged")
            return "fssimport";

        // For partial merge, check which schema has this inventory
        try
        {
            var connectionString = _sqlSettings.BuildConnectionString();
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Check if inventory exists in fsapp schema
            var sql = @"SELECT COUNT(*) FROM [fsapp].[CollectionInfo] WHERE InventoryID = @InventoryId";
            await using var command = new SqlCommand(sql, connection);
            command.Parameters.AddWithValue("@InventoryId", inventoryId);

            var count = (int)(await command.ExecuteScalarAsync(cancellationToken) ?? 0);
            return count > 0 ? "fsapp" : "fssimport";
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error determining schema for inventory {InventoryId}, defaulting to fssimport", inventoryId);
            return "fssimport";
        }
    }

    /// <summary>
    /// Gets a human-readable label for an inventory.
    /// </summary>
    private async Task<string> GetInventoryLabelAsync(
        Guid inventoryId,
        string schema,
        CancellationToken cancellationToken)
    {
        try
        {
            var connectionString = _sqlSettings.BuildConnectionString();
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var sql = $@"
                SELECT TOP 1 ComputerName, ScanPath
                FROM [{schema}].[CollectionInfo]
                WHERE InventoryID = @InventoryId";

            await using var command = new SqlCommand(sql, connection);
            command.Parameters.AddWithValue("@InventoryId", inventoryId);

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                var computer = reader.IsDBNull(0) ? "Unknown" : reader.GetString(0);
                var path = reader.IsDBNull(1) ? "" : reader.GetString(1);
                return string.IsNullOrEmpty(path) ? computer : $"{computer} - {path}";
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error getting label for inventory {InventoryId}", inventoryId);
        }

        return inventoryId.ToString()[..8] + "...";
    }

    /// <summary>
    /// Queries logs from the database with pagination and filtering.
    /// </summary>
    private async Task<PagedCollectionLogs> QueryLogsAsync(
        Guid uploadId,
        List<Guid> inventoryIds,
        string inventoryLabel,
        string schema,
        bool isMerged,
        CollectionLogFilter? filter,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        // Validate and constrain parameters
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);
        filter ??= new CollectionLogFilter();

        var result = new PagedCollectionLogs
        {
            UploadId = uploadId,
            InventoryId = inventoryIds.Count == 1 ? inventoryIds[0] : null,
            InventoryLabel = inventoryLabel,
            DataSource = schema,
            IsMerged = isMerged,
            Page = page,
            PageSize = pageSize,
            AppliedFilter = filter
        };

        if (!_sqlSettings.IsConfigured)
        {
            _logger.LogWarning("SQL Server not configured, cannot query collection logs");
            return result;
        }

        try
        {
            var connectionString = _sqlSettings.BuildConnectionString();
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Build WHERE clause
            var whereBuilder = new StringBuilder();
            var parameters = new List<SqlParameter>();

            // Inventory filter (always applied)
            whereBuilder.Append("InventoryID IN (");
            for (int i = 0; i < inventoryIds.Count; i++)
            {
                if (i > 0) whereBuilder.Append(", ");
                whereBuilder.Append($"@invId{i}");
                parameters.Add(new SqlParameter($"@invId{i}", inventoryIds[i]));
            }
            whereBuilder.Append(')');

            // Severity filter
            if (!string.IsNullOrWhiteSpace(filter.Severity))
            {
                whereBuilder.Append(" AND Severity = @severity");
                parameters.Add(new SqlParameter("@severity", filter.Severity));
            }

            // Source filter
            if (!string.IsNullOrWhiteSpace(filter.Source))
            {
                whereBuilder.Append(" AND Source = @source");
                parameters.Add(new SqlParameter("@source", filter.Source));
            }

            // Text search filter
            if (!string.IsNullOrWhiteSpace(filter.SearchText))
            {
                whereBuilder.Append(" AND (Message LIKE @search OR Path LIKE @search)");
                parameters.Add(new SqlParameter("@search", $"%{filter.SearchText}%"));
            }

            // Date range filter
            if (filter.FromDate.HasValue)
            {
                whereBuilder.Append(" AND Timestamp >= @fromDate");
                parameters.Add(new SqlParameter("@fromDate", filter.FromDate.Value));
            }

            if (filter.ToDate.HasValue)
            {
                whereBuilder.Append(" AND Timestamp <= @toDate");
                parameters.Add(new SqlParameter("@toDate", filter.ToDate.Value));
            }

            var whereClause = whereBuilder.ToString();

            // Get total count
            var countSql = $"SELECT COUNT(*) FROM [{schema}].[EventLog] WHERE {whereClause}";
            await using (var countCommand = new SqlCommand(countSql, connection))
            {
                countCommand.CommandTimeout = 60;
                countCommand.Parameters.AddRange(parameters.ToArray());
                result.TotalItems = (int)(await countCommand.ExecuteScalarAsync(cancellationToken) ?? 0);
            }

            // Get page of data
            var offset = (page - 1) * pageSize;
            var orderColumn = filter.SortBy switch
            {
                "Severity" => "Severity",
                "Source" => "Source",
                "Message" => "Message",
                _ => "Timestamp"
            };
            var orderDirection = filter.Descending ? "DESC" : "ASC";

            var dataSql = $@"
                SELECT EventID, InventoryID, Timestamp, Severity, Source, Message, Path, ErrorCode
                FROM [{schema}].[EventLog]
                WHERE {whereClause}
                ORDER BY {orderColumn} {orderDirection}
                OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY";

            await using var dataCommand = new SqlCommand(dataSql, connection);
            dataCommand.CommandTimeout = 60;

            // Re-add parameters (can't reuse after ExecuteScalarAsync)
            for (int i = 0; i < inventoryIds.Count; i++)
            {
                dataCommand.Parameters.AddWithValue($"@invId{i}", inventoryIds[i]);
            }
            if (!string.IsNullOrWhiteSpace(filter.Severity))
                dataCommand.Parameters.AddWithValue("@severity", filter.Severity);
            if (!string.IsNullOrWhiteSpace(filter.Source))
                dataCommand.Parameters.AddWithValue("@source", filter.Source);
            if (!string.IsNullOrWhiteSpace(filter.SearchText))
                dataCommand.Parameters.AddWithValue("@search", $"%{filter.SearchText}%");
            if (filter.FromDate.HasValue)
                dataCommand.Parameters.AddWithValue("@fromDate", filter.FromDate.Value);
            if (filter.ToDate.HasValue)
                dataCommand.Parameters.AddWithValue("@toDate", filter.ToDate.Value);

            dataCommand.Parameters.AddWithValue("@offset", offset);
            dataCommand.Parameters.AddWithValue("@pageSize", pageSize);

            // Use explicit block to ensure reader is disposed before querying sources
            // (SQL Server connections can only have one active reader at a time without MARS)
            {
                await using var reader = await dataCommand.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    // Normalize severity - treat blank/whitespace as DEBUG
                    var rawSeverity = reader.IsDBNull(3) ? "" : reader.GetString(3).Trim();
                    var severity = string.IsNullOrEmpty(rawSeverity) ? "DEBUG" : rawSeverity.ToUpperInvariant();

                    // Normalize source - trim whitespace
                    var source = reader.IsDBNull(4) ? "" : reader.GetString(4).Trim();

                    var entry = new CollectionLogEntry
                    {
                        EventId = reader.GetInt32(0),
                        InventoryId = reader.GetGuid(1),
                        Timestamp = reader.GetDateTimeOffset(2),
                        Severity = severity,
                        Source = source,
                        Message = reader.IsDBNull(5) ? "" : reader.GetString(5),
                        Path = reader.IsDBNull(6) ? null : reader.GetString(6),
                        ErrorCode = reader.IsDBNull(7) ? null : reader.GetInt32(7)
                    };

                    result.Logs.Add(entry);
                }
            }

            // Get available sources for filtering (reader must be disposed first)
            result.AvailableSources = await GetDistinctSourcesAsync(connection, schema, inventoryIds, cancellationToken);

            _logger.LogDebug("Retrieved {Count} logs (page {Page}/{TotalPages}) from {Schema}.EventLog for {InventoryCount} inventories",
                result.Logs.Count, page, result.TotalPages, schema, inventoryIds.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error querying collection logs from {Schema}.EventLog", schema);
        }

        return result;
    }

    /// <summary>
    /// Gets distinct source values for the filter dropdown.
    /// </summary>
    private async Task<List<string>> GetDistinctSourcesAsync(
        SqlConnection connection,
        string schema,
        List<Guid> inventoryIds,
        CancellationToken cancellationToken)
    {
        var sources = new List<string>();

        try
        {
            var sql = $@"
                SELECT DISTINCT Source
                FROM [{schema}].[EventLog]
                WHERE InventoryID IN ({string.Join(",", inventoryIds.Select((_, i) => $"@id{i}"))})
                AND Source IS NOT NULL
                AND LTRIM(RTRIM(Source)) <> ''
                ORDER BY Source";

            await using var command = new SqlCommand(sql, connection);
            command.CommandTimeout = 30;

            for (int i = 0; i < inventoryIds.Count; i++)
            {
                command.Parameters.AddWithValue($"@id{i}", inventoryIds[i]);
            }

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                if (!reader.IsDBNull(0))
                {
                    var source = reader.GetString(0).Trim();
                    if (!string.IsNullOrEmpty(source))
                        sources.Add(source);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error getting distinct sources");
        }

        return sources;
    }

    /// <inheritdoc/>
    public async Task<PagedCollectionLogs> GetLogsForADDomainAsync(
        Guid uploadId,
        Guid collectionId,
        CollectionLogFilter? filter = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default)
    {
        // Get upload to determine merge status
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null || upload.UploadType != "ADInventory")
        {
            return new PagedCollectionLogs
            {
                UploadId = uploadId,
                InventoryLabel = upload == null ? "Upload not found" : "Not an ADInventory upload"
            };
        }

        var schema = upload.MergeStatus == "Merged" ? "ADData" : "ADImport";
        var domainName = await GetDomainNameAsync(collectionId, schema, cancellationToken);

        return await QueryADLogsAsync(
            uploadId,
            collectionId,
            domainName,
            schema,
            upload.MergeStatus == "Merged",
            filter,
            page,
            pageSize,
            cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<Dictionary<string, int>> GetLogSummaryForADDomainAsync(
        Guid uploadId,
        Guid collectionId,
        CancellationToken cancellationToken = default)
    {
        var summary = new Dictionary<string, int>
        {
            ["ERROR"] = 0,
            ["WARNING"] = 0,
            ["INFO"] = 0,
            ["SUCCESS"] = 0,
            ["OTHER"] = 0
        };

        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null || upload.UploadType != "ADInventory")
            return summary;

        var schema = upload.MergeStatus == "Merged" ? "ADData" : "ADImport";

        try
        {
            var connectionString = _sqlSettings.BuildConnectionString();
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var sql = $@"
                SELECT Level, COUNT(*) AS Count
                FROM [{schema}].[AD_Log]
                WHERE CollectionID = @CollectionId
                GROUP BY Level";

            await using var command = new SqlCommand(sql, connection);
            command.CommandTimeout = 30;
            command.Parameters.AddWithValue("@CollectionId", collectionId);

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var severity = reader.IsDBNull(0) ? "OTHER" : reader.GetString(0).ToUpperInvariant();
                var count = reader.GetInt32(1);

                if (summary.ContainsKey(severity))
                    summary[severity] = count;
                else
                    summary["OTHER"] += count;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting AD log summary for upload {UploadId}, CollectionId {CollectionId}", uploadId, collectionId);
        }

        return summary;
    }

    /// <summary>
    /// Gets the domain name for a CollectionID from ADImport/ADData.CollectionInfo.
    /// </summary>
    private async Task<string> GetDomainNameAsync(
        Guid collectionId,
        string schema,
        CancellationToken cancellationToken)
    {
        try
        {
            var connectionString = _sqlSettings.BuildConnectionString();
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var sql = $@"
                SELECT TOP 1 COALESCE(DomainName, ComputerName)
                FROM [{schema}].[CollectionInfo]
                WHERE CollectionID = @CollectionId";

            await using var command = new SqlCommand(sql, connection);
            command.Parameters.AddWithValue("@CollectionId", collectionId);

            var result = await command.ExecuteScalarAsync(cancellationToken);
            return result?.ToString() ?? $"Collection {collectionId}";
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error getting domain name for CollectionId {CollectionId}", collectionId);
            return $"Collection {collectionId}";
        }
    }

    /// <summary>
    /// Queries AD_Log table for ADInventory uploads.
    /// </summary>
    private async Task<PagedCollectionLogs> QueryADLogsAsync(
        Guid uploadId,
        Guid collectionId,
        string domainName,
        string schema,
        bool isMerged,
        CollectionLogFilter? filter,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        // Validate and constrain parameters
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);
        filter ??= new CollectionLogFilter();

        var result = new PagedCollectionLogs
        {
            UploadId = uploadId,
            InventoryLabel = domainName,
            DataSource = schema,
            IsMerged = isMerged,
            Page = page,
            PageSize = pageSize,
            AppliedFilter = filter
        };

        if (!_sqlSettings.IsConfigured)
        {
            _logger.LogWarning("SQL Server not configured, cannot query AD logs");
            return result;
        }

        try
        {
            var connectionString = _sqlSettings.BuildConnectionString();
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Build WHERE clause
            var whereBuilder = new StringBuilder("CollectionID = @CollectionId");
            var parameters = new List<SqlParameter>
            {
                new SqlParameter("@CollectionId", collectionId)
            };

            // Severity filter (column is "Level" in AD_Log)
            if (!string.IsNullOrWhiteSpace(filter.Severity))
            {
                whereBuilder.Append(" AND Level = @severity");
                parameters.Add(new SqlParameter("@severity", filter.Severity));
            }

            // Source filter (column is "Category" in AD_Log)
            if (!string.IsNullOrWhiteSpace(filter.Source))
            {
                whereBuilder.Append(" AND Category = @source");
                parameters.Add(new SqlParameter("@source", filter.Source));
            }

            // Text search filter - AD_Log has Message column
            if (!string.IsNullOrWhiteSpace(filter.SearchText))
            {
                whereBuilder.Append(" AND Message LIKE @search");
                parameters.Add(new SqlParameter("@search", $"%{filter.SearchText}%"));
            }

            // Date range filter
            if (filter.FromDate.HasValue)
            {
                whereBuilder.Append(" AND Timestamp >= @fromDate");
                parameters.Add(new SqlParameter("@fromDate", filter.FromDate.Value));
            }

            if (filter.ToDate.HasValue)
            {
                whereBuilder.Append(" AND Timestamp <= @toDate");
                parameters.Add(new SqlParameter("@toDate", filter.ToDate.Value));
            }

            var whereClause = whereBuilder.ToString();

            // Get total count
            var countSql = $"SELECT COUNT(*) FROM [{schema}].[AD_Log] WHERE {whereClause}";
            await using (var countCommand = new SqlCommand(countSql, connection))
            {
                countCommand.CommandTimeout = 60;
                countCommand.Parameters.AddRange(parameters.ToArray());
                result.TotalItems = (int)(await countCommand.ExecuteScalarAsync(cancellationToken) ?? 0);
            }

            // Get page of data
            var offset = (page - 1) * pageSize;
            var orderColumn = filter.SortBy switch
            {
                "Severity" => "Level",
                "Source" => "Category",
                "Message" => "Message",
                _ => "Timestamp"
            };
            var orderDirection = filter.Descending ? "DESC" : "ASC";

            // AD_Log schema: LogID, CollectionID, Timestamp, Level, Category, Message, Context, ExceptionMessage, ExceptionType
            var dataSql = $@"
                SELECT LogID, CollectionID, Timestamp, Level, Category, Message, Context, ExceptionMessage, ExceptionType
                FROM [{schema}].[AD_Log]
                WHERE {whereClause}
                ORDER BY {orderColumn} {orderDirection}
                OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY";

            await using var dataCommand = new SqlCommand(dataSql, connection);
            dataCommand.CommandTimeout = 60;

            // Re-add parameters
            dataCommand.Parameters.AddWithValue("@CollectionId", collectionId);
            if (!string.IsNullOrWhiteSpace(filter.Severity))
                dataCommand.Parameters.AddWithValue("@severity", filter.Severity);
            if (!string.IsNullOrWhiteSpace(filter.Source))
                dataCommand.Parameters.AddWithValue("@source", filter.Source);
            if (!string.IsNullOrWhiteSpace(filter.SearchText))
                dataCommand.Parameters.AddWithValue("@search", $"%{filter.SearchText}%");
            if (filter.FromDate.HasValue)
                dataCommand.Parameters.AddWithValue("@fromDate", filter.FromDate.Value);
            if (filter.ToDate.HasValue)
                dataCommand.Parameters.AddWithValue("@toDate", filter.ToDate.Value);

            dataCommand.Parameters.AddWithValue("@offset", offset);
            dataCommand.Parameters.AddWithValue("@pageSize", pageSize);

            await using var reader = await dataCommand.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var rawSeverity = reader.IsDBNull(3) ? "" : reader.GetString(3).Trim();
                var severity = string.IsNullOrEmpty(rawSeverity) ? "DEBUG" : rawSeverity.ToUpperInvariant();
                var category = reader.IsDBNull(4) ? "" : reader.GetString(4).Trim();

                var entry = new CollectionLogEntry
                {
                    EventId = reader.GetInt32(0),
                    // CollectionID is now a native GUID
                    InventoryId = reader.GetGuid(1),
                    Timestamp = new DateTimeOffset(reader.GetDateTime(2), TimeSpan.Zero),
                    Severity = severity,
                    Source = category,
                    Message = reader.IsDBNull(5) ? "" : reader.GetString(5),
                    Path = null,
                    ErrorCode = null,
                    Context = reader.IsDBNull(6) ? null : reader.GetString(6),
                    ExceptionMessage = reader.IsDBNull(7) ? null : reader.GetString(7),
                    ExceptionType = reader.IsDBNull(8) ? null : reader.GetString(8)
                };

                result.Logs.Add(entry);
            }

            _logger.LogDebug("Retrieved {Count} AD logs (page {Page}/{TotalPages}) from {Schema}.AD_Log for CollectionId {CollectionId}",
                result.Logs.Count, page, result.TotalPages, schema, collectionId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error querying AD logs from {Schema}.AD_Log for CollectionId {CollectionId}", schema, collectionId);
        }

        return result;
    }

    /// <inheritdoc/>
    public async Task<PagedCollectionLogs> GetLogsForAllADDomainsAsync(
        Guid uploadId,
        CollectionLogFilter? filter = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default)
    {
        // Get upload to determine merge status and InventoryID
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null || upload.UploadType != "ADInventory")
        {
            return new PagedCollectionLogs
            {
                UploadId = uploadId,
                InventoryLabel = upload == null ? "Upload not found" : "Not an ADInventory upload"
            };
        }

        // Get the InventoryID from import statistics
        var inventoryId = upload.ImportStatistics?.FirstOrDefault()?.InventoryId;
        if (inventoryId == null)
        {
            return new PagedCollectionLogs
            {
                UploadId = uploadId,
                InventoryLabel = "No inventory found"
            };
        }

        var schema = upload.MergeStatus == "Merged" ? "ADData" : "ADImport";
        var isMerged = upload.MergeStatus == "Merged";

        return await QueryAllADLogsAsync(
            uploadId,
            inventoryId.Value,
            schema,
            isMerged,
            filter,
            page,
            pageSize,
            cancellationToken);
    }

    /// <summary>
    /// Queries AD_Log table for all domains in an ADInventory upload.
    /// </summary>
    private async Task<PagedCollectionLogs> QueryAllADLogsAsync(
        Guid uploadId,
        Guid inventoryId,
        string schema,
        bool isMerged,
        CollectionLogFilter? filter,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        // Validate and constrain parameters
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);
        filter ??= new CollectionLogFilter();

        var result = new PagedCollectionLogs
        {
            UploadId = uploadId,
            InventoryLabel = "All AD Domains",
            DataSource = schema,
            IsMerged = isMerged,
            Page = page,
            PageSize = pageSize,
            AppliedFilter = filter
        };

        if (!_sqlSettings.IsConfigured)
        {
            _logger.LogWarning("SQL Server not configured, cannot query AD logs");
            return result;
        }

        try
        {
            var connectionString = _sqlSettings.BuildConnectionString();
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Get all CollectionIDs for this InventoryID
            var collectionIds = new List<Guid>();
            var collectionSql = $@"
                SELECT CollectionID FROM [{schema}].[CollectionInfo]
                WHERE InventoryID = @InventoryId";

            await using (var collCmd = new SqlCommand(collectionSql, connection))
            {
                collCmd.Parameters.AddWithValue("@InventoryId", inventoryId);
                await using var reader = await collCmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    collectionIds.Add(reader.GetGuid(0));
                }
            }

            if (collectionIds.Count == 0)
            {
                return result;
            }

            // Build WHERE clause with all collection IDs
            var whereBuilder = new StringBuilder("CollectionID IN (");
            var parameters = new List<SqlParameter>();
            for (int i = 0; i < collectionIds.Count; i++)
            {
                if (i > 0) whereBuilder.Append(", ");
                whereBuilder.Append($"@collId{i}");
                parameters.Add(new SqlParameter($"@collId{i}", collectionIds[i]));
            }
            whereBuilder.Append(')');

            // Severity filter (column is "Level" in AD_Log)
            if (!string.IsNullOrWhiteSpace(filter.Severity))
            {
                whereBuilder.Append(" AND Level = @severity");
                parameters.Add(new SqlParameter("@severity", filter.Severity));
            }

            // Source filter (column is "Category" in AD_Log)
            if (!string.IsNullOrWhiteSpace(filter.Source))
            {
                whereBuilder.Append(" AND Category = @source");
                parameters.Add(new SqlParameter("@source", filter.Source));
            }

            // Text search filter
            if (!string.IsNullOrWhiteSpace(filter.SearchText))
            {
                whereBuilder.Append(" AND Message LIKE @search");
                parameters.Add(new SqlParameter("@search", $"%{filter.SearchText}%"));
            }

            // Date range filter
            if (filter.FromDate.HasValue)
            {
                whereBuilder.Append(" AND Timestamp >= @fromDate");
                parameters.Add(new SqlParameter("@fromDate", filter.FromDate.Value));
            }

            if (filter.ToDate.HasValue)
            {
                whereBuilder.Append(" AND Timestamp <= @toDate");
                parameters.Add(new SqlParameter("@toDate", filter.ToDate.Value));
            }

            var whereClause = whereBuilder.ToString();

            // Get total count
            var countSql = $"SELECT COUNT(*) FROM [{schema}].[AD_Log] WHERE {whereClause}";
            await using (var countCommand = new SqlCommand(countSql, connection))
            {
                countCommand.CommandTimeout = 60;
                countCommand.Parameters.AddRange(parameters.ToArray());
                result.TotalItems = (int)(await countCommand.ExecuteScalarAsync(cancellationToken) ?? 0);
            }

            // Get page of data
            var offset = (page - 1) * pageSize;
            var orderColumn = filter.SortBy switch
            {
                "Severity" => "Level",
                "Source" => "Category",
                "Message" => "Message",
                _ => "Timestamp"
            };
            var orderDirection = filter.Descending ? "DESC" : "ASC";

            // AD_Log schema: LogID, CollectionID, Timestamp, Level, Category, Message, Context, ExceptionMessage, ExceptionType
            var dataSql = $@"
                SELECT LogID, CollectionID, Timestamp, Level, Category, Message, Context, ExceptionMessage, ExceptionType
                FROM [{schema}].[AD_Log]
                WHERE {whereClause}
                ORDER BY {orderColumn} {orderDirection}
                OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY";

            await using var dataCommand = new SqlCommand(dataSql, connection);
            dataCommand.CommandTimeout = 60;

            // Re-add parameters
            for (int i = 0; i < collectionIds.Count; i++)
            {
                dataCommand.Parameters.AddWithValue($"@collId{i}", collectionIds[i]);
            }
            if (!string.IsNullOrWhiteSpace(filter.Severity))
                dataCommand.Parameters.AddWithValue("@severity", filter.Severity);
            if (!string.IsNullOrWhiteSpace(filter.Source))
                dataCommand.Parameters.AddWithValue("@source", filter.Source);
            if (!string.IsNullOrWhiteSpace(filter.SearchText))
                dataCommand.Parameters.AddWithValue("@search", $"%{filter.SearchText}%");
            if (filter.FromDate.HasValue)
                dataCommand.Parameters.AddWithValue("@fromDate", filter.FromDate.Value);
            if (filter.ToDate.HasValue)
                dataCommand.Parameters.AddWithValue("@toDate", filter.ToDate.Value);

            dataCommand.Parameters.AddWithValue("@offset", offset);
            dataCommand.Parameters.AddWithValue("@pageSize", pageSize);

            await using var reader2 = await dataCommand.ExecuteReaderAsync(cancellationToken);
            while (await reader2.ReadAsync(cancellationToken))
            {
                var rawSeverity = reader2.IsDBNull(3) ? "" : reader2.GetString(3).Trim();
                var severity = string.IsNullOrEmpty(rawSeverity) ? "DEBUG" : rawSeverity.ToUpperInvariant();
                var category = reader2.IsDBNull(4) ? "" : reader2.GetString(4).Trim();

                var entry = new CollectionLogEntry
                {
                    EventId = reader2.GetInt32(0),
                    InventoryId = reader2.GetGuid(1),
                    Timestamp = new DateTimeOffset(reader2.GetDateTime(2), TimeSpan.Zero),
                    Severity = severity,
                    Source = category,
                    Message = reader2.IsDBNull(5) ? "" : reader2.GetString(5),
                    Path = null,
                    ErrorCode = null,
                    Context = reader2.IsDBNull(6) ? null : reader2.GetString(6),
                    ExceptionMessage = reader2.IsDBNull(7) ? null : reader2.GetString(7),
                    ExceptionType = reader2.IsDBNull(8) ? null : reader2.GetString(8)
                };

                result.Logs.Add(entry);
            }

            _logger.LogDebug("Retrieved {Count} AD logs (page {Page}/{TotalPages}) from {Schema}.AD_Log for all domains",
                result.Logs.Count, page, result.TotalPages, schema);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error querying all AD logs from {Schema}.AD_Log", schema);
        }

        return result;
    }

    /// <inheritdoc/>
    public async Task<PagedCollectionLogs> GetLogsForProductionNtfsAsync(
        Guid inventoryId,
        CollectionLogFilter? filter = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default)
    {
        // Always query from production schema (fsapp)
        return await QueryProductionNtfsLogsAsync(
            inventoryId,
            filter,
            page,
            pageSize,
            cancellationToken);
    }

    /// <summary>
    /// Queries EventLog table from production schema (fsapp) for a specific inventory.
    /// </summary>
    private async Task<PagedCollectionLogs> QueryProductionNtfsLogsAsync(
        Guid inventoryId,
        CollectionLogFilter? filter,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        const string schema = "fsapp";
        filter ??= new CollectionLogFilter();
        pageSize = Math.Min(pageSize, MaxPageSize);
        page = Math.Max(page, 1);

        var result = new PagedCollectionLogs
        {
            InventoryId = inventoryId,
            DataSource = $"{schema}.EventLog",
            Page = page,
            PageSize = pageSize
        };

        if (!_sqlSettings.IsConfigured)
        {
            _logger.LogWarning("SQL Server not configured, cannot query production NTFS logs");
            return result;
        }

        try
        {
            await using var connection = new SqlConnection(_sqlSettings.BuildConnectionString());
            await connection.OpenAsync(cancellationToken);

            // Build WHERE clause
            var whereConditions = new List<string> { "[InventoryID] = @InventoryId" };
            var parameters = new List<SqlParameter>
            {
                new("@InventoryId", inventoryId)
            };

            // Severity filter
            if (!string.IsNullOrEmpty(filter.Severity))
            {
                whereConditions.Add("[Severity] = @Severity");
                parameters.Add(new SqlParameter("@Severity", filter.Severity));
            }

            // Source filter
            if (!string.IsNullOrEmpty(filter.Source))
            {
                whereConditions.Add("[Source] = @Source");
                parameters.Add(new SqlParameter("@Source", filter.Source));
            }

            // Text search filter
            if (!string.IsNullOrEmpty(filter.SearchText))
            {
                whereConditions.Add("([Message] LIKE @Search OR [Path] LIKE @Search)");
                parameters.Add(new SqlParameter("@Search", $"%{filter.SearchText}%"));
            }

            var whereClause = string.Join(" AND ", whereConditions);

            // Get total count
            var countSql = $"SELECT COUNT(*) FROM [{schema}].[EventLog] WHERE {whereClause}";
            await using (var countCmd = new SqlCommand(countSql, connection))
            {
                countCmd.CommandTimeout = 60;
                foreach (var param in parameters)
                    countCmd.Parameters.Add(new SqlParameter(param.ParameterName, param.Value));

                result.TotalItems = (int)await countCmd.ExecuteScalarAsync(cancellationToken);
            }

            if (result.TotalItems == 0)
                return result;

            // Build ORDER BY clause
            var orderColumn = filter.SortBy switch
            {
                "Severity" => "Severity",
                "Source" => "Source",
                "Message" => "Message",
                _ => "Timestamp"
            };
            var orderDirection = filter.Descending ? "DESC" : "ASC";

            var dataSql = $@"
                SELECT [EventID], [InventoryID], [Timestamp], [Severity], [Source], [Message], [Path], [ErrorCode]
                FROM [{schema}].[EventLog]
                WHERE {whereClause}
                ORDER BY {orderColumn} {orderDirection}
                OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY";

            await using var dataCmd = new SqlCommand(dataSql, connection);
            dataCmd.CommandTimeout = 60;
            foreach (var param in parameters)
                dataCmd.Parameters.Add(new SqlParameter(param.ParameterName, param.Value));
            dataCmd.Parameters.Add(new SqlParameter("@Offset", (page - 1) * pageSize));
            dataCmd.Parameters.Add(new SqlParameter("@PageSize", pageSize));

            await using var reader = await dataCmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var entry = new CollectionLogEntry
                {
                    EventId = reader.GetInt32(0),
                    InventoryId = reader.GetGuid(1),
                    Timestamp = reader.GetDateTimeOffset(2),
                    Severity = reader.IsDBNull(3) ? "INFO" : reader.GetString(3),
                    Source = reader.IsDBNull(4) ? "" : reader.GetString(4),
                    Message = reader.IsDBNull(5) ? "" : reader.GetString(5),
                    Path = reader.IsDBNull(6) ? null : reader.GetString(6),
                    ErrorCode = reader.IsDBNull(7) ? null : reader.GetInt32(7)
                };
                result.Logs.Add(entry);
            }

            _logger.LogDebug("Retrieved {Count} logs (page {Page}/{TotalPages}) from {Schema}.EventLog for InventoryId {InventoryId}",
                result.Logs.Count, page, result.TotalPages, schema, inventoryId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error querying production NTFS logs from {Schema}.EventLog for InventoryId {InventoryId}", schema, inventoryId);
        }

        return result;
    }

    /// <inheritdoc/>
    public async Task<PagedCollectionLogs> GetLogsForProductionAdAsync(
        Guid collectionId,
        CollectionLogFilter? filter = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default)
    {
        // Always query from production schema (ADData)
        return await QueryProductionADLogsAsync(
            collectionId,
            filter,
            page,
            pageSize,
            cancellationToken);
    }

    /// <summary>
    /// Queries AD_Log table from production schema (ADData) for a specific collection.
    /// </summary>
    private async Task<PagedCollectionLogs> QueryProductionADLogsAsync(
        Guid collectionId,
        CollectionLogFilter? filter,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        const string schema = "ADData";
        filter ??= new CollectionLogFilter();
        pageSize = Math.Min(pageSize, 200);
        page = Math.Max(page, 1);

        var result = new PagedCollectionLogs
        {
            Page = page,
            PageSize = pageSize,
            DataSource = $"{schema}.AD_Log"
        };

        if (!_sqlSettings.IsConfigured)
        {
            _logger.LogWarning("SQL Server not configured, cannot query AD logs");
            return result;
        }

        try
        {
            await using var connection = new SqlConnection(_sqlSettings.BuildConnectionString());
            await connection.OpenAsync(cancellationToken);

            // Build WHERE clause
            var whereConditions = new List<string> { "[CollectionID] = @CollectionId" };
            var parameters = new List<SqlParameter>
            {
                new("@CollectionId", collectionId)
            };

            // Severity filter (column is "Level" in AD_Log)
            if (!string.IsNullOrEmpty(filter.Severity))
            {
                whereConditions.Add("[Level] = @Severity");
                parameters.Add(new SqlParameter("@Severity", filter.Severity));
            }

            // Source filter (column is "Category" in AD_Log)
            if (!string.IsNullOrEmpty(filter.Source))
            {
                whereConditions.Add("[Category] = @Source");
                parameters.Add(new SqlParameter("@Source", filter.Source));
            }

            // Text search filter - AD_Log has Message column
            if (!string.IsNullOrEmpty(filter.SearchText))
            {
                whereConditions.Add("[Message] LIKE @Search");
                parameters.Add(new SqlParameter("@Search", $"%{filter.SearchText}%"));
            }

            var whereClause = string.Join(" AND ", whereConditions);

            // Get total count
            var countSql = $"SELECT COUNT(*) FROM [{schema}].[AD_Log] WHERE {whereClause}";
            await using (var countCmd = new SqlCommand(countSql, connection))
            {
                countCmd.CommandTimeout = 60;
                foreach (var param in parameters)
                    countCmd.Parameters.Add(new SqlParameter(param.ParameterName, param.Value));

                result.TotalItems = (int)await countCmd.ExecuteScalarAsync(cancellationToken);
            }

            if (result.TotalItems == 0)
                return result;

            // Build ORDER BY clause
            var orderBy = GetADLogOrderBy(filter.SortBy, filter.Descending);

            // AD_Log schema: LogID, CollectionID, Timestamp, Level, Category, Message, Context, ExceptionMessage, ExceptionType
            var dataSql = $@"
                SELECT [LogID], [CollectionID], [Timestamp], [Level], [Category], [Message],
                       [Context], [ExceptionMessage], [ExceptionType]
                FROM [{schema}].[AD_Log]
                WHERE {whereClause}
                ORDER BY {orderBy}
                OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY";

            await using var dataCmd = new SqlCommand(dataSql, connection);
            dataCmd.CommandTimeout = 60;
            foreach (var param in parameters)
                dataCmd.Parameters.Add(new SqlParameter(param.ParameterName, param.Value));
            dataCmd.Parameters.Add(new SqlParameter("@Offset", (page - 1) * pageSize));
            dataCmd.Parameters.Add(new SqlParameter("@PageSize", pageSize));

            await using var reader = await dataCmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var entry = new CollectionLogEntry
                {
                    EventId = reader.GetInt32(0),
                    InventoryId = reader.GetGuid(1), // CollectionID maps to InventoryId in the model
                    Timestamp = reader.GetDateTime(2),
                    Severity = reader.IsDBNull(3) ? "INFO" : reader.GetString(3),
                    Source = reader.IsDBNull(4) ? "" : reader.GetString(4),
                    Message = reader.IsDBNull(5) ? "" : reader.GetString(5),
                    // AD-specific fields
                    Context = reader.IsDBNull(6) ? null : reader.GetString(6),
                    ExceptionMessage = reader.IsDBNull(7) ? null : reader.GetString(7),
                    ExceptionType = reader.IsDBNull(8) ? null : reader.GetString(8)
                };
                result.Logs.Add(entry);
            }

            _logger.LogDebug("Retrieved {Count} AD logs (page {Page}/{TotalPages}) from {Schema}.AD_Log for CollectionId {CollectionId}",
                result.Logs.Count, page, result.TotalPages, schema, collectionId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error querying production AD logs from {Schema}.AD_Log for CollectionId {CollectionId}", schema, collectionId);
        }

        return result;
    }

    /// <summary>
    /// Gets the ORDER BY clause for AD_Log queries.
    /// </summary>
    private static string GetADLogOrderBy(string? sortBy, bool descending)
    {
        var column = sortBy?.ToLowerInvariant() switch
        {
            "severity" => "[Level]",
            "source" => "[Category]",
            "message" => "[Message]",
            _ => "[Timestamp]"
        };
        return $"{column} {(descending ? "DESC" : "ASC")}";
    }
}
