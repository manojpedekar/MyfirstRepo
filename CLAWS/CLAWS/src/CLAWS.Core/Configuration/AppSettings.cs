namespace CLAWS.Core.Configuration;

/// <summary>
/// Main application settings.
/// </summary>
public class AppSettings
{
    /// <summary>
    /// SQL Server connection settings.
    /// </summary>
    public SqlServerSettings SqlServer { get; set; } = new();

    /// <summary>
    /// Authorization group settings.
    /// </summary>
    public AuthorizationSettings Authorization { get; set; } = new();

    /// <summary>
    /// File storage settings.
    /// </summary>
    public StorageSettings Storage { get; set; } = new();

    /// <summary>
    /// Upload limit settings.
    /// </summary>
    public UploadLimitSettings UploadLimits { get; set; } = new();

    /// <summary>
    /// Cleanup settings.
    /// </summary>
    public CleanupSettings Cleanup { get; set; } = new();

    /// <summary>
    /// Import settings.
    /// </summary>
    public ImportSettings Import { get; set; } = new();

    /// <summary>
    /// Logging settings.
    /// </summary>
    public LoggingSettings Logging { get; set; } = new();

    /// <summary>
    /// Version requirements.
    /// </summary>
    public VersionSettings Versions { get; set; } = new();

    /// <summary>
    /// Disk space monitoring settings.
    /// </summary>
    public DiskSpaceSettings DiskSpace { get; set; } = new();

    /// <summary>
    /// Database performance settings.
    /// </summary>
    public DatabasePerformanceSettings DatabasePerformance { get; set; } = new();

    /// <summary>
    /// LDAP authentication settings.
    /// </summary>
    public LdapSettings Ldap { get; set; } = new();

    /// <summary>
    /// Cloud Integration validation settings.
    /// </summary>
    public CloudIntegrationSettings CloudIntegration { get; set; } = new();

    /// <summary>
    /// Hangfire job timeout settings.
    /// </summary>
    public JobTimeoutSettings JobTimeouts { get; set; } = new();

    /// <summary>
    /// Chunked upload settings for large files.
    /// </summary>
    public ChunkedUploadSettings ChunkedUpload { get; set; } = new();

    /// <summary>
    /// HTTP server (Kestrel) settings.
    /// </summary>
    public HttpServerSettings HttpServer { get; set; } = new();
}

/// <summary>
/// SQL Server connection settings.
/// </summary>
public class SqlServerSettings
{
    /// <summary>
    /// SQL Server hostname or instance.
    /// </summary>
    public string Server { get; set; } = string.Empty;

    /// <summary>
    /// Target database name.
    /// </summary>
    public string Database { get; set; } = string.Empty;

    /// <summary>
    /// Use Windows Authentication (true) or SQL Authentication (false).
    /// </summary>
    public bool UseWindowsAuth { get; set; } = true;

    /// <summary>
    /// SQL Auth username (if UseWindowsAuth is false).
    /// </summary>
    public string? Username { get; set; }

    /// <summary>
    /// SQL Auth password (plain text, used at runtime after decryption).
    /// </summary>
    public string? Password { get; set; }

    /// <summary>
    /// DPAPI-encrypted SQL Auth password (base64 encoded, from config file).
    /// This is decrypted at startup and stored in Password property.
    /// </summary>
    public string? EncryptedPassword { get; set; }

    /// <summary>
    /// Connection timeout in seconds.
    /// </summary>
    public int ConnectionTimeout { get; set; } = 30;

    /// <summary>
    /// Default command timeout for imports in seconds.
    /// </summary>
    public int CommandTimeout { get; set; } = 3600; // 1 hour

    /// <summary>
    /// Whether the SQL Server is configured.
    /// </summary>
    public bool IsConfigured => !string.IsNullOrWhiteSpace(Server) && !string.IsNullOrWhiteSpace(Database);

    /// <summary>
    /// Builds a connection string from the settings.
    /// </summary>
    public string BuildConnectionString()
    {
        var builder = new Microsoft.Data.SqlClient.SqlConnectionStringBuilder
        {
            DataSource = Server,
            InitialCatalog = Database,
            ConnectTimeout = ConnectionTimeout,
            TrustServerCertificate = true
        };

        if (UseWindowsAuth)
        {
            builder.IntegratedSecurity = true;
        }
        else
        {
            builder.UserID = Username;
            builder.Password = Password;
        }

        return builder.ConnectionString;
    }
}

