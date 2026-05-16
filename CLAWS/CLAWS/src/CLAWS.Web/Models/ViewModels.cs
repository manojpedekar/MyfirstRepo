using System.Text.Json.Serialization;

namespace CLAWS.Web.Models;

/// <summary>
/// Metadata for the CollectNTFSPerms download bundle.
/// </summary>
public class CollectNTFSPermsMetadata
{
    /// <summary>
    /// Version of the CollectNTFSPerms tool.
    /// </summary>
    [JsonPropertyName("version")]
    public string? Version { get; set; }

    /// <summary>
    /// Release date of this version.
    /// </summary>
    [JsonPropertyName("releasedate")]
    public DateTime? ReleaseDate { get; set; }
}

/// <summary>
/// Metadata for the ADInventory download bundle.
/// </summary>
public class ADInventoryMetadata
{
    /// <summary>
    /// Version of the ADInventory tool.
    /// </summary>
    [JsonPropertyName("version")]
    public string? Version { get; set; }

    /// <summary>
    /// Release date of this version.
    /// </summary>
    [JsonPropertyName("releasedate")]
    public DateTime? ReleaseDate { get; set; }
}

/// <summary>
/// View model for the home page.
/// </summary>
public class HomeViewModel
{
    /// <summary>
    /// Whether the database is configured.
    /// </summary>
    public bool IsDbConfigured { get; set; }

    /// <summary>
    /// Whether authorization groups are configured.
    /// </summary>
    public bool IsAuthConfigured { get; set; }

    /// <summary>
    /// Whether storage is using the application directory.
    /// </summary>
    public bool IsUsingAppDirectory { get; set; }

    /// <summary>
    /// Whether the CollectNTFSPerms download bundle is available.
    /// </summary>
    public bool IsDownloadAvailable { get; set; }

    /// <summary>
    /// Metadata for the CollectNTFSPerms download (version, release date).
    /// </summary>
    public CollectNTFSPermsMetadata? DownloadMetadata { get; set; }

    /// <summary>
    /// Whether the ADInventory download bundle is available.
    /// </summary>
    public bool IsADInventoryDownloadAvailable { get; set; }

    /// <summary>
    /// Metadata for the ADInventory download (version, release date).
    /// </summary>
    public ADInventoryMetadata? ADInventoryMetadata { get; set; }
}

/// <summary>
/// View model for the upload page.
/// </summary>
public class UploadViewModel : HomeViewModel
{
    /// <summary>
    /// Maximum file size in bytes.
    /// </summary>
    public long MaxFileSizeBytes { get; set; }

    /// <summary>
    /// Maximum file size in MB.
    /// </summary>
    public double MaxFileSizeMB { get; set; }

    /// <summary>
    /// Whether automatic validation is enabled globally.
    /// </summary>
    public bool EnableAutomaticValidation { get; set; }

    /// <summary>
    /// Whether automatic merge is enabled globally.
    /// </summary>
    public bool EnableAutomaticMerge { get; set; }
}

/// <summary>
/// View model for error pages.
/// </summary>
public class ErrorViewModel
{
    /// <summary>
    /// Request ID for tracking.
    /// </summary>
    public string? RequestId { get; set; }

    /// <summary>
    /// Whether to show the request ID.
    /// </summary>
    public bool ShowRequestId => !string.IsNullOrEmpty(RequestId);
}

/// <summary>
/// View model for upload status.
/// </summary>
public class StatusViewModel
{
    /// <summary>
    /// Whether the database is configured.
    /// </summary>
    public bool IsDbConfigured { get; set; }

    /// <summary>
    /// Whether authorization groups are configured.
    /// </summary>
    public bool IsAuthConfigured { get; set; }

    /// <summary>
    /// List of uploads.
    /// </summary>
    public List<UploadItem> Uploads { get; set; } = new();
}

/// <summary>
/// Upload item for status display.
/// </summary>
public class UploadItem
{
    public Guid UploadId { get; set; }
    public string OriginalFilename { get; set; } = string.Empty;
    public long FileSizeBytes { get; set; }
    public string Status { get; set; } = string.Empty;
    public string? StatusMessage { get; set; }
    public DateTime UploadedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public int? ImportProgress { get; set; }
    public string? CurrentPhase { get; set; }
    public string UploadedBy { get; set; } = string.Empty;

    // Upload type (NTFSPermissions or ADInventory)
    public string? UploadType { get; set; }

    // Total records imported (for display in summary)
    public long? TotalRecordsImported { get; set; }

    // Validation and merge status
    public string ValidationStatus { get; set; } = "NotValidated";
    public string? ValidationMessage { get; set; }
    public DateTime? ValidationCompletedAt { get; set; }
    public string MergeStatus { get; set; } = "NotMerged";
    public string? MergeMessage { get; set; }
    public DateTime? MergeCompletedAt { get; set; }

    // Auto-processing settings
    public string? AutoProcessingOverride { get; set; }

    // Error details (for failed uploads)
    public string? ErrorDetails { get; set; }

    /// <summary>
    /// Indicates if the failure was due to duplicate InventoryIDs.
    /// </summary>
    public bool IsDuplicateError => StatusMessage?.Contains("duplicate", StringComparison.OrdinalIgnoreCase) ?? false;

    /// <summary>
    /// Path to the upload file (for checking if restart is possible).
    /// </summary>
    public string? FilePath { get; set; }

    /// <summary>
    /// Indicates if this upload can be restarted (failed/cancelled with file still present).
    /// </summary>
    public bool CanRestart => Status is "Failed" or "Cancelled";

    // List of inventories in this upload (for NTFSPermissions)
    public List<InventoryItem> Inventories { get; set; } = new();

    // List of domain collections in this upload (for ADInventory)
    public List<DomainCollectionItem> DomainCollections { get; set; } = new();
}

/// <summary>
/// Inventory item for display within an upload.
/// </summary>
public class InventoryItem
{
    public Guid InventoryId { get; set; }
    public string? ComputerName { get; set; }
    public string? ScanPath { get; set; }
    public DateTime? CollectionDateTime { get; set; }
    public long TotalRecords { get; set; }
}

/// <summary>
/// Domain collection item for ADInventory uploads.
/// </summary>
public class DomainCollectionItem
{
    public Guid InventoryId { get; set; }
    public Guid CollectionId { get; set; }
    public string DomainName { get; set; } = string.Empty;
    public DateTime? CollectionDateTime { get; set; }
    public long TotalRecords { get; set; }
}

/// <summary>
/// View model for admin dashboard.
/// </summary>
public class AdminDashboardViewModel : HomeViewModel
{
    /// <summary>
    /// Total uploads count.
    /// </summary>
    public int TotalUploads { get; set; }

    /// <summary>
    /// Uploads in queue.
    /// </summary>
    public int QueuedUploads { get; set; }

    /// <summary>
    /// Active imports.
    /// </summary>
    public int ActiveImports { get; set; }

    /// <summary>
    /// Completed imports today.
    /// </summary>
    public int CompletedToday { get; set; }

    /// <summary>
    /// Failed imports today.
    /// </summary>
    public int FailedToday { get; set; }

    /// <summary>
    /// Disk space status.
    /// </summary>
    public DiskSpaceInfo DiskSpace { get; set; } = new();

    /// <summary>
    /// Recent uploads.
    /// </summary>
    public List<UploadItem> RecentUploads { get; set; } = new();
}

/// <summary>
/// Disk space information.
/// </summary>
public class DiskSpaceInfo
{
    public string DriveName { get; set; } = string.Empty;
    public string TotalFormatted { get; set; } = string.Empty;
    public string FreeFormatted { get; set; } = string.Empty;
    public string UsedFormatted { get; set; } = string.Empty;
    public double UsedPercent { get; set; }
    public bool IsWarning { get; set; }
    public bool IsCritical { get; set; }
}

/// <summary>
/// View model for SQL Server configuration.
/// </summary>
public class SqlServerConfigViewModel
{
    /// <summary>
    /// SQL Server hostname or IP address.
    /// </summary>
    public string Server { get; set; } = string.Empty;

    /// <summary>
    /// Database name.
    /// </summary>
    public string Database { get; set; } = string.Empty;

    /// <summary>
    /// Whether to use Windows Authentication.
    /// </summary>
    public bool UseWindowsAuth { get; set; } = true;

    /// <summary>
    /// SQL username (if not using Windows Auth).
    /// </summary>
    public string? Username { get; set; }

    /// <summary>
    /// SQL password (if not using Windows Auth).
    /// </summary>
    public string? Password { get; set; }

    /// <summary>
    /// Whether to trust the server certificate.
    /// </summary>
    public bool TrustServerCertificate { get; set; } = true;

    /// <summary>
    /// Encryption mode: Optional, Mandatory, or Strict.
    /// </summary>
    public string Encrypt { get; set; } = "Optional";

    /// <summary>
    /// Whether the current configuration is valid and connected.
    /// </summary>
    public bool IsConnected { get; set; }

    /// <summary>
    /// Connection test result message.
    /// </summary>
    public string? ConnectionTestMessage { get; set; }

    /// <summary>
    /// Whether a restart is required for changes to take effect.
    /// </summary>
    public bool RestartRequired { get; set; }
}

/// <summary>
/// View model for the configuration page.
/// </summary>
public class ConfigurationViewModel
{
    /// <summary>
    /// SQL Server configuration.
    /// </summary>
    public SqlServerConfigViewModel SqlServer { get; set; } = new();

    /// <summary>
    /// Import storage base path.
    /// </summary>
    public string StoragePath { get; set; } = string.Empty;

    /// <summary>
    /// AD group for site admin access (full access).
    /// </summary>
    public string SiteAdminGroup { get; set; } = string.Empty;

    /// <summary>
    /// AD group for NTFS Perms Admin access.
    /// </summary>
    public string NtfsPermsAdminGroup { get; set; } = string.Empty;

    /// <summary>
    /// AD group for AD Admin access.
    /// </summary>
    public string AdAdminGroup { get; set; } = string.Empty;

    /// <summary>
    /// Whether the database is currently configured.
    /// </summary>
    public bool IsDbConfigured { get; set; }

    /// <summary>
    /// Disk space monitoring configuration.
    /// </summary>
    public DiskSpaceConfigViewModel DiskSpace { get; set; } = new();

    /// <summary>
    /// Database performance configuration.
    /// </summary>
    public DatabasePerformanceConfigViewModel DatabasePerformance { get; set; } = new();

    /// <summary>
    /// Upload limits configuration.
    /// </summary>
    public UploadLimitsConfigViewModel UploadLimits { get; set; } = new();

    /// <summary>
    /// Import settings configuration.
    /// </summary>
    public ImportSettingsConfigViewModel ImportSettings { get; set; } = new();

    /// <summary>
    /// Cleanup settings configuration.
    /// </summary>
    public CleanupSettingsConfigViewModel CleanupSettings { get; set; } = new();

