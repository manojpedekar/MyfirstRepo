using Hangfire;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CLAWS.Core.Configuration;
using CLAWS.Core.Services;
using CLAWS.Data.Context;
using CLAWS.Data.Repositories;
using CLAWS.Jobs;
using CLAWS.Web.Models;
using CLAWS.Web.Services;

using Microsoft.AspNetCore.Authorization;

namespace CLAWS.Web.Controllers;

/// <summary>
/// Controller for administrative functions.
/// Requires Site Admin role for all actions.
/// </summary>
[Authorize(Policy = "SiteAdminOnly")]
public class AdminController : Controller
{
    private readonly ILogger<AdminController> _logger;
    private readonly IUploadRepository _uploadRepository;
    private readonly IApiKeyService _apiKeyService;
    private readonly IDiskSpaceService _diskSpaceService;
    private readonly IConfigurationFileService _configFileService;
    private readonly IMigrationService _migrationService;
    private readonly IAppLogService _appLogService;
    private readonly IBannerMessageService _bannerMessageService;
    private readonly IVersionService _versionService;
    private readonly IProductionDataService _productionDataService;
    private readonly IChunkedUploadService _chunkedUploadService;
    private readonly IBackgroundJobClient _backgroundJobClient;
    private readonly ApplicationDbContext _dbContext;
    private readonly AppSettings _appSettings;

    public AdminController(
        ILogger<AdminController> logger,
        IUploadRepository uploadRepository,
        IApiKeyService apiKeyService,
        IDiskSpaceService diskSpaceService,
        IConfigurationFileService configFileService,
        IMigrationService migrationService,
        IAppLogService appLogService,
        IBannerMessageService bannerMessageService,
        IVersionService versionService,
        IProductionDataService productionDataService,
        IChunkedUploadService chunkedUploadService,
        IBackgroundJobClient backgroundJobClient,
        ApplicationDbContext dbContext,
        AppSettings appSettings)
    {
        _logger = logger;
        _uploadRepository = uploadRepository;
        _apiKeyService = apiKeyService;
        _diskSpaceService = diskSpaceService;
        _configFileService = configFileService;
        _migrationService = migrationService;
        _appLogService = appLogService;
        _bannerMessageService = bannerMessageService;
        _versionService = versionService;
        _productionDataService = productionDataService;
        _chunkedUploadService = chunkedUploadService;
        _backgroundJobClient = backgroundJobClient;
        _dbContext = dbContext;
        _appSettings = appSettings;
    }

    /// <summary>
    /// Admin dashboard.
    /// </summary>
    public async Task<IActionResult> Index(CancellationToken cancellationToken)
    {
        var diskStatus = _diskSpaceService.GetDiskSpaceStatus(
            _appSettings.Storage.ImportBasePath,
            _appSettings.UploadLimits.MinFreeDiskSpaceBytes,
            _appSettings.DiskSpace.WarningThresholdPercent,
            _appSettings.DiskSpace.CriticalThresholdPercent);

        var totalUploads = await _uploadRepository.GetCountAsync(null, null, cancellationToken);
        var queuedUploads = await _uploadRepository.GetCountAsync("Queued", null, cancellationToken);
        var activeImports = await _uploadRepository.GetCountAsync("Importing", null, cancellationToken);

        var recentUploads = await _uploadRepository.GetAllAsync(0, 10, null, cancellationToken);

        var model = new AdminDashboardViewModel
        {
            IsDbConfigured = _appSettings.SqlServer.IsConfigured,
            IsAuthConfigured = _appSettings.Authorization.IsConfigured,
            IsUsingAppDirectory = _appSettings.Storage.IsUsingApplicationDirectory(
                Path.GetDirectoryName(typeof(Program).Assembly.Location) ?? ""),
            TotalUploads = totalUploads,
            QueuedUploads = queuedUploads,
            ActiveImports = activeImports,
            DiskSpace = new DiskSpaceInfo
            {
                DriveName = diskStatus.DriveName ?? "Unknown",
                TotalFormatted = diskStatus.TotalFormatted,
                FreeFormatted = diskStatus.FreeFormatted,
                UsedFormatted = diskStatus.UsedFormatted,
                UsedPercent = diskStatus.UsedPercent,
                IsWarning = diskStatus.IsWarning,
                IsCritical = diskStatus.IsCritical
            },
            RecentUploads = recentUploads.Select(u => new UploadItem
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
                UploadType = u.UploadType
            }).ToList()
        };