/// <summary>
/// Authorization group settings.
/// </summary>
public class AuthorizationSettings
{
    /// <summary>
    /// AD group for full site admin access (all features including Admin menu).
    /// </summary>
    public string? SiteAdminGroup { get; set; }

    /// <summary>
    /// AD group for NTFS Permissions admin access.
    /// Can manage any NTFS upload and delete NTFS production data.
    /// </summary>
    public string? NtfsPermsAdminGroup { get; set; }

    /// <summary>
    /// AD group for AD Inventory admin access.
    /// Can manage any AD upload, delete AD production data, and edit DML.
    /// </summary>
    public string? AdAdminGroup { get; set; }

    /// <summary>
    /// Whether any authorization groups are configured.
    /// </summary>
    public bool IsConfigured => !string.IsNullOrWhiteSpace(SiteAdminGroup);
}

/// <summary>
/// File storage settings.
/// </summary>
public class StorageSettings
{
    /// <summary>
    /// Base path for all import operations.
    /// </summary>
    public string ImportBasePath { get; set; } = string.Empty;

    /// <summary>
    /// Subdirectory for incoming uploads.
    /// </summary>
    public string UploadFolder { get; set; } = "Uploads";

    /// <summary>
    /// Subdirectory for ZIP extraction.
    /// </summary>
    public string ExtractionFolder { get; set; } = "Extraction";

    /// <summary>
    /// Subdirectory for successful imports.
    /// </summary>
    public string CompletedFolder { get; set; } = "Completed";

    /// <summary>
    /// Subdirectory for failed imports.
    /// </summary>
    public string ErrorsFolder { get; set; } = "Errors";

    /// <summary>
    /// Gets the full path to the upload folder.
    /// </summary>
    public string GetUploadPath() => Path.Combine(ImportBasePath, UploadFolder);

    /// <summary>
    /// Gets the full path to the extraction folder.
    /// </summary>
    public string GetExtractionPath() => Path.Combine(ImportBasePath, ExtractionFolder);

    /// <summary>
    /// Gets the full path to the completed folder.
    /// </summary>
    public string GetCompletedPath() => Path.Combine(ImportBasePath, CompletedFolder);

    /// <summary>
    /// Gets the full path to the errors folder.
    /// </summary>
    public string GetErrorsPath() => Path.Combine(ImportBasePath, ErrorsFolder);

    /// <summary>
    /// Checks if the import base path is within the application directory.
    /// </summary>
    public bool IsUsingApplicationDirectory(string appDirectory)
    {
        if (string.IsNullOrWhiteSpace(ImportBasePath)) return true;
        var normalizedBasePath = Path.GetFullPath(ImportBasePath).TrimEnd(Path.DirectorySeparatorChar);
        var normalizedAppDir = Path.GetFullPath(appDirectory).TrimEnd(Path.DirectorySeparatorChar);
        return normalizedBasePath.StartsWith(normalizedAppDir, StringComparison.OrdinalIgnoreCase);
    }
}

/// <summary>
/// Upload limit settings.
/// </summary>
public class UploadLimitSettings
{
    /// <summary>
    /// Maximum ZIP file size in bytes.
    /// </summary>
    public long MaxUploadSizeBytes { get; set; } = 3L * 1024 * 1024 * 1024; // 3 GB

    /// <summary>
    /// Maximum extracted SQLite file size in bytes.
    /// </summary>
    public long MaxExtractedSizeBytes { get; set; } = 50L * 1024 * 1024 * 1024; // 50 GB

    /// <summary>
    /// Minimum free disk space required in bytes.
    /// </summary>
    public long MinFreeDiskSpaceBytes { get; set; } = 50L * 1024 * 1024 * 1024; // 50 GB

    /// <summary>
    /// Maximum concurrent extractions.
    /// </summary>
    public int MaxConcurrentExtractions { get; set; } = 2;

    /// <summary>
    /// Maximum compression ratio before rejecting (zip bomb protection).
    /// </summary>
    public double MaxCompressionRatio { get; set; } = 100.0;
}