    /// <summary>
    /// Version requirements configuration (from SQL Server).
    /// </summary>
    public VersionRequirementsConfigViewModel VersionRequirements { get; set; } = new();

    /// <summary>
    /// LDAP authentication configuration.
    /// </summary>
    public LdapConfigViewModel Ldap { get; set; } = new();

    /// <summary>
    /// Cloud Integration validation configuration.
    /// </summary>
    public CloudIntegrationConfigViewModel CloudIntegration { get; set; } = new();

    /// <summary>
    /// Job timeout configuration.
    /// </summary>
    public JobTimeoutsConfigViewModel JobTimeouts { get; set; } = new();

    /// <summary>
    /// HTTP server configuration.
    /// </summary>
    public HttpServerConfigViewModel HttpServer { get; set; } = new();

    /// <summary>
    /// Chunked upload configuration.
    /// </summary>
    public ChunkedUploadConfigViewModel ChunkedUpload { get; set; } = new();
}

/// <summary>
/// View model for disk space monitoring configuration.
/// </summary>
public class DiskSpaceConfigViewModel
{
    /// <summary>
    /// Warning threshold as percentage of free space (0-100).
    /// </summary>
    public double WarningThresholdPercent { get; set; } = 20.0;

    /// <summary>
    /// Critical threshold as percentage of free space (0-100).
    /// </summary>
    public double CriticalThresholdPercent { get; set; } = 10.0;
}

/// <summary>
/// View model for database performance configuration.
/// </summary>
public class DatabasePerformanceConfigViewModel
{
    /// <summary>
    /// Command timeout in minutes for validation and migration operations.
    /// </summary>
    public int CommandTimeoutMinutes { get; set; } = 30;

    /// <summary>
    /// Connection timeout in seconds for initial database connection.
    /// </summary>
    public int ConnectionTimeoutSeconds { get; set; } = 30;

    /// <summary>
    /// Batch size for bulk import operations (records per batch).
    /// </summary>
    public int ImportBatchSize { get; set; } = 10000;

    /// <summary>
    /// Maximum number of concurrent extraction operations.
    /// </summary>
    public int MaxConcurrentExtractions { get; set; } = 2;

    /// <summary>
    /// Batch size for production collection deletion operations (records per batch).
    /// </summary>
    public int DeletionBatchSize { get; set; } = 50000;

    /// <summary>
    /// Timeout in seconds for each SqlBulkCopy batch operation.
    /// </summary>
    public int BulkCopyTimeoutSeconds { get; set; } = 600;

    /// <summary>
    /// Whether table partitioning is enabled in the database.
    /// </summary>
    public bool PartitioningEnabled { get; set; } = false;

    /// <summary>
    /// Whether to automatically prepare partitions before import.
    /// </summary>
    public bool AutoPreparePartitions { get; set; } = true;
}

/// <summary>
/// View model for upload limits configuration.
/// </summary>
public class UploadLimitsConfigViewModel
{
    /// <summary>
    /// Maximum ZIP file size in GB.
    /// </summary>
    public double MaxUploadSizeGB { get; set; } = 3.0;

    /// <summary>
    /// Maximum extracted SQLite file size in GB.
    /// </summary>
    public double MaxExtractedSizeGB { get; set; } = 50.0;

    /// <summary>
    /// Minimum free disk space required in GB.
    /// </summary>
    public double MinFreeDiskSpaceGB { get; set; } = 50.0;

    /// <summary>
    /// Maximum compression ratio before rejecting (zip bomb protection).
    /// </summary>
    public double MaxCompressionRatio { get; set; } = 100.0;
}

/// <summary>
/// View model for import settings configuration.
/// </summary>
public class ImportSettingsConfigViewModel
{
    /// <summary>
    /// Transaction mode: PerTable, PerBatch, or PerCollection.
    /// </summary>
    public string TransactionMode { get; set; } = "PerTable";

    /// <summary>
    /// Action for duplicate InventoryIDs: Reject, Update, or Skip.
    /// </summary>
    public string DuplicateHandling { get; set; } = "Reject";

    /// <summary>
    /// Enable automatic validation after upload processing completes.
    /// </summary>
    public bool EnableAutomaticValidation { get; set; } = false;

    /// <summary>
    /// Enable automatic merge after validation passes.
    /// Requires EnableAutomaticValidation to be true.
    /// </summary>
    public bool EnableAutomaticMerge { get; set; } = false;

    /// <summary>
    /// SQLite integrity check mode: Full, Quick, None, or Auto.
    /// </summary>
    public string IntegrityCheckMode { get; set; } = "Quick";

    /// <summary>
    /// File size threshold in MB for Auto integrity check mode.
    /// Files larger than this use quick_check, smaller files use full integrity_check.
    /// </summary>
    public int AutoIntegrityCheckThresholdMB { get; set; } = 500;
}

/// <summary>
/// View model for cleanup settings configuration.
/// </summary>
public class CleanupSettingsConfigViewModel
{
    /// <summary>
    /// Enable automatic cleanup of completed folder.
    /// </summary>
    public bool AutoPruneCompleted { get; set; } = true;

    /// <summary>
    /// Days to retain files in completed folder.
    /// </summary>
    public int CompletedRetentionDays { get; set; } = 7;

    /// <summary>
    /// Days to retain files in errors folder (0 = never auto-delete).
    /// </summary>
    public int ErrorRetentionDays { get; set; } = 0;

    /// <summary>
    /// Days to retain orphaned files in extraction folder.
    /// </summary>
    public int ExtractionRetentionDays { get; set; } = 7;

    /// <summary>
    /// Enable automatic cleanup of old AD collections per domain.
    /// </summary>
    public bool AutoPruneAdCollections { get; set; } = true;

    /// <summary>
    /// Number of AD collections to keep per domain.
    /// </summary>
    public int AdCollectionsToKeepPerDomain { get; set; } = 3;

    /// <summary>
    /// Cron expression for AD collection cleanup schedule.
    /// </summary>
    public string AdCollectionPruneSchedule { get; set; } = "0 */6 * * *";
}

/// <summary>
/// View model for version requirements configuration (from fsapp.SchemaVersion table).
/// </summary>
public class VersionRequirementsConfigViewModel
{
    /// <summary>
    /// Minimum required CollectNTFSPerm EXE version.
    /// </summary>
    public string MinExeVersion { get; set; } = string.Empty;

    /// <summary>
    /// Minimum required database schema version.
    /// </summary>
    public string MinDbVersion { get; set; } = string.Empty;

    /// <summary>
    /// When the EXE version requirement was last updated.
    /// </summary>
    public DateTime? ExeVersionAppliedDate { get; set; }

    /// <summary>
    /// When the DB version requirement was last updated.
    /// </summary>
    public DateTime? DbVersionAppliedDate { get; set; }

    /// <summary>
    /// Description for the EXE version entry.
    /// </summary>
    public string? ExeVersionDescription { get; set; }

    /// <summary>
    /// Description for the DB version entry.
    /// </summary>
    public string? DbVersionDescription { get; set; }
}

/// <summary>
/// View model for job timeout configuration.
/// </summary>
public class JobTimeoutsConfigViewModel
{
    /// <summary>
    /// Upload processing job timeout in minutes.
    /// </summary>
    public int UploadProcessingMinutes { get; set; } = 120;

    /// <summary>
    /// Validation job timeout in minutes.
    /// </summary>
    public int ValidationMinutes { get; set; } = 120;

    /// <summary>
    /// Migration job timeout in minutes.
    /// </summary>
    public int MigrationMinutes { get; set; } = 120;

    /// <summary>
    /// Combined validation and migration job timeout in minutes.
    /// </summary>
    public int ValidateAndMigrateMinutes { get; set; } = 240;

    /// <summary>
    /// Deletion job timeout in minutes.
    /// </summary>
    public int DeletionMinutes { get; set; } = 60;

    /// <summary>
    /// Orphaned data cleanup job timeout in minutes.
    /// </summary>
    public int OrphanedCleanupMinutes { get; set; } = 120;

    /// <summary>
    /// Schema truncate job timeout in minutes.
    /// </summary>
    public int SchemaTruncateMinutes { get; set; } = 120;
}

/// <summary>
/// View model for HTTP server (Kestrel) configuration.
/// </summary>
public class HttpServerConfigViewModel
{
    /// <summary>
    /// Keep-alive timeout in minutes.
    /// </summary>
    public int KeepAliveTimeoutMinutes { get; set; } = 60;

    /// <summary>
    /// Request headers timeout in minutes.
    /// </summary>
    public int RequestHeadersTimeoutMinutes { get; set; } = 60;
}

/// <summary>
/// View model for chunked upload configuration.
/// </summary>
public class ChunkedUploadConfigViewModel
{
    /// <summary>
    /// Enable chunked upload support for large files.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Chunk size in MB.
    /// </summary>
    public int ChunkSizeMB { get; set; } = 50;

    /// <summary>
    /// File size threshold in MB above which chunked upload is used.
    /// </summary>
    public int ChunkedThresholdMB { get; set; } = 500;

    /// <summary>
    /// Maximum concurrent chunked uploads per user.
    /// </summary>
    public int MaxConcurrentUploadsPerUser { get; set; } = 2;

    /// <summary>
    /// Maximum concurrent chunked uploads system-wide.
    /// </summary>
    public int MaxConcurrentUploadsGlobal { get; set; } = 10;

    /// <summary>
    /// Maximum concurrent chunk uploads from client per session.
    /// </summary>
    public int MaxConcurrentChunksPerUpload { get; set; } = 3;

    /// <summary>
    /// Hours before incomplete chunked upload sessions expire.
    /// </summary>
    public int SessionExpirationHours { get; set; } = 6;

    /// <summary>
    /// Minutes before expiration to show warning.
    /// </summary>
    public int ExpirationWarningMinutes { get; set; } = 30;

    /// <summary>
    /// Maximum retries for individual chunk uploads.
    /// </summary>
    public int MaxChunkRetries { get; set; } = 3;
}

/// <summary>
/// View model for the all uploads page.
/// </summary>
public class UploadsViewModel
{
    /// <summary>
    /// List of uploads.
    /// </summary>
    public List<UploadItem> Uploads { get; set; } = new();

    /// <summary>
    /// Current page number.
    /// </summary>
    public int Page { get; set; } = 1;

    /// <summary>
    /// Page size.
    /// </summary>
    public int PageSize { get; set; } = 50;

    /// <summary>
    /// Total number of items.
    /// </summary>
    public int TotalItems { get; set; }

    /// <summary>
    /// Total number of pages.
    /// </summary>
    public int TotalPages => (int)Math.Ceiling(TotalItems / (double)PageSize);

    /// <summary>
    /// Status filter.
    /// </summary>
    public string? StatusFilter { get; set; }
}

/// <summary>
/// View model for the logs page.
/// </summary>
public class LogsViewModel
{
    /// <summary>
    /// List of log entries.
    /// </summary>
    public List<LogItem> Logs { get; set; } = new();

    /// <summary>
    /// Current page number.
    /// </summary>
    public int Page { get; set; } = 1;

