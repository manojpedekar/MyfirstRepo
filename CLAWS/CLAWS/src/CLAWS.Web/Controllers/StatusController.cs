using Hangfire;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using CLAWS.Core.Configuration;
using CLAWS.Core.Services;
using CLAWS.Data.Repositories;
using CLAWS.Jobs;
using CLAWS.Web.Models;
using CLAWS.Web.Services;

namespace CLAWS.Web.Controllers;

/// <summary>
/// Controller for viewing upload status.
/// All authenticated users can view all uploads.
/// Users can manage their own uploads; type-specific admins can manage all uploads of their type.
/// </summary>
[Authorize]
public class StatusController : Controller
{
    private readonly ILogger<StatusController> _logger;
    private readonly IUploadRepository _uploadRepository;
    private readonly IUploadService _uploadService;
    private readonly IMigrationService _migrationService;
    private readonly IApiKeyRepository _apiKeyRepository;
    private readonly IBackgroundJobClient _backgroundJobClient;
    private readonly AppSettings _appSettings;

    public StatusController(
        ILogger<StatusController> logger,
        IUploadRepository uploadRepository,
        IUploadService uploadService,
        IMigrationService migrationService,
        IApiKeyRepository apiKeyRepository,
        IBackgroundJobClient backgroundJobClient,
        AppSettings appSettings)
    {
        _logger = logger;
        _uploadRepository = uploadRepository;
        _uploadService = uploadService;
        _migrationService = migrationService;
        _apiKeyRepository = apiKeyRepository;
        _backgroundJobClient = backgroundJobClient;
        _appSettings = appSettings;
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
    /// Checks if the current user can manage the given upload.
    /// Users can manage their own uploads. Type-specific admins can manage uploads of their type.
    /// Site admins can manage all uploads.
    /// </summary>
    private async Task<bool> CanManageUploadAsync(Data.Entities.Upload upload, string userName, CancellationToken cancellationToken)
    {
        // Owner can always manage their own
        if (await UserOwnsUploadAsync(upload.UploadedBy, userName, cancellationToken))
            return true;

        // Site Admin can manage all
        if (!string.IsNullOrEmpty(_appSettings.Authorization.SiteAdminGroup) &&
            User.IsInRole(_appSettings.Authorization.SiteAdminGroup))
            return true;

        // Type-specific admins can manage their type
        if (upload.UploadType == "NTFSPermissions" &&
            !string.IsNullOrEmpty(_appSettings.Authorization.NtfsPermsAdminGroup) &&
            User.IsInRole(_appSettings.Authorization.NtfsPermsAdminGroup))
            return true;

        if (upload.UploadType == "ADInventory" &&
            !string.IsNullOrEmpty(_appSettings.Authorization.AdAdminGroup) &&
            User.IsInRole(_appSettings.Authorization.AdAdminGroup))
            return true;

        return false;
    }

    public async Task<IActionResult> Index(CancellationToken cancellationToken)
    {
        // Show all uploads to all users (read-only visibility)
        var uploads = await _uploadRepository.GetAllAsync(0, 100, null, cancellationToken);

        var model = new StatusViewModel
        {
            IsDbConfigured = _appSettings.SqlServer.IsConfigured,
            IsAuthConfigured = _appSettings.Authorization.IsConfigured,
            Uploads = uploads.Select(u => new UploadItem
            {
                UploadId = u.UploadId,
                OriginalFilename = u.OriginalFilename,
                FileSizeBytes = u.FileSizeBytes,
                Status = u.Status,
                StatusMessage = u.StatusMessage,
                UploadedAt = u.UploadedAt,
                CompletedAt = u.CompletedAt,
                ImportProgress = u.ImportProgress,
                CurrentPhase = u.CurrentPhase,
                ValidationStatus = u.ValidationStatus,
                ValidationMessage = u.ValidationMessage,
                MergeStatus = u.MergeStatus,
                MergeMessage = u.MergeMessage,
                UploadedBy = u.UploadedBy,
                UploadType = u.UploadType
            }).ToList()
        };

        return View(model);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Details(Guid id, CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(id, cancellationToken);
        if (upload == null)
        {
            return NotFound();
        }

        // All authenticated users can view upload details
        // Pass management permission to the view for button visibility
        var userName = User.Identity?.Name ?? "Unknown";
        ViewBag.CanManage = await CanManageUploadAsync(upload, userName, cancellationToken);

        // Get inventory information based on upload type
        var model = new UploadItem
        {
            UploadId = upload.UploadId,
            OriginalFilename = upload.OriginalFilename,
            FileSizeBytes = upload.FileSizeBytes,
            Status = upload.Status,
            StatusMessage = upload.StatusMessage,
            UploadedAt = upload.UploadedAt,
            CompletedAt = upload.CompletedAt,
            ImportProgress = upload.ImportProgress,
            CurrentPhase = upload.CurrentPhase,
            UploadType = upload.UploadType,
            TotalRecordsImported = upload.RowsProcessed,
            ValidationStatus = upload.ValidationStatus,
            ValidationMessage = upload.ValidationMessage,
            ValidationCompletedAt = upload.ValidationCompletedAt,
            MergeStatus = upload.MergeStatus,
            MergeMessage = upload.MergeMessage,
            MergeCompletedAt = upload.MergeCompletedAt,
            ErrorDetails = upload.ErrorDetails
        };

        // Only query domain/inventory info when upload is completed AND no operations are in progress
        // (querying during import/validation/merge causes conflicts with bulk operations and locks)
        var isOperationInProgress = upload.ValidationStatus == "InProgress" || upload.MergeStatus == "InProgress";
        if (upload.Status == "Completed" && !isOperationInProgress)
        {
            if (upload.UploadType == "ADInventory")
            {
                // For ADInventory uploads, get domain info with record counts
                var domains = await _migrationService.GetADInventoryDomainInfoAsync(id, cancellationToken);
                model.DomainCollections = domains.Select(d => new DomainCollectionItem
                {
                    InventoryId = d.InventoryId,
                    CollectionId = d.CollectionId,
                    DomainName = d.DomainName,
                    CollectionDateTime = d.CollectionDateTime,
                    TotalRecords = d.TotalRecords
                }).ToList();
            }
            else
            {
                // For NTFSPermissions uploads, get inventory info
                var inventories = await _migrationService.GetInventoryInfoAsync(id, cancellationToken);
                model.Inventories = inventories.Select(i => new InventoryItem
                {
                    InventoryId = i.InventoryId,
                    ComputerName = i.ComputerName,
                    ScanPath = i.ScanPath,
                    CollectionDateTime = i.CollectionDateTime,
                    TotalRecords = i.TotalRecords
                }).ToList();
            }
        }

        return View(model);
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Delete(Guid id, CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(id, cancellationToken);
        if (upload == null)
        {
            return NotFound();
        }

        // Check if user can manage this upload (owner, type-specific admin, or site admin)
        var userName = User.Identity?.Name ?? "Unknown";
        if (!await CanManageUploadAsync(upload, userName, cancellationToken))
        {
            return Forbid();
        }

        _logger.LogInformation("User {User} queuing deletion job for upload {UploadId}", userName, id);

        // Enqueue background job for deletion to prevent HTTP timeout issues
        var jobId = _backgroundJobClient.Enqueue<IUploadDeletionJob>(
            job => job.DeleteUploadAsync(id, userName, CancellationToken.None));

        TempData["Success"] = $"Deletion job queued (Job ID: {jobId}). The upload will be deleted in the background.";
        TempData["DeletionJobId"] = jobId;

        return RedirectToAction("Index");
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Validate(Guid id, CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(id, cancellationToken);
        if (upload == null)
        {
            return NotFound();
        }

        // Check if user can manage this upload (owner, type-specific admin, or site admin)
        var userName = User.Identity?.Name ?? "Unknown";
        if (!await CanManageUploadAsync(upload, userName, cancellationToken))
        {
            return Forbid();
        }

        // Only allow validation on completed uploads
        if (upload.Status != "Completed")
        {
            TempData["Error"] = "Validation can only be performed on completed uploads.";
            return RedirectToAction("Details", new { id });
        }

        // Check if validation is already in progress
        if (upload.ValidationStatus == "InProgress")
        {
            TempData["Error"] = "Validation is already in progress for this upload.";
            return RedirectToAction("Details", new { id });
        }

        _logger.LogInformation("User {User} queuing validation job for upload {UploadId}", userName, id);

        // Enqueue background job for validation
        var jobId = _backgroundJobClient.Enqueue<IValidationMigrationJob>(
            job => job.ValidateAsync(id, userName, CancellationToken.None));

        TempData["Success"] = $"Validation job queued (Job ID: {jobId}). Progress will be shown below.";
        TempData["ValidationJobId"] = jobId;

        return RedirectToAction("Details", new { id });
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Merge(Guid id, CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(id, cancellationToken);
        if (upload == null)
        {
            return NotFound();
        }

        // Check if user can manage this upload (owner, type-specific admin, or site admin)
        var userName = User.Identity?.Name ?? "Unknown";
        if (!await CanManageUploadAsync(upload, userName, cancellationToken))
        {
            return Forbid();
        }

        // Only allow merge on completed uploads
        if (upload.Status != "Completed")
        {
            TempData["Error"] = "Merge can only be performed on completed uploads.";
            return RedirectToAction("Details", new { id });
        }

        // Check if merge is already in progress
        if (upload.MergeStatus == "InProgress")
        {
            TempData["Error"] = "Merge is already in progress for this upload.";
            return RedirectToAction("Details", new { id });
        }

        _logger.LogInformation("User {User} queuing merge job for upload {UploadId}", userName, id);

        // Enqueue background job for migration
        var jobId = _backgroundJobClient.Enqueue<IValidationMigrationJob>(
            job => job.MigrateAsync(id, userName, CancellationToken.None));

        TempData["Success"] = $"Merge job queued (Job ID: {jobId}). Progress will be shown below.";
        TempData["MergeJobId"] = jobId;

        return RedirectToAction("Details", new { id });
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> ValidateAndMerge(Guid id, CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(id, cancellationToken);
        if (upload == null)
        {
            return NotFound();
        }

        // Check if user can manage this upload (owner, type-specific admin, or site admin)
        var userName = User.Identity?.Name ?? "Unknown";
        if (!await CanManageUploadAsync(upload, userName, cancellationToken))
        {
            return Forbid();
        }

        // Only allow on completed uploads
        if (upload.Status != "Completed")
        {
            TempData["Error"] = "Validate & Merge can only be performed on completed uploads.";
            return RedirectToAction("Details", new { id });
        }

        // Check if validation or merge is already in progress
        if (upload.ValidationStatus == "InProgress" || upload.MergeStatus == "InProgress")
        {
            TempData["Error"] = "Validation or merge is already in progress for this upload.";
            return RedirectToAction("Details", new { id });
        }

        _logger.LogInformation("User {User} queuing validate & merge job for upload {UploadId}", userName, id);

        // Enqueue background job for validation and migration
        var jobId = _backgroundJobClient.Enqueue<IValidationMigrationJob>(
            job => job.ValidateAndMigrateAsync(id, userName, CancellationToken.None));

        TempData["Success"] = $"Validate & Merge job queued (Job ID: {jobId}). Progress will be shown below.";
        TempData["ValidateAndMergeJobId"] = jobId;

        return RedirectToAction("Details", new { id });
    }

}
