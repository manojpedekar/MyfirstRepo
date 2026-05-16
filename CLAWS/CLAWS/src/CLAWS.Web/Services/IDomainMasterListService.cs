using CLAWS.Web.Models;

namespace CLAWS.Web.Services;

/// <summary>
/// Service for managing Domain Master List (DML) data.
/// </summary>
public interface IDomainMasterListService
{
    /// <summary>
    /// Gets all domains, optionally including decommissioned ones.
    /// </summary>
    Task<List<DomainMasterListItem>> GetAllDomainsAsync(bool includeDecommissioned, CancellationToken cancellationToken);

    /// <summary>
    /// Gets a domain by its ID, including notes.
    /// </summary>
    Task<DomainMasterListItem?> GetDomainByIdAsync(int domainId, CancellationToken cancellationToken);

    /// <summary>
    /// Creates a new domain.
    /// </summary>
    Task<(bool Success, string Message, int? DomainId)> CreateDomainAsync(DomainCreateRequest request, CancellationToken cancellationToken);

    /// <summary>
    /// Updates an existing domain.
    /// </summary>
    Task<(bool Success, string Message)> UpdateDomainAsync(DomainUpdateRequest request, CancellationToken cancellationToken);

    /// <summary>
    /// Deletes a domain by its ID.
    /// </summary>
    Task<(bool Success, string Message)> DeleteDomainAsync(int domainId, CancellationToken cancellationToken);

    /// <summary>
    /// Adds a note to a domain.
    /// </summary>
    Task<(bool Success, string Message, int? NoteId)> AddNoteAsync(int domainId, string? noteSubject, string noteText, string createdBy, CancellationToken cancellationToken);

    /// <summary>
    /// Gets the domain name by ID.
    /// </summary>
    Task<string?> GetDomainNameAsync(int domainId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets notes for a domain.
    /// </summary>
    Task<List<DomainNoteItem>> GetNotesAsync(int domainId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets domain counts (total, active, decommissioned).
    /// </summary>
    Task<(int Total, int Active, int Decommissioned)> GetDomainCountsAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Gets responsibility level lookup values.
    /// </summary>
    Task<List<DmlLookupItem>> GetResponsibilityLevelsAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Gets tri-state lookup values.
    /// </summary>
    Task<List<DmlLookupItem>> GetTriStatesAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Gets baseline status lookup values.
    /// </summary>
    Task<List<DmlLookupItem>> GetBaselineStatusesAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Gets AD inventory information (forest and domain) for a domain from the most recent collection.
    /// Returns null if no inventory data exists for the domain.
    /// </summary>
    Task<AdInventoryInfo?> GetAdInventoryInfoAsync(string domainName, CancellationToken cancellationToken);

    /// <summary>
    /// Gets Sites & Services summary information for a collection.
    /// Returns site counts and site summary data.
    /// </summary>
    Task<SitesAndServicesInfo?> GetSitesAndServicesSummaryAsync(Guid collectionId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets site links with pagination support for large environments.
    /// </summary>
    Task<(List<SiteLinkInfo> SiteLinks, int TotalCount)> GetSiteLinksAsync(
        Guid collectionId,
        int skip = 0,
        int take = 50,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets subnets with optional filtering by site and pagination.
    /// </summary>
    Task<(List<SubnetInfo> Subnets, int TotalCount)> GetSubnetsAsync(
        Guid collectionId,
        string? siteFilter = null,
        int skip = 0,
        int take = 100,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets domain health information (SYSVOL, GPO, Optional Features) for a domain.
    /// </summary>
    Task<DomainHealthInfo?> GetDomainHealthAsync(Guid collectionId, string domainName, CancellationToken cancellationToken);

    /// <summary>
    /// Gets optional features for a forest from AD_OptionalFeature table.
    /// </summary>
    Task<List<OptionalFeatureInfo>> GetOptionalFeaturesAsync(Guid collectionId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets trust relationships for a domain from AD_Trust table.
    /// </summary>
    Task<(List<TrustInfo> Trusts, int TotalCount)> GetTrustsAsync(Guid collectionId, string domainName, CancellationToken cancellationToken);

    /// <summary>
    /// Gets all log entries for a collection from AD_Log table.
    /// </summary>
    Task<List<AdLogEntry>> GetCollectionLogsAsync(Guid collectionId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets topology visualization data for Cytoscape.js.
    /// Includes sites, domain controllers, site links, and subnets.
    /// </summary>
    Task<TopologyData?> GetTopologyDataAsync(Guid collectionId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets collection metadata (domain name, forest name, collection datetime) for a collection.
    /// </summary>
    Task<(string? DomainName, string? ForestName, DateTime? CollectionDateTime)?> GetCollectionMetadataAsync(
        Guid collectionId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets Terminal Server License Servers group membership (SID S-1-5-32-561).
    /// </summary>
    Task<TSLicenseServersInfo?> GetTSLicenseServersAsync(Guid collectionId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets KMS (Key Management Service) servers for a domain from AD_KMSService table.
    /// </summary>
    Task<KmsServicesInfo?> GetKmsServicesAsync(Guid collectionId, string domainName, CancellationToken cancellationToken);

    /// <summary>
    /// Gets AD FS and Device Registration Service configuration for a forest from AD_ADFSConfiguration table.
    /// </summary>
    Task<AdfsConfigurationInfo?> GetAdfsConfigurationAsync(Guid collectionId, string forestName, CancellationToken cancellationToken);

    /// <summary>
    /// Gets PKI infrastructure summary for a forest from AD_EnterpriseCA, AD_CertificateTemplate,
    /// AD_TrustedRootCA, and AD_NTAuthCA tables.
    /// </summary>
    Task<PkiSummaryInfo?> GetPkiSummaryAsync(Guid collectionId, string forestName, CancellationToken cancellationToken);

    /// <summary>
    /// Gets certificate templates for PKI modal display.
    /// </summary>
    Task<List<CertificateTemplateDetail>> GetCertificateTemplatesAsync(
        Guid collectionId, string forestName, CancellationToken cancellationToken);

    /// <summary>
    /// Gets trusted root CAs for PKI modal display.
    /// </summary>
    Task<List<TrustedRootCaDetail>> GetTrustedRootCAsAsync(
        Guid collectionId, string forestName, CancellationToken cancellationToken);

    /// <summary>
    /// Gets NTAuth certificates for PKI modal display.
    /// </summary>
    Task<List<NTAuthCertificateDetail>> GetNTAuthCertificatesAsync(
        Guid collectionId, string forestName, CancellationToken cancellationToken);

    /// <summary>
    /// Gets Enterprise CA details for PKI modal display.
    /// </summary>
    Task<EnterpriseCaDetail?> GetEnterpriseCaDetailAsync(
        Guid collectionId, string forestName, string caName, CancellationToken cancellationToken);
}