    /// <summary>
    /// Page size.
    /// </summary>
    public int PageSize { get; set; } = 100;

    /// <summary>
    /// Total number of items.
    /// </summary>
    public int TotalItems { get; set; }

    /// <summary>
    /// Total number of pages.
    /// </summary>
    public int TotalPages => (int)Math.Ceiling(TotalItems / (double)PageSize);

    /// <summary>
    /// Severity filter.
    /// </summary>
    public string? SeverityFilter { get; set; }

    /// <summary>
    /// Category filter.
    /// </summary>
    public string? CategoryFilter { get; set; }

    /// <summary>
    /// Upload ID filter.
    /// </summary>
    public Guid? UploadIdFilter { get; set; }

    /// <summary>
    /// Search text filter for message content.
    /// </summary>
    public string? SearchFilter { get; set; }

    /// <summary>
    /// Sort column.
    /// </summary>
    public string SortBy { get; set; } = "Timestamp";

    /// <summary>
    /// Sort descending (default true for newest first).
    /// </summary>
    public bool Descending { get; set; } = true;

    /// <summary>
    /// Available severity levels for filtering.
    /// </summary>
    public List<string> AvailableSeverities { get; set; } = new() { "DEBUG", "INFO", "NOTICE", "WARNING", "ERROR", "CRITICAL", "ALERT", "EMERGENCY" };

    /// <summary>
    /// Available categories for filtering.
    /// </summary>
    public List<string> AvailableCategories { get; set; } = new() { "Upload", "Validation", "Import", "API", "ScheduledTask", "Security", "Configuration", "System" };

    /// <summary>
    /// Whether the database is configured.
    /// </summary>
    public bool IsDbConfigured { get; set; }
}

/// <summary>
/// Log item for display.
/// </summary>
public class LogItem
{
    public long LogId { get; set; }
    public DateTime Timestamp { get; set; }
    public string SeverityName { get; set; } = string.Empty;
    public string Hostname { get; set; } = string.Empty;
    public string? MessageId { get; set; }
    public Guid? UploadId { get; set; }
    public string? UserId { get; set; }
    public string? SourceIP { get; set; }
    public string? Category { get; set; }
    public string Message { get; set; } = string.Empty;
    public string? Exception { get; set; }
}

/// <summary>
/// View model for orphaned data cleanup page.
/// </summary>
public class OrphanedDataViewModel
{
    /// <summary>
    /// List of orphaned inventories.
    /// </summary>
    public List<OrphanedInventoryItem> Inventories { get; set; } = new();

    /// <summary>
    /// Success message to display.
    /// </summary>
    public string? SuccessMessage { get; set; }

    /// <summary>
    /// Error message to display.
    /// </summary>
    public string? ErrorMessage { get; set; }
}

/// <summary>
/// Orphaned inventory item for display.
/// </summary>
public class OrphanedInventoryItem
{
    public Guid InventoryId { get; set; }
    public string? ComputerName { get; set; }
    public string? ScanPath { get; set; }
    public DateTime? CollectionDateTime { get; set; }
    public long FoldersCount { get; set; }
    public long FilesCount { get; set; }
    public long PermissionsCount { get; set; }

    /// <summary>
    /// Total records (folders + files + permissions).
    /// </summary>
    public long TotalRecords => FoldersCount + FilesCount + PermissionsCount;
}

/// <summary>
/// View model for the banner messages management page.
/// </summary>
public class BannerMessagesViewModel
{
    /// <summary>
    /// List of all banner messages.
    /// </summary>
    public List<BannerMessageItem> Messages { get; set; } = new();

    /// <summary>
    /// Whether the database is configured.
    /// </summary>
    public bool IsDbConfigured { get; set; }

    /// <summary>
    /// Success message to display.
    /// </summary>
    public string? SuccessMessage { get; set; }

    /// <summary>
    /// Error message to display.
    /// </summary>
    public string? ErrorMessage { get; set; }
}

