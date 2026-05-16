namespace CLAWS.Core.Services;

/// <summary>
/// Service for Cloud Integration validation operations.
/// </summary>
public interface ICloudIntegrationService
{
    /// <summary>
    /// Gets all domains that need Cloud Integration validation.
    /// </summary>
    Task<List<CloudIntegrationDomainInfo>> GetDomainsForValidationAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Processes a single domain's Cloud Integration validation.
    /// </summary>
    Task<CloudIntegrationValidationResult> ProcessDomainValidationAsync(
        CloudIntegrationDomainInfo domain,
        Dictionary<string, LdapDomainInfo> ldapResults,
        CancellationToken cancellationToken);
}

/// <summary>
/// Domain information needed for Cloud Integration validation.
/// </summary>
public class CloudIntegrationDomainInfo
{
    public int DomainMasterListID { get; set; }
    public string DomainName { get; set; } = string.Empty;
    public string? NetBIOSName { get; set; }
    public byte IsCloudIntegrated { get; set; }
    public string? XldapUrl { get; set; }
}

/// <summary>
/// Result of processing a single domain's Cloud Integration validation.
/// </summary>
public class CloudIntegrationValidationResult
{
    public bool WasUpdated { get; set; }
    public byte? OldState { get; set; }
    public byte? NewState { get; set; }
    public string? OldXldapUrl { get; set; }
    public string? NewXldapUrl { get; set; }
    public string? NoteCreated { get; set; }
}

/// <summary>
/// Information about a domain from LDAP.
/// </summary>
public class LdapDomainInfo
{
    public string Name { get; set; } = string.Empty;
    public string? XldapUrl { get; set; }
    public string DistinguishedName { get; set; } = string.Empty;
}