/// <summary>
/// Cleanup settings.
/// </summary>
public class CleanupSettings
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
    /// Days to retain orphaned files in extraction folder (0 = never auto-delete).
    /// </summary>
    public int ExtractionRetentionDays { get; set; } = 7;

    /// <summary>
    /// Days to retain completed/failed/cancelled upload records in the database (0 = never auto-delete).
    /// Should be >= CompletedRetentionDays to ensure files are cleaned up before records.
    /// </summary>
    public int UploadRecordRetentionDays { get; set; } = 7;

    /// <summary>
    /// Cron expression for cleanup task.
    /// </summary>
    public string PruneSchedule { get; set; } = "0 2 * * *"; // 2 AM daily

    /// <summary>
    /// Enable automatic cleanup of old AD collections per domain.
    /// </summary>
    public bool AutoPruneAdCollections { get; set; } = true;

    /// <summary>
    /// Number of AD collections to keep per domain.
    /// Older collections beyond this limit will be deleted.
    /// </summary>
    public int AdCollectionsToKeepPerDomain { get; set; } = 3;

    /// <summary>
    /// Cron expression for AD collection cleanup task.
    /// Default: every 6 hours (4 times per day).
    /// </summary>
    public string AdCollectionPruneSchedule { get; set; } = "0 */6 * * *";
}

/// <summary>
/// Import settings.
/// </summary>
public class ImportSettings
{
    /// <summary>
    /// Records per batch during import.
    /// </summary>
    public int BatchSize { get; set; } = 10000;

    /// <summary>
    /// Transaction mode: PerTable, PerBatch, or PerCollection.
    /// </summary>
    public TransactionMode TransactionMode { get; set; } = TransactionMode.PerTable;

    /// <summary>
    /// Action for duplicate InventoryIDs.
    /// </summary>
    public DuplicateHandling DuplicateHandling { get; set; } = DuplicateHandling.Reject;

    /// <summary>
    /// Automatically validate imported data after upload processing completes.
    /// </summary>
    public bool EnableAutomaticValidation { get; set; } = false;

    /// <summary>
    /// Automatically merge validated data to production tables after validation passes.
    /// Requires EnableAutomaticValidation to be true. If validation fails, merge will not proceed.
    /// </summary>
    public bool EnableAutomaticMerge { get; set; } = false;

    /// <summary>
    /// SQLite integrity check mode for uploaded databases.
    /// </summary>
    public IntegrityCheckMode IntegrityCheckMode { get; set; } = IntegrityCheckMode.Quick;

    /// <summary>
    /// File size threshold in MB for Auto integrity check mode.
    /// Files larger than this threshold use quick_check, smaller files use full integrity_check.
    /// </summary>
    public int AutoIntegrityCheckThresholdMB { get; set; } = 500;
}

/// <summary>
/// Transaction mode for imports.
/// </summary>
public enum TransactionMode
{
    /// <summary>One transaction per table.</summary>
    PerTable,

    /// <summary>One transaction per batch.</summary>
    PerBatch,

    /// <summary>One transaction for entire collection.</summary>
    PerCollection
}

/// <summary>
/// How to handle duplicate InventoryIDs.
/// </summary>
public enum DuplicateHandling
{
    /// <summary>Reject the upload if any InventoryID already exists.</summary>
    Reject,

    /// <summary>Update existing data with new data.</summary>
    Update,

    /// <summary>Skip collections that already exist.</summary>
    Skip
}

/// <summary>
/// SQLite integrity check mode for uploaded databases.
/// </summary>
public enum IntegrityCheckMode
{
    /// <summary>Use PRAGMA integrity_check (thorough, slower).</summary>
    Full,

    /// <summary>Use PRAGMA quick_check (faster, recommended default).</summary>
    Quick,

    /// <summary>Skip integrity check entirely.</summary>
    None,

    /// <summary>Use quick_check for files over threshold, integrity_check for smaller files.</summary>
    Auto
}

/// <summary>
/// Logging settings.
/// </summary>
public class LoggingSettings
{
    /// <summary>
    /// Directory for log files.
    /// </summary>
    public string LogDirectory { get; set; } = string.Empty;

    /// <summary>
    /// Days to retain log files.
    /// </summary>
    public int FileLogRetentionDays { get; set; } = 30;

    /// <summary>
    /// Minimum severity for file logging.
    /// </summary>
    public string FileLogLevel { get; set; } = "Information";

    /// <summary>
    /// Days to retain database logs.
    /// </summary>
    public int DatabaseLogRetentionDays { get; set; } = 90;

    /// <summary>
    /// Minimum severity for database logging.
    /// </summary>
    public string DatabaseLogLevel { get; set; } = "Information";