/// <summary>
/// Banner message item for display in admin list.
/// </summary>
public class BannerMessageItem
{
    public Guid BannerMessageId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public string MessageType { get; set; } = string.Empty;
    public bool IsEnabled { get; set; }
    public int DisplayOrder { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public string CreatedBy { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public string LastModifiedBy { get; set; } = string.Empty;
    public DateTime LastModifiedAt { get; set; }

    /// <summary>
    /// Whether the message is currently active (enabled and within date range).
    /// </summary>
    public bool IsActive
    {
        get
        {
            if (!IsEnabled) return false;
            var now = DateTime.UtcNow;
            if (StartDate.HasValue && StartDate > now) return false;
            if (EndDate.HasValue && EndDate < now) return false;
            return true;
        }
    }

    /// <summary>
    /// Bootstrap class for the message type.
    /// </summary>
    public string TypeCssClass => MessageType switch
    {
        "Info" => "info",
        "Warning" => "warning",
        "Error" => "danger",
        _ => "secondary"
    };

    /// <summary>
    /// Bootstrap icon for the message type.
    /// </summary>
    public string TypeIcon => MessageType switch
    {
        "Info" => "bi-info-circle",
        "Warning" => "bi-exclamation-triangle",
        "Error" => "bi-x-circle",
        _ => "bi-chat"
    };
}

/// <summary>
/// View model for creating or editing a banner message.
/// </summary>
public class BannerMessageFormViewModel
{
    /// <summary>
    /// Banner message ID (null for create, populated for edit).
    /// </summary>
    public Guid? BannerMessageId { get; set; }

    /// <summary>
    /// Short title for the banner.
    /// </summary>
    public string Title { get; set; } = string.Empty;

    /// <summary>
    /// Full message content.
    /// </summary>
    public string Message { get; set; } = string.Empty;

    /// <summary>
    /// Message type: Info, Warning, or Error.
    /// </summary>
    public string MessageType { get; set; } = "Info";

    /// <summary>
    /// Whether the banner is enabled.
    /// </summary>
    public bool IsEnabled { get; set; }

    /// <summary>
    /// Display order (lower = displayed first).
    /// </summary>
    public int DisplayOrder { get; set; }

    /// <summary>
    /// Optional start date for scheduled display.
    /// </summary>
    public DateTime? StartDate { get; set; }

    /// <summary>
    /// Optional end date for scheduled display.
    /// </summary>
    public DateTime? EndDate { get; set; }

    /// <summary>
    /// Whether this is an edit operation.
    /// </summary>
    public bool IsEdit => BannerMessageId.HasValue;
}

/// <summary>
/// View model for maintenance page.
/// </summary>
public class MaintenanceViewModel
{
    /// <summary>
    /// Schema information for each data store.
    /// </summary>
    public List<SchemaInfo> Schemas { get; set; } = new();

    /// <summary>
    /// Success message from last operation.
    /// </summary>
    public string? SuccessMessage { get; set; }

    /// <summary>
    /// Error message from last operation.
    /// </summary>
    public string? ErrorMessage { get; set; }
}

/// <summary>
/// Information about a database schema.
/// </summary>
public class SchemaInfo
{
    /// <summary>
    /// Schema name (e.g., "ADData", "fssimport").
    /// </summary>
    public string SchemaName { get; set; } = string.Empty;

    /// <summary>
    /// Display name for the schema.
    /// </summary>
    public string DisplayName { get; set; } = string.Empty;

    /// <summary>
    /// Description of what this schema contains.
    /// </summary>
    public string Description { get; set; } = string.Empty;

    /// <summary>
    /// Number of tables in this schema.
    /// </summary>
    public int TableCount { get; set; }

    /// <summary>
    /// Approximate total row count across all tables.
    /// </summary>
    public long TotalRows { get; set; }

    /// <summary>
    /// List of tables in this schema.
    /// </summary>
    public List<TableInfo> Tables { get; set; } = new();

    /// <summary>
    /// CSS class for styling (e.g., "danger", "warning").
    /// </summary>
    public string StyleClass { get; set; } = "secondary";
}

/// <summary>
/// Information about a database table.
/// </summary>
public class TableInfo
{
    /// <summary>
    /// Table name.
    /// </summary>
    public string TableName { get; set; } = string.Empty;

    /// <summary>
    /// Approximate row count.
    /// </summary>
    public long RowCount { get; set; }
}

/// <summary>
/// View model for LDAP authentication configuration.
/// </summary>
public class LdapConfigViewModel
{
    /// <summary>
    /// Whether LDAP authentication is enabled.
    /// </summary>
    public bool Enabled { get; set; } = false;

    /// <summary>
    /// LDAP server hostname (e.g., ldaps.ssnc-corp.global).
    /// </summary>
    public string Server { get; set; } = string.Empty;

    /// <summary>
    /// LDAP server port. Default is 636 for LDAPS, 389 for LDAP.
    /// </summary>
    public int Port { get; set; } = 636;

    /// <summary>
    /// Whether to use SSL/TLS (LDAPS). Default is true.
    /// </summary>
    public bool UseSsl { get; set; } = true;

    /// <summary>
    /// Base DN for user search (e.g., DC=ssnc-corp,DC=global).
    /// </summary>
    public string BaseDn { get; set; } = string.Empty;

    /// <summary>
    /// User search filter. Use {0} as placeholder for username.
    /// </summary>
    public string UserSearchFilter { get; set; } = "(sAMAccountName={0})";

    /// <summary>
    /// Domain prefix for authentication (e.g., SSNC-CORP).
    /// </summary>
    public string? Domain { get; set; }

    /// <summary>
    /// Connection timeout in seconds.
    /// </summary>
    public int ConnectionTimeout { get; set; } = 30;

    /// <summary>
    /// Whether to allow fallback to local Keymaster account when LDAP is unavailable.
    /// </summary>
    public bool AllowKeymasterFallback { get; set; } = true;

    /// <summary>
    /// Local Windows username for fallback authentication (default: Keymaster).
    /// </summary>
    public string KeymasterUsername { get; set; } = "Keymaster";
}

/// <summary>
/// View model for Cloud Integration validation configuration.
/// </summary>
public class CloudIntegrationConfigViewModel
{
    /// <summary>
    /// Whether Cloud Integration validation is enabled.
    /// </summary>
    public bool Enabled { get; set; } = false;

    /// <summary>
    /// Cron schedule for the daily validation job (default: 4 AM).
    /// </summary>
    public string Schedule { get; set; } = "0 4 * * *";

    /// <summary>
    /// LDAP search base for cloud integration OUs.
    /// </summary>
    public string LdapSearchBase { get; set; } = "OU=DirectoryList,OU=CloudUI,OU=Domain Delegation,DC=ssnc-corp,DC=global";

    /// <summary>
    /// LDAP server hostname for cloud integration queries.
    /// </summary>
    public string LdapServer { get; set; } = string.Empty;

    /// <summary>
    /// LDAP server port (default: 636 for LDAPS).
    /// </summary>
    public int LdapPort { get; set; } = 636;

    /// <summary>
    /// Whether to use SSL/TLS for LDAP connection.
    /// </summary>
    public bool LdapUseSsl { get; set; } = true;

    /// <summary>
    /// Service account username for LDAP queries.
    /// </summary>
    public string? ServiceAccountUsername { get; set; }

    /// <summary>
    /// Service account domain for LDAP queries.
    /// </summary>
    public string? ServiceAccountDomain { get; set; }

    /// <summary>
    /// Whether a service account password is configured (password not exposed).
    /// </summary>
    public bool HasServiceAccountPassword { get; set; }

    /// <summary>
    /// Connection timeout in seconds for LDAP queries.
    /// </summary>
    public int ConnectionTimeout { get; set; } = 30;

    /// <summary>
    /// Batch size for processing domains.
    /// </summary>
    public int BatchSize { get; set; } = 100;

    /// <summary>
    /// Delay between batches in milliseconds.
    /// </summary>
    public int DelayBetweenBatchesMs { get; set; } = 1000;
}

/// <summary>
/// Request model for testing Cloud Integration LDAP connection.
/// </summary>
public class CloudIntegrationTestRequest
{
    /// <summary>
    /// LDAP server hostname.
    /// </summary>
    public string LdapServer { get; set; } = string.Empty;

    /// <summary>
    /// LDAP server port.
    /// </summary>
    public int LdapPort { get; set; } = 636;

    /// <summary>
    /// Whether to use SSL/TLS.
    /// </summary>
    public bool LdapUseSsl { get; set; } = true;

    /// <summary>
    /// LDAP search base DN.
    /// </summary>
    public string LdapSearchBase { get; set; } = string.Empty;

    /// <summary>
    /// Service account domain.
    /// </summary>
    public string? ServiceAccountDomain { get; set; }

    /// <summary>
    /// Service account username.
    /// </summary>
    public string? ServiceAccountUsername { get; set; }

    /// <summary>
    /// Service account password (plain text for testing, not stored).
    /// </summary>
    public string? ServiceAccountPassword { get; set; }

    /// <summary>
    /// Connection timeout in seconds.
    /// </summary>
    public int ConnectionTimeout { get; set; } = 30;
}

/// <summary>
/// View model for the login page.
/// </summary>
public class LoginViewModel
{
    /// <summary>
    /// Username for authentication.
    /// </summary>
    public string Username { get; set; } = string.Empty;

    /// <summary>
    /// Password for authentication.
    /// </summary>
    public string Password { get; set; } = string.Empty;

    /// <summary>
    /// Whether to remember the user (persistent cookie).
    /// </summary>
    public bool RememberMe { get; set; } = false;

    /// <summary>
    /// URL to return to after successful login.
    /// </summary>
    public string? ReturnUrl { get; set; }

    /// <summary>
    /// Error message to display on the login page.
    /// </summary>
    public string? ErrorMessage { get; set; }

    /// <summary>
    /// Whether LDAP is configured and available.
    /// </summary>
    public bool IsLdapConfigured { get; set; }

    /// <summary>
    /// Whether Keymaster fallback is allowed.
    /// </summary>
    public bool AllowKeymasterFallback { get; set; }

    /// <summary>
    /// Configured domain for LDAP authentication.
    /// </summary>
    public string? Domain { get; set; }

    /// <summary>
    /// Keymaster username for fallback.
    /// </summary>
    public string KeymasterUsername { get; set; } = "Keymaster";

    /// <summary>
    /// Whether user is logging in as Keymaster.
    /// </summary>
    public bool UseKeymaster { get; set; }

    /// <summary>
    /// LDAP port (636 for LDAPS, 389 for LDAP).
    /// </summary>
    public int Port { get; set; } = 636;
}

/// <summary>
/// View model for the production collections management page.
/// </summary>
public class ProductionCollectionsViewModel
{
    /// <summary>
    /// NTFS Permissions collections from fsapp.CollectionInfo.
    /// </summary>
    public List<NtfsProductionCollectionItem> NtfsCollections { get; set; } = new();

    /// <summary>
    /// AD Inventory collections from ADData.CollectionInfo.
    /// </summary>
    public List<AdProductionCollectionItem> AdCollections { get; set; } = new();

    /// <summary>
    /// Success message to display.
    /// </summary>
    public string? SuccessMessage { get; set; }

    /// <summary>
    /// Error message to display.
    /// </summary>
    public string? ErrorMessage { get; set; }

    /// <summary>
    /// Total NTFS records across all collections.
    /// </summary>
    public long TotalNtfsRecords => NtfsCollections.Sum(c => c.TotalRecords);

    /// <summary>
    /// Total AD records across all collections.
    /// </summary>
    public long TotalAdRecords => AdCollections.Sum(c => c.TotalRecords);

    /// <summary>
    /// IDs of collections currently being deleted or queued for deletion.
    /// Used to show progress indicators and prevent duplicate deletion requests.
    /// </summary>
    public List<string> ActiveDeletionIds { get; set; } = new();
}

/// <summary>
/// NTFS Permissions production collection item (from fsapp.CollectionInfo).
/// </summary>
public class NtfsProductionCollectionItem
{
    public Guid InventoryId { get; set; }
    public string? ComputerName { get; set; }
    public string? ScanPath { get; set; }
    public DateTime? CollectionDateTime { get; set; }

    // Record counts
    public long FoldersCount { get; set; }
    public long AclCount { get; set; }
    public long AceCount { get; set; }
    public long SidsCount { get; set; }
    public long SmbSharesCount { get; set; }

    /// <summary>
    /// Total records in this collection.
    /// </summary>
    public long TotalRecords => FoldersCount + AclCount + AceCount + SidsCount + SmbSharesCount;

    /// <summary>
    /// Application version used for collection.
    /// </summary>
    public string? ExeVersion { get; set; }
}

/// <summary>
/// AD Inventory production collection item (from ADData.CollectionInfo).
/// </summary>
public class AdProductionCollectionItem
{
    /// <summary>
    /// The CollectionID (UNIQUEIDENTIFIER) for this collection.
    /// </summary>
    public Guid CollectionId { get; set; }
    public Guid? InventoryId { get; set; }
    public string? DomainName { get; set; }
    public string? ComputerName { get; set; }
    public DateTime? CollectionDateTime { get; set; }

    // Record counts
    public long ObjectCount { get; set; }
    public long GroupMembershipCount { get; set; }
    public long FspCount { get; set; }
    public long TrustCount { get; set; }
    public long FlatMembershipCount { get; set; }

    /// <summary>
    /// Total records in this collection.
    /// </summary>
    public long TotalRecords => ObjectCount + GroupMembershipCount + FspCount + TrustCount + FlatMembershipCount;
}

/// <summary>
/// View model for the NTFS Permissions production data page.
/// </summary>
public class NtfsPermissionsViewModel
{
    /// <summary>
    /// NTFS Permissions collections from fsapp.CollectionInfo.
    /// </summary>
    public List<NtfsProductionCollectionItem> Collections { get; set; } = new();

    /// <summary>
    /// Total records across all collections.
    /// </summary>
    public long TotalRecords => Collections.Sum(c => c.TotalRecords);

    /// <summary>
    /// IDs of collections currently being deleted or queued for deletion.
    /// </summary>
    public List<string> ActiveDeletionIds { get; set; } = new();

    /// <summary>
    /// Error message to display.
    /// </summary>
    public string? ErrorMessage { get; set; }
}

/// <summary>
/// View model for the AD Inventory production data page.
/// </summary>
public class AdInventoryViewModel
{
    /// <summary>
    /// AD Inventory collections from ADData.CollectionInfo.
    /// </summary>
    public List<AdProductionCollectionItem> Collections { get; set; } = new();

    /// <summary>
    /// Total records across all collections.
    /// </summary>
    public long TotalRecords => Collections.Sum(c => c.TotalRecords);

    /// <summary>
    /// IDs of collections currently being deleted or queued for deletion.
    /// </summary>
    public List<string> ActiveDeletionIds { get; set; } = new();

    /// <summary>
    /// Error message to display.
    /// </summary>
    public string? ErrorMessage { get; set; }
}

#region Domain Master List (DML)

/// <summary>
/// Lookup item for dropdowns (responsibility levels, tri-states, baseline status).
/// </summary>
public class DmlLookupItem
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public int SortOrder { get; set; }
}

/// <summary>
/// View model for the DML index page (domain list).
/// </summary>
public class DomainMasterListViewModel
{
    /// <summary>
    /// List of domains.
    /// </summary>
    public List<DomainMasterListItem> Domains { get; set; } = new();

    /// <summary>
    /// Total count of domains (including decommissioned).
    /// </summary>
    public int TotalCount { get; set; }

    /// <summary>
    /// Count of active (non-decommissioned) domains.
    /// </summary>
    public int ActiveCount { get; set; }

    /// <summary>
    /// Count of decommissioned domains.
    /// </summary>
    public int DecommissionedCount { get; set; }

    /// <summary>
    /// Whether to include decommissioned domains in the list.
    /// </summary>
    public bool IncludeDecommissioned { get; set; }

    /// <summary>
    /// Error message to display.
    /// </summary>
    public string? ErrorMessage { get; set; }

    /// <summary>
    /// Success message to display.
    /// </summary>
    public string? SuccessMessage { get; set; }
}

/// <summary>
/// Domain item for display in grid and detail views.
/// </summary>
public class DomainMasterListItem
{
    public int DomainID { get; set; }
    public string DomainName { get; set; } = string.Empty;
    public string? NetBIOSName { get; set; }
    public string? BusinessUnit { get; set; }

    // Responsibility level (FK and display)
    public int? DSResponsibilityLevelID { get; set; }
    public string? DSResponsibilityLevel { get; set; }

    // Boolean flags
    public bool IsThirdPartyManaged { get; set; }
    public bool IsDecommissioned { get; set; }
    public bool IsPatchHold { get; set; }
    public bool HasHealthCheck { get; set; }
    public bool HasNetwrixAuditor { get; set; }
    public bool IsSafeguardReady { get; set; }
    public bool IsClientFacing { get; set; }
    public bool IsSPLA { get; set; }
    public bool IsRegulated { get; set; }
    public bool MSPCustomer { get; set; }

    // Trust relationships (FK and display)
    public byte Trust_ADMgmt_TriStateID { get; set; } = 2;
    public string? Trust_ADMgmt { get; set; }
    public byte Trust_SSCViolet_TriStateID { get; set; } = 2;
    public string? Trust_SSCViolet { get; set; }
    public byte Trust_SSNC_Corp_TriStateID { get; set; } = 2;
    public string? Trust_SSNC_Corp { get; set; }

    // Cloud integration and baseline (FK and display)
    public byte IsCloudIntegrated { get; set; } = 2;
    public string? IsCloudIntegratedState { get; set; }
    public byte BaselineStatusID { get; set; } = 2;
    public string? BaselineStatus { get; set; }

    // Text fields
    public string? POC { get; set; }
    public string? Purpose { get; set; }
    public string? Roadmap { get; set; }
    public string? ManagementServer { get; set; }
    public string? LdapUrl { get; set; }

