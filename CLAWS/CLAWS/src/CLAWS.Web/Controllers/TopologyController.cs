using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using CLAWS.Core.Configuration;
using CLAWS.Web.Models;
using CLAWS.Web.Services;
using System.Diagnostics;

namespace CLAWS.Web.Controllers;

/// <summary>
/// Controller for AD Site Topology visualization.
/// </summary>
[Authorize(Policy = "AdAdminOrSiteAdmin")]
public class TopologyController : Controller
{
    private readonly ILogger<TopologyController> _logger;
    private readonly IDomainMasterListService _dmlService;
    private readonly AppSettings _appSettings;

    public TopologyController(
        ILogger<TopologyController> logger,
        IDomainMasterListService dmlService,
        AppSettings appSettings)
    {
        _logger = logger;
        _dmlService = dmlService;
        _appSettings = appSettings;
    }

    /// <summary>
    /// Display the topology visualization page.
    /// </summary>
    /// <param name="collectionId">The collection ID to visualize.</param>
    /// <param name="domainId">The domain ID for back navigation.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    public async Task<IActionResult> Index(Guid collectionId, int domainId = 0, CancellationToken cancellationToken = default)
    {
        var extendedLogging = _appSettings.Logging.EnableExtendedLogging;

        if (extendedLogging)
        {
            _logger.LogInformation("[Topology] Index requested - CollectionId: {CollectionId}, DomainId: {DomainId}",
                collectionId, domainId);
        }

        if (!_appSettings.SqlServer.IsConfigured)
        {
            _logger.LogWarning("[Topology] Database is not configured");
            return View(new TopologyViewModel
            {
                ErrorMessage = "Database is not configured."
            });
        }

        if (collectionId == Guid.Empty)
        {
            _logger.LogWarning("[Topology] No collection ID provided");
            return View(new TopologyViewModel
            {
                ErrorMessage = "No collection ID provided."
            });
        }

        try
        {
            // Get collection metadata
            if (extendedLogging)
            {
                _logger.LogInformation("[Topology] Fetching collection metadata for {CollectionId}", collectionId);
            }

            var metadata = await _dmlService.GetCollectionMetadataAsync(collectionId, cancellationToken);
            if (metadata == null)
            {
                _logger.LogWarning("[Topology] Collection {CollectionId} not found", collectionId);
                return View(new TopologyViewModel
                {
                    CollectionId = collectionId,
                    DomainId = domainId,
                    ErrorMessage = "Collection not found."
                });
            }

            if (extendedLogging)
            {
                _logger.LogInformation("[Topology] Metadata retrieved - Domain: {Domain}, Forest: {Forest}, DateTime: {DateTime}",
                    metadata.Value.DomainName, metadata.Value.ForestName, metadata.Value.CollectionDateTime);
            }

            // Get site/subnet/link counts
            if (extendedLogging)
            {
                _logger.LogInformation("[Topology] Fetching Sites & Services summary for {CollectionId}", collectionId);
            }

            var sitesInfo = await _dmlService.GetSitesAndServicesSummaryAsync(collectionId, cancellationToken);

            if (extendedLogging)
            {
                _logger.LogInformation("[Topology] Summary - Sites: {Sites}, Subnets: {Subnets}, Links: {Links}, DCs: {DCs}",
                    sitesInfo?.SiteCount ?? 0, sitesInfo?.SubnetCount ?? 0,
                    sitesInfo?.SiteLinkCount ?? 0, sitesInfo?.DomainControllerCount ?? 0);
            }

            var model = new TopologyViewModel
            {
                CollectionId = collectionId,
                DomainId = domainId,
                DomainName = metadata.Value.DomainName ?? "Unknown",
                ForestName = metadata.Value.ForestName,
                CollectionDateTime = metadata.Value.CollectionDateTime,
                Summary = new TopologySummary
                {
                    SiteCount = sitesInfo?.SiteCount ?? 0,
                    SubnetCount = sitesInfo?.SubnetCount ?? 0,
                    SiteLinkCount = sitesInfo?.SiteLinkCount ?? 0,
                    DomainControllerCount = sitesInfo?.DomainControllerCount ?? 0
                }
            };

            return View(model);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Topology] Error loading topology page for collection {CollectionId}", collectionId);
            return View(new TopologyViewModel
            {
                CollectionId = collectionId,
                DomainId = domainId,
                ErrorMessage = $"Error loading topology: {ex.Message}"
            });
        }
    }

    /// <summary>
    /// API endpoint to get topology data for Cytoscape.js.
    /// </summary>
    /// <param name="collectionId">The collection ID.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    [HttpGet]
    public async Task<IActionResult> GetData(Guid collectionId, CancellationToken cancellationToken = default)
    {
        var extendedLogging = _appSettings.Logging.EnableExtendedLogging;
        var sw = Stopwatch.StartNew();

        if (extendedLogging)
        {
            _logger.LogInformation("[Topology] GetData API called - CollectionId: {CollectionId}", collectionId);
        }

        if (!_appSettings.SqlServer.IsConfigured)
        {
            _logger.LogWarning("[Topology] GetData - Database is not configured");
            return BadRequest(new { error = "Database is not configured." });
        }

        if (collectionId == Guid.Empty)
        {
            _logger.LogWarning("[Topology] GetData - No collection ID provided");
            return BadRequest(new { error = "No collection ID provided." });
        }

        try
        {
            if (extendedLogging)
            {
                _logger.LogInformation("[Topology] GetData - Fetching topology data from service");
            }

            var topologyData = await _dmlService.GetTopologyDataAsync(collectionId, cancellationToken);

            sw.Stop();

            if (topologyData == null)
            {
                _logger.LogWarning("[Topology] GetData - Topology data not found for collection {CollectionId} (elapsed: {Elapsed}ms)",
                    collectionId, sw.ElapsedMilliseconds);
                return NotFound(new { error = "Topology data not found." });
            }

            if (extendedLogging)
            {
                _logger.LogInformation("[Topology] GetData - Success: {Sites} sites, {DCs} DCs, {Links} links, {Subnets} subnets (elapsed: {Elapsed}ms)",
                    topologyData.Sites.Count, topologyData.DomainControllers.Count,
                    topologyData.SiteLinks.Count, topologyData.Subnets.Count, sw.ElapsedMilliseconds);
            }

            // Log performance if enabled and threshold exceeded
            if (_appSettings.Logging.EnablePerformanceLogging &&
                sw.ElapsedMilliseconds > _appSettings.Logging.PerformanceThresholdMs)
            {
                _logger.LogWarning("[Topology] GetData - Performance threshold exceeded: {Elapsed}ms (threshold: {Threshold}ms)",
                    sw.ElapsedMilliseconds, _appSettings.Logging.PerformanceThresholdMs);
            }

            return Json(topologyData);
        }
        catch (Exception ex)
        {
            sw.Stop();
            _logger.LogError(ex, "[Topology] GetData - Error fetching topology data for collection {CollectionId} (elapsed: {Elapsed}ms)",
                collectionId, sw.ElapsedMilliseconds);
            return StatusCode(500, new { error = $"Error fetching topology data: {ex.Message}" });
        }
    }
}