    /// <summary>
    /// Enable debug-level logging.
    /// </summary>
    public bool EnableDebugLogging { get; set; } = false;

    /// <summary>
    /// Enable extended logging for authentication, authorization, and diagnostics.
    /// When enabled, logs detailed information about:
    /// - User group memberships during login
    /// - Authorization role matching
    /// - LDAP authentication details
    /// - Import/migration operation details
    /// Default: false (to reduce log volume in production).
    /// </summary>
    public bool EnableExtendedLogging { get; set; } = false;

    /// <summary>
    /// Enable request/response logging for API calls.
    /// WARNING: May expose sensitive data in logs. Use only for debugging.
    /// Default: false.
    /// </summary>
    public bool EnableRequestLogging { get; set; } = false;

    /// <summary>
    /// Enable performance timing logs for slow operations.
    /// Logs operations that exceed the threshold.
    /// Default: false.
    /// </summary>
    public bool EnablePerformanceLogging { get; set; } = false;

    /// <summary>
    /// Threshold in milliseconds for performance logging.
    /// Operations exceeding this time will be logged when EnablePerformanceLogging is true.
    /// Default: 1000 (1 second).
    /// </summary>
    public int PerformanceThresholdMs { get; set; } = 1000;

    /// <summary>
    /// Enable detailed upload diagnostics logging.
    /// When enabled, logs detailed information about:
    /// - Upload request details (Content-Length, headers, client info)
    /// - Streaming progress (bytes received, throughput, ETA)
    /// - Connection events (stalls, timeouts, disconnects)
    /// - Error context (phase, bytes received, connection state)
    /// - File I/O operations (writes, cleanup)
    /// Useful for debugging large file upload failures.
    /// Default: false.
    /// </summary>
    public bool EnableUploadDiagnostics { get; set; } = false;

    /// <summary>
    /// Interval in megabytes for upload progress logging.
    /// Progress is logged every N MB when EnableUploadDiagnostics is true.
    /// Default: 50 MB.
    /// </summary>
    public int UploadProgressIntervalMB { get; set; } = 50;

    /// <summary>
    /// Interval as percentage for upload progress logging.
    /// Progress is logged every N% when EnableUploadDiagnostics is true.
    /// The smaller of MB interval or percentage interval triggers logging.
    /// Default: 10%.
    /// </summary>
    public int UploadProgressIntervalPercent { get; set; } = 10;
}

/// <summary>
/// Version requirement settings.
/// </summary>
public class VersionSettings
{
    /// <summary>
    /// Minimum SQLite schema version accepted.
    /// </summary>
    public string? MinimumDbVersion { get; set; }

    /// <summary>
    /// Minimum CollectNTFSPerms application version accepted.
    /// </summary>
    public string? MinimumAppVersion { get; set; }
}

/// <summary>
/// Disk space monitoring settings.
/// </summary>
public class DiskSpaceSettings
{
    /// <summary>
    /// Warning threshold as percentage of free space (0-100).
    /// Warnings are triggered when free space falls below this percentage.
    /// Set to 0 to disable percentage-based warnings.
    /// </summary>
    public double WarningThresholdPercent { get; set; } = 20.0;

    /// <summary>
    /// Critical threshold as percentage of free space (0-100).
    /// Critical alerts are triggered when free space falls below this percentage.
    /// Set to 0 to use only the minimum bytes threshold.
    /// </summary>
    public double CriticalThresholdPercent { get; set; } = 10.0;

    /// <summary>
    /// Whether to enable disk space monitoring job.
    /// </summary>
    public bool EnableMonitoring { get; set; } = true;

    /// <summary>
    /// Interval in minutes between disk space checks.
    /// </summary>
    public int MonitoringIntervalMinutes { get; set; } = 15;
}

/// <summary>
/// Database performance settings for validation and migration operations.
/// </summary>
public class DatabasePerformanceSettings
{
    /// <summary>
    /// Command timeout in minutes for long-running operations (validation, migration).
    /// Default: 30 minutes.
    /// </summary>
    public int CommandTimeoutMinutes { get; set; } = 30;

    /// <summary>
    /// Connection timeout in seconds for initial database connection.
    /// Default: 30 seconds.
    /// </summary>
    public int ConnectionTimeoutSeconds { get; set; } = 30;

    /// <summary>
    /// Batch size for bulk import operations (records per batch).
    /// Larger values = faster but more memory. Default: 10000.
    /// </summary>
    public int ImportBatchSize { get; set; } = 10000;