    // Timestamps
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public DateTime? LastInventoryDate { get; set; }

    // Most recent AD collection (for logs access)
    public Guid? CollectionId { get; set; }

    // Notes (for detail view)
    public List<DomainNoteItem> Notes { get; set; } = new();

    /// <summary>
    /// Whether there's a collection available for viewing logs.
    /// </summary>
    public bool HasCollection => CollectionId.HasValue;
}

/// <summary>
/// Domain note item for display.
/// </summary>
public class DomainNoteItem
{
    public int DomainNoteID { get; set; }
    public int DomainID { get; set; }
    public string? NoteSubject { get; set; }
    public string NoteText { get; set; } = string.Empty;
    public string? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; }
    public bool IsSystem { get; set; }
}

/// <summary>
/// View model for the domain collection logs page.
/// </summary>
public class DomainLogsViewModel
{
    public int DomainID { get; set; }
    public string DomainName { get; set; } = string.Empty;
    public Guid CollectionId { get; set; }
    public DateTime? CollectionDateTime { get; set; }
    public List<AdLogEntry> Logs { get; set; } = new();

    /// <summary>
    /// Count of error-level logs.
    /// </summary>
    public int ErrorCount => Logs.Count(l => l.Level.Equals("Error", StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Count of warning-level logs.
    /// </summary>
    public int WarningCount => Logs.Count(l => l.Level.Equals("Warning", StringComparison.OrdinalIgnoreCase));
}

/// <summary>
/// Log entry from AD_Log table for an AD collection.
/// </summary>
public class AdLogEntry
{
    public int LogID { get; set; }
    public DateTime Timestamp { get; set; }
    public string Level { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public string? Context { get; set; }
    public string? ExceptionMessage { get; set; }
    public string? ExceptionType { get; set; }

    /// <summary>
    /// Bootstrap CSS class for level badge.
    /// </summary>
    public string LevelBadgeClass => Level.ToUpperInvariant() switch
    {
        "ERROR" => "danger",
        "WARNING" => "warning",
        "INFO" => "info",
        "DEBUG" => "secondary",
        _ => "light"
    };

    /// <summary>
    /// Bootstrap icon class for level.
    /// </summary>
    public string LevelIcon => Level.ToUpperInvariant() switch
    {
        "ERROR" => "bi-x-circle-fill",
        "WARNING" => "bi-exclamation-triangle-fill",
        "INFO" => "bi-info-circle-fill",
        "DEBUG" => "bi-bug-fill",
        _ => "bi-record-circle"
    };

    /// <summary>
    /// Context with unescaped backslashes for display.
    /// </summary>
    public string? DisplayContext => Context?.Replace("\\\\", "\\");
}

/// <summary>
/// View model for the DML edit/create page.
/// </summary>
public class DomainEditViewModel
{
    /// <summary>
    /// The domain being edited (null for create).
    /// </summary>
    public DomainMasterListItem Domain { get; set; } = new();

    /// <summary>
    /// Whether this is a new domain (create) or existing (edit).
    /// </summary>
    public bool IsNew => Domain.DomainID == 0;

    /// <summary>
    /// Lookup values for responsibility level dropdown.
    /// </summary>
    public List<DmlLookupItem> ResponsibilityLevels { get; set; } = new();

    /// <summary>
    /// Lookup values for tri-state dropdowns.
    /// </summary>
    public List<DmlLookupItem> TriStates { get; set; } = new();

    /// <summary>
    /// Lookup values for baseline status dropdown.
    /// </summary>
    public List<DmlLookupItem> BaselineStatuses { get; set; } = new();

    /// <summary>
    /// AD inventory information from the most recent collection (if available).
    /// </summary>
    public AdInventoryInfo? AdInventory { get; set; }

    /// <summary>
    /// Sites & Services topology information for this domain's forest.
    /// </summary>
    public SitesAndServicesInfo? SitesAndServices { get; set; }

    /// <summary>
    /// Domain health information (SYSVOL, GPO, Optional Features).
    /// </summary>
    public DomainHealthInfo? DomainHealth { get; set; }

    /// <summary>
    /// Terminal Server License Servers group membership.
    /// </summary>
    public TSLicenseServersInfo? TSLicenseServers { get; set; }

    /// <summary>
    /// KMS Services discovered for this domain.
    /// </summary>
    public KmsServicesInfo? KmsServices { get; set; }

    /// <summary>
    /// AD FS and Device Registration Service configuration for this forest.
    /// </summary>
    public AdfsConfigurationInfo? AdfsConfiguration { get; set; }

    /// <summary>
    /// PKI infrastructure summary for this forest.
    /// </summary>
    public PkiSummaryInfo? PkiSummary { get; set; }

    /// <summary>
    /// Active tab for the inventory display (overview, sites, health, audit).
    /// </summary>
    public string ActiveTab { get; set; } = "overview";

    /// <summary>
    /// Error message to display.
    /// </summary>
    public string? ErrorMessage { get; set; }

    /// <summary>
    /// Success message to display.
    /// </summary>
    public string? SuccessMessage { get; set; }
}

/// <summary>
/// AD inventory information from the most recent collection for a domain.
/// </summary>
public class AdInventoryInfo
{
    /// <summary>
    /// Whether inventory data is available for this domain.
    /// </summary>
    public bool HasInventory { get; set; }

    /// <summary>
    /// CollectionID for lazy loading additional data (Sites & Services, Health).
    /// </summary>
    public Guid? CollectionId { get; set; }

    /// <summary>
    /// Collection date/time of the inventory data.
    /// </summary>
    public DateTime? CollectionDateTime { get; set; }

    /// <summary>
    /// Forest information from the most recent inventory.
    /// </summary>
    public AdForestInfo? Forest { get; set; }

    /// <summary>
    /// Domain information from the most recent inventory.
    /// </summary>
    public AdDomainInfo? Domain { get; set; }

    /// <summary>
    /// Domain Controllers from the most recent inventory (IsCriticalSystemObject = 1).
    /// </summary>
    public List<DomainControllerInfo> DomainControllers { get; set; } = new();

    /// <summary>
    /// Key trust relationships summary for the 3 tracked domains.
    /// Keys: "ADMgmt", "SSNCCorp", "SSCViolet"
    /// </summary>
    public Dictionary<string, KeyTrustInfo> KeyTrusts { get; set; } = new();

    /// <summary>
    /// Whether any key trust data was loaded from inventory.
    /// </summary>
    public bool HasKeyTrustData => KeyTrusts.Count > 0;
}

/// <summary>
/// AD Forest information from ADData.AD_Forest table.
/// </summary>
public class AdForestInfo
{
    public string? ForestName { get; set; }
    public string? ForestMode { get; set; }
    public string? SchemaMaster { get; set; }
    public string? DomainNamingMaster { get; set; }
    public int? SchemaVersion { get; set; }
    public int? ExchangeSchemaVersion { get; set; }
    public DateTime? WhenCreated { get; set; }

    /// <summary>
    /// Human-readable schema version name.
    /// </summary>
    public string SchemaVersionDisplay => SchemaVersion switch
    {
        87 => "Windows Server 2016",
        88 => "Windows Server 2019",
        89 => "Windows Server 2022",
        90 => "Windows Server 2025",
        _ when SchemaVersion.HasValue => $"Schema {SchemaVersion}",
        _ => "Unknown"
    };

    /// <summary>
    /// Human-readable Exchange schema version name.
    /// </summary>
    public string ExchangeSchemaVersionDisplay => ExchangeSchemaVersion switch
    {
        15312 => "Exchange 2013 CU7+",
        15317 => "Exchange 2016",
        15323 => "Exchange 2016 CU1",
        15326 => "Exchange 2016 CU3-CU5",
        15330 => "Exchange 2016 CU7+",
        15332 => "Exchange 2019",
        15333 => "Exchange 2019 CU1+",
        17003 => "Exchange 2019 CU12+",
        _ when ExchangeSchemaVersion.HasValue => $"Exchange Schema {ExchangeSchemaVersion}",
        _ => "Not installed"
    };
}

/// <summary>
/// AD Domain information from ADData.AD_Domain table.
/// </summary>
public class AdDomainInfo
{
    public string? DomainName { get; set; }
    public string? DomainMode { get; set; }
    public string? PDCEmulator { get; set; }
    public string? RIDMaster { get; set; }
    public string? InfrastructureMaster { get; set; }
    public DateTime? WhenCreated { get; set; }
    public DateTime? WhenChanged { get; set; }

    /// <summary>
    /// Parent domain information with link to DomainMasterList if available.
    /// </summary>
    public LinkedDomainInfo? ParentDomain { get; set; }

    /// <summary>
    /// Child domains with links to DomainMasterList if available.
    /// </summary>
    public List<LinkedDomainInfo> ChildDomains { get; set; } = new();
}

/// <summary>
/// Domain reference with optional link to DomainMasterList.
/// </summary>
public class LinkedDomainInfo
{
    /// <summary>
    /// Domain name (DNS name).
    /// </summary>
    public string DomainName { get; set; } = string.Empty;

    /// <summary>
    /// DomainID from DomainMasterList if this domain exists in the master list.
    /// Null if domain is not in the master list.
    /// </summary>
    public int? DomainId { get; set; }

    /// <summary>
    /// Whether this domain exists in the DomainMasterList and can be linked.
    /// </summary>
    public bool HasLink => DomainId.HasValue;
}

/// <summary>
/// Domain Controller information from ADData.v_AD_Computers view.
/// </summary>
public class DomainControllerInfo
{
    public string? SamAccountName { get; set; }
    public string? DisplayName { get; set; }
    public string? DNSHostName { get; set; }
    public string? OperatingSystem { get; set; }
    public string? OperatingSystemVersion { get; set; }
    public bool? Enabled { get; set; }
    public DateTime? WhenCreated { get; set; }
    public DateTime? LastLogonTimestamp { get; set; }
    public DateTime? PasswordLastSet { get; set; }
}

#region Sites & Services and Domain Health

/// <summary>
/// Sites and Services topology information for a forest.
/// </summary>
public class SitesAndServicesInfo
{
    /// <summary>
    /// Whether Sites & Services data is available.
    /// </summary>
    public bool HasData { get; set; }

    /// <summary>
    /// Total number of sites.
    /// </summary>
    public int SiteCount { get; set; }

    /// <summary>
    /// Total number of subnets.
    /// </summary>
    public int SubnetCount { get; set; }

    /// <summary>
    /// Total number of site links.
    /// </summary>
    public int SiteLinkCount { get; set; }

    /// <summary>
    /// Total number of domain controllers.
    /// </summary>
    public int DomainControllerCount { get; set; }

    /// <summary>
    /// Site summary information (always loaded).
    /// </summary>
    public List<SiteSummaryInfo> Sites { get; set; } = new();
}

/// <summary>
/// Summary info for a site.
/// </summary>
public class SiteSummaryInfo
{
    public string SiteName { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Location { get; set; }
    public int SubnetCount { get; set; }
    public int DomainControllerCount { get; set; }
    public int GlobalCatalogCount { get; set; }
    public string? InterSiteTopologyGenerator { get; set; }
    public bool? IsGroupCachingEnabled { get; set; }
    public DateTime? WhenCreated { get; set; }
}

/// <summary>
/// Subnet information.
/// </summary>
public class SubnetInfo
{
    public string SubnetName { get; set; } = string.Empty;
    public string? SiteName { get; set; }
    public string? Description { get; set; }
    public string? Location { get; set; }
    public DateTime? WhenCreated { get; set; }
}

/// <summary>
/// Site link information.
/// </summary>
public class SiteLinkInfo
{
    public string SiteLinkName { get; set; } = string.Empty;
    public int? Cost { get; set; }
    public int? ReplicationInterval { get; set; }
    public string? Description { get; set; }
    public string? TransportType { get; set; }
    public bool? UseNotification { get; set; }
    public bool? TwoWaySync { get; set; }
    public bool? CompressionDisabled { get; set; }
    public int? SiteCount { get; set; }
    public string? SiteList { get; set; }
    public List<string> Sites { get; set; } = new();
    public DateTime? WhenCreated { get; set; }

    /// <summary>
    /// Bootstrap CSS class based on cost health.
    /// </summary>
    public string CostHealthClass => Cost switch
    {
        <= 100 => "success",
        <= 300 => "warning",
        _ => "danger"
    };
}

/// <summary>
/// Trust relationship information from AD_Trust table.
/// </summary>
public class TrustInfo
{
    public string SourceDomain { get; set; } = string.Empty;
    public string TargetDomain { get; set; } = string.Empty;
    public string TrustType { get; set; } = string.Empty;
    public string TrustDirection { get; set; } = string.Empty;
    public int? TrustAttributes { get; set; }
    public bool IsTransitive { get; set; }
    public string? FlatName { get; set; }
    public DateTime? WhenCreated { get; set; }

    /// <summary>
    /// Bootstrap badge class based on trust direction.
    /// </summary>
    public string DirectionBadgeClass => TrustDirection?.ToUpperInvariant() switch
    {
        "BIDIRECTIONAL" => "success",
        "INBOUND" => "info",
        "OUTBOUND" => "warning",
        _ => "secondary"
    };

    /// <summary>
    /// Icon for trust direction.
    /// </summary>
    public string DirectionIcon => TrustDirection?.ToUpperInvariant() switch
    {
        "BIDIRECTIONAL" => "bi-arrow-left-right",
        "INBOUND" => "bi-arrow-left",
        "OUTBOUND" => "bi-arrow-right",
        _ => "bi-dash"
    };

    /// <summary>
    /// Bootstrap badge class based on trust type.
    /// </summary>
    public string TypeBadgeClass => TrustType?.ToUpperInvariant() switch
    {
        "FOREST" => "primary",
        "PARENTCHILD" or "PARENT-CHILD" => "success",
        "EXTERNAL" => "warning",
        "CROSSLINK" or "CROSS-LINK" => "info",
        _ => "secondary"
    };
}

/// <summary>
/// Summary of a key trust relationship for display in the Edit page.
/// </summary>
public class KeyTrustInfo
{
    /// <summary>
    /// Whether a trust was found for this key domain.
    /// </summary>
    public bool HasTrust { get; set; }

    /// <summary>
    /// The trust direction (Inbound, Outbound, Bidirectional).
    /// </summary>
    public string? Direction { get; set; }

    /// <summary>
    /// The trust type (Forest, External, etc.).
    /// </summary>
    public string? TrustType { get; set; }

    /// <summary>
    /// The actual domain name matched (may differ in case).
    /// </summary>
    public string? MatchedDomain { get; set; }

    /// <summary>
    /// Bootstrap badge class for the direction.
    /// </summary>
    public string BadgeClass => Direction?.ToUpperInvariant() switch
    {
        "BIDIRECTIONAL" => "bg-success",
        "INBOUND" => "bg-info",
        "OUTBOUND" => "bg-warning text-dark",
        _ => "bg-secondary"
    };

    /// <summary>
    /// Bootstrap icon class for the direction arrow.
    /// </summary>
    public string DirectionIcon => Direction?.ToUpperInvariant() switch
    {
        "BIDIRECTIONAL" => "bi-arrow-left-right",
        "INBOUND" => "bi-arrow-left",
        "OUTBOUND" => "bi-arrow-right",
        _ => "bi-dash"
    };

    /// <summary>
    /// Display text for the direction.
    /// </summary>
    public string DirectionText => HasTrust ? (Direction ?? "Unknown") : "None";
}

/// <summary>
/// Domain health information from AD_Domain table.
/// </summary>
public class DomainHealthInfo
{
    /// <summary>
    /// Whether health data is available.
    /// </summary>
    public bool HasData { get; set; }

    // SYSVOL Replication Health
    public string? SysvolReplicationMethod { get; set; }
    public string? SysvolMigrationState { get; set; }
    public bool? DFSRExists { get; set; }
    public bool? FRSExists { get; set; }
    public int? DFSRFlags { get; set; }
    public bool? SYSVOLAccessible { get; set; }

    // GPO Health
    public int? GPOTotalCount { get; set; }
    public int? GPOHealthyCount { get; set; }
    public int? GPOOrphanedGPCCount { get; set; }
    public int? GPOOrphanedGPTCount { get; set; }
    public int? GPOVersionMismatchCount { get; set; }
    public string? GPOOverallHealth { get; set; }
    public bool? DefaultDomainPolicyExists { get; set; }
    public bool? DefaultDCPolicyExists { get; set; }

    /// <summary>
    /// Optional Features for this forest.
    /// </summary>
    public List<OptionalFeatureInfo> OptionalFeatures { get; set; } = new();

    /// <summary>
    /// Health-related log entries from the collection (warnings/errors about GPO, SYSVOL, etc.).
    /// </summary>
    public List<HealthLogEntry> HealthLogs { get; set; } = new();

    /// <summary>
    /// Whether there are health-related logs to display.
    /// </summary>
    public bool HasHealthLogs => HealthLogs.Count > 0;

    /// <summary>
    /// Bootstrap CSS class for SYSVOL health status.
    /// </summary>
    public string SysvolHealthClass => SysvolReplicationMethod?.ToUpperInvariant() switch
    {
        "DFSR" => "success",
        "FRS" => "warning",
        "UNKNOWN" => "danger",
        _ when SYSVOLAccessible == false => "danger",
        _ => "secondary"
    };

    /// <summary>
    /// Bootstrap CSS class for GPO health status.
    /// </summary>
    public string GPOHealthClass => GPOOverallHealth?.ToUpperInvariant() switch
    {
        "HEALTHY" => "success",
        "WARNING" => "warning",
        "CRITICAL" => "danger",
        _ => "secondary"
    };

    /// <summary>
    /// Total count of unhealthy GPOs.
    /// </summary>
    public int GPOUnhealthyCount =>
        (GPOOrphanedGPCCount ?? 0) +
        (GPOOrphanedGPTCount ?? 0) +
        (GPOVersionMismatchCount ?? 0);

    /// <summary>
    /// Percentage of healthy GPOs.
    /// </summary>
    public double GPOHealthPercent =>
        GPOTotalCount > 0
            ? Math.Round(((double)(GPOHealthyCount ?? 0) / GPOTotalCount.Value) * 100, 1)
            : 0;
}

/// <summary>
/// Log entry from AD_Log table related to health collection issues.
/// </summary>
public class HealthLogEntry
{
    public int LogID { get; set; }
    public DateTime Timestamp { get; set; }
    public string Level { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public string? Context { get; set; }
    public string? ExceptionMessage { get; set; }
    public string? ExceptionType { get; set; }

    /// <summary>
    /// Bootstrap CSS class for level badge.
    /// </summary>
    public string LevelBadgeClass => Level.ToUpperInvariant() switch
    {
        "ERROR" => "danger",
        "WARNING" => "warning",
        "INFO" => "info",
        _ => "secondary"
    };

    /// <summary>
    /// Bootstrap icon class for level.
    /// </summary>
    public string LevelIcon => Level.ToUpperInvariant() switch
    {
        "ERROR" => "bi-x-circle-fill",
        "WARNING" => "bi-exclamation-triangle-fill",
        "INFO" => "bi-info-circle-fill",
        _ => "bi-record-circle"
    };
}

/// <summary>
/// Optional feature information from AD_OptionalFeature table.
/// </summary>
public class OptionalFeatureInfo
{
    public string FeatureName { get; set; } = string.Empty;
    public bool IsEnabled { get; set; }
    public string? RequiredForestLevelName { get; set; }
    public string? Description { get; set; }

    /// <summary>
    /// Bootstrap CSS class for status badge.
    /// </summary>
    public string StatusBadgeClass => IsEnabled ? "success" : "secondary";

    /// <summary>
    /// Bootstrap icon class for status.
    /// </summary>
    public string StatusIcon => IsEnabled ? "bi-check-circle-fill" : "bi-x-circle";
}

/// <summary>
/// Terminal Server License Servers group membership information.
/// </summary>
public class TSLicenseServersInfo
{
    /// <summary>
    /// Whether any members were found.
    /// </summary>
    public bool HasMembers { get; set; }

    /// <summary>
    /// Total member count.
    /// </summary>
    public int MemberCount { get; set; }

    /// <summary>
    /// List of group members.
    /// </summary>
    public List<TSLicenseServerMember> Members { get; set; } = new();
}

/// <summary>
/// Member of the Terminal Server License Servers group.
/// </summary>
public class TSLicenseServerMember
{
    /// <summary>
    /// Member SID string.
    /// </summary>
    public string MemberSID { get; set; } = string.Empty;

    /// <summary>
    /// Display name for the member (DNSHostName, SamAccountName, or translated well-known SID).
    /// </summary>
    public string DisplayName { get; set; } = string.Empty;

    /// <summary>
    /// Member type: Computer, User, Group, Well-Known, or Unknown.
    /// </summary>
    public string MemberType { get; set; } = string.Empty;

    /// <summary>
    /// Operating system (for computers only).
    /// </summary>
    public string? OperatingSystem { get; set; }

    /// <summary>
    /// Whether the account is enabled (null for well-known SIDs).
    /// </summary>
    public bool? Enabled { get; set; }

    /// <summary>
    /// Whether this is a well-known SID (e.g., S-1-5-20 NETWORK SERVICE).
    /// </summary>
    public bool IsWellKnown { get; set; }

    /// <summary>
    /// Whether this computer is a domain controller (IsCriticalSystemObject = 1).
    /// Only applicable when MemberType is "Computer".
    /// </summary>
    public bool IsDomainController { get; set; }

    /// <summary>
    /// Domain name where the SID was resolved from (if from a trusted domain).
    /// Null if resolved from the current collection or unresolved.
    /// </summary>
    public string? ResolvedFromDomain { get; set; }

    /// <summary>
    /// Whether this member was resolved from a trusted domain (not the current collection).
    /// </summary>
    public bool IsFromTrustedDomain => !string.IsNullOrEmpty(ResolvedFromDomain);

    /// <summary>
    /// Bootstrap badge class for member type.
    /// </summary>
    public string TypeBadgeClass => MemberType switch
    {
        "Computer" => "primary",
        "User" => "info",
        "Group" => "warning",
        "Well-Known" => "secondary",
        _ => "dark"
    };

    /// <summary>
    /// Bootstrap icon for member type.
    /// </summary>
    public string TypeIcon => MemberType switch
    {
        "Computer" => "bi-pc-display",
        "User" => "bi-person",
        "Group" => "bi-people",
        "Well-Known" => "bi-shield-check",
        _ => "bi-question-circle"
    };
}

/// <summary>
/// KMS (Key Management Service) servers information for a domain.
/// </summary>
public class KmsServicesInfo
{
    /// <summary>
    /// Whether any KMS servers were found.
    /// </summary>
    public bool HasServers { get; set; }

    /// <summary>
    /// Total server count.
    /// </summary>
    public int ServerCount { get; set; }

    /// <summary>
    /// List of KMS servers discovered via DNS SRV records.
    /// </summary>
    public List<KmsServerInfo> Servers { get; set; } = new();
}

/// <summary>
/// Individual KMS server information from AD_KMSService table.
/// </summary>
public class KmsServerInfo
{
    /// <summary>
    /// Target hostname from DNS SRV record.
    /// </summary>
    public string TargetHostname { get; set; } = string.Empty;

    /// <summary>
    /// KMS port (default 1688).
    /// </summary>
    public int Port { get; set; } = 1688;

    /// <summary>
    /// DNS SRV priority (lower = preferred).
    /// </summary>
    public int? Priority { get; set; }

    /// <summary>
    /// DNS SRV weight for load balancing.
    /// </summary>
    public int? Weight { get; set; }

    /// <summary>
    /// Resolved IP address (optional).
    /// </summary>
    public string? ResolvedIP { get; set; }

    /// <summary>
    /// Record source (DNS or Manual).
    /// </summary>
    public string RecordSource { get; set; } = "DNS";
}

/// <summary>
/// AD FS and Device Registration Service configuration information.
/// </summary>
public class AdfsConfigurationInfo
{
    /// <summary>
    /// Whether any ADFS configuration was found.
    /// </summary>
    public bool HasConfiguration { get; set; }

    /// <summary>
    /// Forest name this configuration belongs to.
    /// </summary>
    public string? ForestName { get; set; }

    /// <summary>
    /// List of ADFS and DRS service configurations.
    /// </summary>
    public List<AdfsServiceInfo> Services { get; set; } = new();

    /// <summary>
    /// Count of ADFS services.
    /// </summary>
    public int AdfsCount => Services.Count(s => s.ServiceType == "ADFS");

    /// <summary>
    /// Count of Device Registration Services.
    /// </summary>
    public int DrsCount => Services.Count(s => s.ServiceType == "DRS");
}

/// <summary>
/// Individual ADFS or DRS service configuration from AD_ADFSConfiguration table.
/// </summary>
public class AdfsServiceInfo
{
    /// <summary>
    /// Service type: ADFS or DRS.
    /// </summary>
    public string ServiceType { get; set; } = string.Empty;

    /// <summary>
    /// Service name from CN attribute.
    /// </summary>
    public string? ServiceName { get; set; }

    /// <summary>
    /// Federation service name (for ADFS).
    /// </summary>
    public string? FederationServiceName { get; set; }

    /// <summary>
    /// Azure AD tenant ID (from keywords).
    /// </summary>
    public string? AzureTenantId { get; set; }

    /// <summary>
    /// Azure AD object ID (from keywords).
    /// </summary>
    public string? AzureObjectId { get; set; }

    /// <summary>
    /// Associated domain name.
    /// </summary>
    public string? DomainName { get; set; }

    /// <summary>
    /// Service binding information (URL).
    /// </summary>
    public string? ServiceBindingInfo { get; set; }

    /// <summary>
    /// Whether Azure AD integration is configured.
    /// </summary>
    public bool HasAzureIntegration => !string.IsNullOrEmpty(AzureTenantId);

    /// <summary>
    /// Bootstrap badge class for service type.
    /// </summary>
    public string TypeBadgeClass => ServiceType switch
    {
        "ADFS" => "primary",
        "DRS" => "success",
        _ => "secondary"
    };
}

/// <summary>
/// PKI (Public Key Infrastructure) summary information for a forest.
/// </summary>
public class PkiSummaryInfo
{
    /// <summary>
    /// Whether any PKI data was found.
    /// </summary>
    public bool HasData { get; set; }

    /// <summary>
    /// Forest name this PKI configuration belongs to.
    /// </summary>
    public string? ForestName { get; set; }

    /// <summary>
    /// List of Enterprise Certification Authorities.
    /// </summary>
    public List<EnterpriseCaInfo> EnterpriseCAs { get; set; } = new();

    /// <summary>
    /// Total count of certificate templates.
    /// </summary>
    public int CertificateTemplateCount { get; set; }

    /// <summary>
    /// Total count of trusted root CAs.
    /// </summary>
    public int TrustedRootCACount { get; set; }

    /// <summary>
    /// Total count of NTAuth certificates.
    /// </summary>
    public int NTAuthCertificateCount { get; set; }

    /// <summary>
    /// NTAuth certificates expiring within 90 days.
    /// </summary>
    public int NTAuthExpiringCount { get; set; }
}

/// <summary>
/// Enterprise CA information from AD_EnterpriseCA table.
/// </summary>
public class EnterpriseCaInfo
{
    /// <summary>
    /// CA display name.
    /// </summary>
    public string CAName { get; set; } = string.Empty;

    /// <summary>
    /// DNS hostname of the CA server.
    /// </summary>
    public string? DNSHostName { get; set; }

    /// <summary>
    /// CA type (Enterprise Root, Enterprise Subordinate).
    /// </summary>
    public string? CAType { get; set; }

    /// <summary>
    /// Number of certificate templates published on this CA.
    /// </summary>
    public int TemplateCount { get; set; }

    /// <summary>
    /// Whether this is a root CA.
    /// </summary>
    public bool IsRoot => CAType?.Contains("Root", StringComparison.OrdinalIgnoreCase) == true;

    /// <summary>
    /// Bootstrap icon for CA type.
    /// </summary>
    public string TypeIcon => IsRoot ? "bi-building" : "bi-building-fill";

    /// <summary>
    /// Bootstrap badge class for CA type.
    /// </summary>
    public string TypeBadgeClass => IsRoot ? "warning" : "info";
}

/// <summary>
/// Certificate Template detail for PKI modal display.
/// </summary>
public class CertificateTemplateDetail
{
    /// <summary>
    /// Internal template name identifier.
    /// </summary>
    public string TemplateName { get; set; } = "";

    /// <summary>
    /// User-friendly display name.
    /// </summary>
    public string? DisplayName { get; set; }

    /// <summary>
    /// Template schema version (1-4).
    /// </summary>
    public int SchemaVersion { get; set; }

    /// <summary>
    /// Minimum key size in bits.
    /// </summary>
    public int MinKeySize { get; set; }

    /// <summary>
    /// Certificate validity period (e.g., "2 Years").
    /// </summary>
    public string? ValidityPeriod { get; set; }

    /// <summary>
    /// Certificate renewal period (e.g., "6 Months").
    /// </summary>
    public string? RenewalPeriod { get; set; }

    /// <summary>
    /// Number of RA signatures required.
    /// </summary>
    public int RASignaturesRequired { get; set; }

    /// <summary>
    /// Extended Key Usage OIDs as JSON array.
    /// </summary>
    public string? ExtendedKeyUsage { get; set; }

    /// <summary>
    /// Bootstrap badge class for schema version.
    /// </summary>
    public string SchemaVersionBadgeClass => SchemaVersion switch
    {
        1 => "secondary",
        2 => "primary",
        3 => "success",
        4 => "info",
        _ => "secondary"
    };

    /// <summary>
    /// Whether the key size is considered weak (&lt; 2048 bits).
    /// </summary>
    public bool HasWeakKeySize => MinKeySize > 0 && MinKeySize < 2048;
}

/// <summary>
/// Trusted Root CA detail for PKI modal display.
/// </summary>
public class TrustedRootCaDetail
{
    /// <summary>
    /// CA name.
    /// </summary>
    public string CAName { get; set; } = "";

    /// <summary>
    /// Certificate subject distinguished name.
    /// </summary>
    public string? CertificateSubject { get; set; }

    /// <summary>
    /// Certificate SHA-1 thumbprint.
    /// </summary>
    public string? CertificateThumbprint { get; set; }

    /// <summary>
    /// Certificate validity start date.
    /// </summary>
    public DateTime? CertificateNotBefore { get; set; }

    /// <summary>
    /// Certificate expiration date.
    /// </summary>
    public DateTime? CertificateNotAfter { get; set; }

    /// <summary>
    /// Container type (CertificationAuthorities, AIA, CDP).
    /// </summary>
    public string? ContainerType { get; set; }

    /// <summary>
    /// Expiration status: expired, expiring, valid, or unknown.
    /// </summary>
    public string ExpirationStatus => CertificateNotAfter switch
    {
        null => "unknown",
        var d when d < DateTime.UtcNow => "expired",
        var d when d < DateTime.UtcNow.AddDays(90) => "expiring",
        _ => "valid"
    };

    /// <summary>
    /// Bootstrap badge class for expiration status.
    /// </summary>
    public string ExpirationBadgeClass => ExpirationStatus switch
    {
        "expired" => "danger",
        "expiring" => "warning",
        "valid" => "success",
        _ => "secondary"
    };

    /// <summary>
    /// Days remaining until expiration.
    /// </summary>
    public int? DaysRemaining => CertificateNotAfter.HasValue
        ? (int)(CertificateNotAfter.Value - DateTime.UtcNow).TotalDays
        : null;
}

/// <summary>
/// NTAuth Certificate detail for PKI modal display.
/// </summary>
public class NTAuthCertificateDetail
{
    /// <summary>
    /// Certificate subject (issuing CA).
    /// </summary>
    public string? CertificateSubject { get; set; }

    /// <summary>
    /// Certificate SHA-1 thumbprint.
    /// </summary>
    public string? CertificateThumbprint { get; set; }

    /// <summary>
    /// Certificate validity start date.
    /// </summary>
    public DateTime? CertificateNotBefore { get; set; }

    /// <summary>
    /// Certificate expiration date.
    /// </summary>
    public DateTime? CertificateNotAfter { get; set; }

    /// <summary>
    /// Index position in NTAuth store.
    /// </summary>
    public int CertificateIndex { get; set; }

    /// <summary>
    /// Expiration status with additional warning tier for 180 days.
    /// </summary>
    public string ExpirationStatus => CertificateNotAfter switch
    {
        null => "unknown",
        var d when d < DateTime.UtcNow => "expired",
        var d when d < DateTime.UtcNow.AddDays(90) => "expiring",
        var d when d < DateTime.UtcNow.AddDays(180) => "warning",
        _ => "valid"
    };

    /// <summary>
    /// Bootstrap badge class for expiration status (more severe for NTAuth).
    /// </summary>
    public string ExpirationBadgeClass => ExpirationStatus switch
    {
        "expired" => "danger",
        "expiring" => "danger",
        "warning" => "warning",
        "valid" => "success",
        _ => "secondary"
    };

    /// <summary>
    /// Days remaining until expiration.
    /// </summary>
    public int? DaysRemaining => CertificateNotAfter.HasValue
        ? (int)(CertificateNotAfter.Value - DateTime.UtcNow).TotalDays
        : null;
}

/// <summary>
/// Enterprise CA detail for PKI modal display (enriched version).
/// </summary>
public class EnterpriseCaDetail
{
    /// <summary>
    /// CA display name.
    /// </summary>
    public string CAName { get; set; } = "";

    /// <summary>
    /// DNS hostname of the CA server.
    /// </summary>
    public string? DNSHostName { get; set; }

    /// <summary>
    /// CA type (Enterprise Root, Enterprise Subordinate).
    /// </summary>
    public string? CAType { get; set; }

    /// <summary>
    /// Certificate subject distinguished name.
    /// </summary>
    public string? CACertificateDN { get; set; }

    /// <summary>
    /// Full AD distinguished name.
    /// </summary>
    public string? DistinguishedName { get; set; }

    /// <summary>
    /// When the CA object was created in AD.
    /// </summary>
    public DateTime? WhenCreated { get; set; }

    /// <summary>
    /// When the CA object was last modified in AD.
    /// </summary>
    public DateTime? WhenChanged { get; set; }

    /// <summary>
    /// List of published certificate template names.
    /// </summary>
    public List<string> PublishedTemplates { get; set; } = new();

    /// <summary>
    /// Bootstrap badge class for CA type.
    /// </summary>
    public string TypeBadgeClass => CAType?.Contains("Root") == true ? "warning" : "primary";

    /// <summary>
    /// Bootstrap icon for CA type.
    /// </summary>
    public string TypeIcon => CAType?.Contains("Root") == true ? "bi-shield-fill" : "bi-building";
}

#endregion

/// <summary>
/// API request model for creating a domain.
/// </summary>
public class DomainCreateRequest
{
    public string DomainName { get; set; } = string.Empty;
    public string? NetBIOSName { get; set; }
    public string? BusinessUnit { get; set; }
    public int? DSResponsibilityLevelID { get; set; }
    public bool IsThirdPartyManaged { get; set; }
    public bool IsDecommissioned { get; set; }
    public byte Trust_ADMgmt_TriStateID { get; set; } = 2;
    public byte Trust_SSCViolet_TriStateID { get; set; } = 2;
    public byte Trust_SSNC_Corp_TriStateID { get; set; } = 2;
    public bool IsPatchHold { get; set; }
    public bool HasHealthCheck { get; set; }
    public bool HasNetwrixAuditor { get; set; }
    public bool IsSafeguardReady { get; set; }
    public byte IsCloudIntegrated { get; set; } = 2;
    public byte BaselineStatusID { get; set; } = 2;
    public bool IsClientFacing { get; set; }
    public bool IsSPLA { get; set; }
    public bool IsRegulated { get; set; }
    public bool MSPCustomer { get; set; }
    public string? POC { get; set; }
    public string? Purpose { get; set; }
    public string? Roadmap { get; set; }
    public string? ManagementServer { get; set; }
}

/// <summary>
/// API request model for updating a domain.
/// </summary>
public class DomainUpdateRequest : DomainCreateRequest
{
    public int DomainID { get; set; }
}

/// <summary>
/// API request model for adding a note.
/// </summary>
public class AddNoteRequest
{
    public string? NoteSubject { get; set; }
    public string NoteText { get; set; } = string.Empty;
}

/// <summary>
/// View model for the DML notes page.
/// </summary>
public class DomainNotesViewModel
{
    public int DomainID { get; set; }
    public string DomainName { get; set; } = string.Empty;
    public List<DomainNoteItem> Notes { get; set; } = new();
    public int? SelectedNoteId { get; set; }
    public string? ErrorMessage { get; set; }
    public string? SuccessMessage { get; set; }
}

#endregion

#region Topology Visualization

/// <summary>
/// View model for the AD topology visualization page.
/// </summary>
public class TopologyViewModel
{
    /// <summary>
    /// CollectionID for the topology data.
    /// </summary>
    public Guid CollectionId { get; set; }

    /// <summary>
    /// Domain ID from DomainMasterList for navigation back.
    /// </summary>
    public int DomainId { get; set; }

    /// <summary>
    /// Domain name for display.
    /// </summary>
    public string DomainName { get; set; } = string.Empty;

    /// <summary>
    /// Forest name for display.
    /// </summary>
    public string? ForestName { get; set; }

    /// <summary>
    /// Collection date/time.
    /// </summary>
    public DateTime? CollectionDateTime { get; set; }

    /// <summary>
    /// Summary counts for the topology.
    /// </summary>
    public TopologySummary Summary { get; set; } = new();

    /// <summary>
    /// Error message to display.
    /// </summary>
    public string? ErrorMessage { get; set; }
}

/// <summary>
/// Summary counts for topology visualization.
/// </summary>
public class TopologySummary
{
    public int SiteCount { get; set; }
    public int SubnetCount { get; set; }
    public int SiteLinkCount { get; set; }
    public int DomainControllerCount { get; set; }
}

/// <summary>
/// Topology data for Cytoscape.js visualization (JSON API response).
/// </summary>
public class TopologyData
{
    /// <summary>
    /// Sites as nodes.
    /// </summary>
    public List<TopologySiteNode> Sites { get; set; } = new();

    /// <summary>
    /// Domain controllers as nodes within sites.
    /// </summary>
    public List<TopologyDCNode> DomainControllers { get; set; } = new();

    /// <summary>
    /// Site links as edges between sites.
    /// </summary>
    public List<TopologySiteLinkEdge> SiteLinks { get; set; } = new();

    /// <summary>
    /// Subnets for detail display.
    /// </summary>
    public List<TopologySubnetNode> Subnets { get; set; } = new();
}

/// <summary>
/// Site node for Cytoscape.js.
/// </summary>
public class TopologySiteNode
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Location { get; set; }
    public int SubnetCount { get; set; }
    public int DomainControllerCount { get; set; }
    public int GlobalCatalogCount { get; set; }
    public string? ISTG { get; set; }
    public bool? IsGroupCachingEnabled { get; set; }
}

/// <summary>
/// Domain controller node for Cytoscape.js.
/// </summary>
public class TopologyDCNode
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string SiteId { get; set; } = string.Empty;
    public string? SiteName { get; set; }
    public string? DNSHostName { get; set; }
    public bool IsGlobalCatalog { get; set; }
    public bool IsRODC { get; set; }
    public bool IsISTG { get; set; }
    public string? OperatingSystem { get; set; }
}

/// <summary>
/// Site link edge for Cytoscape.js.
/// </summary>
public class TopologySiteLinkEdge
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int? Cost { get; set; }
    public int? ReplicationInterval { get; set; }
    public string? TransportType { get; set; }
    public bool? UseNotification { get; set; }
    public bool? TwoWaySync { get; set; }
    public List<string> SiteIds { get; set; } = new();
    public List<string> SiteNames { get; set; } = new();
}

/// <summary>
/// Subnet node for detail display.
/// </summary>
public class TopologySubnetNode
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string SiteId { get; set; } = string.Empty;
    public string? SiteName { get; set; }
    public string? Description { get; set; }
    public string? Location { get; set; }
}

#endregion

#region Logging View Models

/// <summary>
/// View model for the logging configuration page.
/// </summary>
public class LoggingConfigViewModel
{
    /// <summary>
    /// Enable extended logging for authentication, authorization, and diagnostics.
    /// Logs detailed information about user groups, role matching, LDAP details, etc.
    /// </summary>
    public bool EnableExtendedLogging { get; set; }

