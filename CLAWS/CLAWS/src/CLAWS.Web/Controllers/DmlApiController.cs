using Microsoft.AspNetCore.Mvc;
using CLAWS.Core.Configuration;
using CLAWS.Core.Models;
using CLAWS.Web.Filters;
using CLAWS.Web.Models;
using CLAWS.Web.Services;

namespace CLAWS.Web.Controllers;

/// <summary>
/// REST API controller for Domain Master List (DML) operations.
/// Uses API key authentication for machine-to-machine communication.
///
/// Authorization Model:
/// - All endpoints require a valid API key (enforced by ApiKeyAuthFilter)
/// - API keys are scoped to the application, not to specific roles
/// - Interactive users should use the DomainMasterListController (web UI) which enforces role-based access
///
/// Future enhancements (see authorization-review-2026-01-06.md Phase 5):
/// - Add scope field to API keys for granular permissions
/// - Limit API operations based on key creator's roles
/// </summary>
[Route("api/v1/dml")]
[ApiController]
[ServiceFilter(typeof(ApiKeyAuthFilter))]
public class DmlApiController : ControllerBase
{
    private readonly ILogger<DmlApiController> _logger;
    private readonly IDomainMasterListService _dmlService;
    private readonly AppSettings _appSettings;

    public DmlApiController(
        ILogger<DmlApiController> logger,
        IDomainMasterListService dmlService,
        AppSettings appSettings)
    {
        _logger = logger;
        _dmlService = dmlService;
        _appSettings = appSettings;
    }

