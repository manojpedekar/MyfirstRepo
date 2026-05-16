using Microsoft.Data.SqlClient;
using CLAWS.Core.Configuration;
using CLAWS.Web.Models;

namespace CLAWS.Web.Services;

/// <summary>
/// Implementation of Domain Master List (DML) service.
/// </summary>
public class DomainMasterListService : IDomainMasterListService
{
    private readonly ILogger<DomainMasterListService> _logger;
    private readonly SqlServerSettings _sqlSettings;
    private readonly DatabasePerformanceSettings _perfSettings;
    private readonly LoggingSettings _loggingSettings;

    public DomainMasterListService(
        ILogger<DomainMasterListService> logger,
        SqlServerSettings sqlSettings,
        DatabasePerformanceSettings perfSettings,
        LoggingSettings loggingSettings)
    {
        _logger = logger;
        _sqlSettings = sqlSettings;
        _perfSettings = perfSettings;
        _loggingSettings = loggingSettings;
    }

    /// <inheritdoc/>
    public async Task<List<DomainMasterListItem>> GetAllDomainsAsync(bool includeDecommissioned, CancellationToken cancellationToken)
    {
        var results = new List<DomainMasterListItem>();

        if (!_sqlSettings.IsConfigured)
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Use the view for joined data, sorted by DomainName
            // Include most recent CollectionId from ADData for log access
            var query = @"
                SELECT
                    d.DomainID,
                    d.DomainName,
                    d.NetBIOSName,
                    d.BusinessUnit,
                    d.DSResponsibilityLevelID,
                    r.LevelName AS DSResponsibilityLevel,
                    d.IsThirdPartyManaged,
                    d.IsDecommissioned,
                    d.Trust_ADMgmt_TriStateID,
                    t1.StateName AS Trust_ADMgmt,
                    d.Trust_SSCViolet_TriStateID,
                    t2.StateName AS Trust_SSCViolet,
                    d.Trust_SSNC_Corp_TriStateID,
                    t3.StateName AS Trust_SSNC_Corp,
                    d.IsPatchHold,
                    d.HasHealthCheck,
                    d.HasNetwrixAuditor,
                    d.IsSafeguardReady,
                    d.IsCloudIntegrated,
                    t4.StateName AS IsCloudIntegratedState,
                    d.BaselineStatusID,
                    b.StatusName AS BaselineStatus,
                    d.IsClientFacing,
                    d.IsSPLA,
                    d.IsRegulated,
                    d.MSPCustomer,
                    d.POC,
                    d.Purpose,
                    d.Roadmap,
                    d.ManagementServer,
                    d.xldapURL,
                    d.CreatedAt,
                    d.UpdatedAt,
                    d.LastInventoryDate,
                    (SELECT TOP 1 ci.CollectionID
                     FROM ADData.CollectionInfo ci
                     WHERE LOWER(ci.DomainName) = LOWER(d.DomainName)
                     ORDER BY ci.CollectionDateTime DESC) AS CollectionId
                FROM DML.DomainMasterList d
                LEFT JOIN DML.DSResponsibilityLevel r ON d.DSResponsibilityLevelID = r.DSResponsibilityLevelID
                LEFT JOIN DML.TriState t1 ON d.Trust_ADMgmt_TriStateID = t1.TriStateID
                LEFT JOIN DML.TriState t2 ON d.Trust_SSCViolet_TriStateID = t2.TriStateID
                LEFT JOIN DML.TriState t3 ON d.Trust_SSNC_Corp_TriStateID = t3.TriStateID
                LEFT JOIN DML.TriState t4 ON d.IsCloudIntegrated = t4.TriStateID
                LEFT JOIN DML.BaselineStatus b ON d.BaselineStatusID = b.BaselineStatusID
                WHERE (@IncludeDecommissioned = 1 OR d.IsDecommissioned = 0)
                ORDER BY d.DomainName ASC";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@IncludeDecommissioned", includeDecommissioned ? 1 : 0);

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add(MapDomainFromReader(reader));
            }

            _logger.LogDebug("Retrieved {Count} domains from DML.DomainMasterList", results.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error querying domains from DML.DomainMasterList");
        }

        return results;
    }

    /// <inheritdoc/>
    public async Task<DomainMasterListItem?> GetDomainByIdAsync(int domainId, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured)
            return null;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                SELECT
                    d.DomainID,
                    d.DomainName,
                    d.NetBIOSName,
                    d.BusinessUnit,
                    d.DSResponsibilityLevelID,
                    r.LevelName AS DSResponsibilityLevel,
                    d.IsThirdPartyManaged,
                    d.IsDecommissioned,
                    d.Trust_ADMgmt_TriStateID,
                    t1.StateName AS Trust_ADMgmt,
                    d.Trust_SSCViolet_TriStateID,
                    t2.StateName AS Trust_SSCViolet,
                    d.Trust_SSNC_Corp_TriStateID,
                    t3.StateName AS Trust_SSNC_Corp,
                    d.IsPatchHold,
                    d.HasHealthCheck,
                    d.HasNetwrixAuditor,
                    d.IsSafeguardReady,
                    d.IsCloudIntegrated,
                    t4.StateName AS IsCloudIntegratedState,
                    d.BaselineStatusID,
                    b.StatusName AS BaselineStatus,
                    d.IsClientFacing,
                    d.IsSPLA,
                    d.IsRegulated,
                    d.MSPCustomer,
                    d.POC,
                    d.Purpose,
                    d.Roadmap,
                    d.ManagementServer,
                    d.xldapURL,
                    d.CreatedAt,
                    d.UpdatedAt,
                    d.LastInventoryDate,
                    (SELECT TOP 1 ci.CollectionID
                     FROM ADData.CollectionInfo ci
                     WHERE LOWER(ci.DomainName) = LOWER(d.DomainName)
                     ORDER BY ci.CollectionDateTime DESC) AS CollectionId
                FROM DML.DomainMasterList d
                LEFT JOIN DML.DSResponsibilityLevel r ON d.DSResponsibilityLevelID = r.DSResponsibilityLevelID
                LEFT JOIN DML.TriState t1 ON d.Trust_ADMgmt_TriStateID = t1.TriStateID
                LEFT JOIN DML.TriState t2 ON d.Trust_SSCViolet_TriStateID = t2.TriStateID
                LEFT JOIN DML.TriState t3 ON d.Trust_SSNC_Corp_TriStateID = t3.TriStateID
                LEFT JOIN DML.TriState t4 ON d.IsCloudIntegrated = t4.TriStateID
                LEFT JOIN DML.BaselineStatus b ON d.BaselineStatusID = b.BaselineStatusID
                WHERE d.DomainID = @DomainId";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@DomainId", domainId);

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                var domain = MapDomainFromReader(reader);
                await reader.CloseAsync();

                // Load notes
                domain.Notes = await GetNotesAsync(domainId, cancellationToken);

                return domain;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting domain {DomainId} from DML.DomainMasterList", domainId);
        }

        return null;
    }

    /// <inheritdoc/>
    public async Task<(bool Success, string Message, int? DomainId)> CreateDomainAsync(DomainCreateRequest request, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured)
            return (false, "Database is not configured.", null);

        if (string.IsNullOrWhiteSpace(request.DomainName))
            return (false, "Domain name is required.", null);

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                INSERT INTO DML.DomainMasterList (
                    DomainName, NetBIOSName, BusinessUnit, DSResponsibilityLevelID,
                    IsThirdPartyManaged, IsDecommissioned,
                    Trust_ADMgmt_TriStateID, Trust_SSCViolet_TriStateID, Trust_SSNC_Corp_TriStateID,
                    IsPatchHold, HasHealthCheck, HasNetwrixAuditor,
                    IsSafeguardReady, IsCloudIntegrated, BaselineStatusID, IsClientFacing,
                    IsSPLA, IsRegulated, MSPCustomer,
                    POC, Purpose, Roadmap, ManagementServer
                )
                OUTPUT INSERTED.DomainID
                VALUES (
                    @DomainName, @NetBIOSName, @BusinessUnit, @DSResponsibilityLevelID,
                    @IsThirdPartyManaged, @IsDecommissioned,
                    @Trust_ADMgmt_TriStateID, @Trust_SSCViolet_TriStateID, @Trust_SSNC_Corp_TriStateID,
                    @IsPatchHold, @HasHealthCheck, @HasNetwrixAuditor,
                    @IsSafeguardReady, @IsCloudIntegrated, @BaselineStatusID, @IsClientFacing,
                    @IsSPLA, @IsRegulated, @MSPCustomer,
                    @POC, @Purpose, @Roadmap, @ManagementServer
                )";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            AddDomainParameters(cmd, request);

            var domainId = (int)(await cmd.ExecuteScalarAsync(cancellationToken))!;

            _logger.LogInformation("Created domain {DomainId}: {DomainName}", domainId, request.DomainName);
            return (true, "Domain created successfully.", domainId);
        }
        catch (SqlException ex) when (ex.Number == 2627 || ex.Number == 2601) // Unique constraint violation
        {
            _logger.LogWarning("Duplicate domain name: {DomainName}", request.DomainName);
            return (false, $"A domain with name '{request.DomainName}' already exists.", null);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating domain {DomainName}", request.DomainName);
            return (false, $"Error creating domain: {ex.Message}", null);
        }
    }

    /// <inheritdoc/>
    public async Task<(bool Success, string Message)> UpdateDomainAsync(DomainUpdateRequest request, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured)
            return (false, "Database is not configured.");

        if (string.IsNullOrWhiteSpace(request.DomainName))
            return (false, "Domain name is required.");

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                UPDATE DML.DomainMasterList SET
                    DomainName = @DomainName,
                    NetBIOSName = @NetBIOSName,
                    BusinessUnit = @BusinessUnit,
                    DSResponsibilityLevelID = @DSResponsibilityLevelID,
                    IsThirdPartyManaged = @IsThirdPartyManaged,
                    IsDecommissioned = @IsDecommissioned,
                    Trust_ADMgmt_TriStateID = @Trust_ADMgmt_TriStateID,
                    Trust_SSCViolet_TriStateID = @Trust_SSCViolet_TriStateID,
                    Trust_SSNC_Corp_TriStateID = @Trust_SSNC_Corp_TriStateID,
                    IsPatchHold = @IsPatchHold,
                    HasHealthCheck = @HasHealthCheck,
                    HasNetwrixAuditor = @HasNetwrixAuditor,
                    IsSafeguardReady = @IsSafeguardReady,
                    IsCloudIntegrated = @IsCloudIntegrated,
                    BaselineStatusID = @BaselineStatusID,
                    IsClientFacing = @IsClientFacing,
                    IsSPLA = @IsSPLA,
                    IsRegulated = @IsRegulated,
                    MSPCustomer = @MSPCustomer,
                    POC = @POC,
                    Purpose = @Purpose,
                    Roadmap = @Roadmap,
                    ManagementServer = @ManagementServer,
                    UpdatedAt = SYSUTCDATETIME()
                WHERE DomainID = @DomainID";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@DomainID", request.DomainID);
            AddDomainParameters(cmd, request);

            var rowsAffected = await cmd.ExecuteNonQueryAsync(cancellationToken);

            if (rowsAffected == 0)
                return (false, "Domain not found.");

            _logger.LogInformation("Updated domain {DomainId}: {DomainName}", request.DomainID, request.DomainName);
            return (true, "Domain updated successfully.");
        }
        catch (SqlException ex) when (ex.Number == 2627 || ex.Number == 2601)
        {
            _logger.LogWarning("Duplicate domain name on update: {DomainName}", request.DomainName);
            return (false, $"A domain with name '{request.DomainName}' already exists.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating domain {DomainId}", request.DomainID);
            return (false, $"Error updating domain: {ex.Message}");
        }
    }

    /// <inheritdoc/>
    public async Task<(bool Success, string Message)> DeleteDomainAsync(int domainId, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured)
            return (false, "Database is not configured.");

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Notes are deleted via CASCADE
            var query = "DELETE FROM DML.DomainMasterList WHERE DomainID = @DomainId";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@DomainId", domainId);

            var rowsAffected = await cmd.ExecuteNonQueryAsync(cancellationToken);

            if (rowsAffected == 0)
                return (false, "Domain not found.");

            _logger.LogInformation("Deleted domain {DomainId}", domainId);
            return (true, "Domain deleted successfully.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting domain {DomainId}", domainId);
            return (false, $"Error deleting domain: {ex.Message}");
        }
    }

    /// <inheritdoc/>
    public async Task<(bool Success, string Message, int? NoteId)> AddNoteAsync(int domainId, string? noteSubject, string noteText, string createdBy, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured)
            return (false, "Database is not configured.", null);

        if (string.IsNullOrWhiteSpace(noteText))
            return (false, "Note text is required.", null);

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                INSERT INTO DML.DomainNotes (DomainID, NoteSubject, NoteText, CreatedBy)
                OUTPUT INSERTED.DomainNoteID
                VALUES (@DomainId, @NoteSubject, @NoteText, @CreatedBy)";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@DomainId", domainId);
            cmd.Parameters.AddWithValue("@NoteSubject", (object?)noteSubject ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@NoteText", noteText);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);

            var noteId = (int)(await cmd.ExecuteScalarAsync(cancellationToken))!;

            _logger.LogInformation("Added note {NoteId} to domain {DomainId} by {CreatedBy}", noteId, domainId, createdBy);
            return (true, "Note added successfully.", noteId);
        }
        catch (SqlException ex) when (ex.Number == 547) // FK violation
        {
            return (false, "Domain not found.", null);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error adding note to domain {DomainId}", domainId);
            return (false, $"Error adding note: {ex.Message}", null);
        }
    }

    /// <inheritdoc/>
    public async Task<string?> GetDomainNameAsync(int domainId, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured)
            return null;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = "SELECT DomainName FROM DML.DomainMasterList WHERE DomainID = @DomainId";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@DomainId", domainId);

            var result = await cmd.ExecuteScalarAsync(cancellationToken);
            return result as string;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting domain name for {DomainId}", domainId);
            return null;
        }
    }

    /// <inheritdoc/>
    public async Task<List<DomainNoteItem>> GetNotesAsync(int domainId, CancellationToken cancellationToken)
    {
        var results = new List<DomainNoteItem>();

        if (!_sqlSettings.IsConfigured)
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                SELECT DomainNoteID, DomainID, NoteSubject, NoteText, CreatedBy, CreatedAt, IsSystem
                FROM DML.DomainNotes
                WHERE DomainID = @DomainId
                ORDER BY CreatedAt DESC";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@DomainId", domainId);

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add(new DomainNoteItem
                {
                    DomainNoteID = reader.GetInt32(0),
                    DomainID = reader.GetInt32(1),
                    NoteSubject = reader.IsDBNull(2) ? null : reader.GetString(2),
                    NoteText = reader.GetString(3),
                    CreatedBy = reader.IsDBNull(4) ? null : reader.GetString(4),
                    CreatedAt = reader.GetDateTime(5),
                    IsSystem = reader.GetBoolean(6)
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting notes for domain {DomainId}", domainId);
        }

        return results;
    }

    /// <inheritdoc/>
    public async Task<(int Total, int Active, int Decommissioned)> GetDomainCountsAsync(CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured)
            return (0, 0, 0);

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                SELECT
                    COUNT(*) AS Total,
                    ISNULL(SUM(CASE WHEN IsDecommissioned = 0 THEN 1 ELSE 0 END), 0) AS Active,
                    ISNULL(SUM(CASE WHEN IsDecommissioned = 1 THEN 1 ELSE 0 END), 0) AS Decommissioned
                FROM DML.DomainMasterList";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                return (
                    reader.IsDBNull(0) ? 0 : reader.GetInt32(0),
                    reader.IsDBNull(1) ? 0 : reader.GetInt32(1),
                    reader.IsDBNull(2) ? 0 : reader.GetInt32(2)
                );
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting domain counts");
        }

        return (0, 0, 0);
    }

    /// <inheritdoc/>
    public async Task<List<DmlLookupItem>> GetResponsibilityLevelsAsync(CancellationToken cancellationToken)
    {
        return await GetLookupAsync("DML.DSResponsibilityLevel", "DSResponsibilityLevelID", "LevelName", cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<List<DmlLookupItem>> GetTriStatesAsync(CancellationToken cancellationToken)
    {
        return await GetLookupAsync("DML.TriState", "TriStateID", "StateName", cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<List<DmlLookupItem>> GetBaselineStatusesAsync(CancellationToken cancellationToken)
    {
        return await GetLookupAsync("DML.BaselineStatus", "BaselineStatusID", "StatusName", cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<AdInventoryInfo?> GetAdInventoryInfoAsync(string domainName, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured || string.IsNullOrWhiteSpace(domainName))
            return null;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // First, get the most recent CollectionID and CollectionDateTime for this domain
            // Use LOWER() for case-insensitive matching since domain names may differ in case
            var collectionQuery = @"
                SELECT TOP 1 CollectionID, CollectionDateTime
                FROM ADData.CollectionInfo
                WHERE LOWER(DomainName) = LOWER(@DomainName)
                ORDER BY CollectionDateTime DESC";

            Guid? collectionId = null;
            DateTime? collectionDateTime = null;

            await using (var cmd = new SqlCommand(collectionQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@DomainName", domainName);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                if (await reader.ReadAsync(cancellationToken))
                {
                    collectionId = reader.GetGuid(0);
                    collectionDateTime = reader.GetDateTime(1);
                }
            }

            // If no collection found, return info with HasInventory = false
            if (!collectionId.HasValue)
            {
                return new AdInventoryInfo { HasInventory = false };
            }

            var inventoryInfo = new AdInventoryInfo
            {
                HasInventory = true,
                CollectionId = collectionId,
                CollectionDateTime = collectionDateTime
            };

            // Get Forest information using CollectionID
            var forestQuery = @"
                SELECT TOP 1
                    ForestName,
                    ForestMode,
                    SchemaMaster,
                    DomainNamingMaster,
                    SchemaVersion,
                    ExchangeSchemaVersion,
                    WhenCreated
                FROM ADData.AD_Forest
                WHERE CollectionID = @CollectionID";

            await using (var cmd = new SqlCommand(forestQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId.Value);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                if (await reader.ReadAsync(cancellationToken))
                {
                    inventoryInfo.Forest = new AdForestInfo
                    {
                        ForestName = reader.IsDBNull(0) ? null : reader.GetString(0),
                        ForestMode = reader.IsDBNull(1) ? null : reader.GetString(1),
                        SchemaMaster = reader.IsDBNull(2) ? null : reader.GetString(2),
                        DomainNamingMaster = reader.IsDBNull(3) ? null : reader.GetString(3),
                        SchemaVersion = reader.IsDBNull(4) ? null : reader.GetInt32(4),
                        ExchangeSchemaVersion = reader.IsDBNull(5) ? null : reader.GetInt32(5),
                        WhenCreated = reader.IsDBNull(6) ? null : reader.GetDateTime(6)
                    };
                }
            }

            // Get Domain information using CollectionID
            // Use LOWER() for case-insensitive domain name matching
            // Include ParentDomain and ChildDomains for hierarchy display
            // Include ForestName to enable forest lookup for child domains
            string? parentDomainName = null;
            string? childDomainsJson = null;
            string? forestNameFromDomain = null;

            var domainQuery = @"
                SELECT TOP 1
                    DomainName,
                    DomainMode,
                    PDCEmulator,
                    RIDMaster,
                    InfrastructureMaster,
                    WhenCreated,
                    WhenChanged,
                    ParentDomain,
                    ChildDomains,
                    ForestName
                FROM ADData.AD_Domain
                WHERE CollectionID = @CollectionID
                  AND LOWER(DomainName) = LOWER(@DomainName)";

            await using (var cmd = new SqlCommand(domainQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId.Value);
                cmd.Parameters.AddWithValue("@DomainName", domainName);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                if (await reader.ReadAsync(cancellationToken))
                {
                    inventoryInfo.Domain = new AdDomainInfo
                    {
                        DomainName = reader.IsDBNull(0) ? null : reader.GetString(0),
                        DomainMode = reader.IsDBNull(1) ? null : reader.GetString(1),
                        PDCEmulator = reader.IsDBNull(2) ? null : reader.GetString(2),
                        RIDMaster = reader.IsDBNull(3) ? null : reader.GetString(3),
                        InfrastructureMaster = reader.IsDBNull(4) ? null : reader.GetString(4),
                        WhenCreated = reader.IsDBNull(5) ? null : reader.GetDateTime(5),
                        WhenChanged = reader.IsDBNull(6) ? null : reader.GetDateTime(6)
                    };
                    parentDomainName = reader.IsDBNull(7) ? null : reader.GetString(7);
                    childDomainsJson = reader.IsDBNull(8) ? null : reader.GetString(8);
                    forestNameFromDomain = reader.IsDBNull(9) ? null : reader.GetString(9);
                }
            }

            // If forest info wasn't found in the current collection (common for child domains),
            // look it up by ForestName across all collections (most recent first)
            if (inventoryInfo.Forest == null && !string.IsNullOrEmpty(forestNameFromDomain))
            {
                var forestByNameQuery = @"
                    SELECT TOP 1
                        f.ForestName,
                        f.ForestMode,
                        f.SchemaMaster,
                        f.DomainNamingMaster,
                        f.SchemaVersion,
                        f.ExchangeSchemaVersion,
                        f.WhenCreated
                    FROM ADData.AD_Forest f
                    INNER JOIN ADData.CollectionInfo c ON f.CollectionID = c.CollectionID
                    WHERE LOWER(f.ForestName) = LOWER(@ForestName)
                    ORDER BY c.CollectionDateTime DESC";

                await using var forestCmd = new SqlCommand(forestByNameQuery, connection);
                forestCmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                forestCmd.Parameters.AddWithValue("@ForestName", forestNameFromDomain);

                await using var forestReader = await forestCmd.ExecuteReaderAsync(cancellationToken);
                if (await forestReader.ReadAsync(cancellationToken))
                {
                    inventoryInfo.Forest = new AdForestInfo
                    {
                        ForestName = forestReader.IsDBNull(0) ? null : forestReader.GetString(0),
                        ForestMode = forestReader.IsDBNull(1) ? null : forestReader.GetString(1),
                        SchemaMaster = forestReader.IsDBNull(2) ? null : forestReader.GetString(2),
                        DomainNamingMaster = forestReader.IsDBNull(3) ? null : forestReader.GetString(3),
                        SchemaVersion = forestReader.IsDBNull(4) ? null : forestReader.GetInt32(4),
                        ExchangeSchemaVersion = forestReader.IsDBNull(5) ? null : forestReader.GetInt32(5),
                        WhenCreated = forestReader.IsDBNull(6) ? null : forestReader.GetDateTime(6)
                    };
                }
            }

            // Resolve parent and child domains to DomainMasterList entries
            if (inventoryInfo.Domain != null)
            {
                var domainNamesToResolve = new List<string>();

                if (!string.IsNullOrEmpty(parentDomainName))
                    domainNamesToResolve.Add(parentDomainName);

                // Parse child domains from JSON array
                var childDomainNames = new List<string>();
                if (!string.IsNullOrEmpty(childDomainsJson))
                {
                    try
                    {
                        childDomainNames = System.Text.Json.JsonSerializer.Deserialize<List<string>>(childDomainsJson) ?? new List<string>();
                        domainNamesToResolve.AddRange(childDomainNames);
                    }
                    catch (System.Text.Json.JsonException)
                    {
                        // If JSON parsing fails, ignore child domains
                        _logger.LogWarning("Failed to parse ChildDomains JSON for domain {DomainName}: {Json}", domainName, childDomainsJson);
                    }
                }

                // Look up DomainIDs from DomainMasterList
                var domainIdMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                if (domainNamesToResolve.Count > 0)
                {
                    var lookupQuery = @"
                        SELECT DomainID, DomainName
                        FROM DML.DomainMasterList
                        WHERE LOWER(DomainName) IN (" + string.Join(", ", domainNamesToResolve.Select((_, i) => $"LOWER(@Domain{i})")) + ")";

                    await using var lookupCmd = new SqlCommand(lookupQuery, connection);
                    lookupCmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                    for (int i = 0; i < domainNamesToResolve.Count; i++)
                    {
                        lookupCmd.Parameters.AddWithValue($"@Domain{i}", domainNamesToResolve[i]);
                    }

                    await using var lookupReader = await lookupCmd.ExecuteReaderAsync(cancellationToken);
                    while (await lookupReader.ReadAsync(cancellationToken))
                    {
                        var id = lookupReader.GetInt32(0);
                        var name = lookupReader.GetString(1);
                        domainIdMap[name] = id;
                    }
                }

                // Set parent domain with link if available
                if (!string.IsNullOrEmpty(parentDomainName))
                {
                    inventoryInfo.Domain.ParentDomain = new LinkedDomainInfo
                    {
                        DomainName = parentDomainName,
                        DomainId = domainIdMap.TryGetValue(parentDomainName, out var parentId) ? parentId : null
                    };
                }

                // Set child domains with links if available
                foreach (var childName in childDomainNames)
                {
                    inventoryInfo.Domain.ChildDomains.Add(new LinkedDomainInfo
                    {
                        DomainName = childName,
                        DomainId = domainIdMap.TryGetValue(childName, out var childId) ? childId : null
                    });
                }
            }

            // Get Domain Controllers (computers with IsCriticalSystemObject = 1)
            var dcQuery = @"
                SELECT
                    SamAccountName,
                    DisplayName,
                    DNSHostName,
                    OperatingSystem,
                    OperatingSystemVersion,
                    Enabled,
                    WhenCreated,
                    LastLogonTimestamp,
                    PasswordLastSet
                FROM ADData.v_AD_Computers
                WHERE CollectionID = @CollectionID AND IsCriticalSystemObject = 1
                ORDER BY DNSHostName";

            await using (var cmd = new SqlCommand(dcQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId.Value);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    inventoryInfo.DomainControllers.Add(new DomainControllerInfo
                    {
                        SamAccountName = reader.IsDBNull(0) ? null : reader.GetString(0),
                        DisplayName = reader.IsDBNull(1) ? null : reader.GetString(1),
                        DNSHostName = reader.IsDBNull(2) ? null : reader.GetString(2),
                        OperatingSystem = reader.IsDBNull(3) ? null : reader.GetString(3),
                        OperatingSystemVersion = reader.IsDBNull(4) ? null : reader.GetString(4),
                        Enabled = reader.IsDBNull(5) ? null : reader.GetBoolean(5),
                        WhenCreated = reader.IsDBNull(6) ? null : reader.GetDateTime(6),
                        LastLogonTimestamp = reader.IsDBNull(7) ? null : reader.GetDateTime(7),
                        PasswordLastSet = reader.IsDBNull(8) ? null : reader.GetDateTime(8)
                    });
                }
            }

            // Load key trust relationships for the 3 tracked domains
            var keyTrustDomains = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
            {
                { "ADMgmt", new[] { "admgmt.ssncad.global", "admgmt" } },
                { "SSNCCorp", new[] { "ssnc-corp.global", "ssnc-corp" } },
                { "SSCViolet", new[] { "sscviolet.ssncad.global", "sscviolet" } }
            };

            var trustQuery = @"
                SELECT
                    SourceDomain,
                    TargetDomain,
                    TrustDirection,
                    TrustType
                FROM ADData.AD_Trust
                WHERE CollectionID = @CollectionID
                  AND (LOWER(SourceDomain) = LOWER(@DomainName) OR LOWER(TargetDomain) = LOWER(@DomainName))";

            var allTrusts = new List<(string Source, string Target, string Direction, string Type)>();

            await using (var cmd = new SqlCommand(trustQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId.Value);
                cmd.Parameters.AddWithValue("@DomainName", domainName);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    allTrusts.Add((
                        reader.GetString(0),
                        reader.GetString(1),
                        reader.GetString(2),
                        reader.GetString(3)
                    ));
                }
            }

            // Match trusts to key domains
            foreach (var (key, patterns) in keyTrustDomains)
            {
                var matchedTrust = allTrusts.FirstOrDefault(t =>
                    patterns.Any(p =>
                        t.Target.Equals(p, StringComparison.OrdinalIgnoreCase) ||
                        t.Source.Equals(p, StringComparison.OrdinalIgnoreCase)));

                if (matchedTrust != default)
                {
                    // Determine direction relative to current domain
                    var isSource = matchedTrust.Source.Equals(domainName, StringComparison.OrdinalIgnoreCase);
                    var direction = matchedTrust.Direction;

                    // If this domain is the target, we need to flip Inbound/Outbound
                    if (!isSource && direction.Equals("Inbound", StringComparison.OrdinalIgnoreCase))
                        direction = "Outbound";
                    else if (!isSource && direction.Equals("Outbound", StringComparison.OrdinalIgnoreCase))
                        direction = "Inbound";

                    var matchedDomain = isSource ? matchedTrust.Target : matchedTrust.Source;

                    inventoryInfo.KeyTrusts[key] = new KeyTrustInfo
                    {
                        HasTrust = true,
                        Direction = direction,
                        TrustType = matchedTrust.Type,
                        MatchedDomain = matchedDomain
                    };
                }
                else
                {
                    inventoryInfo.KeyTrusts[key] = new KeyTrustInfo { HasTrust = false };
                }
            }

            _logger.LogDebug("Retrieved AD inventory info for domain {DomainName} from collection {CollectionID} ({CollectionDateTime}): {DCCount} DCs, {TrustCount} key trusts",
                domainName, collectionId, collectionDateTime, inventoryInfo.DomainControllers.Count, inventoryInfo.KeyTrusts.Count(t => t.Value.HasTrust));

            return inventoryInfo;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting AD inventory info for domain {DomainName}", domainName);
            return null;
        }
    }

    /// <inheritdoc/>
    public async Task<SitesAndServicesInfo?> GetSitesAndServicesSummaryAsync(Guid collectionId, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured)
            return null;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var result = new SitesAndServicesInfo();

            // Get counts
            var countsQuery = @"
                SELECT
                    (SELECT COUNT(*) FROM ADData.AD_Site WHERE CollectionID = @CollectionID) AS SiteCount,
                    (SELECT COUNT(*) FROM ADData.AD_Subnet WHERE CollectionID = @CollectionID) AS SubnetCount,
                    (SELECT COUNT(*) FROM ADData.AD_SiteLink WHERE CollectionID = @CollectionID) AS SiteLinkCount,
                    (SELECT COUNT(*) FROM ADData.AD_DomainController WHERE CollectionID = @CollectionID) AS DCCount";

            await using (var cmd = new SqlCommand(countsQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                if (await reader.ReadAsync(cancellationToken))
                {
                    result.SiteCount = reader.GetInt32(0);
                    result.SubnetCount = reader.GetInt32(1);
                    result.SiteLinkCount = reader.GetInt32(2);
                    result.DomainControllerCount = reader.GetInt32(3);
                    result.HasData = result.SiteCount > 0;
                }
            }

            if (!result.HasData)
                return result;

            // Get site summaries with subnet and DC counts
            var sitesQuery = @"
                SELECT
                    s.SiteName,
                    s.Description,
                    s.Location,
                    (SELECT COUNT(*) FROM ADData.AD_SiteSubnet ss WHERE ss.SiteName = s.SiteName AND ss.CollectionID = s.CollectionID) AS SubnetCount,
                    (SELECT COUNT(*) FROM ADData.AD_DomainController dc WHERE dc.SiteName = s.SiteName AND dc.CollectionID = s.CollectionID) AS DCCount,
                    (SELECT COUNT(*) FROM ADData.AD_DomainController dc WHERE dc.SiteName = s.SiteName AND dc.CollectionID = s.CollectionID AND dc.IsGlobalCatalog = 1) AS GCCount,
                    ss.InterSiteTopologyGenerator,
                    ss.IsGroupCachingEnabled,
                    s.WhenCreated
                FROM ADData.AD_Site s
                LEFT JOIN ADData.AD_SiteSettings ss ON s.SiteName = ss.SiteName AND s.CollectionID = ss.CollectionID
                WHERE s.CollectionID = @CollectionID
                ORDER BY s.SiteName";

            await using (var cmd = new SqlCommand(sitesQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    result.Sites.Add(new SiteSummaryInfo
                    {
                        SiteName = reader.GetString(0),
                        Description = reader.IsDBNull(1) ? null : reader.GetString(1),
                        Location = reader.IsDBNull(2) ? null : reader.GetString(2),
                        SubnetCount = reader.GetInt32(3),
                        DomainControllerCount = reader.GetInt32(4),
                        GlobalCatalogCount = reader.GetInt32(5),
                        InterSiteTopologyGenerator = reader.IsDBNull(6) ? null : reader.GetString(6),
                        IsGroupCachingEnabled = reader.IsDBNull(7) ? null : reader.GetBoolean(7),
                        WhenCreated = reader.IsDBNull(8) ? null : reader.GetDateTime(8)
                    });
                }
            }

            _logger.LogDebug("Retrieved Sites & Services summary for collection {CollectionID}: {SiteCount} sites, {SubnetCount} subnets, {SiteLinkCount} site links",
                collectionId, result.SiteCount, result.SubnetCount, result.SiteLinkCount);

            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting Sites & Services summary for collection {CollectionID}", collectionId);
            return null;
        }
    }

    /// <inheritdoc/>
    public async Task<(List<SiteLinkInfo> SiteLinks, int TotalCount)> GetSiteLinksAsync(
        Guid collectionId,
        int skip = 0,
        int take = 50,
        CancellationToken cancellationToken = default)
    {
        var results = new List<SiteLinkInfo>();

        if (!_sqlSettings.IsConfigured)
            return (results, 0);

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Get total count
            int totalCount = 0;
            var countQuery = "SELECT COUNT(*) FROM ADData.AD_SiteLink WHERE CollectionID = @CollectionID";

            await using (var cmd = new SqlCommand(countQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);
                totalCount = (int)(await cmd.ExecuteScalarAsync(cancellationToken))!;
            }

            if (totalCount == 0)
                return (results, 0);

            // Get paginated site links with site list
            var query = @"
                SELECT
                    sl.SiteLinkName,
                    sl.Cost,
                    sl.ReplicationInterval,
                    sl.Description,
                    sl.TransportType,
                    sl.UseNotification,
                    sl.TwoWaySync,
                    sl.CompressionDisabled,
                    (SELECT COUNT(*) FROM ADData.AD_SiteLinkSite sls WHERE sls.SiteLinkName = sl.SiteLinkName AND sls.CollectionID = sl.CollectionID) AS SiteCount,
                    (SELECT STRING_AGG(sls2.SiteName, ', ') WITHIN GROUP (ORDER BY sls2.SiteName)
                     FROM ADData.AD_SiteLinkSite sls2
                     WHERE sls2.SiteLinkName = sl.SiteLinkName AND sls2.CollectionID = sl.CollectionID) AS SiteList,
                    sl.WhenCreated
                FROM ADData.AD_SiteLink sl
                WHERE sl.CollectionID = @CollectionID
                ORDER BY sl.SiteLinkName
                OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY";

            await using (var cmd = new SqlCommand(query, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);
                cmd.Parameters.AddWithValue("@Skip", skip);
                cmd.Parameters.AddWithValue("@Take", take);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    var siteList = reader.IsDBNull(9) ? null : reader.GetString(9);
                    results.Add(new SiteLinkInfo
                    {
                        SiteLinkName = reader.GetString(0),
                        Cost = reader.IsDBNull(1) ? null : Convert.ToInt32(reader.GetValue(1)),
                        ReplicationInterval = reader.IsDBNull(2) ? null : Convert.ToInt32(reader.GetValue(2)),
                        Description = reader.IsDBNull(3) ? null : reader.GetString(3),
                        TransportType = reader.IsDBNull(4) ? null : reader.GetString(4),
                        UseNotification = reader.IsDBNull(5) ? null : reader.GetBoolean(5),
                        TwoWaySync = reader.IsDBNull(6) ? null : reader.GetBoolean(6),
                        CompressionDisabled = reader.IsDBNull(7) ? null : reader.GetBoolean(7),
                        SiteCount = reader.IsDBNull(8) ? null : Convert.ToInt32(reader.GetValue(8)),
                        SiteList = siteList,
                        Sites = string.IsNullOrEmpty(siteList) ? new List<string>() : siteList.Split(", ").ToList(),
                        WhenCreated = reader.IsDBNull(10) ? null : reader.GetDateTime(10)
                    });
                }
            }

            _logger.LogDebug("Retrieved {Count}/{TotalCount} site links for collection {CollectionID}",
                results.Count, totalCount, collectionId);

            return (results, totalCount);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting site links for collection {CollectionID}", collectionId);
            return (results, 0);
        }
    }

    /// <inheritdoc/>
    public async Task<(List<SubnetInfo> Subnets, int TotalCount)> GetSubnetsAsync(
        Guid collectionId,
        string? siteFilter = null,
        int skip = 0,
        int take = 100,
        CancellationToken cancellationToken = default)
    {
        var results = new List<SubnetInfo>();

        if (!_sqlSettings.IsConfigured)
            return (results, 0);

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Build filter condition - handle special "__unassigned__" value for subnets not assigned to any site
            var isUnassignedFilter = siteFilter == "__unassigned__";
            var filterCondition = string.IsNullOrWhiteSpace(siteFilter)
                ? ""
                : isUnassignedFilter
                    ? " AND ss.SiteName IS NULL"
                    : " AND ss.SiteName = @SiteFilter";

            // Get total count
            int totalCount = 0;
            var countQuery = $@"
                SELECT COUNT(*)
                FROM ADData.AD_Subnet sub
                LEFT JOIN ADData.AD_SiteSubnet ss ON sub.SubnetName = ss.SubnetName AND sub.CollectionID = ss.CollectionID
                WHERE sub.CollectionID = @CollectionID{filterCondition}";

            await using (var cmd = new SqlCommand(countQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);
                if (!string.IsNullOrWhiteSpace(siteFilter) && !isUnassignedFilter)
                    cmd.Parameters.AddWithValue("@SiteFilter", siteFilter);
                totalCount = (int)(await cmd.ExecuteScalarAsync(cancellationToken))!;
            }

            if (totalCount == 0)
                return (results, 0);

            // Get paginated subnets
            var query = $@"
                SELECT
                    sub.SubnetName,
                    ss.SiteName,
                    sub.Description,
                    sub.Location,
                    sub.WhenCreated
                FROM ADData.AD_Subnet sub
                LEFT JOIN ADData.AD_SiteSubnet ss ON sub.SubnetName = ss.SubnetName AND sub.CollectionID = ss.CollectionID
                WHERE sub.CollectionID = @CollectionID{filterCondition}
                ORDER BY sub.SubnetName
                OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY";

            await using (var cmd = new SqlCommand(query, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);
                cmd.Parameters.AddWithValue("@Skip", skip);
                cmd.Parameters.AddWithValue("@Take", take);
                if (!string.IsNullOrWhiteSpace(siteFilter) && !isUnassignedFilter)
                    cmd.Parameters.AddWithValue("@SiteFilter", siteFilter);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    results.Add(new SubnetInfo
                    {
                        SubnetName = reader.GetString(0),
                        SiteName = reader.IsDBNull(1) ? null : reader.GetString(1),
                        Description = reader.IsDBNull(2) ? null : reader.GetString(2),
                        Location = reader.IsDBNull(3) ? null : reader.GetString(3),
                        WhenCreated = reader.IsDBNull(4) ? null : reader.GetDateTime(4)
                    });
                }
            }

            _logger.LogDebug("Retrieved {Count}/{TotalCount} subnets for collection {CollectionID} (filter: {Filter})",
                results.Count, totalCount, collectionId, siteFilter ?? "none");

            return (results, totalCount);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting subnets for collection {CollectionID}", collectionId);
            return (results, 0);
        }
    }

    /// <inheritdoc/>
    public async Task<DomainHealthInfo?> GetDomainHealthAsync(Guid collectionId, string domainName, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured || string.IsNullOrWhiteSpace(domainName))
            return null;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var result = new DomainHealthInfo();

            // Get domain health data from AD_Domain
            var healthQuery = @"
                SELECT
                    SysvolReplicationMethod,
                    SysvolMigrationState,
                    DFSRExists,
                    FRSExists,
                    DFSRFlags,
                    SYSVOLAccessible,
                    GPOTotalCount,
                    GPOHealthyCount,
                    GPOOrphanedGPCCount,
                    GPOOrphanedGPTCount,
                    GPOVersionMismatchCount
                FROM ADData.AD_Domain
                WHERE CollectionID = @CollectionID
                  AND LOWER(DomainName) = LOWER(@DomainName)";

            await using (var cmd = new SqlCommand(healthQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);
                cmd.Parameters.AddWithValue("@DomainName", domainName);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                if (await reader.ReadAsync(cancellationToken))
                {
                    result.HasData = true;
                    result.SysvolReplicationMethod = reader.IsDBNull(0) ? null : reader.GetString(0);
                    result.SysvolMigrationState = reader.IsDBNull(1) ? null : reader.GetString(1);
                    result.DFSRExists = reader.IsDBNull(2) ? null : reader.GetBoolean(2);
                    result.FRSExists = reader.IsDBNull(3) ? null : reader.GetBoolean(3);
                    result.DFSRFlags = reader.IsDBNull(4) ? null : reader.GetInt32(4);
                    result.SYSVOLAccessible = reader.IsDBNull(5) ? null : reader.GetBoolean(5);
                    result.GPOTotalCount = reader.IsDBNull(6) ? null : reader.GetInt32(6);
                    result.GPOHealthyCount = reader.IsDBNull(7) ? null : reader.GetInt32(7);
                    result.GPOOrphanedGPCCount = reader.IsDBNull(8) ? null : reader.GetInt32(8);
                    result.GPOOrphanedGPTCount = reader.IsDBNull(9) ? null : reader.GetInt32(9);
                    result.GPOVersionMismatchCount = reader.IsDBNull(10) ? null : reader.GetInt32(10);
                }
            }

            if (!result.HasData)
                return result;

            // Get optional features
            result.OptionalFeatures = await GetOptionalFeaturesAsync(collectionId, cancellationToken);

            // Get health-related logs if there are GPO issues or SYSVOL problems
            if (result.GPOUnhealthyCount > 0 || result.SYSVOLAccessible == false)
            {
                result.HealthLogs = await GetHealthLogsAsync(collectionId, cancellationToken);
            }

            _logger.LogDebug("Retrieved domain health for {DomainName} from collection {CollectionID}: SYSVOL={SysvolMethod}, GPOTotal={GPOCount}, HealthLogs={LogCount}",
                domainName, collectionId, result.SysvolReplicationMethod, result.GPOTotalCount, result.HealthLogs.Count);

            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting domain health for {DomainName} from collection {CollectionID}", domainName, collectionId);
            return null;
        }
    }

    /// <inheritdoc/>
    public async Task<List<OptionalFeatureInfo>> GetOptionalFeaturesAsync(Guid collectionId, CancellationToken cancellationToken)
    {
        var results = new List<OptionalFeatureInfo>();

        if (!_sqlSettings.IsConfigured)
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                SELECT
                    FeatureName,
                    IsEnabled,
                    RequiredForestLevelName,
                    Description
                FROM ADData.AD_OptionalFeature
                WHERE CollectionID = @CollectionID
                ORDER BY FeatureName";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@CollectionID", collectionId);

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add(new OptionalFeatureInfo
                {
                    FeatureName = reader.GetString(0),
                    IsEnabled = reader.GetBoolean(1),
                    RequiredForestLevelName = reader.IsDBNull(2) ? null : reader.GetString(2),
                    Description = reader.IsDBNull(3) ? null : reader.GetString(3)
                });
            }

            _logger.LogDebug("Retrieved {Count} optional features for collection {CollectionID}", results.Count, collectionId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting optional features for collection {CollectionID}", collectionId);
        }

        return results;
    }

    /// <inheritdoc/>
    public async Task<(List<TrustInfo> Trusts, int TotalCount)> GetTrustsAsync(Guid collectionId, string domainName, CancellationToken cancellationToken)
    {
        var results = new List<TrustInfo>();

        if (!_sqlSettings.IsConfigured)
            return (results, 0);

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Get trusts where the domain is either source or target
            var query = @"
                SELECT
                    SourceDomain,
                    TargetDomain,
                    TrustType,
                    TrustDirection,
                    TrustAttributes,
                    IsTransitive,
                    FlatName,
                    WhenCreated
                FROM ADData.AD_Trust
                WHERE CollectionID = @CollectionID
                  AND (LOWER(SourceDomain) = LOWER(@DomainName) OR LOWER(TargetDomain) = LOWER(@DomainName))
                ORDER BY TargetDomain";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@CollectionID", collectionId);
            cmd.Parameters.AddWithValue("@DomainName", domainName);

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add(new TrustInfo
                {
                    SourceDomain = reader.GetString(0),
                    TargetDomain = reader.GetString(1),
                    TrustType = reader.GetString(2),
                    TrustDirection = reader.GetString(3),
                    TrustAttributes = reader.IsDBNull(4) ? null : reader.GetInt32(4),
                    IsTransitive = reader.GetBoolean(5),
                    FlatName = reader.IsDBNull(6) ? null : reader.GetString(6),
                    WhenCreated = reader.IsDBNull(7) ? null : reader.GetDateTime(7)
                });
            }

            _logger.LogDebug("Retrieved {Count} trusts for domain {DomainName} in collection {CollectionID}",
                results.Count, domainName, collectionId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting trusts for domain {DomainName} in collection {CollectionID}",
                domainName, collectionId);
        }

        return (results, results.Count);
    }

    /// <summary>
    /// Gets health-related log entries from the collection (GPO, SYSVOL warnings/errors).
    /// </summary>
    private async Task<List<HealthLogEntry>> GetHealthLogsAsync(Guid collectionId, CancellationToken cancellationToken)
    {
        var results = new List<HealthLogEntry>();

        if (!_sqlSettings.IsConfigured)
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Query logs related to GPO, SYSVOL, and domain health collection
            // These are Warning or Error level entries with relevant messages
            var query = @"
                SELECT TOP 50
                    LogID,
                    Timestamp,
                    Level,
                    Category,
                    Message,
                    Context,
                    ExceptionMessage,
                    ExceptionType
                FROM ADData.AD_Log
                WHERE CollectionID = @CollectionID
                  AND Level IN ('Warning', 'Error')
                  AND (
                      Message LIKE '%GPO%'
                      OR Message LIKE '%GPT%'
                      OR Message LIKE '%GPC%'
                      OR Message LIKE '%SYSVOL%'
                      OR Message LIKE '%Group Policy%'
                      OR Message LIKE '%Policies%'
                      OR Category LIKE '%Health%'
                      OR Category LIKE '%GPO%'
                  )
                ORDER BY Timestamp DESC";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@CollectionID", collectionId);

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add(new HealthLogEntry
                {
                    LogID = reader.GetInt32(0),
                    Timestamp = reader.GetDateTime(1),
                    Level = reader.GetString(2),
                    Category = reader.IsDBNull(3) ? string.Empty : reader.GetString(3),
                    Message = reader.GetString(4),
                    Context = reader.IsDBNull(5) ? null : reader.GetString(5),
                    ExceptionMessage = reader.IsDBNull(6) ? null : reader.GetString(6),
                    ExceptionType = reader.IsDBNull(7) ? null : reader.GetString(7)
                });
            }

            _logger.LogDebug("Retrieved {Count} health-related log entries for collection {CollectionID}", results.Count, collectionId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting health logs for collection {CollectionID}", collectionId);
        }

        return results;
    }

    /// <inheritdoc/>
    public async Task<List<AdLogEntry>> GetCollectionLogsAsync(Guid collectionId, CancellationToken cancellationToken)
    {
        var results = new List<AdLogEntry>();

        if (!_sqlSettings.IsConfigured)
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Get all log entries for this collection, ordered by timestamp
            var query = @"
                SELECT
                    LogID,
                    Timestamp,
                    Level,
                    Category,
                    Message,
                    Context,
                    ExceptionMessage,
                    ExceptionType
                FROM ADData.AD_Log
                WHERE CollectionID = @CollectionID
                ORDER BY Timestamp DESC";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@CollectionID", collectionId);

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add(new AdLogEntry
                {
                    LogID = reader.GetInt32(0),
                    Timestamp = reader.GetDateTime(1),
                    Level = reader.GetString(2),
                    Category = reader.IsDBNull(3) ? string.Empty : reader.GetString(3),
                    Message = reader.GetString(4),
                    Context = reader.IsDBNull(5) ? null : reader.GetString(5),
                    ExceptionMessage = reader.IsDBNull(6) ? null : reader.GetString(6),
                    ExceptionType = reader.IsDBNull(7) ? null : reader.GetString(7)
                });
            }

            _logger.LogDebug("Retrieved {Count} log entries for collection {CollectionID}", results.Count, collectionId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting logs for collection {CollectionID}", collectionId);
        }

        return results;
    }

    private async Task<List<DmlLookupItem>> GetLookupAsync(string tableName, string idColumn, string nameColumn, CancellationToken cancellationToken)
    {
        var results = new List<DmlLookupItem>();

        if (!_sqlSettings.IsConfigured)
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = $"SELECT {idColumn}, {nameColumn}, SortOrder FROM {tableName} ORDER BY SortOrder";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add(new DmlLookupItem
                {
                    Id = Convert.ToInt32(reader.GetValue(0)),
                    Name = reader.GetString(1),
                    SortOrder = Convert.ToInt32(reader.GetValue(2))
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting lookup values from {TableName}", tableName);
        }

        return results;
    }

    private static DomainMasterListItem MapDomainFromReader(SqlDataReader reader)
    {
        return new DomainMasterListItem
        {
            DomainID = reader.GetInt32(0),
            DomainName = reader.GetString(1),
            NetBIOSName = reader.IsDBNull(2) ? null : reader.GetString(2),
            BusinessUnit = reader.IsDBNull(3) ? null : reader.GetString(3),
            DSResponsibilityLevelID = reader.IsDBNull(4) ? null : reader.GetInt32(4),
            DSResponsibilityLevel = reader.IsDBNull(5) ? null : reader.GetString(5),
            IsThirdPartyManaged = reader.GetBoolean(6),
            IsDecommissioned = reader.GetBoolean(7),
            Trust_ADMgmt_TriStateID = reader.GetByte(8),
            Trust_ADMgmt = reader.IsDBNull(9) ? null : reader.GetString(9),
            Trust_SSCViolet_TriStateID = reader.GetByte(10),
            Trust_SSCViolet = reader.IsDBNull(11) ? null : reader.GetString(11),
            Trust_SSNC_Corp_TriStateID = reader.GetByte(12),
            Trust_SSNC_Corp = reader.IsDBNull(13) ? null : reader.GetString(13),
            IsPatchHold = reader.GetBoolean(14),
            HasHealthCheck = reader.GetBoolean(15),
            HasNetwrixAuditor = reader.GetBoolean(16),
            IsSafeguardReady = reader.GetBoolean(17),
            IsCloudIntegrated = reader.GetByte(18),
            IsCloudIntegratedState = reader.IsDBNull(19) ? null : reader.GetString(19),
            BaselineStatusID = reader.GetByte(20),
            BaselineStatus = reader.IsDBNull(21) ? null : reader.GetString(21),
            IsClientFacing = reader.GetBoolean(22),
            IsSPLA = reader.GetBoolean(23),
            IsRegulated = reader.GetBoolean(24),
            MSPCustomer = reader.GetBoolean(25),
            POC = reader.IsDBNull(26) ? null : reader.GetString(26),
            Purpose = reader.IsDBNull(27) ? null : reader.GetString(27),
            Roadmap = reader.IsDBNull(28) ? null : reader.GetString(28),
            ManagementServer = reader.IsDBNull(29) ? null : reader.GetString(29),
            LdapUrl = reader.IsDBNull(30) ? null : reader.GetString(30),
            CreatedAt = reader.GetDateTime(31),
            UpdatedAt = reader.IsDBNull(32) ? null : reader.GetDateTime(32),
            LastInventoryDate = reader.IsDBNull(33) ? null : reader.GetDateTime(33),
            CollectionId = reader.IsDBNull(34) ? null : reader.GetGuid(34)
        };
    }

    private static void AddDomainParameters(SqlCommand cmd, DomainCreateRequest request)
    {
        cmd.Parameters.AddWithValue("@DomainName", request.DomainName);
        cmd.Parameters.AddWithValue("@NetBIOSName", (object?)request.NetBIOSName?.ToUpperInvariant() ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@BusinessUnit", (object?)request.BusinessUnit ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@DSResponsibilityLevelID", (object?)request.DSResponsibilityLevelID ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@IsThirdPartyManaged", request.IsThirdPartyManaged);
        cmd.Parameters.AddWithValue("@IsDecommissioned", request.IsDecommissioned);
        cmd.Parameters.AddWithValue("@Trust_ADMgmt_TriStateID", request.Trust_ADMgmt_TriStateID);
        cmd.Parameters.AddWithValue("@Trust_SSCViolet_TriStateID", request.Trust_SSCViolet_TriStateID);
        cmd.Parameters.AddWithValue("@Trust_SSNC_Corp_TriStateID", request.Trust_SSNC_Corp_TriStateID);
        cmd.Parameters.AddWithValue("@IsPatchHold", request.IsPatchHold);
        cmd.Parameters.AddWithValue("@HasHealthCheck", request.HasHealthCheck);
        cmd.Parameters.AddWithValue("@HasNetwrixAuditor", request.HasNetwrixAuditor);
        cmd.Parameters.AddWithValue("@IsSafeguardReady", request.IsSafeguardReady);
        cmd.Parameters.AddWithValue("@IsCloudIntegrated", request.IsCloudIntegrated);
        cmd.Parameters.AddWithValue("@BaselineStatusID", request.BaselineStatusID);
        cmd.Parameters.AddWithValue("@IsClientFacing", request.IsClientFacing);
        cmd.Parameters.AddWithValue("@IsSPLA", request.IsSPLA);
        cmd.Parameters.AddWithValue("@IsRegulated", request.IsRegulated);
        cmd.Parameters.AddWithValue("@MSPCustomer", request.MSPCustomer);
        cmd.Parameters.AddWithValue("@POC", (object?)request.POC ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@Purpose", (object?)request.Purpose ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@Roadmap", (object?)request.Roadmap ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@ManagementServer", (object?)request.ManagementServer ?? DBNull.Value);
    }

    /// <inheritdoc/>
    public async Task<TopologyData?> GetTopologyDataAsync(Guid collectionId, CancellationToken cancellationToken)
    {
        var extendedLogging = _loggingSettings.EnableExtendedLogging;

        if (extendedLogging)
        {
            _logger.LogInformation("[Topology Service] GetTopologyDataAsync called for CollectionId: {CollectionId}", collectionId);
        }

        if (!_sqlSettings.IsConfigured)
        {
            _logger.LogWarning("[Topology Service] SQL Server is not configured");
            return null;
        }

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            if (extendedLogging)
            {
                _logger.LogInformation("[Topology Service] Opening SQL connection");
            }

            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            if (extendedLogging)
            {
                _logger.LogInformation("[Topology Service] SQL connection opened successfully");
            }

            var result = new TopologyData();

            // Get sites with their summary info
            if (extendedLogging)
            {
                _logger.LogInformation("[Topology Service] Executing sites query");
            }
            var sitesQuery = @"
                SELECT
                    s.SiteName,
                    s.Description,
                    s.Location,
                    (SELECT COUNT(*) FROM ADData.AD_SiteSubnet ss WHERE ss.SiteName = s.SiteName AND ss.CollectionID = s.CollectionID) AS SubnetCount,
                    (SELECT COUNT(*) FROM ADData.AD_DomainController dc WHERE dc.SiteName = s.SiteName AND dc.CollectionID = s.CollectionID) AS DCCount,
                    (SELECT COUNT(*) FROM ADData.AD_DomainController dc WHERE dc.SiteName = s.SiteName AND dc.CollectionID = s.CollectionID AND dc.IsGlobalCatalog = 1) AS GCCount,
                    ss.InterSiteTopologyGenerator,
                    ss.IsGroupCachingEnabled
                FROM ADData.AD_Site s
                LEFT JOIN ADData.AD_SiteSettings ss ON s.SiteName = ss.SiteName AND s.CollectionID = ss.CollectionID
                WHERE s.CollectionID = @CollectionID
                ORDER BY s.SiteName";

            await using (var cmd = new SqlCommand(sitesQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    var siteName = reader.GetString(0);
                    result.Sites.Add(new TopologySiteNode
                    {
                        Id = $"site-{siteName}",
                        Name = siteName,
                        Description = reader.IsDBNull(1) ? null : reader.GetString(1),
                        Location = reader.IsDBNull(2) ? null : reader.GetString(2),
                        SubnetCount = reader.GetInt32(3),
                        DomainControllerCount = reader.GetInt32(4),
                        GlobalCatalogCount = reader.GetInt32(5),
                        ISTG = reader.IsDBNull(6) ? null : reader.GetString(6),
                        IsGroupCachingEnabled = reader.IsDBNull(7) ? null : reader.GetBoolean(7)
                    });
                }
            }

            if (extendedLogging)
            {
                _logger.LogInformation("[Topology Service] Sites query returned {Count} sites", result.Sites.Count);
            }

            // Build a set of ISTG names for quick lookup
            var istgNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var site in result.Sites)
            {
                if (!string.IsNullOrEmpty(site.ISTG))
                    istgNames.Add(site.ISTG);
            }

            if (extendedLogging)
            {
                _logger.LogInformation("[Topology Service] Executing domain controllers query");
            }

            // Get domain controllers with computer info from AD_Object
            // Join AD_DomainController with AD_Object to get DNSHostName and OperatingSystem
            var dcsQuery = @"
                SELECT
                    dc.ServerName,
                    dc.SiteName,
                    dc.IsGlobalCatalog,
                    dc.IsRODC,
                    obj.DNSHostName,
                    obj.OperatingSystem
                FROM ADData.AD_DomainController dc
                LEFT JOIN ADData.AD_Object obj ON dc.DistinguishedName = obj.DistinguishedName
                    AND dc.CollectionID = obj.CollectionID
                WHERE dc.CollectionID = @CollectionID
                ORDER BY dc.SiteName, dc.ServerName";

            await using (var cmd = new SqlCommand(dcsQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    var serverName = reader.GetString(0);
                    var siteName = reader.IsDBNull(1) ? null : reader.GetString(1);
                    result.DomainControllers.Add(new TopologyDCNode
                    {
                        Id = $"dc-{serverName}",
                        Name = serverName,
                        SiteId = siteName != null ? $"site-{siteName}" : "",
                        SiteName = siteName,
                        DNSHostName = reader.IsDBNull(4) ? null : reader.GetString(4),
                        IsGlobalCatalog = reader.GetBoolean(2),
                        IsRODC = !reader.IsDBNull(3) && reader.GetBoolean(3),
                        IsISTG = istgNames.Contains(serverName),
                        OperatingSystem = reader.IsDBNull(5) ? null : reader.GetString(5)
                    });
                }
            }

            if (extendedLogging)
            {
                _logger.LogInformation("[Topology Service] Domain controllers query returned {Count} DCs", result.DomainControllers.Count);
                _logger.LogInformation("[Topology Service] Executing site links query");
            }

            // Get site links with their connected sites
            var siteLinksQuery = @"
                SELECT
                    sl.SiteLinkName,
                    sl.Cost,
                    sl.ReplicationInterval,
                    sl.TransportType,
                    CASE WHEN (sl.Options & 1) = 1 THEN 1 ELSE 0 END AS UseNotification,
                    CASE WHEN (sl.Options & 2) = 2 THEN 1 ELSE 0 END AS TwoWaySync
                FROM ADData.AD_SiteLink sl
                WHERE sl.CollectionID = @CollectionID
                ORDER BY sl.SiteLinkName";

            var siteLinkSitesQuery = @"
                SELECT SiteLinkName, SiteName
                FROM ADData.AD_SiteLinkSite
                WHERE CollectionID = @CollectionID
                ORDER BY SiteLinkName, SiteName";

            // First get all site link to site mappings
            var siteLinkSitesMap = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
            await using (var cmd = new SqlCommand(siteLinkSitesQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    var linkName = reader.GetString(0);
                    var siteName = reader.GetString(1);

                    if (!siteLinkSitesMap.TryGetValue(linkName, out var sites))
                    {
                        sites = new List<string>();
                        siteLinkSitesMap[linkName] = sites;
                    }
                    sites.Add(siteName);
                }
            }

            // Now get site links and combine with site info
            await using (var cmd = new SqlCommand(siteLinksQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    var linkName = reader.GetString(0);
                    siteLinkSitesMap.TryGetValue(linkName, out var connectedSites);

                    result.SiteLinks.Add(new TopologySiteLinkEdge
                    {
                        Id = $"link-{linkName}",
                        Name = linkName,
                        Cost = reader.IsDBNull(1) ? null : reader.GetInt16(1),
                        ReplicationInterval = reader.IsDBNull(2) ? null : reader.GetInt16(2),
                        TransportType = reader.IsDBNull(3) ? null : reader.GetString(3),
                        UseNotification = reader.GetInt32(4) == 1,
                        TwoWaySync = reader.GetInt32(5) == 1,
                        SiteIds = connectedSites?.Select(s => $"site-{s}").ToList() ?? new List<string>(),
                        SiteNames = connectedSites ?? new List<string>()
                    });
                }
            }

            if (extendedLogging)
            {
                _logger.LogInformation("[Topology Service] Site links query returned {Count} links, {MapCount} site-link mappings",
                    result.SiteLinks.Count, siteLinkSitesMap.Count);
                _logger.LogInformation("[Topology Service] Executing subnets query");
            }

            // Get subnets
            var subnetsQuery = @"
                SELECT
                    sub.SubnetName,
                    sub.SiteName,
                    sub.Description,
                    sub.Location
                FROM ADData.AD_Subnet sub
                WHERE sub.CollectionID = @CollectionID
                ORDER BY sub.SiteName, sub.SubnetName";

            await using (var cmd = new SqlCommand(subnetsQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    var subnetName = reader.GetString(0);
                    var siteName = reader.IsDBNull(1) ? null : reader.GetString(1);
                    result.Subnets.Add(new TopologySubnetNode
                    {
                        Id = $"subnet-{subnetName}",
                        Name = subnetName,
                        SiteId = siteName != null ? $"site-{siteName}" : "",
                        SiteName = siteName,
                        Description = reader.IsDBNull(2) ? null : reader.GetString(2),
                        Location = reader.IsDBNull(3) ? null : reader.GetString(3)
                    });
                }
            }

            if (extendedLogging)
            {
                _logger.LogInformation("[Topology Service] Subnets query returned {Count} subnets", result.Subnets.Count);
                _logger.LogInformation("[Topology Service] GetTopologyDataAsync complete - Sites: {Sites}, DCs: {DCs}, Links: {Links}, Subnets: {Subnets}",
                    result.Sites.Count, result.DomainControllers.Count, result.SiteLinks.Count, result.Subnets.Count);
            }

            _logger.LogDebug("Retrieved topology data: {Sites} sites, {DCs} DCs, {Links} links, {Subnets} subnets",
                result.Sites.Count, result.DomainControllers.Count, result.SiteLinks.Count, result.Subnets.Count);

            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Topology Service] Error getting topology data for collection {CollectionId}", collectionId);
            return null;
        }
    }

    /// <inheritdoc/>
    public async Task<(string? DomainName, string? ForestName, DateTime? CollectionDateTime)?> GetCollectionMetadataAsync(
        Guid collectionId, CancellationToken cancellationToken)
    {
        var extendedLogging = _loggingSettings.EnableExtendedLogging;

        if (extendedLogging)
        {
            _logger.LogInformation("[Topology Service] GetCollectionMetadataAsync called for CollectionId: {CollectionId}", collectionId);
        }

        if (!_sqlSettings.IsConfigured)
        {
            _logger.LogWarning("[Topology Service] GetCollectionMetadataAsync - SQL Server is not configured");
            return null;
        }

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                SELECT
                    ci.DomainName,
                    f.ForestName,
                    ci.CollectionDateTime
                FROM ADData.CollectionInfo ci
                LEFT JOIN ADData.AD_Forest f ON ci.CollectionID = f.CollectionID
                WHERE ci.CollectionID = @CollectionID";

            if (extendedLogging)
            {
                _logger.LogInformation("[Topology Service] Executing collection metadata query");
            }

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@CollectionID", collectionId);

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                var domainName = reader.IsDBNull(0) ? null : reader.GetString(0);
                var forestName = reader.IsDBNull(1) ? null : reader.GetString(1);
                var collectionDateTime = reader.IsDBNull(2) ? (DateTime?)null : reader.GetDateTime(2);

                if (extendedLogging)
                {
                    _logger.LogInformation("[Topology Service] Collection metadata found - Domain: {Domain}, Forest: {Forest}, DateTime: {DateTime}",
                        domainName, forestName, collectionDateTime);
                }

                return (domainName, forestName, collectionDateTime);
            }

            if (extendedLogging)
            {
                _logger.LogWarning("[Topology Service] No collection metadata found for CollectionId: {CollectionId}", collectionId);
            }

            return null;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Topology Service] Error getting collection metadata for {CollectionId}", collectionId);
            return null;
        }
    }

    /// <inheritdoc/>
    public async Task<TSLicenseServersInfo?> GetTSLicenseServersAsync(Guid collectionId, CancellationToken cancellationToken)
    {
        // Terminal Server License Servers group SID (built-in domain local group)
        const string tsLicenseServersSid = "S-1-5-32-561";

        // Well-known SID translations
        var wellKnownSids = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            { "S-1-5-18", "SYSTEM" },
            { "S-1-5-19", "LOCAL SERVICE" },
            { "S-1-5-20", "NETWORK SERVICE" },
            { "S-1-5-32-544", "Administrators" },
            { "S-1-5-32-545", "Users" },
            { "S-1-5-32-546", "Guests" }
        };

        if (!_sqlSettings.IsConfigured)
            return null;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Query group membership with member details from AD_Object
            // Resolves SIDs from:
            // 1. Current collection (same domain)
            // 2. Latest collections from trusted domains (Inbound or Bidirectional trusts)
            var query = @"
                ;WITH LatestCollections AS (
                    -- Get the latest CollectionID for each domain
                    SELECT
                        DomainName,
                        CollectionID,
                        ROW_NUMBER() OVER (PARTITION BY LOWER(DomainName) ORDER BY CollectionDateTime DESC) AS rn
                    FROM ADData.CollectionInfo
                ),
                TrustedDomainCollections AS (
                    -- Get latest CollectionIDs for domains with Inbound or Bidirectional trusts
                    SELECT DISTINCT lc.CollectionID
                    FROM ADData.AD_Trust t
                    INNER JOIN LatestCollections lc ON LOWER(t.TargetDomain) = LOWER(lc.DomainName) AND lc.rn = 1
                    WHERE t.CollectionID = @CollectionID
                      AND t.TrustDirection IN ('Inbound', 'Bidirectional')
                ),
                AllRelevantCollections AS (
                    -- Current collection + trusted domain collections
                    SELECT @CollectionID AS CollectionID
                    UNION
                    SELECT CollectionID FROM TrustedDomainCollections
                ),
                ResolvedMembers AS (
                    -- Get member info, preferring current collection, then trusted collections
                    SELECT
                        gm.MemberSID,
                        m.SamAccountName,
                        m.DNSHostName,
                        m.ObjectType,
                        m.OperatingSystem,
                        m.Enabled,
                        m.IsCriticalSystemObject,
                        m.DomainName AS ResolvedFromDomain,
                        ROW_NUMBER() OVER (
                            PARTITION BY gm.MemberSID
                            ORDER BY CASE WHEN m.CollectionID = @CollectionID THEN 0 ELSE 1 END
                        ) AS rn
                    FROM ADData.AD_GroupMembership gm
                    LEFT JOIN ADData.AD_Object m ON gm.MemberSID = m.SID_String
                        AND m.CollectionID IN (SELECT CollectionID FROM AllRelevantCollections)
                    WHERE gm.CollectionID = @CollectionID
                      AND gm.GroupSID = @GroupSID
                )
                SELECT
                    MemberSID,
                    SamAccountName AS MemberName,
                    DNSHostName AS MemberDNSHostName,
                    ObjectType AS MemberObjectType,
                    OperatingSystem AS MemberOperatingSystem,
                    Enabled AS MemberEnabled,
                    IsCriticalSystemObject,
                    ResolvedFromDomain
                FROM ResolvedMembers
                WHERE rn = 1
                ORDER BY
                    CASE WHEN ObjectType = 3 THEN 0 ELSE 1 END,  -- Computers first
                    COALESCE(DNSHostName, SamAccountName, MemberSID)";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@CollectionID", collectionId);
            cmd.Parameters.AddWithValue("@GroupSID", tsLicenseServersSid);

            var members = new List<TSLicenseServerMember>();

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var memberSid = reader.GetString(0);
                var memberName = reader.IsDBNull(1) ? null : reader.GetString(1);
                var dnsHostName = reader.IsDBNull(2) ? null : reader.GetString(2);
                var objectType = reader.IsDBNull(3) ? (int?)null : reader.GetInt32(3);
                var operatingSystem = reader.IsDBNull(4) ? null : reader.GetString(4);
                var enabled = reader.IsDBNull(5) ? (bool?)null : reader.GetBoolean(5);
                var isCriticalSystemObject = reader.IsDBNull(6) ? (bool?)null : reader.GetBoolean(6);
                var resolvedFromDomain = reader.IsDBNull(7) ? null : reader.GetString(7);

                // Determine if this is a well-known SID
                var isWellKnown = wellKnownSids.ContainsKey(memberSid);

                // Determine display name
                string displayName;
                if (isWellKnown)
                {
                    displayName = wellKnownSids[memberSid];
                }
                else if (!string.IsNullOrEmpty(dnsHostName))
                {
                    displayName = dnsHostName;
                }
                else if (!string.IsNullOrEmpty(memberName))
                {
                    displayName = memberName;
                }
                else
                {
                    displayName = memberSid;
                }

                // Determine member type
                string memberType;
                if (isWellKnown)
                {
                    memberType = "Well-Known";
                }
                else if (objectType == 3)
                {
                    memberType = "Computer";
                }
                else if (objectType == 2)
                {
                    memberType = "Group";
                }
                else if (objectType == 1)
                {
                    memberType = "User";
                }
                else
                {
                    memberType = "Unknown";
                }

                // Shorten OS display (e.g., "Windows Server 2022 Datacenter" -> "Server 2022")
                string? shortOs = null;
                if (!string.IsNullOrEmpty(operatingSystem))
                {
                    shortOs = operatingSystem
                        .Replace("Windows Server ", "Server ")
                        .Replace("Microsoft Windows ", "")
                        .Replace(" Standard", "")
                        .Replace(" Datacenter", "")
                        .Replace(" Enterprise", "");
                }

                members.Add(new TSLicenseServerMember
                {
                    MemberSID = memberSid,
                    DisplayName = displayName,
                    MemberType = memberType,
                    OperatingSystem = shortOs,
                    Enabled = isWellKnown ? null : enabled,
                    IsWellKnown = isWellKnown,
                    IsDomainController = objectType == 3 && isCriticalSystemObject == true,
                    ResolvedFromDomain = resolvedFromDomain
                });
            }

            _logger.LogDebug("Found {Count} members in Terminal Server License Servers group for collection {CollectionId}",
                members.Count, collectionId);

            return new TSLicenseServersInfo
            {
                HasMembers = members.Count > 0,
                MemberCount = members.Count,
                Members = members
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting Terminal Server License Servers for collection {CollectionId}", collectionId);
            return null;
        }
    }

    /// <inheritdoc/>
    public async Task<KmsServicesInfo?> GetKmsServicesAsync(Guid collectionId, string domainName, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured || string.IsNullOrEmpty(domainName))
            return null;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                SELECT
                    TargetHostname,
                    Port,
                    Priority,
                    Weight,
                    ResolvedIP,
                    RecordSource
                FROM ADData.AD_KMSService
                WHERE CollectionID = @CollectionID
                  AND LOWER(DomainName) = LOWER(@DomainName)
                ORDER BY Priority, Weight DESC, TargetHostname";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@CollectionID", collectionId);
            cmd.Parameters.AddWithValue("@DomainName", domainName);

            var servers = new List<KmsServerInfo>();

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                servers.Add(new KmsServerInfo
                {
                    TargetHostname = reader.GetString(0),
                    Port = reader.GetInt32(1),
                    Priority = reader.IsDBNull(2) ? null : reader.GetInt32(2),
                    Weight = reader.IsDBNull(3) ? null : reader.GetInt32(3),
                    ResolvedIP = reader.IsDBNull(4) ? null : reader.GetString(4),
                    RecordSource = reader.IsDBNull(5) ? "DNS" : reader.GetString(5)
                });
            }

            _logger.LogDebug("Found {Count} KMS servers for domain {DomainName} in collection {CollectionId}",
                servers.Count, domainName, collectionId);

            return new KmsServicesInfo
            {
                HasServers = servers.Count > 0,
                ServerCount = servers.Count,
                Servers = servers
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting KMS services for domain {DomainName} in collection {CollectionId}",
                domainName, collectionId);
            return null;
        }
    }

    /// <inheritdoc/>
    public async Task<AdfsConfigurationInfo?> GetAdfsConfigurationAsync(Guid collectionId, string forestName, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured || string.IsNullOrEmpty(forestName))
            return null;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                SELECT
                    ServiceType,
                    ServiceName,
                    FederationServiceName,
                    AzureTenantId,
                    AzureObjectId,
                    DomainName,
                    ServiceBindingInfo
                FROM ADData.AD_ADFSConfiguration
                WHERE CollectionID = @CollectionID
                  AND LOWER(ForestName) = LOWER(@ForestName)
                ORDER BY ServiceType, ServiceName";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@CollectionID", collectionId);
            cmd.Parameters.AddWithValue("@ForestName", forestName);

            var services = new List<AdfsServiceInfo>();

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                services.Add(new AdfsServiceInfo
                {
                    ServiceType = reader.GetString(0),
                    ServiceName = reader.IsDBNull(1) ? null : reader.GetString(1),
                    FederationServiceName = reader.IsDBNull(2) ? null : reader.GetString(2),
                    AzureTenantId = reader.IsDBNull(3) ? null : reader.GetString(3),
                    AzureObjectId = reader.IsDBNull(4) ? null : reader.GetString(4),
                    DomainName = reader.IsDBNull(5) ? null : reader.GetString(5),
                    ServiceBindingInfo = reader.IsDBNull(6) ? null : reader.GetString(6)
                });
            }

            _logger.LogDebug("Found {Count} ADFS configurations for forest {ForestName} in collection {CollectionId}",
                services.Count, forestName, collectionId);

            return new AdfsConfigurationInfo
            {
                HasConfiguration = services.Count > 0,
                ForestName = forestName,
                Services = services
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting ADFS configuration for forest {ForestName} in collection {CollectionId}",
                forestName, collectionId);
            return null;
        }
    }

    /// <inheritdoc/>
    public async Task<PkiSummaryInfo?> GetPkiSummaryAsync(Guid collectionId, string forestName, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured || string.IsNullOrEmpty(forestName))
            return null;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Query Enterprise CAs with template counts
            var caQuery = @"
                SELECT
                    CAName,
                    DNSHostName,
                    CAType,
                    -- Count templates from the JSON array (rough count via length)
                    -- Cast to INT because LEN() returns BIGINT
                    CAST(CASE
                        WHEN CertificateTemplates IS NULL OR CertificateTemplates = '' OR CertificateTemplates = '[]' THEN 0
                        ELSE LEN(CertificateTemplates) - LEN(REPLACE(CertificateTemplates, ',', '')) + 1
                    END AS INT) AS TemplateCount
                FROM ADData.AD_EnterpriseCA
                WHERE CollectionID = @CollectionID
                  AND LOWER(ForestName) = LOWER(@ForestName)
                ORDER BY
                    CASE WHEN CAType LIKE '%Root%' THEN 0 ELSE 1 END,
                    CAName";

            var enterpriseCAs = new List<EnterpriseCaInfo>();

            await using (var cmd = new SqlCommand(caQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);
                cmd.Parameters.AddWithValue("@ForestName", forestName);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    enterpriseCAs.Add(new EnterpriseCaInfo
                    {
                        CAName = reader.GetString(0),
                        DNSHostName = reader.IsDBNull(1) ? null : reader.GetString(1),
                        CAType = reader.IsDBNull(2) ? null : reader.GetString(2),
                        TemplateCount = reader.GetInt32(3)
                    });
                }
            }

            // Query counts for templates, trusted roots, and NTAuth certs
            var countsQuery = @"
                SELECT
                    (SELECT COUNT(*) FROM ADData.AD_CertificateTemplate
                     WHERE CollectionID = @CollectionID AND LOWER(ForestName) = LOWER(@ForestName)) AS TemplateCount,
                    (SELECT COUNT(*) FROM ADData.AD_TrustedRootCA
                     WHERE CollectionID = @CollectionID AND LOWER(ForestName) = LOWER(@ForestName)) AS TrustedRootCount,
                    (SELECT COUNT(*) FROM ADData.AD_NTAuthCA
                     WHERE CollectionID = @CollectionID AND LOWER(ForestName) = LOWER(@ForestName)) AS NTAuthCount,
                    (SELECT COUNT(*) FROM ADData.AD_NTAuthCA
                     WHERE CollectionID = @CollectionID AND LOWER(ForestName) = LOWER(@ForestName)
                       AND CertificateNotAfter IS NOT NULL
                       AND TRY_CAST(CertificateNotAfter AS DATETIME2) < DATEADD(DAY, 90, GETUTCDATE())) AS NTAuthExpiringCount";

            int templateCount = 0, trustedRootCount = 0, ntAuthCount = 0, ntAuthExpiringCount = 0;

            await using (var cmd = new SqlCommand(countsQuery, connection))
            {
                cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
                cmd.Parameters.AddWithValue("@CollectionID", collectionId);
                cmd.Parameters.AddWithValue("@ForestName", forestName);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                if (await reader.ReadAsync(cancellationToken))
                {
                    templateCount = reader.GetInt32(0);
                    trustedRootCount = reader.GetInt32(1);
                    ntAuthCount = reader.GetInt32(2);
                    ntAuthExpiringCount = reader.GetInt32(3);
                }
            }

            var hasData = enterpriseCAs.Count > 0 || templateCount > 0 || trustedRootCount > 0 || ntAuthCount > 0;

            _logger.LogDebug("Found PKI data for forest {ForestName}: {CACount} CAs, {TemplateCount} templates, {RootCount} trusted roots, {NTAuthCount} NTAuth certs",
                forestName, enterpriseCAs.Count, templateCount, trustedRootCount, ntAuthCount);

            return new PkiSummaryInfo
            {
                HasData = hasData,
                ForestName = forestName,
                EnterpriseCAs = enterpriseCAs,
                CertificateTemplateCount = templateCount,
                TrustedRootCACount = trustedRootCount,
                NTAuthCertificateCount = ntAuthCount,
                NTAuthExpiringCount = ntAuthExpiringCount
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting PKI summary for forest {ForestName} in collection {CollectionId}",
                forestName, collectionId);
            return null;
        }
    }

    /// <inheritdoc/>
    public async Task<List<CertificateTemplateDetail>> GetCertificateTemplatesAsync(
        Guid collectionId, string forestName, CancellationToken cancellationToken)
    {
        var results = new List<CertificateTemplateDetail>();

        if (!_sqlSettings.IsConfigured || string.IsNullOrEmpty(forestName))
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                SELECT TemplateName, DisplayName, SchemaVersion, MinKeySize,
                       ValidityPeriod, RenewalPeriod, RASignaturesRequired, ExtendedKeyUsage
                FROM ADData.AD_CertificateTemplate
                WHERE CollectionID = @CollectionID
                  AND LOWER(ForestName) = LOWER(@ForestName)
                ORDER BY COALESCE(DisplayName, TemplateName)";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@CollectionID", collectionId);
            cmd.Parameters.AddWithValue("@ForestName", forestName);

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add(new CertificateTemplateDetail
                {
                    TemplateName = reader.GetString(0),
                    DisplayName = reader.IsDBNull(1) ? null : reader.GetString(1),
                    SchemaVersion = reader.IsDBNull(2) ? 0 : reader.GetInt32(2),
                    MinKeySize = reader.IsDBNull(3) ? 0 : reader.GetInt32(3),
                    ValidityPeriod = reader.IsDBNull(4) ? null : reader.GetString(4),
                    RenewalPeriod = reader.IsDBNull(5) ? null : reader.GetString(5),
                    RASignaturesRequired = reader.IsDBNull(6) ? 0 : reader.GetInt32(6),
                    ExtendedKeyUsage = reader.IsDBNull(7) ? null : reader.GetString(7)
                });
            }

            _logger.LogDebug("Found {Count} certificate templates for forest {ForestName}",
                results.Count, forestName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting certificate templates for forest {ForestName} in collection {CollectionId}",
                forestName, collectionId);
        }

        return results;
    }

    /// <inheritdoc/>
    public async Task<List<TrustedRootCaDetail>> GetTrustedRootCAsAsync(
        Guid collectionId, string forestName, CancellationToken cancellationToken)
    {
        var results = new List<TrustedRootCaDetail>();

        if (!_sqlSettings.IsConfigured || string.IsNullOrEmpty(forestName))
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                SELECT CAName, CertificateSubject, CertificateThumbprint,
                       CertificateNotBefore, CertificateNotAfter, ContainerType
                FROM ADData.AD_TrustedRootCA
                WHERE CollectionID = @CollectionID
                  AND LOWER(ForestName) = LOWER(@ForestName)
                ORDER BY CertificateNotAfter, CAName";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@CollectionID", collectionId);
            cmd.Parameters.AddWithValue("@ForestName", forestName);

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add(new TrustedRootCaDetail
                {
                    CAName = reader.IsDBNull(0) ? "" : reader.GetString(0),
                    CertificateSubject = reader.IsDBNull(1) ? null : reader.GetString(1),
                    CertificateThumbprint = reader.IsDBNull(2) ? null : reader.GetString(2),
                    CertificateNotBefore = reader.IsDBNull(3) ? null : reader.GetDateTime(3),
                    CertificateNotAfter = reader.IsDBNull(4) ? null : reader.GetDateTime(4),
                    ContainerType = reader.IsDBNull(5) ? null : reader.GetString(5)
                });
            }

            _logger.LogDebug("Found {Count} trusted root CAs for forest {ForestName}",
                results.Count, forestName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting trusted root CAs for forest {ForestName} in collection {CollectionId}",
                forestName, collectionId);
        }

        return results;
    }

    /// <inheritdoc/>
    public async Task<List<NTAuthCertificateDetail>> GetNTAuthCertificatesAsync(
        Guid collectionId, string forestName, CancellationToken cancellationToken)
    {
        var results = new List<NTAuthCertificateDetail>();

        if (!_sqlSettings.IsConfigured || string.IsNullOrEmpty(forestName))
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                SELECT CertificateSubject, CertificateThumbprint,
                       CertificateNotBefore, CertificateNotAfter, CertificateIndex
                FROM ADData.AD_NTAuthCA
                WHERE CollectionID = @CollectionID
                  AND LOWER(ForestName) = LOWER(@ForestName)
                ORDER BY CertificateNotAfter, CertificateIndex";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@CollectionID", collectionId);
            cmd.Parameters.AddWithValue("@ForestName", forestName);

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add(new NTAuthCertificateDetail
                {
                    CertificateSubject = reader.IsDBNull(0) ? null : reader.GetString(0),
                    CertificateThumbprint = reader.IsDBNull(1) ? null : reader.GetString(1),
                    CertificateNotBefore = reader.IsDBNull(2) ? null : reader.GetDateTime(2),
                    CertificateNotAfter = reader.IsDBNull(3) ? null : reader.GetDateTime(3),
                    CertificateIndex = reader.IsDBNull(4) ? 0 : reader.GetInt32(4)
                });
            }

            _logger.LogDebug("Found {Count} NTAuth certificates for forest {ForestName}",
                results.Count, forestName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting NTAuth certificates for forest {ForestName} in collection {CollectionId}",
                forestName, collectionId);
        }

        return results;
    }

    /// <inheritdoc/>
    public async Task<EnterpriseCaDetail?> GetEnterpriseCaDetailAsync(
        Guid collectionId, string forestName, string caName, CancellationToken cancellationToken)
    {
        if (!_sqlSettings.IsConfigured || string.IsNullOrEmpty(forestName) || string.IsNullOrEmpty(caName))
            return null;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var query = @"
                SELECT CAName, DNSHostName, CAType, CACertificateDN,
                       DistinguishedName, CertificateTemplates, WhenCreated, WhenChanged
                FROM ADData.AD_EnterpriseCA
                WHERE CollectionID = @CollectionID
                  AND LOWER(ForestName) = LOWER(@ForestName)
                  AND CAName = @CAName";

            await using var cmd = new SqlCommand(query, connection);
            cmd.CommandTimeout = _perfSettings.CommandTimeoutSeconds;
            cmd.Parameters.AddWithValue("@CollectionID", collectionId);
            cmd.Parameters.AddWithValue("@ForestName", forestName);
            cmd.Parameters.AddWithValue("@CAName", caName);

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                var detail = new EnterpriseCaDetail
                {
                    CAName = reader.GetString(0),
                    DNSHostName = reader.IsDBNull(1) ? null : reader.GetString(1),
                    CAType = reader.IsDBNull(2) ? null : reader.GetString(2),
                    CACertificateDN = reader.IsDBNull(3) ? null : reader.GetString(3),
                    DistinguishedName = reader.IsDBNull(4) ? null : reader.GetString(4),
                    WhenCreated = reader.IsDBNull(6) ? null : reader.GetDateTime(6),
                    WhenChanged = reader.IsDBNull(7) ? null : reader.GetDateTime(7)
                };

                // Parse CertificateTemplates JSON array
                var templatesJson = reader.IsDBNull(5) ? null : reader.GetString(5);
                if (!string.IsNullOrEmpty(templatesJson))
                {
                    try
                    {
                        var templates = System.Text.Json.JsonSerializer.Deserialize<List<string>>(templatesJson);
                        if (templates != null)
                        {
                            detail.PublishedTemplates = templates;
                        }
                    }
                    catch (System.Text.Json.JsonException)
                    {
                        // If JSON parsing fails, try comma-separated format
                        detail.PublishedTemplates = templatesJson
                            .Trim('[', ']', '"')
                            .Split(new[] { "\",\"", "," }, StringSplitOptions.RemoveEmptyEntries)
                            .Select(t => t.Trim('"', ' '))
                            .Where(t => !string.IsNullOrWhiteSpace(t))
                            .ToList();
                    }
                }

                _logger.LogDebug("Found Enterprise CA {CAName} with {TemplateCount} templates",
                    detail.CAName, detail.PublishedTemplates.Count);

                return detail;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting Enterprise CA {CAName} for forest {ForestName} in collection {CollectionId}",
                caName, forestName, collectionId);
        }

        return null;
    }
}