    /// <summary>
    /// Enable request/response logging for API calls.
    /// WARNING: May expose sensitive data in logs.
    /// </summary>
    public bool EnableRequestLogging { get; set; }

    /// <summary>
    /// Enable performance timing logs for slow operations.
    /// </summary>
    public bool EnablePerformanceLogging { get; set; }

    /// <summary>
    /// Threshold in milliseconds for performance logging.
    /// </summary>
    public int PerformanceThresholdMs { get; set; } = 1000;

    /// <summary>
    /// Enable detailed upload diagnostics logging.
    /// Logs streaming progress, connection events, and error context.
    /// </summary>
    public bool EnableUploadDiagnostics { get; set; }

    /// <summary>
    /// Interval in megabytes for upload progress logging.
    /// </summary>
    public int UploadProgressIntervalMB { get; set; } = 50;

    /// <summary>
    /// Interval as percentage for upload progress logging.
    /// </summary>
    public int UploadProgressIntervalPercent { get; set; } = 10;

    /// <summary>
    /// Days to retain log files.
    /// </summary>
    public int FileLogRetentionDays { get; set; } = 30;

    /// <summary>
    /// Days to retain database logs.
    /// </summary>
    public int DatabaseLogRetentionDays { get; set; } = 90;

    /// <summary>
    /// Success message to display.
    /// </summary>
    public string? SuccessMessage { get; set; }