    /// <summary>
    /// Get all domains, optionally filtered by domain name.
    /// </summary>
    /// <param name="includeDecommissioned">Whether to include decommissioned domains.</param>
    /// <param name="domain">Optional domain name filter (case-insensitive).</param>
    /// <param name="exactMatch">If true, requires exact match; if false (default), partial match.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<DmlListResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> GetDomains(
        [FromQuery] bool includeDecommissioned = false,
        [FromQuery] string? domain = null,
        [FromQuery] bool exactMatch = false,
        CancellationToken cancellationToken = default)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            return StatusCode(503, ApiResponse.Fail("DATABASE_NOT_CONFIGURED", "Database is not configured."));
        }

        var domains = await _dmlService.GetAllDomainsAsync(includeDecommissioned, cancellationToken);
        var counts = await _dmlService.GetDomainCountsAsync(cancellationToken);

        // Apply domain filter if specified
        if (!string.IsNullOrWhiteSpace(domain))
        {
            domains = exactMatch
                ? domains.Where(d => d.DomainName.Equals(domain, StringComparison.OrdinalIgnoreCase)).ToList()
                : domains.Where(d => d.DomainName.Contains(domain, StringComparison.OrdinalIgnoreCase)).ToList();
        }

        return Ok(ApiResponse<DmlListResponse>.Ok(new DmlListResponse
        {
            Domains = domains,
            TotalCount = counts.Total,
            ActiveCount = counts.Active,
            DecommissionedCount = counts.Decommissioned
        }));
    }

    /// <summary>
    /// Get a domain by ID.
    /// </summary>
    /// <param name="id">Domain ID.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    [HttpGet("{id:int}")]
    [ProducesResponseType(typeof(ApiResponse<DomainMasterListItem>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> GetDomain(int id, CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            return StatusCode(503, ApiResponse.Fail("DATABASE_NOT_CONFIGURED", "Database is not configured."));
        }

        var domain = await _dmlService.GetDomainByIdAsync(id, cancellationToken);

        if (domain == null)
        {
            return NotFound(ApiResponse.Fail("NOT_FOUND", "Domain not found."));
        }

        return Ok(ApiResponse<DomainMasterListItem>.Ok(domain));
    }

    /// <summary>
    /// Create a new domain.
    /// </summary>
    /// <param name="request">Domain creation request.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    [HttpPost]
    [ProducesResponseType(typeof(ApiResponse<DmlCreateResponse>), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> CreateDomain(
        [FromBody] DomainCreateRequest request,
        CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            return StatusCode(503, ApiResponse.Fail("DATABASE_NOT_CONFIGURED", "Database is not configured."));
        }

        if (string.IsNullOrWhiteSpace(request.DomainName))
        {
            return BadRequest(ApiResponse.Fail("VALIDATION_ERROR", "Domain name is required."));
        }

        var (success, message, domainId) = await _dmlService.CreateDomainAsync(request, cancellationToken);

        if (!success)
        {
            return BadRequest(ApiResponse.Fail("CREATE_FAILED", message));
        }

        var userName = HttpContext.Items["ApiKeyUser"]?.ToString() ?? "API";
        _logger.LogInformation("Domain {DomainId} created via API by {User}", domainId, userName);

        return StatusCode(201, ApiResponse<DmlCreateResponse>.Ok(new DmlCreateResponse
        {
            DomainId = domainId!.Value,
            Message = message
        }));
    }

    /// <summary>
    /// Update a domain.
    /// </summary>
    /// <param name="id">Domain ID.</param>
    /// <param name="request">Domain update request.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    [HttpPut("{id:int}")]
    [ProducesResponseType(typeof(ApiResponse<DmlUpdateResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> UpdateDomain(
        int id,
        [FromBody] DomainCreateRequest request,
        CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            return StatusCode(503, ApiResponse.Fail("DATABASE_NOT_CONFIGURED", "Database is not configured."));
        }

        if (string.IsNullOrWhiteSpace(request.DomainName))
        {
            return BadRequest(ApiResponse.Fail("VALIDATION_ERROR", "Domain name is required."));
        }

        var updateRequest = new DomainUpdateRequest
        {
            DomainID = id,
            DomainName = request.DomainName,
            NetBIOSName = request.NetBIOSName,
            BusinessUnit = request.BusinessUnit,
            DSResponsibilityLevelID = request.DSResponsibilityLevelID,
            IsThirdPartyManaged = request.IsThirdPartyManaged,
            IsDecommissioned = request.IsDecommissioned,
            Trust_ADMgmt_TriStateID = request.Trust_ADMgmt_TriStateID,
            Trust_SSCViolet_TriStateID = request.Trust_SSCViolet_TriStateID,
            Trust_SSNC_Corp_TriStateID = request.Trust_SSNC_Corp_TriStateID,
            IsPatchHold = request.IsPatchHold,
            HasHealthCheck = request.HasHealthCheck,
            HasNetwrixAuditor = request.HasNetwrixAuditor,
            IsSafeguardReady = request.IsSafeguardReady,
            IsCloudIntegrated = request.IsCloudIntegrated,
            BaselineStatusID = request.BaselineStatusID,
            IsClientFacing = request.IsClientFacing,
            POC = request.POC,
            Purpose = request.Purpose,
            Roadmap = request.Roadmap,
            ManagementServer = request.ManagementServer
        };

        var (success, message) = await _dmlService.UpdateDomainAsync(updateRequest, cancellationToken);

        if (!success)
        {
            if (message.Contains("not found", StringComparison.OrdinalIgnoreCase))
            {
                return NotFound(ApiResponse.Fail("NOT_FOUND", message));
            }
            return BadRequest(ApiResponse.Fail("UPDATE_FAILED", message));
        }

        var userName = HttpContext.Items["ApiKeyUser"]?.ToString() ?? "API";
        _logger.LogInformation("Domain {DomainId} updated via API by {User}", id, userName);

        return Ok(ApiResponse<DmlUpdateResponse>.Ok(new DmlUpdateResponse
        {
            Message = message
        }));
    }

    /// <summary>
    /// Delete a domain.
    /// </summary>
    /// <param name="id">Domain ID.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    [HttpDelete("{id:int}")]
    [ProducesResponseType(typeof(ApiResponse<DmlDeleteResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> DeleteDomain(int id, CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            return StatusCode(503, ApiResponse.Fail("DATABASE_NOT_CONFIGURED", "Database is not configured."));
        }

        var (success, message) = await _dmlService.DeleteDomainAsync(id, cancellationToken);

        if (!success)
        {
            if (message.Contains("not found", StringComparison.OrdinalIgnoreCase))
            {
                return NotFound(ApiResponse.Fail("NOT_FOUND", message));
            }
            return BadRequest(ApiResponse.Fail("DELETE_FAILED", message));
        }

        var userName = HttpContext.Items["ApiKeyUser"]?.ToString() ?? "API";
        _logger.LogInformation("Domain {DomainId} deleted via API by {User}", id, userName);

        return Ok(ApiResponse<DmlDeleteResponse>.Ok(new DmlDeleteResponse
        {
            Message = message
        }));
    }

    /// <summary>
    /// Get notes for a domain.
    /// </summary>
    /// <param name="id">Domain ID.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    [HttpGet("{id:int}/notes")]
    [ProducesResponseType(typeof(ApiResponse<DmlNotesResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> GetNotes(int id, CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            return StatusCode(503, ApiResponse.Fail("DATABASE_NOT_CONFIGURED", "Database is not configured."));
        }

        var notes = await _dmlService.GetNotesAsync(id, cancellationToken);

        return Ok(ApiResponse<DmlNotesResponse>.Ok(new DmlNotesResponse
        {
            DomainId = id,
            Notes = notes
        }));
    }

    /// <summary>
    /// Add a note to a domain.
    /// </summary>
    /// <param name="id">Domain ID.</param>
    /// <param name="request">Add note request.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    [HttpPost("{id:int}/notes")]
    [ProducesResponseType(typeof(ApiResponse<DmlAddNoteResponse>), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> AddNote(
        int id,
        [FromBody] AddNoteRequest request,
        CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            return StatusCode(503, ApiResponse.Fail("DATABASE_NOT_CONFIGURED", "Database is not configured."));
        }

        if (string.IsNullOrWhiteSpace(request.NoteText))
        {
            return BadRequest(ApiResponse.Fail("VALIDATION_ERROR", "Note text is required."));
        }

        var userName = HttpContext.Items["ApiKeyUser"]?.ToString() ?? "API";
        var (success, message, noteId) = await _dmlService.AddNoteAsync(id, request.NoteSubject, request.NoteText, userName, cancellationToken);

        if (!success)
        {
            if (message.Contains("not found", StringComparison.OrdinalIgnoreCase))
            {
                return NotFound(ApiResponse.Fail("NOT_FOUND", message));
            }
            return BadRequest(ApiResponse.Fail("ADD_NOTE_FAILED", message));
        }

        _logger.LogInformation("Note {NoteId} added to domain {DomainId} via API by {User}", noteId, id, userName);

        return StatusCode(201, ApiResponse<DmlAddNoteResponse>.Ok(new DmlAddNoteResponse
        {
            NoteId = noteId!.Value,
            Message = message
        }));
    }

    /// <summary>
    /// Get lookup values for dropdowns.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    [HttpGet("lookups")]
    [ProducesResponseType(typeof(ApiResponse<DmlLookupsResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> GetLookups(CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            return StatusCode(503, ApiResponse.Fail("DATABASE_NOT_CONFIGURED", "Database is not configured."));
        }

        var responsibilityLevels = await _dmlService.GetResponsibilityLevelsAsync(cancellationToken);
        var triStates = await _dmlService.GetTriStatesAsync(cancellationToken);
        var baselineStatuses = await _dmlService.GetBaselineStatusesAsync(cancellationToken);

        return Ok(ApiResponse<DmlLookupsResponse>.Ok(new DmlLookupsResponse
        {
            ResponsibilityLevels = responsibilityLevels,
            TriStates = triStates,
            BaselineStatuses = baselineStatuses
        }));
    }
}

#region API Response Models

/// <summary>
/// Response for listing domains.
/// </summary>
public class DmlListResponse
{
    public List<DomainMasterListItem> Domains { get; set; } = new();
    public int TotalCount { get; set; }
    public int ActiveCount { get; set; }
    public int DecommissionedCount { get; set; }
}

/// <summary>
/// Response for creating a domain.
/// </summary>
public class DmlCreateResponse
{
    public int DomainId { get; set; }
    public string Message { get; set; } = string.Empty;
}

/// <summary>
/// Response for updating a domain.
/// </summary>
public class DmlUpdateResponse
{
    public string Message { get; set; } = string.Empty;
}

/// <summary>
/// Response for deleting a domain.
/// </summary>
public class DmlDeleteResponse
{
    public string Message { get; set; } = string.Empty;
}

/// <summary>
/// Response for listing notes.
/// </summary>
public class DmlNotesResponse
{
    public int DomainId { get; set; }
    public List<DomainNoteItem> Notes { get; set; } = new();
}

/// <summary>
/// Response for adding a note.
/// </summary>
public class DmlAddNoteResponse
{
    public int NoteId { get; set; }
    public string Message { get; set; } = string.Empty;
}

/// <summary>
/// Response for lookup values.
/// </summary>
public class DmlLookupsResponse
{
    public List<DmlLookupItem> ResponsibilityLevels { get; set; } = new();
    public List<DmlLookupItem> TriStates { get; set; } = new();
    public List<DmlLookupItem> BaselineStatuses { get; set; } = new();
}

#endregion
