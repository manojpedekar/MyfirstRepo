using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using CLAWS.Core.Configuration;
using CLAWS.Data.Repositories;
using CLAWS.Web.Models;
using CLAWS.Web.Services;

namespace CLAWS.Web.Controllers;

/// <summary>
/// API controller for collection logs (EventLog data from NTFS permission scans).
/// </summary>
[Route("api/collection-logs")]
[ApiController]
[Authorize]
public class CollectionLogsController : ControllerBase
{
    private readonly ILogger<CollectionLogsController> _logger;
    private readonly ICollectionLogService _logService;
    private readonly IUploadRepository _uploadRepository;
    private readonly IApiKeyRepository _apiKeyRepository;
    private readonly AppSettings _appSettings;

    public CollectionLogsController(
        ILogger<CollectionLogsController> logger,
        ICollectionLogService logService,
        IUploadRepository uploadRepository,
        IApiKeyRepository apiKeyRepository,
        AppSettings appSettings)
    {
        _logger = logger;
        _logService = logService;
        _uploadRepository = uploadRepository;
        _apiKeyRepository = apiKeyRepository;
        _appSettings = appSettings;
    }

    /// <summary>
    /// Gets collection logs for all inventories in an upload.
    /// </summary>
    /// <param name="uploadId">Upload ID</param>
    /// <param name="severity">Filter by severity (ERROR, WARNING, INFO, SUCCESS)</param>
    /// <param name="source">Filter by source component</param>
    /// <param name="search">Search text in message/path</param>
    /// <param name="page">Page number (1-based)</param>
    /// <param name="pageSize">Items per page (max 200)</param>
    /// <param name="sortBy">Column to sort by (Timestamp, Severity, Source, Message)</param>
    /// <param name="descending">Sort in descending order</param>
    /// <param name="cancellationToken">Cancellation token</param>
    [HttpGet("{uploadId:guid}")]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 200)]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 403)]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 404)]
    public async Task<IActionResult> GetLogsForUpload(
        Guid uploadId,
        [FromQuery] string? severity = null,
        [FromQuery] string? source = null,
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] string sortBy = "Timestamp",
        [FromQuery] bool descending = false,
        CancellationToken cancellationToken = default)
    {
        // Check authorization
        var authResult = await CheckAuthorizationAsync(uploadId, cancellationToken);
        if (authResult != null)
            return authResult;

        var filter = new CollectionLogFilter
        {
            Severity = severity,
            Source = source,
            SearchText = search,
            SortBy = sortBy,
            Descending = descending
        };

        var logs = await _logService.GetLogsForUploadAsync(
            uploadId,
            filter,
            page,
            pageSize,
            cancellationToken);

        return Ok(CollectionLogsApiResponse.Ok(logs));
    }

    /// <summary>
    /// Gets collection logs for a specific inventory.
    /// </summary>
    /// <param name="uploadId">Upload ID</param>
    /// <param name="inventoryId">Inventory ID</param>
    /// <param name="severity">Filter by severity (ERROR, WARNING, INFO, SUCCESS)</param>
    /// <param name="source">Filter by source component</param>
    /// <param name="search">Search text in message/path</param>
    /// <param name="page">Page number (1-based)</param>
    /// <param name="pageSize">Items per page (max 200)</param>
    /// <param name="sortBy">Column to sort by (Timestamp, Severity, Source, Message)</param>
    /// <param name="descending">Sort in descending order</param>
    /// <param name="cancellationToken">Cancellation token</param>
    [HttpGet("{uploadId:guid}/{inventoryId:guid}")]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 200)]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 403)]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 404)]
    public async Task<IActionResult> GetLogsForInventory(
        Guid uploadId,
        Guid inventoryId,
        [FromQuery] string? severity = null,
        [FromQuery] string? source = null,
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] string sortBy = "Timestamp",
        [FromQuery] bool descending = false,
        CancellationToken cancellationToken = default)
    {
        // Check authorization
        var authResult = await CheckAuthorizationAsync(uploadId, cancellationToken);
        if (authResult != null)
            return authResult;

        var filter = new CollectionLogFilter
        {
            Severity = severity,
            Source = source,
            SearchText = search,
            SortBy = sortBy,
            Descending = descending
        };

        var logs = await _logService.GetLogsForInventoryAsync(
            uploadId,
            inventoryId,
            filter,
            page,
            pageSize,
            cancellationToken);

        return Ok(CollectionLogsApiResponse.Ok(logs));
    }

    /// <summary>
    /// Gets a summary of log counts by severity.
    /// </summary>
    /// <param name="uploadId">Upload ID</param>
    /// <param name="inventoryId">Optional inventory ID to filter</param>
    /// <param name="cancellationToken">Cancellation token</param>
    [HttpGet("{uploadId:guid}/summary")]
    [ProducesResponseType(typeof(Dictionary<string, int>), 200)]
    [ProducesResponseType(403)]
    [ProducesResponseType(404)]
    public async Task<IActionResult> GetLogSummary(
        Guid uploadId,
        [FromQuery] Guid? inventoryId = null,
        CancellationToken cancellationToken = default)
    {
        // Check authorization
        var authResult = await CheckAuthorizationAsync(uploadId, cancellationToken);
        if (authResult != null)
            return authResult;

        var summary = await _logService.GetLogSummaryAsync(
            uploadId,
            inventoryId,
            cancellationToken);

        return Ok(new { success = true, data = summary });
    }

    /// <summary>
    /// Gets collection logs for all ADInventory domains in an upload.
    /// </summary>
    /// <param name="uploadId">Upload ID</param>
    /// <param name="severity">Filter by severity (ERROR, WARNING, INFO, SUCCESS)</param>
    /// <param name="source">Filter by source component</param>
    /// <param name="search">Search text in message</param>
    /// <param name="page">Page number (1-based)</param>
    /// <param name="pageSize">Items per page (max 200)</param>
    /// <param name="sortBy">Column to sort by (Timestamp, Severity, Message)</param>
    /// <param name="descending">Sort in descending order</param>
    /// <param name="cancellationToken">Cancellation token</param>
    [HttpGet("{uploadId:guid}/ad-domain")]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 200)]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 403)]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 404)]
    public async Task<IActionResult> GetLogsForAllADDomains(
        Guid uploadId,
        [FromQuery] string? severity = null,
        [FromQuery] string? source = null,
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] string sortBy = "Timestamp",
        [FromQuery] bool descending = false,
        CancellationToken cancellationToken = default)
    {
        // Check authorization
        var authResult = await CheckAuthorizationAsync(uploadId, cancellationToken);
        if (authResult != null)
            return authResult;

        var filter = new CollectionLogFilter
        {
            Severity = severity,
            Source = source,
            SearchText = search,
            SortBy = sortBy,
            Descending = descending
        };

        var logs = await _logService.GetLogsForAllADDomainsAsync(
            uploadId,
            filter,
            page,
            pageSize,
            cancellationToken);

        return Ok(CollectionLogsApiResponse.Ok(logs));
    }

    /// <summary>
    /// Gets collection logs for an ADInventory domain (by CollectionID).
    /// </summary>
    /// <param name="uploadId">Upload ID</param>
    /// <param name="collectionId">Collection ID (domain-specific)</param>
    /// <param name="severity">Filter by severity (ERROR, WARNING, INFO, SUCCESS)</param>
    /// <param name="source">Filter by source component</param>
    /// <param name="search">Search text in message/path</param>
    /// <param name="page">Page number (1-based)</param>
    /// <param name="pageSize">Items per page (max 200)</param>
    /// <param name="sortBy">Column to sort by (Timestamp, Severity, Source, Message)</param>
    /// <param name="descending">Sort in descending order</param>
    /// <param name="cancellationToken">Cancellation token</param>
    [HttpGet("{uploadId:guid}/ad-domain/{collectionId:guid}")]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 200)]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 403)]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 404)]
    public async Task<IActionResult> GetLogsForADDomain(
        Guid uploadId,
        Guid collectionId,
        [FromQuery] string? severity = null,
        [FromQuery] string? source = null,
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] string sortBy = "Timestamp",
        [FromQuery] bool descending = false,
        CancellationToken cancellationToken = default)
    {
        // Check authorization
        var authResult = await CheckAuthorizationAsync(uploadId, cancellationToken);
        if (authResult != null)
            return authResult;

        var filter = new CollectionLogFilter
        {
            Severity = severity,
            Source = source,
            SearchText = search,
            SortBy = sortBy,
            Descending = descending
        };

        var logs = await _logService.GetLogsForADDomainAsync(
            uploadId,
            collectionId,
            filter,
            page,
            pageSize,
            cancellationToken);

        return Ok(CollectionLogsApiResponse.Ok(logs));
    }

    /// <summary>
    /// Gets a summary of log counts by severity for an ADInventory domain.
    /// </summary>
    /// <param name="uploadId">Upload ID</param>
    /// <param name="collectionId">Collection ID (domain-specific)</param>
    /// <param name="cancellationToken">Cancellation token</param>
    [HttpGet("{uploadId:guid}/ad-domain/{collectionId:guid}/summary")]
    [ProducesResponseType(typeof(Dictionary<string, int>), 200)]
    [ProducesResponseType(403)]
    [ProducesResponseType(404)]
    public async Task<IActionResult> GetLogSummaryForADDomain(
        Guid uploadId,
        Guid collectionId,
        CancellationToken cancellationToken = default)
    {
        // Check authorization
        var authResult = await CheckAuthorizationAsync(uploadId, cancellationToken);
        if (authResult != null)
            return authResult;

        var summary = await _logService.GetLogSummaryForADDomainAsync(
            uploadId,
            collectionId,
            cancellationToken);

        return Ok(new { success = true, data = summary });
    }

    /// <summary>
    /// Gets collection logs for an NTFS Permissions collection from production schema.
    /// Requires NTFS Perms Admin or Site Admin authorization.
    /// </summary>
    /// <param name="inventoryId">Inventory ID</param>
    /// <param name="severity">Filter by severity (ERROR, WARNING, INFO, SUCCESS)</param>
    /// <param name="source">Filter by source component</param>
    /// <param name="search">Search text in message/path</param>
    /// <param name="page">Page number (1-based)</param>
    /// <param name="pageSize">Items per page (max 200)</param>
    /// <param name="sortBy">Column to sort by (Timestamp, Severity, Source, Message)</param>
    /// <param name="descending">Sort in descending order</param>
    /// <param name="cancellationToken">Cancellation token</param>
    [HttpGet("production/ntfs/{inventoryId:guid}")]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 200)]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 403)]
    public async Task<IActionResult> GetLogsForProductionNtfs(
        Guid inventoryId,
        [FromQuery] string? severity = null,
        [FromQuery] string? source = null,
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] string sortBy = "Timestamp",
        [FromQuery] bool descending = false,
        CancellationToken cancellationToken = default)
    {
        // Check NTFS admin authorization
        if (!CanAccessNtfsProduction())
        {
            return StatusCode(403, CollectionLogsApiResponse.Fail("Access denied. NTFS Perms Admin or Site Admin privileges required."));
        }

        var filter = new CollectionLogFilter
        {
            Severity = severity,
            Source = source,
            SearchText = search,
            SortBy = sortBy,
            Descending = descending
        };

        var logs = await _logService.GetLogsForProductionNtfsAsync(
            inventoryId,
            filter,
            page,
            pageSize,
            cancellationToken);

        return Ok(CollectionLogsApiResponse.Ok(logs));
    }

    /// <summary>
    /// Gets collection logs for an AD Inventory collection from production schema.
    /// Requires AD Admin or Site Admin authorization.
    /// </summary>
    /// <param name="collectionId">Collection ID (AD domain-specific)</param>
    /// <param name="severity">Filter by severity (ERROR, WARNING, INFO, SUCCESS)</param>
    /// <param name="source">Filter by source component</param>
    /// <param name="search">Search text in message</param>
    /// <param name="page">Page number (1-based)</param>
    /// <param name="pageSize">Items per page (max 200)</param>
    /// <param name="sortBy">Column to sort by (Timestamp, Severity, Source, Message)</param>
    /// <param name="descending">Sort in descending order</param>
    /// <param name="cancellationToken">Cancellation token</param>
    [HttpGet("production/ad/{collectionId:guid}")]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 200)]
    [ProducesResponseType(typeof(CollectionLogsApiResponse), 403)]
    public async Task<IActionResult> GetLogsForProductionAd(
        Guid collectionId,
        [FromQuery] string? severity = null,
        [FromQuery] string? source = null,
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] string sortBy = "Timestamp",
        [FromQuery] bool descending = false,
        CancellationToken cancellationToken = default)
    {
        // Check AD admin authorization
        if (!CanAccessAdProduction())
        {
            return StatusCode(403, CollectionLogsApiResponse.Fail("Access denied. AD Admin or Site Admin privileges required."));
        }

        var filter = new CollectionLogFilter
        {
            Severity = severity,
            Source = source,
            SearchText = search,
            SortBy = sortBy,
            Descending = descending
        };

        var logs = await _logService.GetLogsForProductionAdAsync(
            collectionId,
            filter,
            page,
            pageSize,
            cancellationToken);

        return Ok(CollectionLogsApiResponse.Ok(logs));
    }

    /// <summary>
    /// Checks if the current user is a site admin.
    /// </summary>
    private bool IsSiteAdmin()
    {
        return !string.IsNullOrEmpty(_appSettings.Authorization.SiteAdminGroup) &&
               User.IsInRole(_appSettings.Authorization.SiteAdminGroup);
    }

    /// <summary>
    /// Checks if the current user can access NTFS production data (NTFS Perms Admin or Site Admin).
    /// </summary>
    private bool CanAccessNtfsProduction()
    {
        if (IsSiteAdmin()) return true;
        return !string.IsNullOrEmpty(_appSettings.Authorization.NtfsPermsAdminGroup) &&
               User.IsInRole(_appSettings.Authorization.NtfsPermsAdminGroup);
    }

    /// <summary>
    /// Checks if the current user can access AD production data (AD Admin or Site Admin).
    /// </summary>
    private bool CanAccessAdProduction()
    {
        if (IsSiteAdmin()) return true;
        return !string.IsNullOrEmpty(_appSettings.Authorization.AdAdminGroup) &&
               User.IsInRole(_appSettings.Authorization.AdAdminGroup);
    }

    /// <summary>
    /// Checks if the current user owns the upload (either directly or via API key they created).
    /// </summary>
    private async Task<bool> UserOwnsUploadAsync(string uploadedBy, string userName, CancellationToken cancellationToken)
    {
        // Direct ownership
        if (uploadedBy == userName)
            return true;

        // Check if uploaded via API key owned by this user
        if (uploadedBy.StartsWith("API:"))
        {
            var apiKeyDescription = uploadedBy.Substring(4); // Remove "API:" prefix
            var apiKey = await _apiKeyRepository.GetByDescriptionAsync(apiKeyDescription, cancellationToken);
            if (apiKey != null && apiKey.CreatedBy == userName)
                return true;
        }

        return false;
    }

    /// <summary>
    /// Checks if the upload exists.
    /// Returns null if found, or an IActionResult if not found.
    /// All authenticated users can view all collection logs.
    /// </summary>
    private async Task<IActionResult?> CheckAuthorizationAsync(
        Guid uploadId,
        CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);

        if (upload == null)
        {
            return NotFound(CollectionLogsApiResponse.Fail("Upload not found"));
        }

        // All authenticated users can view collection logs
        return null;
    }
}
