using Microsoft.Data.SqlClient;
using CLAWS.Core.Configuration;
using CLAWS.Core.Services;

namespace CLAWS.Web.Services;

/// <summary>
/// Service for Cloud Integration validation operations.
/// </summary>
public class CloudIntegrationService : ICloudIntegrationService
{
    private readonly ILogger<CloudIntegrationService> _logger;
    private readonly SqlServerSettings _sqlSettings;
    private readonly DatabasePerformanceSettings _perfSettings;

    // TriState values
    private const byte TriStateYes = 1;
    private const byte TriStateNo = 2;
    private const byte TriStateNever = 3;

    public CloudIntegrationService(
        ILogger<CloudIntegrationService> logger,
        SqlServerSettings sqlSettings,
        DatabasePerformanceSettings perfSettings)
    {
        _logger = logger;
        _sqlSettings = sqlSettings;
        _perfSettings = perfSettings;
    }

    /// <inheritdoc/>
    public async Task<List<CloudIntegrationDomainInfo>> GetDomainsForValidationAsync(CancellationToken cancellationToken)
    {
        var results = new List<CloudIntegrationDomainInfo>();

        if (!_sqlSettings.IsConfigured)
            return results;

        var connectionString = _sqlSettings.BuildConnectionString();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Get all non-decommissioned domains
            var query = @"
                SELECT
                    DomainID,
                    DomainName,
                    NetBIOSName,
                    IsCloudIntegrated,
                    xldapUrl
                FROM DML.DomainMasterList
                WHERE IsDecommissioned = 0
                ORDER BY DomainName";

            await using var command = new SqlCommand(query, connection);
            command.CommandTimeout = _perfSettings.CommandTimeoutMinutes * 60;

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);

            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add(new CloudIntegrationDomainInfo
                {
                    DomainMasterListID = reader.GetInt32(0),
                    DomainName = reader.GetString(1),
                    NetBIOSName = reader.IsDBNull(2) ? null : reader.GetString(2),
                    IsCloudIntegrated = reader.GetByte(3),
                    XldapUrl = reader.IsDBNull(4) ? null : reader.GetString(4)
                });
            }

            _logger.LogDebug("Retrieved {Count} domains for Cloud Integration validation", results.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving domains for Cloud Integration validation");
            throw;
        }

        return results;
    }

    /// <inheritdoc/>
    public async Task<CloudIntegrationValidationResult> ProcessDomainValidationAsync(
        CloudIntegrationDomainInfo domain,
        Dictionary<string, LdapDomainInfo> ldapResults,
        CancellationToken cancellationToken)
    {
        var result = new CloudIntegrationValidationResult
        {
            OldState = domain.IsCloudIntegrated,
            OldXldapUrl = domain.XldapUrl
        };

        // Try to find the domain in LDAP results by NetBIOSName or DomainName
        LdapDomainInfo? ldapInfo = null;
        if (!string.IsNullOrEmpty(domain.NetBIOSName) && ldapResults.TryGetValue(domain.NetBIOSName, out ldapInfo))
        {
            // Found by NetBIOSName
        }
        else if (ldapResults.TryGetValue(domain.DomainName, out ldapInfo))
        {
            // Found by DomainName
        }

        // Determine new state based on LDAP results
        byte newState;
        string? newXldapUrl;

        if (ldapInfo != null)
        {
            // Domain found in LDAP
            newXldapUrl = ldapInfo.XldapUrl;

            // If xldapURL is present and not empty, domain is cloud integrated
            if (!string.IsNullOrWhiteSpace(ldapInfo.XldapUrl))
            {
                newState = TriStateYes;
            }
            else
            {
                // OU exists but no xldapURL - not integrated
                newState = TriStateNo;
            }
        }
        else
        {
            // Domain not found in LDAP - not integrated
            newState = TriStateNo;
            newXldapUrl = null;
        }

        result.NewState = newState;
        result.NewXldapUrl = newXldapUrl;

        // Check if we should update
        var shouldUpdateState = false;
        var shouldUpdateXldapUrl = false;
        var noteText = new List<string>();

        // Handle IsCloudIntegrated = 3 (Never) - validate but never overwrite
        if (domain.IsCloudIntegrated == TriStateNever)
        {
            if (newState == TriStateYes)
            {
                // Log discrepancy but don't update
                noteText.Add($"[Cloud Integration Validation] Discrepancy detected: LDAP shows xldapURL present but IsCloudIntegrated is set to 'Never'. Manual review recommended. LDAP xldapURL: {newXldapUrl}");
                _logger.LogWarning("Domain {DomainName} has IsCloudIntegrated=Never but LDAP shows xldapURL present: {XldapUrl}",
                    domain.DomainName, newXldapUrl);
            }
        }
        else
        {
            // Can update state (IsCloudIntegrated = 1 or 2)
            if (domain.IsCloudIntegrated != newState)
            {
                shouldUpdateState = true;
                var oldStateName = GetStateName(domain.IsCloudIntegrated);
                var newStateName = GetStateName(newState);
                noteText.Add($"[Cloud Integration Validation] IsCloudIntegrated changed from '{oldStateName}' to '{newStateName}' based on LDAP validation.");
                _logger.LogInformation("Domain {DomainName}: IsCloudIntegrated changing from {OldState} to {NewState}",
                    domain.DomainName, oldStateName, newStateName);
            }
        }

        // Check for xldapURL changes (always track, regardless of IsCloudIntegrated value)
        if (domain.XldapUrl != newXldapUrl)
        {
            shouldUpdateXldapUrl = true;
            if (string.IsNullOrEmpty(domain.XldapUrl) && !string.IsNullOrEmpty(newXldapUrl))
            {
                noteText.Add($"[Cloud Integration Validation] xldapURL set to: {newXldapUrl}");
            }
            else if (!string.IsNullOrEmpty(domain.XldapUrl) && string.IsNullOrEmpty(newXldapUrl))
            {
                noteText.Add($"[Cloud Integration Validation] xldapURL removed (was: {domain.XldapUrl})");
            }
            else
            {
                noteText.Add($"[Cloud Integration Validation] xldapURL changed from '{domain.XldapUrl}' to '{newXldapUrl}'");
            }
        }

        // Apply updates if needed
        if (shouldUpdateState || shouldUpdateXldapUrl || noteText.Count > 0)
        {
            await ApplyUpdatesAsync(domain.DomainMasterListID,
                shouldUpdateState ? newState : null,
                shouldUpdateXldapUrl ? newXldapUrl : domain.XldapUrl,
                shouldUpdateXldapUrl,
                noteText,
                cancellationToken);

            result.WasUpdated = shouldUpdateState || shouldUpdateXldapUrl;
            result.NoteCreated = string.Join(" ", noteText);
        }

        return result;
    }

    private async Task ApplyUpdatesAsync(
        int domainId,
        byte? newState,
        string? newXldapUrl,
        bool updateXldapUrl,
        List<string> notes,
        CancellationToken cancellationToken)
    {
        var connectionString = _sqlSettings.BuildConnectionString();

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = connection.BeginTransaction();

        try
        {
            // Update DomainMasterList if needed
            if (newState.HasValue || updateXldapUrl)
            {
                var updateParts = new List<string>();
                if (newState.HasValue)
                    updateParts.Add("IsCloudIntegrated = @NewState");
                if (updateXldapUrl)
                    updateParts.Add("xldapUrl = @NewXldapUrl");
                updateParts.Add("UpdatedAt = SYSUTCDATETIME()");

                var updateQuery = $@"
                    UPDATE DML.DomainMasterList
                    SET {string.Join(", ", updateParts)}
                    WHERE DomainID = @DomainId";

                await using var updateCommand = new SqlCommand(updateQuery, connection, transaction);
                updateCommand.Parameters.AddWithValue("@DomainId", domainId);
                if (newState.HasValue)
                    updateCommand.Parameters.AddWithValue("@NewState", newState.Value);
                if (updateXldapUrl)
                    updateCommand.Parameters.AddWithValue("@NewXldapUrl", (object?)newXldapUrl ?? DBNull.Value);

                await updateCommand.ExecuteNonQueryAsync(cancellationToken);
            }

            // Insert notes
            foreach (var note in notes)
            {
                var noteQuery = @"
                    INSERT INTO DML.DomainNotes (DomainID, NoteSubject, NoteText, CreatedBy)
                    VALUES (@DomainId, @NoteSubject, @NoteText, @CreatedBy)";

                await using var noteCommand = new SqlCommand(noteQuery, connection, transaction);
                noteCommand.Parameters.AddWithValue("@DomainId", domainId);
                noteCommand.Parameters.AddWithValue("@NoteSubject", "Cloud Integration Validation");
                noteCommand.Parameters.AddWithValue("@NoteText", note);
                noteCommand.Parameters.AddWithValue("@CreatedBy", "CloudIntegrationValidation");

                await noteCommand.ExecuteNonQueryAsync(cancellationToken);
            }

            await transaction.CommitAsync(cancellationToken);
        }
        catch
        {
            await transaction.RollbackAsync(cancellationToken);
            throw;
        }
    }

    private static string GetStateName(byte state) => state switch
    {
        TriStateYes => "Yes",
        TriStateNo => "No",
        TriStateNever => "Never",
        _ => $"Unknown({state})"
    };
}