    /// <summary>
    /// Error message to display.
    /// </summary>
    public string? ErrorMessage { get; set; }
}

#endregion

#region Chunked Uploads

/// <summary>
/// View model for the active chunked uploads admin page.
/// </summary>
public class ChunkedUploadsViewModel
{
    /// <summary>
    /// List of active chunked upload sessions.
    /// </summary>
    public List<CLAWS.Core.Models.ActiveChunkedUpload> ActiveUploads { get; set; } = new();

    /// <summary>
    /// Total number of active sessions.
    /// </summary>
    public int TotalActiveSessions { get; set; }

    /// <summary>
    /// Total bytes pending across all sessions.
    /// </summary>
    public long TotalPendingBytes { get; set; }

    /// <summary>
    /// Chunked upload settings.
    /// </summary>
    public CLAWS.Core.Configuration.ChunkedUploadSettings Settings { get; set; } = new();

    /// <summary>
    /// Format bytes for display.
    /// </summary>
    public static string FormatBytes(long bytes)
    {
        string[] suffixes = { "B", "KB", "MB", "GB", "TB" };
        int i = 0;
        double size = bytes;
        while (size >= 1024 && i < suffixes.Length - 1)
        {
            size /= 1024;
            i++;
        }
        return $"{size:F2} {suffixes[i]}";
    }
}

#endregion
