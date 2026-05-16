using Hangfire;
using Microsoft.AspNetCore.Mvc;
using CLAWS.Core.Configuration;
using CLAWS.Core.Services;
using CLAWS.Jobs;
using CLAWS.Web.Models;
using CLAWS.Web.Services;

using Microsoft.AspNetCore.Authorization;

namespace CLAWS.Web.Controllers;

/// <summary>
/// Controller for viewing production data collections.
/// Provides separate views for NTFS Permissions and AD Inventory data.
/// All authenticated users can view; type-specific admins can delete.
/// </summary>
[Authorize]
public class ProductionDataController : Controller
{
    private readonly ILogger<ProductionDataController> _logger;
    private readonly IProductionDataService _productionDataService;
    private readonly IAppLogService _appLogService;
    private readonly IBackgroundJobClient _backgroundJobClient;
    private readonly AppSettings _appSettings;

    public ProductionDataController(
        ILogger<ProductionDataController> logger,
        IProductionDataService productionDataService,
        IAppLogService appLogService,
        IBackgroundJobClient backgroundJobClient,
        AppSettings appSettings)
    {
        _logger = logger;
        _productionDataService = productionDataService;
        _appLogService = appLogService;
        _backgroundJobClient = backgroundJobClient;
        _appSettings = appSettings;
    }

    /// <summary>
    /// Display NTFS Permissions production collections.
    /// </summary>
    public async Task<IActionResult> NtfsPermissions(CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            return View(new NtfsPermissionsViewModel
            {
                ErrorMessage = "Database is not configured."
            });
        }

        var collections = await _productionDataService.GetNtfsCollectionsAsync(cancellationToken);
        var activeDeletionIds = _productionDataService.GetActiveDeletionIds();

        var model = new NtfsPermissionsViewModel
        {
            Collections = collections,
            ActiveDeletionIds = activeDeletionIds
        };

        return View(model);
    }

    /// <summary>
    /// Display AD Inventory production collections.
    /// </summary>
    public async Task<IActionResult> AdInventory(CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            return View(new AdInventoryViewModel
            {
                ErrorMessage = "Database is not configured."
            });
        }

        var collections = await _productionDataService.GetAdCollectionsAsync(cancellationToken);
        var activeDeletionIds = _productionDataService.GetActiveDeletionIds();

        // Include the just-started deletion ID from TempData (for SignalR subscription)
        // This handles the race condition where the job completes before the page finishes loading
        if (TempData["DeletingId"] is string deletingId && !activeDeletionIds.Contains(deletingId))
        {
            // Check if the collection was already deleted (job completed before page loaded)
            var stillExists = collections.Any(c => c.CollectionId.ToString() == deletingId);
            if (!stillExists)
            {
                // Job already completed and collection is gone - show success instead of spinner
                TempData["Success"] = "Collection deleted successfully.";
            }
            else
            {
                // Collection still exists, add to active list for progress tracking
                activeDeletionIds.Add(deletingId);
            }
        }

        var model = new AdInventoryViewModel
        {
            Collections = collections,
            ActiveDeletionIds = activeDeletionIds
        };

        return View(model);
    }

    /// <summary>
    /// Delete an NTFS Permissions collection from production.
    /// Requires NTFS Perms Admin or Site Admin privileges.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(Policy = "NtfsPermsAdminOrSiteAdmin")]
    public async Task<IActionResult> DeleteNtfsCollection(Guid id, CancellationToken cancellationToken)
    {
        var userName = User.Identity?.Name ?? "Unknown";
        _logger.LogWarning("User {User} initiating background deletion of NTFS production collection {InventoryId}", userName, id);

        // Enqueue background job for deletion
        var jobId = _backgroundJobClient.Enqueue<IProductionDeletionJob>(
            job => job.DeleteNtfsCollectionAsync(id, userName, CancellationToken.None));

        await _appLogService.LogConfigChangeAsync($"DeleteProductionCollection:NTFS:{id}:JobId:{jobId}", userName, cancellationToken);

        TempData["Success"] = $"Deletion job queued (Job ID: {jobId}). Progress will be shown below.";
        TempData["DeletingId"] = id.ToString();

        return RedirectToAction(nameof(NtfsPermissions));
    }

    /// <summary>
    /// Delete an AD Inventory collection from production.
    /// Requires AD Admin or Site Admin privileges.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(Policy = "AdAdminOrSiteAdmin")]
    public async Task<IActionResult> DeleteAdCollection(Guid id, CancellationToken cancellationToken)
    {
        var userName = User.Identity?.Name ?? "Unknown";
        _logger.LogWarning("User {User} initiating background deletion of AD production collection {CollectionId}", userName, id);

        // Enqueue background job for deletion
        var jobId = _backgroundJobClient.Enqueue<IProductionDeletionJob>(
            job => job.DeleteAdCollectionAsync(id, userName, CancellationToken.None));

        await _appLogService.LogConfigChangeAsync($"DeleteProductionCollection:AD:{id}:JobId:{jobId}", userName, cancellationToken);

        // CollectionID is now a GUID, use it directly for progress tracking
        TempData["Success"] = $"Deletion job queued (Job ID: {jobId}). Progress will be shown below.";
        TempData["DeletingId"] = id.ToString();

        return RedirectToAction(nameof(AdInventory));
    }
}
