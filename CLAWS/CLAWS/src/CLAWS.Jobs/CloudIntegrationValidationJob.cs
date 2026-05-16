using Hangfire;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Core.Services;
using System.DirectoryServices.Protocols;
using System.Net;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for validating Cloud Integration status via LDAP lookup.
/// </summary>
public interface ICloudIntegrationValidationJob
{
    /// <summary>
    /// Validates Cloud AD Management integration status for all domains.
    /// </summary>
    [JobDisplayName("DML: Cloud Integration Validation")]
    Task ValidateCloudIntegrationAsync(CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of the Cloud Integration validation job.
/// </summary>
public class CloudIntegrationValidationJob : ICloudIntegrationValidationJob
{
    private readonly ILogger<CloudIntegrationValidationJob> _logger;
    private readonly ISecureCredentialService _credentialService;
    private readonly ICloudIntegrationService _cloudIntegrationService;
    private readonly AppSettings _appSettings;

    public CloudIntegrationValidationJob(
        ILogger<CloudIntegrationValidationJob> logger,
        ISecureCredentialService credentialService,
        ICloudIntegrationService cloudIntegrationService,
        AppSettings appSettings)
    {
        _logger = logger;
        _credentialService = credentialService;
        _cloudIntegrationService = cloudIntegrationService;
        _appSettings = appSettings;
    }

    /// <inheritdoc/>
    public async Task ValidateCloudIntegrationAsync(CancellationToken cancellationToken)
    {
        var config = _appSettings.CloudIntegration;
        if (!config.IsConfigured)
        {
            _logger.LogInformation("Cloud Integration validation skipped - not configured or disabled");
            return;
        }

        _logger.LogInformation("Starting Cloud Integration validation. Server={Server}, SearchBase={SearchBase}",
            config.LdapServer, config.LdapSearchBase);

        try
        {
            // Get decrypted password
            var password = _credentialService.GetCloudIntegrationPassword();
            if (string.IsNullOrEmpty(password))
            {
                _logger.LogError("Cloud Integration validation failed - unable to retrieve service account password");
                return;
            }

            // Get all domains to validate
            var domains = await _cloudIntegrationService.GetDomainsForValidationAsync(cancellationToken);
            _logger.LogInformation("Found {Count} domains to validate", domains.Count);

            if (domains.Count == 0)
            {
                _logger.LogInformation("No domains to validate");
                return;
            }

            // Query LDAP for all domain OUs
            var ldapResults = QueryLdapForDomainStatus(config, password);
            _logger.LogInformation("Retrieved {Count} domain OUs from LDAP", ldapResults.Count);

            // Process in batches
            var processedCount = 0;
            var updatedCount = 0;
            var errorCount = 0;

            foreach (var batch in domains.Chunk(config.BatchSize))
            {
                if (cancellationToken.IsCancellationRequested)
                    break;

                foreach (var domain in batch)
                {
                    try
                    {
                        var result = await _cloudIntegrationService.ProcessDomainValidationAsync(
                            domain, ldapResults, cancellationToken);

                        processedCount++;
                        if (result.WasUpdated)
                            updatedCount++;
                    }
                    catch (Exception ex)
                    {
                        errorCount++;
                        _logger.LogError(ex, "Error processing domain {DomainId}: {DomainName}",
                            domain.DomainMasterListID, domain.DomainName);
                    }
                }

                // Delay between batches
                if (config.DelayBetweenBatchesMs > 0)
                {
                    await Task.Delay(config.DelayBetweenBatchesMs, cancellationToken);
                }
            }

            _logger.LogInformation("Cloud Integration validation completed. Processed={Processed}, Updated={Updated}, Errors={Errors}",
                processedCount, updatedCount, errorCount);
        }
        catch (LdapException ex)
        {
            _logger.LogError(ex, "LDAP error during Cloud Integration validation: {Message}", ex.Message);
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during Cloud Integration validation");
            throw;
        }
    }

    private Dictionary<string, LdapDomainInfo> QueryLdapForDomainStatus(
        CloudIntegrationSettings config,
        string password)
    {
        var results = new Dictionary<string, LdapDomainInfo>(StringComparer.OrdinalIgnoreCase);

        // Build credentials
        var username = string.IsNullOrEmpty(config.ServiceAccountDomain)
            ? config.ServiceAccountUsername
            : $"{config.ServiceAccountDomain}\\{config.ServiceAccountUsername}";

        using var connection = new LdapConnection(
            new LdapDirectoryIdentifier(config.LdapServer, config.LdapPort));

        connection.SessionOptions.ProtocolVersion = 3;
        connection.SessionOptions.SecureSocketLayer = config.LdapUseSsl;
        connection.Timeout = TimeSpan.FromSeconds(config.ConnectionTimeout);
        connection.Credential = new NetworkCredential(username, password);
        connection.AuthType = AuthType.Basic;

        // Bind to LDAP
        connection.Bind();

        // Search for all OUs with xldapURL attribute
        var searchRequest = new SearchRequest(
            config.LdapSearchBase,
            "(objectClass=organizationalUnit)",
            SearchScope.OneLevel,
            "name", "xldapURL", "description");

        var searchResponse = (SearchResponse)connection.SendRequest(searchRequest);

        foreach (SearchResultEntry entry in searchResponse.Entries)
        {
            var name = entry.Attributes["name"]?[0]?.ToString();
            var xldapUrl = entry.Attributes["xldapURL"]?[0]?.ToString();

            if (!string.IsNullOrEmpty(name))
            {
                results[name] = new LdapDomainInfo
                {
                    Name = name,
                    XldapUrl = xldapUrl,
                    DistinguishedName = entry.DistinguishedName
                };
            }
        }

        return results;
    }
}