        return View(model);
    }

    public async Task<IActionResult> Configuration(CancellationToken cancellationToken)
    {
        var model = new ConfigurationViewModel
        {
            IsDbConfigured = _appSettings.SqlServer.IsConfigured,
            StoragePath = _appSettings.Storage.ImportBasePath,
            SiteAdminGroup = _appSettings.Authorization.SiteAdminGroup ?? string.Empty,
            NtfsPermsAdminGroup = _appSettings.Authorization.NtfsPermsAdminGroup ?? string.Empty,
            AdAdminGroup = _appSettings.Authorization.AdAdminGroup ?? string.Empty,
            SqlServer = new SqlServerConfigViewModel
            {
                Server = _appSettings.SqlServer.Server ?? string.Empty,
                Database = _appSettings.SqlServer.Database ?? string.Empty,
                UseWindowsAuth = _appSettings.SqlServer.UseWindowsAuth,
                Username = _appSettings.SqlServer.Username,
                TrustServerCertificate = true,
                Encrypt = "Optional",
                IsConnected = _appSettings.SqlServer.IsConfigured
            },
            DiskSpace = new DiskSpaceConfigViewModel
            {
                WarningThresholdPercent = _appSettings.DiskSpace.WarningThresholdPercent,
                CriticalThresholdPercent = _appSettings.DiskSpace.CriticalThresholdPercent
            },
            DatabasePerformance = new DatabasePerformanceConfigViewModel
            {
                CommandTimeoutMinutes = _appSettings.DatabasePerformance.CommandTimeoutMinutes,
                ConnectionTimeoutSeconds = _appSettings.DatabasePerformance.ConnectionTimeoutSeconds,
                ImportBatchSize = _appSettings.DatabasePerformance.ImportBatchSize,
                MaxConcurrentExtractions = _appSettings.DatabasePerformance.MaxConcurrentExtractions,
                DeletionBatchSize = _appSettings.DatabasePerformance.DeletionBatchSize,
                BulkCopyTimeoutSeconds = _appSettings.DatabasePerformance.BulkCopyTimeoutSeconds,
                PartitioningEnabled = _appSettings.DatabasePerformance.PartitioningEnabled,
                AutoPreparePartitions = _appSettings.DatabasePerformance.AutoPreparePartitions
            },
            UploadLimits = new UploadLimitsConfigViewModel
            {
                MaxUploadSizeGB = _appSettings.UploadLimits.MaxUploadSizeBytes / (1024.0 * 1024.0 * 1024.0),
                MaxExtractedSizeGB = _appSettings.UploadLimits.MaxExtractedSizeBytes / (1024.0 * 1024.0 * 1024.0),
                MinFreeDiskSpaceGB = _appSettings.UploadLimits.MinFreeDiskSpaceBytes / (1024.0 * 1024.0 * 1024.0),
                MaxCompressionRatio = _appSettings.UploadLimits.MaxCompressionRatio
            },
            ImportSettings = new ImportSettingsConfigViewModel
            {
                TransactionMode = _appSettings.Import.TransactionMode.ToString(),
                DuplicateHandling = _appSettings.Import.DuplicateHandling.ToString(),
                EnableAutomaticValidation = _appSettings.Import.EnableAutomaticValidation,
                EnableAutomaticMerge = _appSettings.Import.EnableAutomaticMerge,
                IntegrityCheckMode = _appSettings.Import.IntegrityCheckMode.ToString(),
                AutoIntegrityCheckThresholdMB = _appSettings.Import.AutoIntegrityCheckThresholdMB
            },
            CleanupSettings = new CleanupSettingsConfigViewModel
            {
                AutoPruneCompleted = _appSettings.Cleanup.AutoPruneCompleted,
                CompletedRetentionDays = _appSettings.Cleanup.CompletedRetentionDays,
                ErrorRetentionDays = _appSettings.Cleanup.ErrorRetentionDays,
                ExtractionRetentionDays = _appSettings.Cleanup.ExtractionRetentionDays,
                AutoPruneAdCollections = _appSettings.Cleanup.AutoPruneAdCollections,
                AdCollectionsToKeepPerDomain = _appSettings.Cleanup.AdCollectionsToKeepPerDomain,
                AdCollectionPruneSchedule = _appSettings.Cleanup.AdCollectionPruneSchedule
            },
            Ldap = new LdapConfigViewModel
            {
                Enabled = _appSettings.Ldap.Enabled,
                Server = _appSettings.Ldap.Server,
                Port = _appSettings.Ldap.Port,
                UseSsl = _appSettings.Ldap.UseSsl,
                BaseDn = _appSettings.Ldap.BaseDn,
                UserSearchFilter = _appSettings.Ldap.UserSearchFilter,
                Domain = _appSettings.Ldap.Domain,
                ConnectionTimeout = _appSettings.Ldap.ConnectionTimeout,
                AllowKeymasterFallback = _appSettings.Ldap.AllowKeymasterFallback,
                KeymasterUsername = _appSettings.Ldap.KeymasterUsername
            },
            CloudIntegration = BuildCloudIntegrationViewModel(),
            JobTimeouts = new JobTimeoutsConfigViewModel
            {
                UploadProcessingMinutes = _appSettings.JobTimeouts.UploadProcessingMinutes,
                ValidationMinutes = _appSettings.JobTimeouts.ValidationMinutes,
                MigrationMinutes = _appSettings.JobTimeouts.MigrationMinutes,
                ValidateAndMigrateMinutes = _appSettings.JobTimeouts.ValidateAndMigrateMinutes,
                DeletionMinutes = _appSettings.JobTimeouts.DeletionMinutes,
                OrphanedCleanupMinutes = _appSettings.JobTimeouts.OrphanedCleanupMinutes,
                SchemaTruncateMinutes = _appSettings.JobTimeouts.SchemaTruncateMinutes
            },
            HttpServer = new HttpServerConfigViewModel
            {
                KeepAliveTimeoutMinutes = _appSettings.HttpServer.KeepAliveTimeoutMinutes,
                RequestHeadersTimeoutMinutes = _appSettings.HttpServer.RequestHeadersTimeoutMinutes
            },
            ChunkedUpload = new ChunkedUploadConfigViewModel
            {
                Enabled = _appSettings.ChunkedUpload.Enabled,
                ChunkSizeMB = _appSettings.ChunkedUpload.ChunkSizeBytes / (1024 * 1024),
                ChunkedThresholdMB = (int)(_appSettings.ChunkedUpload.ChunkedThresholdBytes / (1024 * 1024)),
                MaxConcurrentUploadsPerUser = _appSettings.ChunkedUpload.MaxConcurrentUploadsPerUser,
                MaxConcurrentUploadsGlobal = _appSettings.ChunkedUpload.MaxConcurrentUploadsGlobal,
                MaxConcurrentChunksPerUpload = _appSettings.ChunkedUpload.MaxConcurrentChunksPerUpload,
                SessionExpirationHours = _appSettings.ChunkedUpload.SessionExpirationHours,
                ExpirationWarningMinutes = _appSettings.ChunkedUpload.ExpirationWarningMinutes,
                MaxChunkRetries = _appSettings.ChunkedUpload.MaxChunkRetries
            }
        };

        // Load version requirements from SQL Server if configured
        if (_appSettings.SqlServer.IsConfigured)
        {
            try
            {
                var connectionString = _appSettings.SqlServer.BuildConnectionString();
                var versionEntries = await _versionService.GetAllVersionEntriesAsync(connectionString, cancellationToken);

                var exeEntry = versionEntries.FirstOrDefault(v => v.SchemaName == "CollectNTFSPerm");
                var dbEntry = versionEntries.FirstOrDefault(v => v.SchemaName == "DBVersion");

                model.VersionRequirements = new VersionRequirementsConfigViewModel
                {
                    MinExeVersion = exeEntry?.Version ?? string.Empty,
                    MinDbVersion = dbEntry?.Version ?? string.Empty,
                    ExeVersionAppliedDate = exeEntry?.AppliedDate,
                    DbVersionAppliedDate = dbEntry?.AppliedDate,
                    ExeVersionDescription = exeEntry?.Description,
                    DbVersionDescription = dbEntry?.Description
                };
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Could not load version requirements from SQL Server");
            }
        }

        if (TempData["RestartRequired"] != null)
        {
            model.SqlServer.RestartRequired = true;
        }

        if (TempData["ConnectionTestMessage"] != null)
        {
            model.SqlServer.ConnectionTestMessage = TempData["ConnectionTestMessage"]?.ToString();
        }

        return View(model);
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveSqlServerConfig(SqlServerConfigViewModel model)
    {
        if (string.IsNullOrWhiteSpace(model.Server))
        {
            TempData["ConnectionTestMessage"] = "Server name is required.";
            return RedirectToAction(nameof(Configuration));
        }

        if (string.IsNullOrWhiteSpace(model.Database))
        {
            TempData["ConnectionTestMessage"] = "Database name is required.";
            return RedirectToAction(nameof(Configuration));
        }

        // Extract plain text password before creating config (will be encrypted separately)
        var plainTextPassword = model.UseWindowsAuth ? null : model.Password;

        var config = new SqlServerFileConfig
        {
            Server = model.Server,
            Database = model.Database,
            UseWindowsAuth = model.UseWindowsAuth,
            Username = model.UseWindowsAuth ? null : model.Username,
            // Don't set Password - it will be encrypted via plainTextPassword parameter
            TrustServerCertificate = model.TrustServerCertificate,
            Encrypt = model.Encrypt ?? "Optional"
        };

        // Test the connection first with the plain text password
        var (success, message) = await _configFileService.TestSqlConnectionAsync(config, plainTextPassword);

        if (!success)
        {
            TempData["ConnectionTestMessage"] = message;
            return RedirectToAction(nameof(Configuration));
        }

        // Save the configuration with encrypted password
        await _configFileService.SaveSqlServerConfigAsync(config, plainTextPassword);

        TempData["ConnectionTestMessage"] = message;
        TempData["RestartRequired"] = true;

        _logger.LogInformation("SQL Server configuration saved by {User}", User.Identity?.Name);
        await _appLogService.LogConfigChangeAsync("SqlServer", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> TestSqlConnection(SqlServerConfigViewModel model)
    {
        // Extract plain text password for testing
        var plainTextPassword = model.UseWindowsAuth ? null : model.Password;

        var config = new SqlServerFileConfig
        {
            Server = model.Server,
            Database = model.Database,
            UseWindowsAuth = model.UseWindowsAuth,
            Username = model.UseWindowsAuth ? null : model.Username,
            // Don't set Password - pass it separately for testing
            TrustServerCertificate = model.TrustServerCertificate,
            Encrypt = model.Encrypt ?? "Optional"
        };

        var (success, message) = await _configFileService.TestSqlConnectionAsync(config, plainTextPassword);

        TempData["ConnectionTestMessage"] = message;

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveStorageConfig(string storagePath)
    {
        if (string.IsNullOrWhiteSpace(storagePath))
        {
            TempData["StorageMessage"] = "Storage path is required.";
            return RedirectToAction(nameof(Configuration));
        }

        await _configFileService.SaveStorageConfigAsync(storagePath);
        TempData["RestartRequired"] = true;
        TempData["StorageMessage"] = "Storage configuration saved. Restart required.";

        await _appLogService.LogConfigChangeAsync("Storage.ImportBasePath", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveAuthorizationConfig(
        string? siteAdminGroup,
        string? ntfsPermsAdminGroup,
        string? adAdminGroup)
    {
        var siteAdminGrp = string.IsNullOrWhiteSpace(siteAdminGroup) ? null : siteAdminGroup.Trim();
        var ntfsPermsAdminGrp = string.IsNullOrWhiteSpace(ntfsPermsAdminGroup) ? null : ntfsPermsAdminGroup.Trim();
        var adAdminGrp = string.IsNullOrWhiteSpace(adAdminGroup) ? null : adAdminGroup.Trim();

        await _configFileService.SaveAuthorizationConfigAsync(siteAdminGrp, ntfsPermsAdminGrp, adAdminGrp);
        TempData["RestartRequired"] = true;
        TempData["AuthMessage"] = "Authorization configuration saved. Restart required.";

        await _appLogService.LogConfigChangeAsync("Authorization", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveDiskSpaceConfig(double warningThresholdPercent, double criticalThresholdPercent)
    {
        // Validate thresholds
        warningThresholdPercent = Math.Clamp(warningThresholdPercent, 0, 100);
        criticalThresholdPercent = Math.Clamp(criticalThresholdPercent, 0, 100);

        await _configFileService.SaveDiskSpaceConfigAsync(warningThresholdPercent, criticalThresholdPercent);
        TempData["RestartRequired"] = true;
        TempData["DiskSpaceMessage"] = "Disk space settings saved. Restart required.";

        _logger.LogInformation("Disk space thresholds updated by {User}: Warning={Warning}%, Critical={Critical}%",
            User.Identity?.Name, warningThresholdPercent, criticalThresholdPercent);
        await _appLogService.LogConfigChangeAsync("DiskSpace", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveDatabasePerformanceConfig(
        int commandTimeoutMinutes,
        int connectionTimeoutSeconds,
        int importBatchSize,
        int maxConcurrentExtractions,
        int deletionBatchSize,
        int bulkCopyTimeoutSeconds,
        bool partitioningEnabled,
        bool autoPreparePartitions)
    {
        // Validate settings
        commandTimeoutMinutes = Math.Clamp(commandTimeoutMinutes, 1, 120); // 1-120 minutes
        connectionTimeoutSeconds = Math.Clamp(connectionTimeoutSeconds, 5, 300); // 5-300 seconds
        importBatchSize = Math.Clamp(importBatchSize, 1000, 100000); // 1000-100000 records
        maxConcurrentExtractions = Math.Clamp(maxConcurrentExtractions, 1, 10); // 1-10 concurrent
        deletionBatchSize = Math.Clamp(deletionBatchSize, 1000, 100000); // 1000-100000 records
        bulkCopyTimeoutSeconds = Math.Clamp(bulkCopyTimeoutSeconds, 60, 3600); // 1-60 minutes

        _logger.LogDebug("SaveDatabasePerformanceConfig received: partitioningEnabled={PartitioningEnabled}, autoPreparePartitions={AutoPreparePartitions}",
            partitioningEnabled, autoPreparePartitions);

        await _configFileService.SaveDatabasePerformanceConfigAsync(
            commandTimeoutMinutes,
            connectionTimeoutSeconds,
            importBatchSize,
            maxConcurrentExtractions,
            deletionBatchSize,
            bulkCopyTimeoutSeconds,
            partitioningEnabled,
            autoPreparePartitions);

        TempData["RestartRequired"] = true;
        TempData["DatabasePerformanceMessage"] = "Database performance settings saved. Restart required.";

        _logger.LogInformation("Database performance settings updated by {User}: CommandTimeout={Timeout}min, ImportBatchSize={ImportBatch}, DeletionBatchSize={DeletionBatch}, BulkCopyTimeout={BulkCopy}s, Partitioning={Partitioning}, AutoPreparePartitions={AutoPrepare}",
            User.Identity?.Name, commandTimeoutMinutes, importBatchSize, deletionBatchSize, bulkCopyTimeoutSeconds, partitioningEnabled, autoPreparePartitions);
        await _appLogService.LogConfigChangeAsync("DatabasePerformance", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveUploadLimitsConfig(
        double maxUploadSizeGB,
        double maxExtractedSizeGB,
        double minFreeDiskSpaceGB,
        double maxCompressionRatio)
    {
        // Validate settings
        maxUploadSizeGB = Math.Clamp(maxUploadSizeGB, 0.1, 100); // 100MB - 100GB
        maxExtractedSizeGB = Math.Clamp(maxExtractedSizeGB, 1, 500); // 1GB - 500GB
        minFreeDiskSpaceGB = Math.Clamp(minFreeDiskSpaceGB, 1, 500); // 1GB - 500GB
        maxCompressionRatio = Math.Clamp(maxCompressionRatio, 10, 1000); // 10:1 - 1000:1

        // Convert GB to bytes
        var maxUploadSizeBytes = (long)(maxUploadSizeGB * 1024 * 1024 * 1024);
        var maxExtractedSizeBytes = (long)(maxExtractedSizeGB * 1024 * 1024 * 1024);
        var minFreeDiskSpaceBytes = (long)(minFreeDiskSpaceGB * 1024 * 1024 * 1024);

        await _configFileService.SaveUploadLimitsConfigAsync(
            maxUploadSizeBytes,
            maxExtractedSizeBytes,
            minFreeDiskSpaceBytes,
            maxCompressionRatio);

        TempData["RestartRequired"] = true;
        TempData["UploadLimitsMessage"] = "Upload limits saved. Restart required.";

        _logger.LogInformation("Upload limits updated by {User}: MaxUpload={MaxUpload}GB",
            User.Identity?.Name, maxUploadSizeGB);
        await _appLogService.LogConfigChangeAsync("UploadLimits", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveChunkedUploadConfig(
        int chunkSizeMB,
        int chunkedThresholdMB,
        int maxConcurrentUploadsPerUser,
        int maxConcurrentUploadsGlobal,
        int maxConcurrentChunksPerUpload,
        int sessionExpirationHours,
        int expirationWarningMinutes,
        int maxChunkRetries)
    {
        // Read enabled checkbox directly from form - ASP.NET Core string binding only takes the FIRST value,
        // but Request.Form returns ALL values. Check if any value is "true".
        var enabledValues = Request.Form["enabled"];
        _logger.LogInformation("SaveChunkedUploadConfig received enabled values: '{EnabledRaw}'", enabledValues.ToString());
        var isEnabled = enabledValues.Any(v => string.Equals(v, "true", StringComparison.OrdinalIgnoreCase));
        _logger.LogInformation("Parsed isEnabled: {IsEnabled}", isEnabled);

        // Validate settings
        chunkSizeMB = Math.Clamp(chunkSizeMB, 10, 200);
        chunkedThresholdMB = Math.Clamp(chunkedThresholdMB, 100, 4000);
        maxConcurrentUploadsPerUser = Math.Clamp(maxConcurrentUploadsPerUser, 1, 10);
        maxConcurrentUploadsGlobal = Math.Clamp(maxConcurrentUploadsGlobal, 1, 50);
        maxConcurrentChunksPerUpload = Math.Clamp(maxConcurrentChunksPerUpload, 1, 6);
        sessionExpirationHours = Math.Clamp(sessionExpirationHours, 1, 24);
        expirationWarningMinutes = Math.Clamp(expirationWarningMinutes, 5, 60);
        maxChunkRetries = Math.Clamp(maxChunkRetries, 1, 10);

        await _configFileService.SaveChunkedUploadConfigAsync(
            isEnabled,
            chunkSizeMB * 1024 * 1024,
            (long)chunkedThresholdMB * 1024 * 1024,
            maxConcurrentUploadsPerUser,
            maxConcurrentUploadsGlobal,
            maxConcurrentChunksPerUpload,
            sessionExpirationHours,
            expirationWarningMinutes,
            maxChunkRetries);

        TempData["RestartRequired"] = true;
        TempData["ChunkedUploadMessage"] = "Chunked upload settings saved. Restart required.";

        _logger.LogInformation("Chunked upload settings updated by {User}: Enabled={Enabled}, ChunkSize={ChunkSize}MB",
            User.Identity?.Name, isEnabled, chunkSizeMB);
        await _appLogService.LogConfigChangeAsync("ChunkedUpload", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveImportConfig(
        string transactionMode,
        string duplicateHandling,
        bool enableAutomaticValidation,
        bool enableAutomaticMerge,
        string integrityCheckMode,
        int autoIntegrityCheckThresholdMB)
    {
        // Validate enum values
        var validTransactionModes = new[] { "PerTable", "PerBatch", "PerCollection" };
        var validDuplicateHandlings = new[] { "Reject", "Update", "Skip" };
        var validIntegrityCheckModes = new[] { "Full", "Quick", "None", "Auto" };

        if (!validTransactionModes.Contains(transactionMode))
            transactionMode = "PerTable";
        if (!validDuplicateHandlings.Contains(duplicateHandling))
            duplicateHandling = "Reject";
        if (!validIntegrityCheckModes.Contains(integrityCheckMode))
            integrityCheckMode = "Quick";

        // Validate threshold
        autoIntegrityCheckThresholdMB = Math.Clamp(autoIntegrityCheckThresholdMB, 1, 10000);

        // Enforce business rule: automatic merge requires automatic validation
        if (enableAutomaticMerge && !enableAutomaticValidation)
        {
            enableAutomaticValidation = true;
        }

        await _configFileService.SaveImportConfigAsync(transactionMode, duplicateHandling, enableAutomaticValidation, enableAutomaticMerge, integrityCheckMode, autoIntegrityCheckThresholdMB);

        TempData["RestartRequired"] = true;
        TempData["ImportMessage"] = "Import settings saved. Restart required.";

        _logger.LogInformation("Import settings updated by {User}: TransactionMode={Mode}, DuplicateHandling={Handling}, AutoValidation={AutoValidation}, AutoMerge={AutoMerge}, IntegrityCheck={IntegrityCheck}",
            User.Identity?.Name, transactionMode, duplicateHandling, enableAutomaticValidation, enableAutomaticMerge, integrityCheckMode);
        await _appLogService.LogConfigChangeAsync("Import", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveCleanupConfig(
        bool autoPruneCompleted,
        int completedRetentionDays,
        int errorRetentionDays,
        int extractionRetentionDays)
    {
        // Validate settings
        completedRetentionDays = Math.Clamp(completedRetentionDays, 0, 365); // 0-365 days
        errorRetentionDays = Math.Clamp(errorRetentionDays, 0, 365); // 0-365 days
        extractionRetentionDays = Math.Clamp(extractionRetentionDays, 0, 365); // 0-365 days

        await _configFileService.SaveCleanupConfigAsync(
            autoPruneCompleted,
            completedRetentionDays,
            errorRetentionDays,
            extractionRetentionDays);

        TempData["RestartRequired"] = true;
        TempData["CleanupMessage"] = "Cleanup settings saved. Restart required.";

        _logger.LogInformation("Cleanup settings updated by {User}: AutoPrune={AutoPrune}, CompletedRetention={Days}d",
            User.Identity?.Name, autoPruneCompleted, completedRetentionDays);
        await _appLogService.LogConfigChangeAsync("Cleanup", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveAdCollectionCleanupConfig(
        bool autoPruneAdCollections,
        int adCollectionsToKeepPerDomain,
        string adCollectionPruneSchedule)
    {
        // Validate settings
        adCollectionsToKeepPerDomain = Math.Clamp(adCollectionsToKeepPerDomain, 1, 100); // 1-100 collections

        // Validate cron expression (basic check)
        if (string.IsNullOrWhiteSpace(adCollectionPruneSchedule))
        {
            adCollectionPruneSchedule = "0 */6 * * *"; // Default: every 6 hours
        }

        await _configFileService.SaveAdCollectionCleanupConfigAsync(
            autoPruneAdCollections,
            adCollectionsToKeepPerDomain,
            adCollectionPruneSchedule);

        TempData["RestartRequired"] = true;
        TempData["AdCollectionCleanupMessage"] = "AD collection cleanup settings saved. Restart required.";

        _logger.LogInformation("AD collection cleanup settings updated by {User}: AutoPrune={AutoPrune}, KeepPerDomain={KeepCount}, Schedule={Schedule}",
            User.Identity?.Name, autoPruneAdCollections, adCollectionsToKeepPerDomain, adCollectionPruneSchedule);
        await _appLogService.LogConfigChangeAsync("AD Collection Cleanup", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveLdapConfig(
        bool enabled,
        string? server,
        int port,
        bool useSsl,
        string? baseDn,
        string? userSearchFilter,
        string? domain,
        int connectionTimeout,
        bool allowKeymasterFallback,
        string? keymasterUsername)
    {
        // Validate settings if LDAP is enabled
        if (enabled)
        {
            if (string.IsNullOrWhiteSpace(server))
            {
                TempData["LdapMessage"] = "LDAP server is required when LDAP is enabled.";
                return RedirectToAction(nameof(Configuration));
            }

            if (string.IsNullOrWhiteSpace(baseDn))
            {
                TempData["LdapMessage"] = "Base DN is required when LDAP is enabled.";
                return RedirectToAction(nameof(Configuration));
            }
        }

        // Clamp values
        port = Math.Clamp(port, 1, 65535);
        connectionTimeout = Math.Clamp(connectionTimeout, 5, 120);

        var config = new LdapFileConfig
        {
            Enabled = enabled,
            Server = server?.Trim() ?? string.Empty,
            Port = port,
            UseSsl = useSsl,
            BaseDn = baseDn?.Trim() ?? string.Empty,
            UserSearchFilter = string.IsNullOrWhiteSpace(userSearchFilter) ? "(sAMAccountName={0})" : userSearchFilter.Trim(),
            Domain = string.IsNullOrWhiteSpace(domain) ? null : domain.Trim(),
            ConnectionTimeout = connectionTimeout,
            AllowKeymasterFallback = allowKeymasterFallback,
            KeymasterUsername = string.IsNullOrWhiteSpace(keymasterUsername) ? "Keymaster" : keymasterUsername.Trim()
        };

        await _configFileService.SaveLdapConfigAsync(config);

        TempData["RestartRequired"] = true;
        TempData["LdapMessage"] = "LDAP configuration saved. Restart required.";

        _logger.LogInformation("LDAP settings updated by {User}: Enabled={Enabled}, Server={Server}",
            User.Identity?.Name, enabled, server);
        await _appLogService.LogConfigChangeAsync("Ldap", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveCloudIntegrationConfig(
        bool enabled,
        string? ldapServer,
        int ldapPort,
        bool ldapUseSsl,
        string? ldapSearchBase,
        string? serviceAccountDomain,
        string? serviceAccountUsername,
        string? serviceAccountPassword,
        int connectionTimeout,
        string? schedule,
        int batchSize,
        int delayBetweenBatchesMs)
    {
        _logger.LogInformation("SaveCloudIntegrationConfig called: enabled={Enabled}, ldapServer={LdapServer}, ldapSearchBase={LdapSearchBase}",
            enabled, ldapServer, ldapSearchBase);

        // Validate settings if Cloud Integration is enabled
        if (enabled)
        {
            if (string.IsNullOrWhiteSpace(ldapServer))
            {
                TempData["CloudIntegrationMessage"] = "LDAP server is required when Cloud Integration is enabled.";
                return RedirectToAction(nameof(Configuration));
            }

            if (string.IsNullOrWhiteSpace(ldapSearchBase))
            {
                TempData["CloudIntegrationMessage"] = "LDAP search base is required when Cloud Integration is enabled.";
                return RedirectToAction(nameof(Configuration));
            }

            // Check if password is required (new config or no existing password)
            var existingConfig = _configFileService.LoadCloudIntegrationConfig();
            if (string.IsNullOrEmpty(existingConfig?.EncryptedServiceAccountPassword) &&
                string.IsNullOrWhiteSpace(serviceAccountPassword))
            {
                TempData["CloudIntegrationMessage"] = "Service account password is required.";
                return RedirectToAction(nameof(Configuration));
            }
        }

        // Clamp values
        ldapPort = Math.Clamp(ldapPort, 1, 65535);
        connectionTimeout = Math.Clamp(connectionTimeout, 5, 120);
        batchSize = Math.Clamp(batchSize, 10, 1000);
        delayBetweenBatchesMs = Math.Clamp(delayBetweenBatchesMs, 0, 10000);

        var config = new CloudIntegrationFileConfig
        {
            Enabled = enabled,
            LdapServer = ldapServer?.Trim() ?? string.Empty,
            LdapPort = ldapPort,
            LdapUseSsl = ldapUseSsl,
            LdapSearchBase = ldapSearchBase?.Trim() ?? string.Empty,
            ServiceAccountDomain = string.IsNullOrWhiteSpace(serviceAccountDomain) ? null : serviceAccountDomain.Trim(),
            ServiceAccountUsername = string.IsNullOrWhiteSpace(serviceAccountUsername) ? null : serviceAccountUsername.Trim(),
            ConnectionTimeout = connectionTimeout,
            Schedule = string.IsNullOrWhiteSpace(schedule) ? "0 4 * * *" : schedule.Trim(),
            BatchSize = batchSize,
            DelayBetweenBatchesMs = delayBetweenBatchesMs
        };

        // Password is passed separately for encryption
        var passwordToEncrypt = string.IsNullOrWhiteSpace(serviceAccountPassword) ? null : serviceAccountPassword;

        await _configFileService.SaveCloudIntegrationConfigAsync(config, passwordToEncrypt);

        TempData["RestartRequired"] = true;
        TempData["CloudIntegrationMessage"] = "Cloud Integration configuration saved. Restart required.";

        _logger.LogInformation("Cloud Integration settings updated by {User}: Enabled={Enabled}, Server={Server}",
            User.Identity?.Name, enabled, ldapServer);
        await _appLogService.LogConfigChangeAsync("CloudIntegration", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public IActionResult TestCloudIntegrationConnection([FromBody] CloudIntegrationTestRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.LdapServer))
            {
                return Json(new { success = false, message = "LDAP server is required." });
            }

            if (string.IsNullOrWhiteSpace(request.LdapSearchBase))
            {
                return Json(new { success = false, message = "LDAP search base is required." });
            }

            // Get password - use provided or decrypt stored
            var password = request.ServiceAccountPassword;
            if (string.IsNullOrEmpty(password))
            {
                password = _configFileService.DecryptCloudIntegrationPassword();
                if (string.IsNullOrEmpty(password))
                {
                    return Json(new { success = false, message = "No password provided and no stored password found." });
                }
            }

            // Build credentials
            var username = string.IsNullOrEmpty(request.ServiceAccountDomain)
                ? request.ServiceAccountUsername
                : $"{request.ServiceAccountDomain}\\{request.ServiceAccountUsername}";

            if (string.IsNullOrEmpty(username))
            {
                return Json(new { success = false, message = "Service account username is required." });
            }

            // Test LDAP connection
            using var connection = new System.DirectoryServices.Protocols.LdapConnection(
                new System.DirectoryServices.Protocols.LdapDirectoryIdentifier(request.LdapServer, request.LdapPort));

            connection.SessionOptions.ProtocolVersion = 3;
            connection.SessionOptions.SecureSocketLayer = request.LdapUseSsl;
            connection.Timeout = TimeSpan.FromSeconds(request.ConnectionTimeout);
            connection.Credential = new System.Net.NetworkCredential(username, password);
            connection.AuthType = System.DirectoryServices.Protocols.AuthType.Basic;

            // Attempt to bind
            connection.Bind();

            // Try a simple search to verify the search base is valid
            // Use SizeLimit=1 since we just need to verify the search base exists
            var searchRequest = new System.DirectoryServices.Protocols.SearchRequest(
                request.LdapSearchBase,
                "(objectClass=organizationalUnit)",
                System.DirectoryServices.Protocols.SearchScope.OneLevel,
                "name");
            searchRequest.SizeLimit = 1;

            int entryCount = 0;
            bool sizeLimitExceeded = false;

            try
            {
                var searchResponse = (System.DirectoryServices.Protocols.SearchResponse)connection.SendRequest(searchRequest);
                entryCount = searchResponse.Entries.Count;
            }
            catch (System.DirectoryServices.Protocols.DirectoryOperationException opEx)
                when (opEx.Message.Contains("size limit", StringComparison.OrdinalIgnoreCase))
            {
                // Size limit exceeded means we found results - connection is working
                sizeLimitExceeded = true;
                entryCount = 1; // At least one was found
            }

            _logger.LogInformation("Cloud Integration LDAP connection test successful by {User}: Server={Server}, OUs found={Count}{SizeLimitNote}",
                User.Identity?.Name, request.LdapServer, entryCount, sizeLimitExceeded ? " (more available)" : "");

            var message = sizeLimitExceeded
                ? "Connection successful! Found multiple OUs in the search base."
                : $"Connection successful! Found {entryCount} OU(s) in the search base.";

            return Json(new { success = true, message });
        }
        catch (System.DirectoryServices.Protocols.LdapException ex)
        {
            _logger.LogWarning(ex, "Cloud Integration LDAP connection test failed: {Error}", ex.Message);
            return Json(new { success = false, message = $"LDAP error: {ex.Message}" });
        }
        catch (System.DirectoryServices.Protocols.DirectoryOperationException opEx)
        {
            _logger.LogWarning(opEx, "Cloud Integration LDAP connection test failed: {Error}", opEx.Message);
            return Json(new { success = false, message = $"LDAP operation error: {opEx.Message}" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Cloud Integration LDAP connection test failed unexpectedly");
            return Json(new { success = false, message = $"Connection failed: {ex.Message}" });
        }
    }

    /// <summary>
    /// Builds CloudIntegration view model from config file (for immediate display after save).
    /// Falls back to in-memory AppSettings if config file not available.
    /// </summary>
    private CloudIntegrationConfigViewModel BuildCloudIntegrationViewModel()
    {
        // Try to load from config file first (shows saved values immediately)
        var fileConfig = _configFileService.LoadCloudIntegrationConfig();
        if (fileConfig != null)
        {
            return new CloudIntegrationConfigViewModel
            {
                Enabled = fileConfig.Enabled,
                Schedule = fileConfig.Schedule,
                LdapSearchBase = fileConfig.LdapSearchBase,
                LdapServer = fileConfig.LdapServer,
                LdapPort = fileConfig.LdapPort,
                LdapUseSsl = fileConfig.LdapUseSsl,
                ServiceAccountUsername = fileConfig.ServiceAccountUsername,
                ServiceAccountDomain = fileConfig.ServiceAccountDomain,
                HasServiceAccountPassword = !string.IsNullOrEmpty(fileConfig.EncryptedServiceAccountPassword),
                ConnectionTimeout = fileConfig.ConnectionTimeout,
                BatchSize = fileConfig.BatchSize,
                DelayBetweenBatchesMs = fileConfig.DelayBetweenBatchesMs
            };
        }

        // Fall back to in-memory settings
        return new CloudIntegrationConfigViewModel
        {
            Enabled = _appSettings.CloudIntegration.Enabled,
            Schedule = _appSettings.CloudIntegration.Schedule,
            LdapSearchBase = _appSettings.CloudIntegration.LdapSearchBase,
            LdapServer = _appSettings.CloudIntegration.LdapServer,
            LdapPort = _appSettings.CloudIntegration.LdapPort,
            LdapUseSsl = _appSettings.CloudIntegration.LdapUseSsl,
            ServiceAccountUsername = _appSettings.CloudIntegration.ServiceAccountUsername,
            ServiceAccountDomain = _appSettings.CloudIntegration.ServiceAccountDomain,
            HasServiceAccountPassword = !string.IsNullOrEmpty(_appSettings.CloudIntegration.EncryptedServiceAccountPassword),
            ConnectionTimeout = _appSettings.CloudIntegration.ConnectionTimeout,
            BatchSize = _appSettings.CloudIntegration.BatchSize,
            DelayBetweenBatchesMs = _appSettings.CloudIntegration.DelayBetweenBatchesMs
        };
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveJobTimeoutsConfig(
        int uploadProcessingMinutes,
        int validationMinutes,
        int migrationMinutes,
        int validateAndMigrateMinutes,
        int deletionMinutes,
        int schemaTruncateMinutes)
    {
        // Validate and clamp values
        uploadProcessingMinutes = Math.Clamp(uploadProcessingMinutes, 30, 720);
        validationMinutes = Math.Clamp(validationMinutes, 30, 720);
        migrationMinutes = Math.Clamp(migrationMinutes, 30, 720);
        validateAndMigrateMinutes = Math.Clamp(validateAndMigrateMinutes, 60, 1440);
        deletionMinutes = Math.Clamp(deletionMinutes, 15, 480);
        schemaTruncateMinutes = Math.Clamp(schemaTruncateMinutes, 30, 720);

        var config = new JobTimeoutsFileConfig
        {
            UploadProcessingMinutes = uploadProcessingMinutes,
            ValidationMinutes = validationMinutes,
            MigrationMinutes = migrationMinutes,
            ValidateAndMigrateMinutes = validateAndMigrateMinutes,
            DeletionMinutes = deletionMinutes,
            OrphanedCleanupMinutes = 120, // Default, not exposed in UI yet
            SchemaTruncateMinutes = schemaTruncateMinutes
        };

        await _configFileService.SaveJobTimeoutsConfigAsync(config);

        TempData["RestartRequired"] = true;
        TempData["JobTimeoutsMessage"] = "Job timeout settings saved. Restart required.";

        _logger.LogInformation("Job timeout settings updated by {User}: UploadProcessing={Upload}min, Validation={Validation}min, Migration={Migration}min",
            User.Identity?.Name, uploadProcessingMinutes, validationMinutes, migrationMinutes);
        await _appLogService.LogConfigChangeAsync("JobTimeouts", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveHttpServerConfig(
        int keepAliveTimeoutMinutes,
        int requestHeadersTimeoutMinutes)
    {
        // Validate and clamp values
        keepAliveTimeoutMinutes = Math.Clamp(keepAliveTimeoutMinutes, 5, 180);
        requestHeadersTimeoutMinutes = Math.Clamp(requestHeadersTimeoutMinutes, 5, 180);

        var config = new HttpServerFileConfig
        {
            KeepAliveTimeoutMinutes = keepAliveTimeoutMinutes,
            RequestHeadersTimeoutMinutes = requestHeadersTimeoutMinutes
        };

        await _configFileService.SaveHttpServerConfigAsync(config);

        TempData["RestartRequired"] = true;
        TempData["HttpServerMessage"] = "HTTP server settings saved. Restart required.";

        _logger.LogInformation("HTTP server settings updated by {User}: KeepAlive={KeepAlive}min, RequestHeaders={Headers}min",
            User.Identity?.Name, keepAliveTimeoutMinutes, requestHeadersTimeoutMinutes);
        await _appLogService.LogConfigChangeAsync("HttpServer", User.Identity?.Name, CancellationToken.None);

        return RedirectToAction(nameof(Configuration));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveVersionRequirementsConfig(
        string minExeVersion,
        string minDbVersion,
        CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            TempData["VersionRequirementsMessage"] = "SQL Server must be configured first.";
            return RedirectToAction(nameof(Configuration));
        }

        // Validate version formats (basic validation)
        minExeVersion = minExeVersion?.Trim() ?? string.Empty;
        minDbVersion = minDbVersion?.Trim() ?? string.Empty;

        if (string.IsNullOrEmpty(minExeVersion) && string.IsNullOrEmpty(minDbVersion))
        {
            TempData["VersionRequirementsMessage"] = "At least one version must be specified.";
            return RedirectToAction(nameof(Configuration));
        }

        try
        {
            var connectionString = _appSettings.SqlServer.BuildConnectionString();
            var updatedCount = 0;

            if (!string.IsNullOrEmpty(minExeVersion))
            {
                var success = await _versionService.UpdateVersionRequirementAsync(
                    connectionString,
                    "CollectNTFSPerm",
                    minExeVersion,
                    $"Updated by {User.Identity?.Name ?? "Unknown"} via web UI",
                    cancellationToken);
                if (success) updatedCount++;
            }

            if (!string.IsNullOrEmpty(minDbVersion))
            {
                var success = await _versionService.UpdateVersionRequirementAsync(
                    connectionString,
                    "DBVersion",
                    minDbVersion,
                    $"Updated by {User.Identity?.Name ?? "Unknown"} via web UI",
                    cancellationToken);
                if (success) updatedCount++;
            }

            if (updatedCount > 0)
            {
                TempData["VersionRequirementsMessage"] = $"Version requirements updated successfully ({updatedCount} entries).";
                _logger.LogInformation("Version requirements updated by {User}: MinExe={MinExe}, MinDb={MinDb}",
                    User.Identity?.Name, minExeVersion, minDbVersion);
                await _appLogService.LogConfigChangeAsync("VersionRequirements", User.Identity?.Name, cancellationToken);
            }
            else
            {
                TempData["VersionRequirementsMessage"] = "No changes were made.";
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving version requirements");
            TempData["VersionRequirementsMessage"] = $"Error saving version requirements: {ex.Message}";
        }

        return RedirectToAction(nameof(Configuration));
    }

    public async Task<IActionResult> ApiKeys(CancellationToken cancellationToken)
    {
        var keys = await _apiKeyService.GetAllKeysAsync(cancellationToken);
        return View(keys);
    }

    [HttpPost]
    public async Task<IActionResult> GenerateApiKey(string description, DateTime? expiresAt, CancellationToken cancellationToken)
    {
        var userName = User.Identity?.Name ?? "Unknown";
        var (apiKey, plainTextKey) = await _apiKeyService.GenerateKeyAsync(description, userName, expiresAt, cancellationToken);

        TempData["NewApiKey"] = plainTextKey;
        TempData["NewApiKeyDescription"] = description;

        return RedirectToAction(nameof(ApiKeys));
    }

    [HttpPost]
    public async Task<IActionResult> RevokeApiKey(Guid id, CancellationToken cancellationToken)
    {
        await _apiKeyService.RevokeKeyAsync(id, cancellationToken);
        return RedirectToAction(nameof(ApiKeys));
    }

    [HttpPost]
    public async Task<IActionResult> DeleteApiKey(Guid id, CancellationToken cancellationToken)
    {
        await _apiKeyService.DeleteKeyAsync(id, cancellationToken);
        return RedirectToAction(nameof(ApiKeys));
    }

    /// <summary>
    /// Logging configuration page - Admin only.
    /// </summary>
    [HttpGet]
    public IActionResult Logging()
    {
        var model = new LoggingConfigViewModel
        {
            EnableExtendedLogging = _appSettings.Logging.EnableExtendedLogging,
            EnableRequestLogging = _appSettings.Logging.EnableRequestLogging,
            EnablePerformanceLogging = _appSettings.Logging.EnablePerformanceLogging,
            PerformanceThresholdMs = _appSettings.Logging.PerformanceThresholdMs,
            EnableUploadDiagnostics = _appSettings.Logging.EnableUploadDiagnostics,
            UploadProgressIntervalMB = _appSettings.Logging.UploadProgressIntervalMB,
            UploadProgressIntervalPercent = _appSettings.Logging.UploadProgressIntervalPercent,
            FileLogRetentionDays = _appSettings.Logging.FileLogRetentionDays,
            DatabaseLogRetentionDays = _appSettings.Logging.DatabaseLogRetentionDays
        };

        return View(model);
    }

    /// <summary>
    /// Save logging configuration.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveLoggingConfig(LoggingConfigViewModel model, CancellationToken cancellationToken)
    {
        try
        {
            // Update in-memory settings
            _appSettings.Logging.EnableExtendedLogging = model.EnableExtendedLogging;
            _appSettings.Logging.EnableRequestLogging = model.EnableRequestLogging;
            _appSettings.Logging.EnablePerformanceLogging = model.EnablePerformanceLogging;
            _appSettings.Logging.PerformanceThresholdMs = model.PerformanceThresholdMs;
            _appSettings.Logging.EnableUploadDiagnostics = model.EnableUploadDiagnostics;
            _appSettings.Logging.UploadProgressIntervalMB = model.UploadProgressIntervalMB;
            _appSettings.Logging.UploadProgressIntervalPercent = model.UploadProgressIntervalPercent;
            _appSettings.Logging.FileLogRetentionDays = model.FileLogRetentionDays;
            _appSettings.Logging.DatabaseLogRetentionDays = model.DatabaseLogRetentionDays;

            // Persist to configuration file
            await _configFileService.SaveLoggingSettingsAsync(
                model.EnableExtendedLogging,
                model.EnableRequestLogging,
                model.EnablePerformanceLogging,
                model.PerformanceThresholdMs,
                model.EnableUploadDiagnostics,
                model.UploadProgressIntervalMB,
                model.UploadProgressIntervalPercent,
                model.FileLogRetentionDays,
                model.DatabaseLogRetentionDays,
                cancellationToken);

            var userName = User.Identity?.Name ?? "Unknown";
            await _appLogService.LogConfigChangeAsync("Logging", userName, cancellationToken);

            _logger.LogInformation("Logging configuration updated by {User}. ExtendedLogging={Extended}, RequestLogging={Request}, PerformanceLogging={Perf}, UploadDiagnostics={Upload}",
                userName, model.EnableExtendedLogging, model.EnableRequestLogging, model.EnablePerformanceLogging, model.EnableUploadDiagnostics);

            TempData["Success"] = "Logging configuration saved successfully.";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving logging configuration");
            TempData["Error"] = $"Error saving configuration: {ex.Message}";
        }

        return RedirectToAction(nameof(Logging));
    }

    /// <summary>
    /// Uploads list.
    /// </summary>
    public async Task<IActionResult> Uploads(int page = 1, string? status = null, CancellationToken cancellationToken = default)
    {
        const int pageSize = 50;
        var skip = (page - 1) * pageSize;

        var uploads = await _uploadRepository.GetAllAsync(skip, pageSize, status, cancellationToken);
        var total = await _uploadRepository.GetCountAsync(status, null, cancellationToken);

        var model = new UploadsViewModel
        {
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
                UploadType = u.UploadType
            }).ToList(),
            Page = page,
            PageSize = pageSize,
            TotalItems = total,
            StatusFilter = status
        };

        return View(model);
    }

    /// <summary>
    /// Restarts a failed or cancelled upload by re-queuing it for processing.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> RestartUpload(Guid uploadId, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Admin requesting restart of upload {UploadId}", uploadId);

        var uploadService = HttpContext.RequestServices.GetRequiredService<IUploadService>();
        var result = await uploadService.RestartUploadAsync(uploadId, cancellationToken);

        if (result.Success)
        {
            TempData["SuccessMessage"] = $"Upload restarted successfully. Queue position: {result.QueuePosition}";
        }
        else
        {
            TempData["ErrorMessage"] = result.ErrorMessage ?? "Failed to restart upload.";
        }

        return RedirectToAction(nameof(Uploads));
    }

    /// <summary>
    /// Application logs view.
    /// </summary>
    public async Task<IActionResult> Logs(
        [FromQuery] string? severity = null,
        [FromQuery] string? category = null,
        [FromQuery] string? search = null,
        [FromQuery] Guid? uploadId = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 100,
        [FromQuery] string sortBy = "Timestamp",
        [FromQuery] bool descending = true,
        CancellationToken cancellationToken = default)
    {
        var isDbConfigured = _appSettings.SqlServer.IsConfigured;

        var model = new LogsViewModel
        {
            Page = page,
            PageSize = pageSize,
            SeverityFilter = severity,
            CategoryFilter = category,
            SearchFilter = search,
            UploadIdFilter = uploadId,
            SortBy = sortBy,
            Descending = descending,
            IsDbConfigured = isDbConfigured
        };

        if (!isDbConfigured)
        {
            return View(model);
        }

        try
        {
            var query = _dbContext.Logs.AsQueryable();

            // Apply filters
            if (!string.IsNullOrEmpty(severity))
            {
                query = query.Where(l => l.SeverityName == severity);
            }

            if (!string.IsNullOrEmpty(category))
            {
                query = query.Where(l => l.Category == category);
            }

            if (!string.IsNullOrEmpty(search))
            {
                query = query.Where(l => l.Message.Contains(search) ||
                    (l.MessageId != null && l.MessageId.Contains(search)));
            }

            if (uploadId.HasValue)
            {
                query = query.Where(l => l.UploadId == uploadId.Value);
            }

            // Get total count
            model.TotalItems = await query.CountAsync(cancellationToken);

            // Apply sorting
            query = sortBy.ToLowerInvariant() switch
            {
                "severity" or "severityname" => descending
                    ? query.OrderByDescending(l => l.Severity)
                    : query.OrderBy(l => l.Severity),
                "category" => descending
                    ? query.OrderByDescending(l => l.Category)
                    : query.OrderBy(l => l.Category),
                "message" => descending
                    ? query.OrderByDescending(l => l.Message)
                    : query.OrderBy(l => l.Message),
                "hostname" => descending
                    ? query.OrderByDescending(l => l.Hostname)
                    : query.OrderBy(l => l.Hostname),
                _ => descending
                    ? query.OrderByDescending(l => l.Timestamp)
                    : query.OrderBy(l => l.Timestamp)
            };

            // Apply pagination
            var logs = await query
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(l => new LogItem
                {
                    LogId = l.LogId,
                    Timestamp = l.Timestamp,
                    SeverityName = l.SeverityName,
                    Hostname = l.Hostname,
                    MessageId = l.MessageId,
                    UploadId = l.UploadId,
                    UserId = l.UserId,
                    SourceIP = l.SourceIP,
                    Category = l.Category,
                    Message = l.Message,
                    Exception = l.Exception
                })
                .ToListAsync(cancellationToken);

            model.Logs = logs;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching logs from database");
            model.Logs = new List<LogItem>();
        }

        return View(model);
    }

    /// <summary>
    /// Get logs API endpoint.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetLogs(
        [FromQuery] string? severity = null,
        [FromQuery] string? category = null,
        [FromQuery] string? search = null,
        [FromQuery] Guid? uploadId = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 100,
        [FromQuery] string sortBy = "Timestamp",
        [FromQuery] bool descending = true,
        CancellationToken cancellationToken = default)
    {
        var isDbConfigured = _appSettings.SqlServer.IsConfigured;

        if (!isDbConfigured)
        {
            return Json(new { success = false, error = "Database not configured" });
        }

        try
        {
            var query = _dbContext.Logs.AsQueryable();

            // Apply filters
            if (!string.IsNullOrEmpty(severity))
            {
                query = query.Where(l => l.SeverityName == severity);
            }

            if (!string.IsNullOrEmpty(category))
            {
                query = query.Where(l => l.Category == category);
            }

            if (!string.IsNullOrEmpty(search))
            {
                query = query.Where(l => l.Message.Contains(search) ||
                    (l.MessageId != null && l.MessageId.Contains(search)));
            }

            if (uploadId.HasValue)
            {
                query = query.Where(l => l.UploadId == uploadId.Value);
            }

            // Get total count
            var totalItems = await query.CountAsync(cancellationToken);

            // Apply sorting
            query = sortBy.ToLowerInvariant() switch
            {
                "severity" or "severityname" => descending
                    ? query.OrderByDescending(l => l.Severity)
                    : query.OrderBy(l => l.Severity),
                "category" => descending
                    ? query.OrderByDescending(l => l.Category)
                    : query.OrderBy(l => l.Category),
                "message" => descending
                    ? query.OrderByDescending(l => l.Message)
                    : query.OrderBy(l => l.Message),
                "hostname" => descending
                    ? query.OrderByDescending(l => l.Hostname)
                    : query.OrderBy(l => l.Hostname),
                _ => descending
                    ? query.OrderByDescending(l => l.Timestamp)
                    : query.OrderBy(l => l.Timestamp)
            };

            // Apply pagination
            var logs = await query
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(l => new
                {
                    l.LogId,
                    l.Timestamp,
                    l.SeverityName,
                    l.Hostname,
                    l.MessageId,
                    l.UploadId,
                    l.UserId,
                    l.SourceIP,
                    l.Category,
                    l.Message,
                    l.Exception
                })
                .ToListAsync(cancellationToken);

            var totalPages = (int)Math.Ceiling(totalItems / (double)pageSize);

            return Json(new
            {
                success = true,
                logs,
                page,
                pageSize,
                totalItems,
                totalPages
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching logs from database");
            return Json(new { success = false, error = "Error fetching logs" });
        }
    }

    /// <summary>
    /// Orphaned data view.
    /// </summary>
    public async Task<IActionResult> OrphanedData(CancellationToken cancellationToken)
    {
        var orphaned = await _migrationService.GetOrphanedInventoriesAsync(cancellationToken);

        var model = new OrphanedDataViewModel
        {
            Inventories = orphaned.Select(o => new OrphanedInventoryItem
            {
                InventoryId = o.InventoryId,
                ComputerName = o.ComputerName,
                ScanPath = o.ScanPath,
                CollectionDateTime = o.CollectionDateTime,
                FoldersCount = o.FoldersCount,
                FilesCount = o.FilesCount,
                PermissionsCount = o.PermissionsCount
            }).ToList()
        };

        if (TempData["Success"] != null)
        {
            model.SuccessMessage = TempData["Success"]?.ToString();
        }
        if (TempData["Error"] != null)
        {
            model.ErrorMessage = TempData["Error"]?.ToString();
        }

        return View(model);
    }

    /// <summary>
    /// Cleanup single orphaned inventory.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    public IActionResult CleanupOrphanedInventory(Guid id)
    {
        var userName = User.Identity?.Name ?? "Unknown";
        _logger.LogInformation("User {User} queuing cleanup job for orphaned inventory {InventoryId}", userName, id);

        // Enqueue background job for cleanup
        var jobId = _backgroundJobClient.Enqueue<IOrphanedDataCleanupJob>(
            job => job.CleanupOrphanedInventoryAsync(id, userName, CancellationToken.None));

        TempData["Success"] = $"Cleanup job queued for inventory (Job ID: {jobId}). Check Hangfire dashboard for progress.";
        TempData["CleanupJobId"] = jobId;
        TempData["CleanupInventoryId"] = id.ToString();

        return RedirectToAction(nameof(OrphanedData));
    }

    /// <summary>
    /// Cleanup all orphaned inventories.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    public IActionResult CleanupAllOrphanedInventories()
    {
        var userName = User.Identity?.Name ?? "Unknown";
        _logger.LogInformation("User {User} queuing cleanup job for all orphaned inventories", userName);

        // Enqueue background job for cleanup
        var jobId = _backgroundJobClient.Enqueue<IOrphanedDataCleanupJob>(
            job => job.CleanupAllOrphanedInventoriesAsync(userName, CancellationToken.None));

        TempData["Success"] = $"Cleanup job queued for all orphaned inventories (Job ID: {jobId}). Check Hangfire dashboard for progress.";
        TempData["CleanupAllJobId"] = jobId;

        return RedirectToAction(nameof(OrphanedData));
    }

    #region Banner Messages

    /// <summary>
    /// Banner messages list.
    /// </summary>
    public async Task<IActionResult> BannerMessages(CancellationToken cancellationToken)
    {
        var messages = await _bannerMessageService.GetAllAsync(cancellationToken);

        var model = new BannerMessagesViewModel
        {
            IsDbConfigured = _appSettings.SqlServer.IsConfigured,
            Messages = messages.Select(m => new BannerMessageItem
            {
                BannerMessageId = m.BannerMessageId,
                Title = m.Title,
                Message = m.Message,
                MessageType = m.MessageType,
                IsEnabled = m.IsEnabled,
                DisplayOrder = m.DisplayOrder,
                StartDate = m.StartDate,
                EndDate = m.EndDate,
                CreatedBy = m.CreatedBy,
                CreatedAt = m.CreatedAt,
                LastModifiedBy = m.LastModifiedBy,
                LastModifiedAt = m.LastModifiedAt
            }).ToList()
        };

        return View(model);
    }

    /// <summary>
    /// Create banner message.
    /// </summary>
    public IActionResult CreateBannerMessage()
    {
        var model = new BannerMessageFormViewModel
        {
            IsEnabled = true,
            DisplayOrder = 0,
            MessageType = "Info"
        };
        return View("BannerMessageForm", model);
    }

    /// <summary>
    /// Edit banner message.
    /// </summary>
    public async Task<IActionResult> EditBannerMessage(Guid id, CancellationToken cancellationToken)
    {
        var message = await _bannerMessageService.GetByIdAsync(id, cancellationToken);
        if (message == null)
        {
            TempData["Error"] = "Banner message not found.";
            return RedirectToAction(nameof(BannerMessages));
        }

        var model = new BannerMessageFormViewModel
        {
            BannerMessageId = message.BannerMessageId,
            Title = message.Title,
            Message = message.Message,
            MessageType = message.MessageType,
            IsEnabled = message.IsEnabled,
            DisplayOrder = message.DisplayOrder,
            StartDate = message.StartDate,
            EndDate = message.EndDate
        };

        return View("BannerMessageForm", model);
    }

    /// <summary>
    /// Save banner message.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SaveBannerMessage(BannerMessageFormViewModel model, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(model.Title))
        {
            TempData["Error"] = "Title is required.";
            return View("BannerMessageForm", model);
        }

        if (string.IsNullOrWhiteSpace(model.Message))
        {
            TempData["Error"] = "Message is required.";
            return View("BannerMessageForm", model);
        }

        var userName = User.Identity?.Name ?? "Unknown";

        try
        {
            if (model.IsEdit)
            {
                await _bannerMessageService.UpdateAsync(
                    model.BannerMessageId!.Value,
                    model.Title,
                    model.Message,
                    model.MessageType,
                    model.IsEnabled,
                    model.DisplayOrder,
                    model.StartDate,
                    model.EndDate,
                    userName,
                    cancellationToken);

                TempData["Success"] = "Banner message updated successfully.";
            }
            else
            {
                await _bannerMessageService.CreateAsync(
                    model.Title,
                    model.Message,
                    model.MessageType,
                    model.IsEnabled,
                    model.DisplayOrder,
                    model.StartDate,
                    model.EndDate,
                    userName,
                    cancellationToken);

                TempData["Success"] = "Banner message created successfully.";
            }

            await _appLogService.LogConfigChangeAsync("BannerMessages", userName, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving banner message");
            TempData["Error"] = $"Error saving banner message: {ex.Message}";
            return View("BannerMessageForm", model);
        }

        return RedirectToAction(nameof(BannerMessages));
    }

    /// <summary>
    /// Toggle banner message.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> ToggleBannerMessage(Guid id, bool enabled, CancellationToken cancellationToken)
    {
        var userName = User.Identity?.Name ?? "Unknown";

        var result = await _bannerMessageService.SetEnabledAsync(id, enabled, userName, cancellationToken);

        if (result)
        {
            TempData["Success"] = $"Banner message {(enabled ? "enabled" : "disabled")} successfully.";
            await _appLogService.LogConfigChangeAsync("BannerMessages", userName, cancellationToken);
        }
        else
        {
            TempData["Error"] = "Banner message not found.";
        }

        return RedirectToAction(nameof(BannerMessages));
    }

    /// <summary>
    /// Delete banner message.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> DeleteBannerMessage(Guid id, CancellationToken cancellationToken)
    {
        var userName = User.Identity?.Name ?? "Unknown";

        var result = await _bannerMessageService.DeleteAsync(id, cancellationToken);

        if (result)
        {
            TempData["Success"] = "Banner message deleted successfully.";
            await _appLogService.LogConfigChangeAsync("BannerMessages", userName, cancellationToken);
        }
        else
        {
            TempData["Error"] = "Banner message not found.";
        }

        return RedirectToAction(nameof(BannerMessages));
    }

    #endregion

    #region Maintenance

    public async Task<IActionResult> Maintenance(CancellationToken cancellationToken)
    {
        var model = new MaintenanceViewModel();

        if (!_appSettings.SqlServer.IsConfigured)
        {
            model.ErrorMessage = "Database is not configured.";
            return View(model);
        }

        try
        {
            var connectionString = _appSettings.SqlServer.BuildConnectionString();
            await using var connection = new Microsoft.Data.SqlClient.SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Define the schemas we want to show
            var schemaDefinitions = new[]
            {
                ("ADData", "AD Inventory - Production", "Production data for Active Directory inventory (merged data)", "danger"),
                ("ADImport", "AD Inventory - Staging", "Staging data for Active Directory imports (pending merge)", "warning"),
                ("fsapp", "NTFS Perms - Production", "Production data for NTFS permissions (merged data)", "danger"),
                ("fssimport", "NTFS Perms - Staging", "Staging data for NTFS permissions imports (pending merge)", "warning")
            };

            foreach (var (schemaName, displayName, description, styleClass) in schemaDefinitions)
            {
                var schemaInfo = new SchemaInfo
                {
                    SchemaName = schemaName,
                    DisplayName = displayName,
                    Description = description,
                    StyleClass = styleClass
                };

                // Get tables and row counts for this schema (exclude application tables)
                // Use SUM to aggregate row counts across all partitions for partitioned tables
                var tableQuery = @"
                    SELECT t.TABLE_NAME,
                           ISNULL(SUM(p.rows), 0) AS [RowCount]
                    FROM INFORMATION_SCHEMA.TABLES t
                    INNER JOIN sys.schemas s ON s.name = t.TABLE_SCHEMA
                    INNER JOIN sys.tables st ON st.name = t.TABLE_NAME AND st.schema_id = s.schema_id
                    LEFT JOIN sys.partitions p ON p.object_id = st.object_id AND p.index_id IN (0, 1)
                    WHERE t.TABLE_SCHEMA = @Schema AND t.TABLE_TYPE = 'BASE TABLE'
                      AND t.TABLE_NAME NOT IN ('SchemaVersion', 'Version')
                    GROUP BY t.TABLE_NAME
                    ORDER BY t.TABLE_NAME";

                await using var cmd = new Microsoft.Data.SqlClient.SqlCommand(tableQuery, connection);
                cmd.Parameters.AddWithValue("@Schema", schemaName);

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    schemaInfo.Tables.Add(new TableInfo
                    {
                        TableName = reader.GetString(0),
                        RowCount = reader.GetInt64(1)
                    });
                }

                schemaInfo.TableCount = schemaInfo.Tables.Count;
                schemaInfo.TotalRows = schemaInfo.Tables.Sum(t => t.RowCount);

                model.Schemas.Add(schemaInfo);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error loading maintenance data");
            model.ErrorMessage = $"Error loading schema information: {ex.Message}";
        }

        // Note: TempData["Success"] and TempData["Error"] are displayed by _Layout.cshtml
        // No need to copy them to the model

        return View(model);
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> TruncateSchema(string schemaName, CancellationToken cancellationToken)
    {
        var userName = User.Identity?.Name ?? "Unknown";
        var allowedSchemas = new[] { "ADData", "ADImport", "fsapp", "fssimport" };

        if (!allowedSchemas.Contains(schemaName))
        {
            TempData["Error"] = $"Invalid schema: {schemaName}";
            return RedirectToAction(nameof(Maintenance));
        }

        if (!_appSettings.SqlServer.IsConfigured)
        {
            TempData["Error"] = "Database is not configured.";
            return RedirectToAction(nameof(Maintenance));
        }

        _logger.LogWarning("User {User} initiating truncate of schema {Schema}", userName, schemaName);

        // Enqueue background job for truncation (handles large tables with batched deletes)
        var jobId = _backgroundJobClient.Enqueue<ISchemaTruncateJob>(
            job => job.TruncateSchemaAsync(schemaName, userName, CancellationToken.None));

        await _appLogService.LogConfigChangeAsync($"TruncateSchema:{schemaName}:JobId:{jobId}", userName, cancellationToken);

        // Store the progress ID for the UI to track
        var progressId = SchemaTruncateJob.GetProgressId(schemaName);
        TempData["Success"] = $"Truncation job queued (Job ID: {jobId}). Progress will be shown below.";
        TempData["TruncatingSchema"] = schemaName;
        TempData["TruncatingProgressId"] = progressId.ToString();

        return RedirectToAction(nameof(Maintenance));
    }

    #endregion

    #region Production Collections

    public async Task<IActionResult> ProductionCollections(CancellationToken cancellationToken)
    {
        if (!_appSettings.SqlServer.IsConfigured)
        {
            return View(new ProductionCollectionsViewModel
            {
                ErrorMessage = "Database is not configured."
            });
        }

        var ntfsCollections = await _productionDataService.GetNtfsCollectionsAsync(cancellationToken);
        var adCollections = await _productionDataService.GetAdCollectionsAsync(cancellationToken);

        // Get list of collections with active/pending deletion jobs
        var activeDeletionIds = _productionDataService.GetActiveDeletionIds();

        var model = new ProductionCollectionsViewModel
        {
            NtfsCollections = ntfsCollections,
            AdCollections = adCollections,
            ActiveDeletionIds = activeDeletionIds
        };

        if (TempData["Success"] != null)
        {
            model.SuccessMessage = TempData["Success"]?.ToString();
        }
        if (TempData["Error"] != null)
        {
            model.ErrorMessage = TempData["Error"]?.ToString();
        }

        return View(model);
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
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

        return RedirectToAction(nameof(ProductionCollections));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
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

        return RedirectToAction(nameof(ProductionCollections));
    }

    #endregion

    #region Chunked Uploads

    /// <summary>
    /// Shows active chunked upload sessions.
    /// </summary>
    public async Task<IActionResult> ChunkedUploads(CancellationToken cancellationToken)
    {
        var activeUploads = await _chunkedUploadService.GetActiveUploadsAsync(cancellationToken);

        var model = new ChunkedUploadsViewModel
        {
            ActiveUploads = activeUploads,
            TotalActiveSessions = activeUploads.Count,
            TotalPendingBytes = activeUploads.Sum(u => u.FileSize - (long)(u.PercentComplete / 100.0 * u.FileSize)),
            Settings = _appSettings.ChunkedUpload
        };

        return View(model);
    }

    /// <summary>
    /// Cancels an active chunked upload session.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> CancelChunkedUpload(Guid uploadId, CancellationToken cancellationToken)
    {
        var userName = User.Identity?.Name ?? "Unknown";

        _logger.LogWarning("Admin {User} cancelling chunked upload {UploadId}", userName, uploadId);

        var (success, bytesFreed) = await _chunkedUploadService.CancelAsync(uploadId, cancellationToken);

        if (success)
        {
            await _appLogService.LogConfigChangeAsync($"CancelChunkedUpload:{uploadId}:BytesFreed:{bytesFreed}", userName, cancellationToken);
            TempData["Success"] = $"Chunked upload cancelled. Freed {ChunkedUploadsViewModel.FormatBytes(bytesFreed)}.";
        }
        else
        {
            TempData["Error"] = "Failed to cancel chunked upload.";
        }

        return RedirectToAction(nameof(ChunkedUploads));
    }

    #endregion
}
