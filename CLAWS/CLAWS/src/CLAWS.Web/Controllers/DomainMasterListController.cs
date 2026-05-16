using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using CLAWS.Core.Configuration;
using CLAWS.Web.Models;
using CLAWS.Web.Services;

namespace CLAWS.Web.Controllers;

/// <summary>
/// Controller for Domain Master List (DML) management.
/// All authenticated users can view; AD Admin or Site Admin can edit.
/// </summary>
[Authorize]
public class DomainMasterListController : Controller
{
    private readonly ILogger<DomainMasterListController> _logger;
    private readonly IDomainMasterListService _dmlService;
    private readonly AppSettings _appSettings;

    public DomainMasterListController(
        ILogger<DomainMasterListController> logger,
        IDomainMasterListService dmlService,
        AppSettings appSettings)
    {
        _logger = logger;
        _dmlService = dmlService;
        _appSettings = appSettings;
    }

    /// <summary>
    /// Display the domain list.
    /// </summary>
    public async Task<IActionResult> Index(bool includeDecommissioned = false, CancellationToken cancellationToken = default)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            return View(new DomainMasterListViewModel
            {
                ErrorMessage = "Database is not configured."
            });
        }

        var domains = await _dmlService.GetAllDomainsAsync(includeDecommissioned, cancellationToken);
        var counts = await _dmlService.GetDomainCountsAsync(cancellationToken);

        var model = new DomainMasterListViewModel
        {
            Domains = domains,
            TotalCount = counts.Total,
            ActiveCount = counts.Active,
            DecommissionedCount = counts.Decommissioned,
            IncludeDecommissioned = includeDecommissioned
        };

        if (TempData["Success"] != null)
            model.SuccessMessage = TempData["Success"]?.ToString();
        if (TempData["Error"] != null)
            model.ErrorMessage = TempData["Error"]?.ToString();

        return View(model);
    }

    /// <summary>
    /// Display the create form.
    /// Requires AD Admin or Site Admin.
    /// </summary>
    [Authorize(Policy = "AdAdminOrSiteAdmin")]
    public async Task<IActionResult> Create(CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            TempData["Error"] = "Database is not configured.";
            return RedirectToAction(nameof(Index));
        }

        var model = await BuildEditViewModelAsync(new DomainMasterListItem(), cancellationToken);
        return View("Edit", model);
    }

    /// <summary>
    /// Display the edit form.
    /// </summary>
    public async Task<IActionResult> Edit(int id, CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            TempData["Error"] = "Database is not configured.";
            return RedirectToAction(nameof(Index));
        }

        var domain = await _dmlService.GetDomainByIdAsync(id, cancellationToken);
        if (domain == null)
        {
            TempData["Error"] = "Domain not found.";
            return RedirectToAction(nameof(Index));
        }

        var model = await BuildEditViewModelAsync(domain, cancellationToken);
        return View(model);
    }

    /// <summary>
    /// Save a domain (create or update).
    /// Requires AD Admin or Site Admin.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(Policy = "AdAdminOrSiteAdmin")]
    public async Task<IActionResult> Save([Bind(Prefix = "Domain")] DomainMasterListItem domain, CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            TempData["Error"] = "Database is not configured.";
            return RedirectToAction(nameof(Index));
        }

        if (string.IsNullOrWhiteSpace(domain.DomainName))
        {
            var model = await BuildEditViewModelAsync(domain, cancellationToken);
            model.ErrorMessage = "Domain name is required.";
            return View("Edit", model);
        }

        if (domain.DomainID == 0)
        {
            // Create
            var request = MapToCreateRequest(domain);
            var (success, message, domainId) = await _dmlService.CreateDomainAsync(request, cancellationToken);

            if (success)
            {
                TempData["Success"] = message;
                return RedirectToAction(nameof(Edit), new { id = domainId });
            }
            else
            {
                var model = await BuildEditViewModelAsync(domain, cancellationToken);
                model.ErrorMessage = message;
                return View("Edit", model);
            }
        }
        else
        {
            // Update
            var request = MapToUpdateRequest(domain);
            var (success, message) = await _dmlService.UpdateDomainAsync(request, cancellationToken);

            if (success)
            {
                TempData["Success"] = message;
                return RedirectToAction(nameof(Edit), new { id = domain.DomainID });
            }
            else
            {
                var model = await BuildEditViewModelAsync(domain, cancellationToken);
                model.ErrorMessage = message;
                return View("Edit", model);
            }
        }
    }

    /// <summary>
    /// Delete a domain.
    /// Requires AD Admin or Site Admin.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(Policy = "AdAdminOrSiteAdmin")]
    public async Task<IActionResult> Delete(int id, CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            TempData["Error"] = "Database is not configured.";
            return RedirectToAction(nameof(Index));
        }

        var (success, message) = await _dmlService.DeleteDomainAsync(id, cancellationToken);

        if (success)
            TempData["Success"] = message;
        else
            TempData["Error"] = message;

        return RedirectToAction(nameof(Index));
    }

    /// <summary>
    /// Display the notes page for a domain.
    /// </summary>
    public async Task<IActionResult> Notes(int id, int? selected, CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            TempData["Error"] = "Database is not configured.";
            return RedirectToAction(nameof(Index));
        }

        var domainName = await _dmlService.GetDomainNameAsync(id, cancellationToken);
        if (domainName == null)
        {
            TempData["Error"] = "Domain not found.";
            return RedirectToAction(nameof(Index));
        }

        var notes = await _dmlService.GetNotesAsync(id, cancellationToken);

        var model = new DomainNotesViewModel
        {
            DomainID = id,
            DomainName = domainName,
            Notes = notes,
            SelectedNoteId = selected
        };

        if (TempData["Success"] != null)
            model.SuccessMessage = TempData["Success"]?.ToString();
        if (TempData["Error"] != null)
            model.ErrorMessage = TempData["Error"]?.ToString();

        return View(model);
    }

    /// <summary>
    /// Add a note to a domain.
    /// Requires AD Admin or Site Admin.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(Policy = "AdAdminOrSiteAdmin")]
    public async Task<IActionResult> AddNote(int id, string? noteSubject, string noteText, CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            TempData["Error"] = "Database is not configured.";
            return RedirectToAction(nameof(Index));
        }

        var createdBy = User.Identity?.Name ?? "Unknown";
        var (success, message, noteId) = await _dmlService.AddNoteAsync(id, noteSubject, noteText, createdBy, cancellationToken);

        if (success)
            TempData["Success"] = message;
        else
            TempData["Error"] = message;

        return RedirectToAction(nameof(Notes), new { id, selected = noteId });
    }

    /// <summary>
    /// Get site links for a domain (AJAX endpoint for lazy loading).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetSiteLinks(int domainId, int skip = 0, int take = 50, CancellationToken cancellationToken = default)
    {
        if (!_appSettings.SqlServer.IsConfigured)
            return Json(new { success = false, message = "Database is not configured." });

        // Get domain and its collection ID
        var domain = await _dmlService.GetDomainByIdAsync(domainId, cancellationToken);
        if (domain == null)
            return Json(new { success = false, message = "Domain not found." });

        var adInventory = await _dmlService.GetAdInventoryInfoAsync(domain.DomainName, cancellationToken);
        if (adInventory?.CollectionId == null)
            return Json(new { success = false, message = "No inventory data available." });

        var (siteLinks, totalCount) = await _dmlService.GetSiteLinksAsync(adInventory.CollectionId.Value, skip, take, cancellationToken);

        return Json(new
        {
            success = true,
            siteLinks,
            totalCount,
            hasMore = skip + take < totalCount
        });
    }

    /// <summary>
    /// Get subnets for a domain (AJAX endpoint for lazy loading).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetSubnets(int domainId, string? site = null, int skip = 0, int take = 100, CancellationToken cancellationToken = default)
    {
        if (!_appSettings.SqlServer.IsConfigured)
            return Json(new { success = false, message = "Database is not configured." });

        // Get domain and its collection ID
        var domain = await _dmlService.GetDomainByIdAsync(domainId, cancellationToken);
        if (domain == null)
            return Json(new { success = false, message = "Domain not found." });

        var adInventory = await _dmlService.GetAdInventoryInfoAsync(domain.DomainName, cancellationToken);
        if (adInventory?.CollectionId == null)
            return Json(new { success = false, message = "No inventory data available." });

        var (subnets, totalCount) = await _dmlService.GetSubnetsAsync(adInventory.CollectionId.Value, site, skip, take, cancellationToken);

        return Json(new
        {
            success = true,
            subnets,
            totalCount,
            hasMore = skip + take < totalCount
        });
    }

    /// <summary>
    /// Get trust relationships for a domain (AJAX endpoint for modal).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetTrusts(int domainId, CancellationToken cancellationToken = default)
    {
        if (!_appSettings.SqlServer.IsConfigured)
            return Json(new { success = false, message = "Database is not configured." });

        // Get domain and its collection ID
        var domain = await _dmlService.GetDomainByIdAsync(domainId, cancellationToken);
        if (domain == null)
            return Json(new { success = false, message = "Domain not found." });

        var adInventory = await _dmlService.GetAdInventoryInfoAsync(domain.DomainName, cancellationToken);
        if (adInventory?.CollectionId == null)
            return Json(new { success = false, message = "No inventory data available." });

        var (trusts, totalCount) = await _dmlService.GetTrustsAsync(adInventory.CollectionId.Value, domain.DomainName, cancellationToken);

        return Json(new
        {
            success = true,
            trusts,
            totalCount
        });
    }

    /// <summary>
    /// Get certificate templates for PKI modal (AJAX endpoint).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetCertificateTemplates(int domainId, CancellationToken cancellationToken = default)
    {
        if (!_appSettings.SqlServer.IsConfigured)
            return Json(new { success = false, message = "Database is not configured." });

        var domain = await _dmlService.GetDomainByIdAsync(domainId, cancellationToken);
        if (domain == null)
            return Json(new { success = false, message = "Domain not found." });

        var adInventory = await _dmlService.GetAdInventoryInfoAsync(domain.DomainName, cancellationToken);
        if (adInventory?.CollectionId == null)
            return Json(new { success = false, message = "No inventory data available." });

        var forestName = adInventory.Forest?.ForestName;
        if (string.IsNullOrEmpty(forestName))
            return Json(new { success = false, message = "Forest information not available." });

        var templates = await _dmlService.GetCertificateTemplatesAsync(
            adInventory.CollectionId.Value, forestName, cancellationToken);

        return Json(new
        {
            success = true,
            templates,
            totalCount = templates.Count
        });
    }

    /// <summary>
    /// Get trusted root CAs for PKI modal (AJAX endpoint).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetTrustedRootCAs(int domainId, CancellationToken cancellationToken = default)
    {
        if (!_appSettings.SqlServer.IsConfigured)
            return Json(new { success = false, message = "Database is not configured." });

        var domain = await _dmlService.GetDomainByIdAsync(domainId, cancellationToken);
        if (domain == null)
            return Json(new { success = false, message = "Domain not found." });

        var adInventory = await _dmlService.GetAdInventoryInfoAsync(domain.DomainName, cancellationToken);
        if (adInventory?.CollectionId == null)
            return Json(new { success = false, message = "No inventory data available." });

        var forestName = adInventory.Forest?.ForestName;
        if (string.IsNullOrEmpty(forestName))
            return Json(new { success = false, message = "Forest information not available." });

        var trustedRoots = await _dmlService.GetTrustedRootCAsAsync(
            adInventory.CollectionId.Value, forestName, cancellationToken);

        return Json(new
        {
            success = true,
            trustedRoots,
            totalCount = trustedRoots.Count
        });
    }

    /// <summary>
    /// Get NTAuth certificates for PKI modal (AJAX endpoint).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetNTAuthCertificates(int domainId, CancellationToken cancellationToken = default)
    {
        if (!_appSettings.SqlServer.IsConfigured)
            return Json(new { success = false, message = "Database is not configured." });

        var domain = await _dmlService.GetDomainByIdAsync(domainId, cancellationToken);
        if (domain == null)
            return Json(new { success = false, message = "Domain not found." });

        var adInventory = await _dmlService.GetAdInventoryInfoAsync(domain.DomainName, cancellationToken);
        if (adInventory?.CollectionId == null)
            return Json(new { success = false, message = "No inventory data available." });

        var forestName = adInventory.Forest?.ForestName;
        if (string.IsNullOrEmpty(forestName))
            return Json(new { success = false, message = "Forest information not available." });

        var ntAuthCerts = await _dmlService.GetNTAuthCertificatesAsync(
            adInventory.CollectionId.Value, forestName, cancellationToken);

        // Count expiring certificates for warning banner
        var expiringCount = ntAuthCerts.Count(c => c.ExpirationStatus == "expiring" || c.ExpirationStatus == "expired");

        return Json(new
        {
            success = true,
            ntAuthCerts,
            totalCount = ntAuthCerts.Count,
            expiringCount
        });
    }

    /// <summary>
    /// Get Enterprise CA details for PKI modal (AJAX endpoint).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetEnterpriseCaDetail(int domainId, string caName, CancellationToken cancellationToken = default)
    {
        if (!_appSettings.SqlServer.IsConfigured)
            return Json(new { success = false, message = "Database is not configured." });

        if (string.IsNullOrEmpty(caName))
            return Json(new { success = false, message = "CA name is required." });

        var domain = await _dmlService.GetDomainByIdAsync(domainId, cancellationToken);
        if (domain == null)
            return Json(new { success = false, message = "Domain not found." });

        var adInventory = await _dmlService.GetAdInventoryInfoAsync(domain.DomainName, cancellationToken);
        if (adInventory?.CollectionId == null)
            return Json(new { success = false, message = "No inventory data available." });

        var forestName = adInventory.Forest?.ForestName;
        if (string.IsNullOrEmpty(forestName))
            return Json(new { success = false, message = "Forest information not available." });

        var caDetail = await _dmlService.GetEnterpriseCaDetailAsync(
            adInventory.CollectionId.Value, forestName, caName, cancellationToken);

        if (caDetail == null)
            return Json(new { success = false, message = "Enterprise CA not found." });

        return Json(new
        {
            success = true,
            caDetail
        });
    }

    [HttpGet]
    public async Task<IActionResult> Logs(int id, CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            TempData["Error"] = "Database is not configured.";
            return RedirectToAction("Index");
        }

        var domain = await _dmlService.GetDomainByIdAsync(id, cancellationToken);
        if (domain == null)
        {
            TempData["Error"] = "Domain not found.";
            return RedirectToAction("Index");
        }

        if (!domain.HasCollection)
        {
            TempData["Error"] = "No collection data available for this domain.";
            return RedirectToAction("Edit", new { id });
        }

        var logs = await _dmlService.GetCollectionLogsAsync(domain.CollectionId!.Value, cancellationToken);

        // Get collection datetime from AdInventoryInfo
        var adInventory = await _dmlService.GetAdInventoryInfoAsync(domain.DomainName, cancellationToken);

        var viewModel = new DomainLogsViewModel
        {
            DomainID = domain.DomainID,
            DomainName = domain.DomainName,
            CollectionId = domain.CollectionId!.Value,
            CollectionDateTime = adInventory?.CollectionDateTime,
            Logs = logs
        };

        return View(viewModel);
    }

    private async Task<DomainEditViewModel> BuildEditViewModelAsync(DomainMasterListItem domain, CancellationToken cancellationToken)
    {
        var responsibilityLevels = await _dmlService.GetResponsibilityLevelsAsync(cancellationToken);
        var triStates = await _dmlService.GetTriStatesAsync(cancellationToken);
        var baselineStatuses = await _dmlService.GetBaselineStatusesAsync(cancellationToken);

        // Fetch AD inventory info for existing domains
        AdInventoryInfo? adInventory = null;
        SitesAndServicesInfo? sitesAndServices = null;
        DomainHealthInfo? domainHealth = null;
        TSLicenseServersInfo? tsLicenseServers = null;
        KmsServicesInfo? kmsServices = null;
        AdfsConfigurationInfo? adfsConfiguration = null;
        PkiSummaryInfo? pkiSummary = null;

        if (domain.DomainID != 0 && !string.IsNullOrEmpty(domain.DomainName))
        {
            adInventory = await _dmlService.GetAdInventoryInfoAsync(domain.DomainName, cancellationToken);

            // Fetch Sites & Services, Domain Health, TS License Servers, and infrastructure data if we have a collection
            if (adInventory?.CollectionId.HasValue == true)
            {
                var collectionId = adInventory.CollectionId.Value;
                sitesAndServices = await _dmlService.GetSitesAndServicesSummaryAsync(collectionId, cancellationToken);
                domainHealth = await _dmlService.GetDomainHealthAsync(collectionId, domain.DomainName, cancellationToken);
                tsLicenseServers = await _dmlService.GetTSLicenseServersAsync(collectionId, cancellationToken);

                // KMS is domain-scoped
                kmsServices = await _dmlService.GetKmsServicesAsync(collectionId, domain.DomainName, cancellationToken);

                // ADFS and PKI are forest-scoped
                var forestName = adInventory.Forest?.ForestName;
                if (!string.IsNullOrEmpty(forestName))
                {
                    adfsConfiguration = await _dmlService.GetAdfsConfigurationAsync(collectionId, forestName, cancellationToken);
                    pkiSummary = await _dmlService.GetPkiSummaryAsync(collectionId, forestName, cancellationToken);
                }
            }
        }

        return new DomainEditViewModel
        {
            Domain = domain,
            ResponsibilityLevels = responsibilityLevels,
            TriStates = triStates,
            BaselineStatuses = baselineStatuses,
            AdInventory = adInventory,
            SitesAndServices = sitesAndServices,
            DomainHealth = domainHealth,
            TSLicenseServers = tsLicenseServers,
            KmsServices = kmsServices,
            AdfsConfiguration = adfsConfiguration,
            PkiSummary = pkiSummary
        };
    }

    private static DomainCreateRequest MapToCreateRequest(DomainMasterListItem domain)
    {
        return new DomainCreateRequest
        {
            DomainName = domain.DomainName,
            NetBIOSName = domain.NetBIOSName,
            BusinessUnit = domain.BusinessUnit,
            DSResponsibilityLevelID = domain.DSResponsibilityLevelID,
            IsThirdPartyManaged = domain.IsThirdPartyManaged,
            IsDecommissioned = domain.IsDecommissioned,
            Trust_ADMgmt_TriStateID = domain.Trust_ADMgmt_TriStateID,
            Trust_SSCViolet_TriStateID = domain.Trust_SSCViolet_TriStateID,
            Trust_SSNC_Corp_TriStateID = domain.Trust_SSNC_Corp_TriStateID,
            IsPatchHold = domain.IsPatchHold,
            HasHealthCheck = domain.HasHealthCheck,
            HasNetwrixAuditor = domain.HasNetwrixAuditor,
            IsSafeguardReady = domain.IsSafeguardReady,
            IsCloudIntegrated = domain.IsCloudIntegrated,
            BaselineStatusID = domain.BaselineStatusID,
            IsClientFacing = domain.IsClientFacing,
            IsSPLA = domain.IsSPLA,
            IsRegulated = domain.IsRegulated,
            MSPCustomer = domain.MSPCustomer,
            POC = domain.POC,
            Purpose = domain.Purpose,
            Roadmap = domain.Roadmap,
            ManagementServer = domain.ManagementServer
        };
    }

    private static DomainUpdateRequest MapToUpdateRequest(DomainMasterListItem domain)
    {
        return new DomainUpdateRequest
        {
            DomainID = domain.DomainID,
            DomainName = domain.DomainName,
            NetBIOSName = domain.NetBIOSName,
            BusinessUnit = domain.BusinessUnit,
            DSResponsibilityLevelID = domain.DSResponsibilityLevelID,
            IsThirdPartyManaged = domain.IsThirdPartyManaged,
            IsDecommissioned = domain.IsDecommissioned,
            Trust_ADMgmt_TriStateID = domain.Trust_ADMgmt_TriStateID,
            Trust_SSCViolet_TriStateID = domain.Trust_SSCViolet_TriStateID,
            Trust_SSNC_Corp_TriStateID = domain.Trust_SSNC_Corp_TriStateID,
            IsPatchHold = domain.IsPatchHold,
            HasHealthCheck = domain.HasHealthCheck,
            HasNetwrixAuditor = domain.HasNetwrixAuditor,
            IsSafeguardReady = domain.IsSafeguardReady,
            IsCloudIntegrated = domain.IsCloudIntegrated,
            BaselineStatusID = domain.BaselineStatusID,
            IsClientFacing = domain.IsClientFacing,
            IsSPLA = domain.IsSPLA,
            IsRegulated = domain.IsRegulated,
            MSPCustomer = domain.MSPCustomer,
            POC = domain.POC,
            Purpose = domain.Purpose,
            Roadmap = domain.Roadmap,
            ManagementServer = domain.ManagementServer
        };
    }
}