    /// <summary>
    /// Maximum number of concurrent extraction operations.
    /// Default: 2.
    /// </summary>
    public int MaxConcurrentExtractions { get; set; } = 2;

    /// <summary>
    /// Batch size for production collection deletion operations (records per batch).
    /// Larger values = faster deletion but more lock contention. Default: 50000.
    /// Range: 1000-100000.
    /// </summary>
    public int DeletionBatchSize { get; set; } = 50000;

    /// <summary>
    /// Timeout in seconds for each SqlBulkCopy batch operation.
    /// Default: 600 (10 minutes). For very large batches, consider 1200+ seconds.
    /// </summary>
    public int BulkCopyTimeoutSeconds { get; set; } = 600;

    /// <summary>
    /// Whether table partitioning is enabled in the database.
    /// When enabled, uses partition-aware stored procedures for faster deletion operations.
    /// Requires SQL Server Enterprise Edition with partitioning configured.
    /// Default: false.
    /// </summary>
    public bool PartitioningEnabled { get; set; } = false;

    /// <summary>
    /// Whether to automatically prepare partitions before import.
    /// When enabled, calls usp_PreparePartitionForImport before each collection import.
    /// Only effective when PartitioningEnabled is true.
    /// Default: true.
    /// </summary>
    public bool AutoPreparePartitions { get; set; } = true;

    /// <summary>
    /// Gets the command timeout in seconds.
    /// </summary>
    public int CommandTimeoutSeconds => CommandTimeoutMinutes * 60;
}

/// <summary>
/// LDAP authentication settings.
/// </summary>
public class LdapSettings
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
    /// Default: (sAMAccountName={0})
    /// </summary>
    public string UserSearchFilter { get; set; } = "(sAMAccountName={0})";

    /// <summary>
    /// Domain prefix for authentication (e.g., SSNC-CORP).
    /// If specified, will be prepended to username as DOMAIN\username.
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

    /// <summary>
    /// Whether the LDAP server is configured.
    /// </summary>
    public bool IsConfigured => Enabled && !string.IsNullOrWhiteSpace(Server) && !string.IsNullOrWhiteSpace(BaseDn);
}

/// <summary>
/// Cloud Integration validation settings.
/// Used to configure the daily LDAP validation of cloud integration status.
/// </summary>
public class CloudIntegrationSettings
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
    /// Service account domain for LDAP queries (e.g., SSNC-CORP).
    /// </summary>
    public string? ServiceAccountDomain { get; set; }

    /// <summary>
    /// Encrypted service account password (encrypted via Data Protection).
    /// </summary>
    public string? EncryptedServiceAccountPassword { get; set; }

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

    /// <summary>
    /// Whether the Cloud Integration LDAP is configured.
    /// </summary>
    public bool IsConfigured => Enabled &&
                                !string.IsNullOrWhiteSpace(LdapServer) &&
                                !string.IsNullOrWhiteSpace(LdapSearchBase) &&
                                !string.IsNullOrWhiteSpace(ServiceAccountUsername) &&
                                !string.IsNullOrWhiteSpace(EncryptedServiceAccountPassword);
}

/// <summary>
/// Chunked upload settings for handling large file uploads.
/// Files are split into smaller chunks to bypass IIS size limits and enable resume support.
/// </summary>
public class ChunkedUploadSettings
{
    /// <summary>
    /// Enable chunked upload support for large files. Default: true.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Chunk size in bytes. Default: 50 MB.
    /// </summary>
    public int ChunkSizeBytes { get; set; } = 50 * 1024 * 1024;

    /// <summary>
    /// File size threshold above which chunked upload is used. Default: 500 MB.
    /// Files smaller than this use standard single-request upload.
    /// </summary>
    public long ChunkedThresholdBytes { get; set; } = 500 * 1024 * 1024;

    /// <summary>
    /// Maximum concurrent chunked uploads per user. Default: 2.
    /// </summary>
    public int MaxConcurrentUploadsPerUser { get; set; } = 2;

    /// <summary>
    /// Maximum concurrent chunked uploads system-wide. Default: 10.
    /// </summary>
    public int MaxConcurrentUploadsGlobal { get; set; } = 10;

    /// <summary>
    /// Maximum number of concurrent chunk uploads from client per session. Default: 3.
    /// </summary>
    public int MaxConcurrentChunksPerUpload { get; set; } = 3;

    /// <summary>
    /// Hours before incomplete chunked upload sessions expire. Default: 6.
    /// </summary>
    public int SessionExpirationHours { get; set; } = 6;

    /// <summary>
    /// Maximum retries for individual chunk uploads on client. Default: 3.
    /// </summary>
    public int MaxChunkRetries { get; set; } = 3;

    /// <summary>
    /// Minutes before expiration to show first warning to user. Default: 30.
    /// </summary>
    public int ExpirationWarningMinutes { get; set; } = 30;

    /// <summary>
    /// Enable SHA256 hash verification by default. Default: false.
    /// When enabled, adds ~30-60 seconds overhead for large files.
    /// </summary>
    public bool EnableHashVerificationByDefault { get; set; } = false;
}

/// <summary>
/// Hangfire job timeout settings.
/// These control how long background jobs can run before timing out.
/// </summary>
public class JobTimeoutSettings
{
    /// <summary>
    /// Upload processing job timeout in minutes.
    /// Covers ZIP extraction and SQLite import to staging tables.
    /// Default: 120 (2 hours). For large SAN uploads (10GB+), consider 360-480 minutes.
    /// </summary>
    public int UploadProcessingMinutes { get; set; } = 120;

    /// <summary>
    /// Validation job timeout in minutes.
    /// Covers data validation from staging to production readiness.
    /// Default: 120 (2 hours). For large datasets (100M+ ACEs), consider 240-360 minutes.
    /// </summary>
    public int ValidationMinutes { get; set; } = 120;

    /// <summary>
    /// Migration job timeout in minutes.
    /// Covers data migration from staging to production tables.
    /// Default: 120 (2 hours). For large datasets, consider 240-360 minutes.
    /// </summary>
    public int MigrationMinutes { get; set; } = 120;

    /// <summary>
    /// Combined validation and migration job timeout in minutes.
    /// Default: 240 (4 hours). For large datasets, consider 480-720 minutes.
    /// </summary>
    public int ValidateAndMigrateMinutes { get; set; } = 240;

    /// <summary>
    /// Deletion job timeout in minutes for removing collections.
    /// Default: 60 (1 hour). For large datasets, consider 120-180 minutes.
    /// </summary>
    public int DeletionMinutes { get; set; } = 60;

    /// <summary>
    /// Orphaned data cleanup job timeout in minutes.
    /// Default: 120 (2 hours).
    /// </summary>
    public int OrphanedCleanupMinutes { get; set; } = 120;

    /// <summary>
    /// Schema truncate job timeout in minutes.
    /// Default: 120 (2 hours).
    /// </summary>
    public int SchemaTruncateMinutes { get; set; } = 120;

    // Convenience properties for seconds (used by Hangfire filters)

    /// <summary>Gets upload processing timeout in seconds.</summary>
    public int UploadProcessingSeconds => UploadProcessingMinutes * 60;

    /// <summary>Gets validation timeout in seconds.</summary>
    public int ValidationSeconds => ValidationMinutes * 60;

    /// <summary>Gets migration timeout in seconds.</summary>
    public int MigrationSeconds => MigrationMinutes * 60;

    /// <summary>Gets validate and migrate timeout in seconds.</summary>
    public int ValidateAndMigrateSeconds => ValidateAndMigrateMinutes * 60;

    /// <summary>Gets deletion timeout in seconds.</summary>
    public int DeletionSeconds => DeletionMinutes * 60;

    /// <summary>Gets orphaned cleanup timeout in seconds.</summary>
    public int OrphanedCleanupSeconds => OrphanedCleanupMinutes * 60;

    /// <summary>Gets schema truncate timeout in seconds.</summary>
    public int SchemaTruncateSeconds => SchemaTruncateMinutes * 60;
}

/// <summary>
/// HTTP server (Kestrel) settings for connection handling.
/// </summary>
public class HttpServerSettings
{
    /// <summary>
    /// Keep-alive timeout in minutes. Connections idle longer than this are closed.
    /// Default: 60 minutes. Increase for very large uploads over slow connections.
    /// </summary>
    public int KeepAliveTimeoutMinutes { get; set; } = 60;

    /// <summary>
    /// Request headers timeout in minutes. Time allowed for client to send headers.
    /// Default: 60 minutes. Increase for very large uploads.
    /// </summary>
    public int RequestHeadersTimeoutMinutes { get; set; } = 60;
}
