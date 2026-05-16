using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.DataProtection;

namespace CLAWS.Web.Services;

/// <summary>
/// Service for managing configuration stored in local JSON files.
/// </summary>
public interface IConfigurationFileService
{
    /// <summary>
    /// Saves SQL Server configuration to the local config file.
    /// Optionally encrypts the password using Windows DPAPI.
    /// </summary>
    /// <param name="config">The configuration to save.</param>
    /// <param name="plainTextPassword">Optional plain text password to encrypt and save. If null, password is not changed.</param>
    Task SaveSqlServerConfigAsync(SqlServerFileConfig config, string? plainTextPassword = null);

    /// <summary>
    /// Loads SQL Server configuration from the local config file.
    /// </summary>
    SqlServerFileConfig? LoadSqlServerConfig();

    /// <summary>
    /// Decrypts the SQL Server password for use in connection strings.
    /// Uses Windows DPAPI for decryption.
    /// </summary>
    /// <returns>The decrypted password, or null if not configured.</returns>
    string? DecryptSqlServerPassword();

    /// <summary>
    /// Saves storage configuration to the local config file.
    /// </summary>
    Task SaveStorageConfigAsync(string importBasePath);

    /// <summary>
    /// Saves authorization configuration to the local config file.
    /// </summary>
    Task SaveAuthorizationConfigAsync(
        string? siteAdminGroup,
        string? ntfsPermsAdminGroup,
        string? adAdminGroup);

    /// <summary>
    /// Saves disk space monitoring configuration to the local config file.
    /// </summary>
    Task SaveDiskSpaceConfigAsync(double warningThresholdPercent, double criticalThresholdPercent);

    /// <summary>
    /// Saves database performance configuration to the local config file.
    /// </summary>
    Task SaveDatabasePerformanceConfigAsync(int commandTimeoutMinutes, int connectionTimeoutSeconds, int importBatchSize, int maxConcurrentExtractions, int deletionBatchSize, int bulkCopyTimeoutSeconds, bool partitioningEnabled, bool autoPreparePartitions);

    /// <summary>
    /// Saves upload limits configuration to the local config file.
    /// </summary>
    Task SaveUploadLimitsConfigAsync(long maxUploadSizeBytes, long maxExtractedSizeBytes, long minFreeDiskSpaceBytes, double maxCompressionRatio);

    /// <summary>
    /// Saves import configuration to the local config file.
    /// </summary>
    Task SaveImportConfigAsync(string transactionMode, string duplicateHandling, bool enableAutomaticValidation, bool enableAutomaticMerge, string integrityCheckMode, int autoIntegrityCheckThresholdMB);

    /// <summary>
    /// Saves cleanup configuration to the local config file.
    /// </summary>
    Task SaveCleanupConfigAsync(bool autoPruneCompleted, int completedRetentionDays, int errorRetentionDays, int extractionRetentionDays);

    /// <summary>
    /// Saves AD collection cleanup configuration to the local config file.
    /// </summary>
    Task SaveAdCollectionCleanupConfigAsync(bool autoPruneAdCollections, int adCollectionsToKeepPerDomain, string adCollectionPruneSchedule);

    /// <summary>
    /// Saves LDAP configuration to the local config file.
    /// </summary>
    Task SaveLdapConfigAsync(LdapFileConfig config);

    /// <summary>
    /// Saves Cloud Integration configuration to the local config file.
    /// Encrypts the password using ASP.NET Core Data Protection.
    /// </summary>
    /// <param name="config">The configuration to save.</param>
    /// <param name="plainTextPassword">Optional plain text password to encrypt and save. If null, password is not changed.</param>
    Task SaveCloudIntegrationConfigAsync(CloudIntegrationFileConfig config, string? plainTextPassword = null);

    /// <summary>
    /// Loads Cloud Integration configuration from the local config file.
    /// </summary>
    CloudIntegrationFileConfig? LoadCloudIntegrationConfig();

    /// <summary>
    /// Decrypts the Cloud Integration service account password for use in LDAP connections.
    /// </summary>
    /// <returns>The decrypted password, or null if not configured.</returns>
    string? DecryptCloudIntegrationPassword();

    /// <summary>
    /// Saves job timeout configuration to the local config file.
    /// </summary>
    Task SaveJobTimeoutsConfigAsync(JobTimeoutsFileConfig config);

    /// <summary>
    /// Saves HTTP server configuration to the local config file.
    /// </summary>
    Task SaveHttpServerConfigAsync(HttpServerFileConfig config);

    /// <summary>
    /// Saves logging configuration to the local config file.
    /// </summary>
    Task SaveLoggingSettingsAsync(
        bool enableExtendedLogging,
        bool enableRequestLogging,
        bool enablePerformanceLogging,
        int performanceThresholdMs,
        bool enableUploadDiagnostics,
        int uploadProgressIntervalMB,
        int uploadProgressIntervalPercent,
        int fileLogRetentionDays,
        int databaseLogRetentionDays,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Saves chunked upload configuration to the local config file.
    /// </summary>
    Task SaveChunkedUploadConfigAsync(
        bool enabled,
        int chunkSizeBytes,
        long chunkedThresholdBytes,
        int maxConcurrentUploadsPerUser,
        int maxConcurrentUploadsGlobal,
        int maxConcurrentChunksPerUpload,
        int sessionExpirationHours,
        int expirationWarningMinutes,
        int maxChunkRetries);

    /// <summary>
    /// Loads LDAP configuration from the local config file.
    /// </summary>
    LdapFileConfig? LoadLdapConfig();

    /// <summary>
    /// Tests a SQL Server connection with the given configuration.
    /// </summary>
    /// <param name="config">The SQL Server configuration.</param>
    /// <param name="plainTextPassword">Optional plain text password for testing (not encrypted).</param>
    Task<(bool Success, string Message)> TestSqlConnectionAsync(SqlServerFileConfig config, string? plainTextPassword = null);
}

/// <summary>
/// SQL Server configuration for file storage.
/// </summary>
public class SqlServerFileConfig
{
    [JsonPropertyName("Server")]
    public string Server { get; set; } = string.Empty;

    [JsonPropertyName("Database")]
    public string Database { get; set; } = string.Empty;

    [JsonPropertyName("UseWindowsAuth")]
    public bool UseWindowsAuth { get; set; } = true;

    [JsonPropertyName("Username")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Username { get; set; }

    /// <summary>
    /// Plain text password (deprecated, for backward compatibility only).
    /// New configurations should use EncryptedPassword.
    /// </summary>
    [JsonPropertyName("Password")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Password { get; set; }

    /// <summary>
    /// DPAPI-encrypted password (base64 encoded).
    /// This is the preferred storage method for SQL authentication.
    /// </summary>
    [JsonPropertyName("EncryptedPassword")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? EncryptedPassword { get; set; }

    [JsonPropertyName("TrustServerCertificate")]
    public bool TrustServerCertificate { get; set; } = true;

    [JsonPropertyName("Encrypt")]
    public string Encrypt { get; set; } = "Optional";

    /// <summary>
    /// Builds a connection string using the provided decrypted password.
    /// </summary>
    /// <param name="decryptedPassword">The decrypted password to use, or null to use Windows auth.</param>
    public string BuildConnectionString(string? decryptedPassword = null)
    {
        var builder = new Microsoft.Data.SqlClient.SqlConnectionStringBuilder
        {
            DataSource = Server,
            InitialCatalog = Database,
            TrustServerCertificate = TrustServerCertificate
        };

        // Set encryption mode
        if (Encrypt.Equals("Optional", StringComparison.OrdinalIgnoreCase))
        {
            builder.Encrypt = Microsoft.Data.SqlClient.SqlConnectionEncryptOption.Optional;
        }
        else if (Encrypt.Equals("Mandatory", StringComparison.OrdinalIgnoreCase))
        {
            builder.Encrypt = Microsoft.Data.SqlClient.SqlConnectionEncryptOption.Mandatory;
        }
        else if (Encrypt.Equals("Strict", StringComparison.OrdinalIgnoreCase))
        {
            builder.Encrypt = Microsoft.Data.SqlClient.SqlConnectionEncryptOption.Strict;
        }

        if (UseWindowsAuth)
        {
            builder.IntegratedSecurity = true;
        }
        else if (!string.IsNullOrEmpty(Username))
        {
            builder.UserID = Username;
            // Use provided decrypted password, fall back to legacy plain text Password
            builder.Password = decryptedPassword ?? Password ?? string.Empty;
        }

        return builder.ConnectionString;
    }
}

/// <summary>
/// Root object for local configuration file (wraps AppSettings).
/// </summary>
public class LocalConfigFile
{
    [JsonPropertyName("AppSettings")]
    public AppSettingsFileConfig AppSettings { get; set; } = new();
}

/// <summary>
/// AppSettings section of local config file.
/// </summary>
public class AppSettingsFileConfig
{
    [JsonPropertyName("SqlServer")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public SqlServerFileConfig? SqlServer { get; set; }

    [JsonPropertyName("Storage")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public StorageFileConfig? Storage { get; set; }

    [JsonPropertyName("Authorization")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public AuthorizationFileConfig? Authorization { get; set; }

    [JsonPropertyName("DiskSpace")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public DiskSpaceFileConfig? DiskSpace { get; set; }

    [JsonPropertyName("DatabasePerformance")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public DatabasePerformanceFileConfig? DatabasePerformance { get; set; }

    [JsonPropertyName("UploadLimits")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public UploadLimitsFileConfig? UploadLimits { get; set; }

    [JsonPropertyName("Import")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public ImportFileConfig? Import { get; set; }

    [JsonPropertyName("Cleanup")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public CleanupFileConfig? Cleanup { get; set; }

    [JsonPropertyName("Ldap")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public LdapFileConfig? Ldap { get; set; }

    [JsonPropertyName("CloudIntegration")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public CloudIntegrationFileConfig? CloudIntegration { get; set; }

    [JsonPropertyName("JobTimeouts")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JobTimeoutsFileConfig? JobTimeouts { get; set; }

    [JsonPropertyName("HttpServer")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public HttpServerFileConfig? HttpServer { get; set; }

    [JsonPropertyName("Logging")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public LoggingFileConfig? Logging { get; set; }

    [JsonPropertyName("ChunkedUpload")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public ChunkedUploadFileConfig? ChunkedUpload { get; set; }
}

public class StorageFileConfig
{
    [JsonPropertyName("ImportBasePath")]
    public string ImportBasePath { get; set; } = string.Empty;
}

public class AuthorizationFileConfig
{
    [JsonPropertyName("SiteAdminGroup")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? SiteAdminGroup { get; set; }

    [JsonPropertyName("NtfsPermsAdminGroup")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? NtfsPermsAdminGroup { get; set; }

    [JsonPropertyName("AdAdminGroup")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? AdAdminGroup { get; set; }
}

public class DiskSpaceFileConfig
{
    [JsonPropertyName("WarningThresholdPercent")]
    public double WarningThresholdPercent { get; set; } = 20.0;

    [JsonPropertyName("CriticalThresholdPercent")]
    public double CriticalThresholdPercent { get; set; } = 10.0;
}

public class DatabasePerformanceFileConfig
{
    [JsonPropertyName("CommandTimeoutMinutes")]
    public int CommandTimeoutMinutes { get; set; } = 30;

    [JsonPropertyName("ConnectionTimeoutSeconds")]
    public int ConnectionTimeoutSeconds { get; set; } = 30;

    [JsonPropertyName("ImportBatchSize")]
    public int ImportBatchSize { get; set; } = 10000;

    [JsonPropertyName("MaxConcurrentExtractions")]
    public int MaxConcurrentExtractions { get; set; } = 2;

    [JsonPropertyName("DeletionBatchSize")]
    public int DeletionBatchSize { get; set; } = 50000;

    [JsonPropertyName("BulkCopyTimeoutSeconds")]
    public int BulkCopyTimeoutSeconds { get; set; } = 600;

    [JsonPropertyName("PartitioningEnabled")]
    public bool PartitioningEnabled { get; set; } = false;

    [JsonPropertyName("AutoPreparePartitions")]
    public bool AutoPreparePartitions { get; set; } = true;
}

public class UploadLimitsFileConfig
{
    [JsonPropertyName("MaxUploadSizeBytes")]
    public long MaxUploadSizeBytes { get; set; } = 3L * 1024 * 1024 * 1024; // 3 GB

    [JsonPropertyName("MaxExtractedSizeBytes")]
    public long MaxExtractedSizeBytes { get; set; } = 50L * 1024 * 1024 * 1024; // 50 GB

    [JsonPropertyName("MinFreeDiskSpaceBytes")]
    public long MinFreeDiskSpaceBytes { get; set; } = 50L * 1024 * 1024 * 1024; // 50 GB

    [JsonPropertyName("MaxCompressionRatio")]
    public double MaxCompressionRatio { get; set; } = 100.0;
}

public class ImportFileConfig
{
    [JsonPropertyName("TransactionMode")]
    public string TransactionMode { get; set; } = "PerTable";

    [JsonPropertyName("DuplicateHandling")]
    public string DuplicateHandling { get; set; } = "Reject";

    [JsonPropertyName("EnableAutomaticValidation")]
    public bool EnableAutomaticValidation { get; set; } = false;

    [JsonPropertyName("EnableAutomaticMerge")]
    public bool EnableAutomaticMerge { get; set; } = false;

    [JsonPropertyName("IntegrityCheckMode")]
    public string IntegrityCheckMode { get; set; } = "Quick";

    [JsonPropertyName("AutoIntegrityCheckThresholdMB")]
    public int AutoIntegrityCheckThresholdMB { get; set; } = 500;
}

public class CleanupFileConfig
{
    [JsonPropertyName("AutoPruneCompleted")]
    public bool AutoPruneCompleted { get; set; } = true;

    [JsonPropertyName("CompletedRetentionDays")]
    public int CompletedRetentionDays { get; set; } = 7;

    [JsonPropertyName("ErrorRetentionDays")]
    public int ErrorRetentionDays { get; set; } = 0;

    [JsonPropertyName("ExtractionRetentionDays")]
    public int ExtractionRetentionDays { get; set; } = 7;

    [JsonPropertyName("AutoPruneAdCollections")]
    public bool AutoPruneAdCollections { get; set; } = true;

    [JsonPropertyName("AdCollectionsToKeepPerDomain")]
    public int AdCollectionsToKeepPerDomain { get; set; } = 3;

    [JsonPropertyName("AdCollectionPruneSchedule")]
    public string AdCollectionPruneSchedule { get; set; } = "0 */6 * * *";
}

/// <summary>
/// LDAP configuration for file storage.
/// </summary>
public class LdapFileConfig
{
    [JsonPropertyName("Enabled")]
    public bool Enabled { get; set; } = false;

    [JsonPropertyName("Server")]
    public string Server { get; set; } = string.Empty;

    [JsonPropertyName("Port")]
    public int Port { get; set; } = 636;

    [JsonPropertyName("UseSsl")]
    public bool UseSsl { get; set; } = true;

    [JsonPropertyName("BaseDn")]
    public string BaseDn { get; set; } = string.Empty;

    [JsonPropertyName("UserSearchFilter")]
    public string UserSearchFilter { get; set; } = "(sAMAccountName={0})";

    [JsonPropertyName("Domain")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Domain { get; set; }

    [JsonPropertyName("ConnectionTimeout")]
    public int ConnectionTimeout { get; set; } = 30;

    [JsonPropertyName("AllowKeymasterFallback")]
    public bool AllowKeymasterFallback { get; set; } = true;

    [JsonPropertyName("KeymasterUsername")]
    public string KeymasterUsername { get; set; } = "Keymaster";
}

/// <summary>
/// Cloud Integration configuration for file storage.
/// </summary>
public class CloudIntegrationFileConfig
{
    [JsonPropertyName("Enabled")]
    public bool Enabled { get; set; } = false;

    [JsonPropertyName("Schedule")]
    public string Schedule { get; set; } = "0 4 * * *";

    [JsonPropertyName("LdapSearchBase")]
    public string LdapSearchBase { get; set; } = "OU=DirectoryList,OU=CloudUI,OU=Domain Delegation,DC=ssnc-corp,DC=global";

    [JsonPropertyName("LdapServer")]
    public string LdapServer { get; set; } = string.Empty;

    [JsonPropertyName("LdapPort")]
    public int LdapPort { get; set; } = 636;

    [JsonPropertyName("LdapUseSsl")]
    public bool LdapUseSsl { get; set; } = true;

    [JsonPropertyName("ServiceAccountUsername")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? ServiceAccountUsername { get; set; }

    [JsonPropertyName("ServiceAccountDomain")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? ServiceAccountDomain { get; set; }

    [JsonPropertyName("EncryptedServiceAccountPassword")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? EncryptedServiceAccountPassword { get; set; }

    [JsonPropertyName("ConnectionTimeout")]
    public int ConnectionTimeout { get; set; } = 30;

    [JsonPropertyName("BatchSize")]
    public int BatchSize { get; set; } = 100;

    [JsonPropertyName("DelayBetweenBatchesMs")]
    public int DelayBetweenBatchesMs { get; set; } = 1000;
}

/// <summary>
/// Job timeout configuration for file storage.
/// </summary>
public class JobTimeoutsFileConfig
{
    [JsonPropertyName("UploadProcessingMinutes")]
    public int UploadProcessingMinutes { get; set; } = 120;

    [JsonPropertyName("ValidationMinutes")]
    public int ValidationMinutes { get; set; } = 120;

    [JsonPropertyName("MigrationMinutes")]
    public int MigrationMinutes { get; set; } = 120;

    [JsonPropertyName("ValidateAndMigrateMinutes")]
    public int ValidateAndMigrateMinutes { get; set; } = 240;

    [JsonPropertyName("DeletionMinutes")]
    public int DeletionMinutes { get; set; } = 60;

    [JsonPropertyName("OrphanedCleanupMinutes")]
    public int OrphanedCleanupMinutes { get; set; } = 120;

    [JsonPropertyName("SchemaTruncateMinutes")]
    public int SchemaTruncateMinutes { get; set; } = 120;
}

/// <summary>
/// HTTP server (Kestrel) configuration for file storage.
/// </summary>
public class HttpServerFileConfig
{
    [JsonPropertyName("KeepAliveTimeoutMinutes")]
    public int KeepAliveTimeoutMinutes { get; set; } = 60;

    [JsonPropertyName("RequestHeadersTimeoutMinutes")]
    public int RequestHeadersTimeoutMinutes { get; set; } = 60;
}

public class LoggingFileConfig
{
    [JsonPropertyName("EnableExtendedLogging")]
    public bool EnableExtendedLogging { get; set; } = false;

    [JsonPropertyName("EnableRequestLogging")]
    public bool EnableRequestLogging { get; set; } = false;

    [JsonPropertyName("EnablePerformanceLogging")]
    public bool EnablePerformanceLogging { get; set; } = false;

    [JsonPropertyName("PerformanceThresholdMs")]
    public int PerformanceThresholdMs { get; set; } = 1000;

    [JsonPropertyName("EnableUploadDiagnostics")]
    public bool EnableUploadDiagnostics { get; set; } = false;

    [JsonPropertyName("UploadProgressIntervalMB")]
    public int UploadProgressIntervalMB { get; set; } = 50;

    [JsonPropertyName("UploadProgressIntervalPercent")]
    public int UploadProgressIntervalPercent { get; set; } = 10;

    [JsonPropertyName("FileLogRetentionDays")]
    public int FileLogRetentionDays { get; set; } = 30;

    [JsonPropertyName("DatabaseLogRetentionDays")]
    public int DatabaseLogRetentionDays { get; set; } = 90;
}

public class ChunkedUploadFileConfig
{
    [JsonPropertyName("Enabled")]
    public bool Enabled { get; set; } = true;

    [JsonPropertyName("ChunkSizeBytes")]
    public int ChunkSizeBytes { get; set; } = 50 * 1024 * 1024;

    [JsonPropertyName("ChunkedThresholdBytes")]
    public long ChunkedThresholdBytes { get; set; } = 500L * 1024 * 1024;

    [JsonPropertyName("MaxConcurrentUploadsPerUser")]
    public int MaxConcurrentUploadsPerUser { get; set; } = 2;

    [JsonPropertyName("MaxConcurrentUploadsGlobal")]
    public int MaxConcurrentUploadsGlobal { get; set; } = 10;

    [JsonPropertyName("MaxConcurrentChunksPerUpload")]
    public int MaxConcurrentChunksPerUpload { get; set; } = 3;

    [JsonPropertyName("SessionExpirationHours")]
    public int SessionExpirationHours { get; set; } = 6;

    [JsonPropertyName("ExpirationWarningMinutes")]
    public int ExpirationWarningMinutes { get; set; } = 30;

    [JsonPropertyName("MaxChunkRetries")]
    public int MaxChunkRetries { get; set; } = 3;
}

/// <summary>
/// Implementation of configuration file service.
/// </summary>
public class ConfigurationFileService : IConfigurationFileService
{
    private readonly ILogger<ConfigurationFileService> _logger;
    private readonly string _configFilePath;
    private readonly JsonSerializerOptions _jsonOptions;
    private readonly IDataProtector _protector;
    private static readonly SemaphoreSlim _fileLock = new(1, 1);
    private const string CloudIntegrationPurpose = "CloudIntegration.ServiceAccountPassword";

    public ConfigurationFileService(
        ILogger<ConfigurationFileService> logger,
        IWebHostEnvironment environment,
        IDataProtectionProvider dataProtectionProvider)
    {
        _logger = logger;
        _configFilePath = Path.Combine(environment.ContentRootPath, "appsettings.local.json");
        _jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            PropertyNameCaseInsensitive = true
        };
        _protector = dataProtectionProvider.CreateProtector(CloudIntegrationPurpose);
    }

    [SupportedOSPlatform("windows")]
    public async Task SaveSqlServerConfigAsync(SqlServerFileConfig config, string? plainTextPassword = null)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();

            // Handle password encryption with DPAPI
            if (!string.IsNullOrEmpty(plainTextPassword))
            {
                // Encrypt the new password using Windows DPAPI
                config.EncryptedPassword = EncryptWithDpapi(plainTextPassword);
                config.Password = null; // Clear any legacy plain text password
                _logger.LogDebug("SQL Server password encrypted with DPAPI");
            }
            else if (localConfig.AppSettings.SqlServer?.EncryptedPassword != null && config.EncryptedPassword == null)
            {
                // Preserve existing encrypted password if no new password provided
                config.EncryptedPassword = localConfig.AppSettings.SqlServer.EncryptedPassword;
            }

            // Auto-migrate: if legacy plain text password exists and no encrypted password, encrypt it
            if (!string.IsNullOrEmpty(config.Password) && string.IsNullOrEmpty(config.EncryptedPassword))
            {
                _logger.LogInformation("Auto-migrating legacy plain text SQL password to encrypted format");
                config.EncryptedPassword = EncryptWithDpapi(config.Password);
                config.Password = null;
            }

            localConfig.AppSettings.SqlServer = config;
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("SQL Server configuration saved to {Path}", _configFilePath);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    [SupportedOSPlatform("windows")]
    public string? DecryptSqlServerPassword()
    {
        var config = LoadSqlServerConfig();
        if (config == null)
            return null;

        // Try encrypted password first
        if (!string.IsNullOrEmpty(config.EncryptedPassword))
        {
            try
            {
                return DecryptWithDpapi(config.EncryptedPassword);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to decrypt SQL Server password with DPAPI. " +
                    "The password may need to be re-entered if the machine or service account has changed.");
                return null;
            }
        }

        // Fall back to legacy plain text password for backward compatibility
        if (!string.IsNullOrEmpty(config.Password))
        {
            _logger.LogWarning("Using legacy plain text SQL Server password. " +
                "Re-save the configuration to migrate to encrypted storage.");
            return config.Password;
        }

        return null;
    }

    /// <summary>
    /// Encrypts a string using Windows DPAPI (LocalMachine scope).
    /// </summary>
    [SupportedOSPlatform("windows")]
    private static string EncryptWithDpapi(string plainText)
    {
        var plainBytes = Encoding.UTF8.GetBytes(plainText);
        var encryptedBytes = ProtectedData.Protect(
            plainBytes,
            null, // No additional entropy
            DataProtectionScope.LocalMachine);
        return Convert.ToBase64String(encryptedBytes);
    }

    /// <summary>
    /// Decrypts a DPAPI-encrypted string (LocalMachine scope).
    /// </summary>
    [SupportedOSPlatform("windows")]
    private static string DecryptWithDpapi(string encryptedBase64)
    {
        var encryptedBytes = Convert.FromBase64String(encryptedBase64);
        var decryptedBytes = ProtectedData.Unprotect(
            encryptedBytes,
            null, // No additional entropy
            DataProtectionScope.LocalMachine);
        return Encoding.UTF8.GetString(decryptedBytes);
    }

    public SqlServerFileConfig? LoadSqlServerConfig()
    {
        var config = LoadConfigFileSync();
        return config?.AppSettings.SqlServer;
    }

    public async Task SaveStorageConfigAsync(string importBasePath)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            localConfig.AppSettings.Storage = new StorageFileConfig { ImportBasePath = importBasePath };
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("Storage configuration saved to {Path}", _configFilePath);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveAuthorizationConfigAsync(
        string? siteAdminGroup,
        string? ntfsPermsAdminGroup,
        string? adAdminGroup)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            localConfig.AppSettings.Authorization = new AuthorizationFileConfig
            {
                SiteAdminGroup = siteAdminGroup,
                NtfsPermsAdminGroup = ntfsPermsAdminGroup,
                AdAdminGroup = adAdminGroup
            };
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("Authorization configuration saved to {Path}", _configFilePath);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveDiskSpaceConfigAsync(double warningThresholdPercent, double criticalThresholdPercent)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            localConfig.AppSettings.DiskSpace = new DiskSpaceFileConfig
            {
                WarningThresholdPercent = warningThresholdPercent,
                CriticalThresholdPercent = criticalThresholdPercent
            };
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("Disk space configuration saved to {Path}: Warning={Warning}%, Critical={Critical}%",
                _configFilePath, warningThresholdPercent, criticalThresholdPercent);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveDatabasePerformanceConfigAsync(int commandTimeoutMinutes, int connectionTimeoutSeconds, int importBatchSize, int maxConcurrentExtractions, int deletionBatchSize, int bulkCopyTimeoutSeconds, bool partitioningEnabled, bool autoPreparePartitions)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            localConfig.AppSettings.DatabasePerformance = new DatabasePerformanceFileConfig
            {
                CommandTimeoutMinutes = commandTimeoutMinutes,
                ConnectionTimeoutSeconds = connectionTimeoutSeconds,
                ImportBatchSize = importBatchSize,
                MaxConcurrentExtractions = maxConcurrentExtractions,
                DeletionBatchSize = deletionBatchSize,
                BulkCopyTimeoutSeconds = bulkCopyTimeoutSeconds,
                PartitioningEnabled = partitioningEnabled,
                AutoPreparePartitions = autoPreparePartitions
            };
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("Database performance configuration saved to {Path}: CommandTimeout={Timeout}min, ImportBatchSize={ImportBatch}, DeletionBatchSize={DeletionBatch}, BulkCopyTimeout={BulkCopy}s, Partitioning={Partitioning}",
                _configFilePath, commandTimeoutMinutes, importBatchSize, deletionBatchSize, bulkCopyTimeoutSeconds, partitioningEnabled);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveUploadLimitsConfigAsync(long maxUploadSizeBytes, long maxExtractedSizeBytes, long minFreeDiskSpaceBytes, double maxCompressionRatio)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            localConfig.AppSettings.UploadLimits = new UploadLimitsFileConfig
            {
                MaxUploadSizeBytes = maxUploadSizeBytes,
                MaxExtractedSizeBytes = maxExtractedSizeBytes,
                MinFreeDiskSpaceBytes = minFreeDiskSpaceBytes,
                MaxCompressionRatio = maxCompressionRatio
            };
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("Upload limits configuration saved to {Path}: MaxUpload={MaxUpload}GB",
                _configFilePath, maxUploadSizeBytes / (1024.0 * 1024.0 * 1024.0));
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveImportConfigAsync(string transactionMode, string duplicateHandling, bool enableAutomaticValidation, bool enableAutomaticMerge, string integrityCheckMode, int autoIntegrityCheckThresholdMB)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            localConfig.AppSettings.Import = new ImportFileConfig
            {
                TransactionMode = transactionMode,
                DuplicateHandling = duplicateHandling,
                EnableAutomaticValidation = enableAutomaticValidation,
                EnableAutomaticMerge = enableAutomaticMerge,
                IntegrityCheckMode = integrityCheckMode,
                AutoIntegrityCheckThresholdMB = autoIntegrityCheckThresholdMB
            };
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("Import configuration saved to {Path}: TransactionMode={Mode}, DuplicateHandling={Handling}, AutoValidation={AutoValidation}, AutoMerge={AutoMerge}, IntegrityCheck={IntegrityCheck}",
                _configFilePath, transactionMode, duplicateHandling, enableAutomaticValidation, enableAutomaticMerge, integrityCheckMode);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveCleanupConfigAsync(bool autoPruneCompleted, int completedRetentionDays, int errorRetentionDays, int extractionRetentionDays)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            var existingCleanup = localConfig.AppSettings.Cleanup ?? new CleanupFileConfig();
            localConfig.AppSettings.Cleanup = new CleanupFileConfig
            {
                AutoPruneCompleted = autoPruneCompleted,
                CompletedRetentionDays = completedRetentionDays,
                ErrorRetentionDays = errorRetentionDays,
                ExtractionRetentionDays = extractionRetentionDays,
                // Preserve AD collection settings
                AutoPruneAdCollections = existingCleanup.AutoPruneAdCollections,
                AdCollectionsToKeepPerDomain = existingCleanup.AdCollectionsToKeepPerDomain,
                AdCollectionPruneSchedule = existingCleanup.AdCollectionPruneSchedule
            };
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("Cleanup configuration saved to {Path}: AutoPrune={AutoPrune}, CompletedRetention={Days}d",
                _configFilePath, autoPruneCompleted, completedRetentionDays);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveAdCollectionCleanupConfigAsync(bool autoPruneAdCollections, int adCollectionsToKeepPerDomain, string adCollectionPruneSchedule)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            var existingCleanup = localConfig.AppSettings.Cleanup ?? new CleanupFileConfig();
            localConfig.AppSettings.Cleanup = new CleanupFileConfig
            {
                // Preserve file cleanup settings
                AutoPruneCompleted = existingCleanup.AutoPruneCompleted,
                CompletedRetentionDays = existingCleanup.CompletedRetentionDays,
                ErrorRetentionDays = existingCleanup.ErrorRetentionDays,
                ExtractionRetentionDays = existingCleanup.ExtractionRetentionDays,
                // Update AD collection settings
                AutoPruneAdCollections = autoPruneAdCollections,
                AdCollectionsToKeepPerDomain = adCollectionsToKeepPerDomain,
                AdCollectionPruneSchedule = adCollectionPruneSchedule
            };
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("AD collection cleanup configuration saved to {Path}: AutoPrune={AutoPrune}, KeepPerDomain={KeepCount}, Schedule={Schedule}",
                _configFilePath, autoPruneAdCollections, adCollectionsToKeepPerDomain, adCollectionPruneSchedule);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveLdapConfigAsync(LdapFileConfig config)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            localConfig.AppSettings.Ldap = config;
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("LDAP configuration saved to {Path}: Server={Server}, Enabled={Enabled}",
                _configFilePath, config.Server, config.Enabled);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public LdapFileConfig? LoadLdapConfig()
    {
        var config = LoadConfigFileSync();
        return config?.AppSettings.Ldap;
    }

    public async Task SaveCloudIntegrationConfigAsync(CloudIntegrationFileConfig config, string? plainTextPassword = null)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();

            // Handle password encryption
            if (!string.IsNullOrEmpty(plainTextPassword))
            {
                // Encrypt the new password
                config.EncryptedServiceAccountPassword = _protector.Protect(plainTextPassword);
                _logger.LogDebug("Cloud Integration service account password encrypted");
            }
            else if (localConfig.AppSettings.CloudIntegration?.EncryptedServiceAccountPassword != null)
            {
                // Preserve existing encrypted password if no new password provided
                config.EncryptedServiceAccountPassword = localConfig.AppSettings.CloudIntegration.EncryptedServiceAccountPassword;
            }

            localConfig.AppSettings.CloudIntegration = config;
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("Cloud Integration configuration saved to {Path}: Enabled={Enabled}, Server={Server}, SearchBase={SearchBase}, HasPassword={HasPassword}",
                _configFilePath, config.Enabled, config.LdapServer, config.LdapSearchBase,
                !string.IsNullOrEmpty(config.EncryptedServiceAccountPassword));
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public CloudIntegrationFileConfig? LoadCloudIntegrationConfig()
    {
        var config = LoadConfigFileSync();
        var cloudConfig = config?.AppSettings.CloudIntegration;

        if (cloudConfig != null)
        {
            _logger.LogDebug("LoadCloudIntegrationConfig: Enabled={Enabled}, Server={Server}, SearchBase={SearchBase}",
                cloudConfig.Enabled, cloudConfig.LdapServer, cloudConfig.LdapSearchBase);
        }
        else
        {
            _logger.LogDebug("LoadCloudIntegrationConfig: CloudIntegration section is null");
        }

        return cloudConfig;
    }

    public string? DecryptCloudIntegrationPassword()
    {
        var config = LoadCloudIntegrationConfig();
        if (string.IsNullOrEmpty(config?.EncryptedServiceAccountPassword))
        {
            return null;
        }

        try
        {
            return _protector.Unprotect(config.EncryptedServiceAccountPassword);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to decrypt Cloud Integration service account password. " +
                "The password may need to be re-entered if the data protection keys have changed.");
            return null;
        }
    }

    public async Task SaveJobTimeoutsConfigAsync(JobTimeoutsFileConfig config)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            localConfig.AppSettings.JobTimeouts = config;
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("Job timeouts configuration saved to {Path}: UploadProcessing={Upload}min, Validation={Validation}min, Migration={Migration}min",
                _configFilePath, config.UploadProcessingMinutes, config.ValidationMinutes, config.MigrationMinutes);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveHttpServerConfigAsync(HttpServerFileConfig config)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            localConfig.AppSettings.HttpServer = config;
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("HTTP server configuration saved to {Path}: KeepAlive={KeepAlive}min, RequestHeaders={Headers}min",
                _configFilePath, config.KeepAliveTimeoutMinutes, config.RequestHeadersTimeoutMinutes);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveLoggingSettingsAsync(
        bool enableExtendedLogging,
        bool enableRequestLogging,
        bool enablePerformanceLogging,
        int performanceThresholdMs,
        bool enableUploadDiagnostics,
        int uploadProgressIntervalMB,
        int uploadProgressIntervalPercent,
        int fileLogRetentionDays,
        int databaseLogRetentionDays,
        CancellationToken cancellationToken = default)
    {
        await _fileLock.WaitAsync(cancellationToken);
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            localConfig.AppSettings.Logging ??= new LoggingFileConfig();
            localConfig.AppSettings.Logging.EnableExtendedLogging = enableExtendedLogging;
            localConfig.AppSettings.Logging.EnableRequestLogging = enableRequestLogging;
            localConfig.AppSettings.Logging.EnablePerformanceLogging = enablePerformanceLogging;
            localConfig.AppSettings.Logging.PerformanceThresholdMs = performanceThresholdMs;
            localConfig.AppSettings.Logging.EnableUploadDiagnostics = enableUploadDiagnostics;
            localConfig.AppSettings.Logging.UploadProgressIntervalMB = uploadProgressIntervalMB;
            localConfig.AppSettings.Logging.UploadProgressIntervalPercent = uploadProgressIntervalPercent;
            localConfig.AppSettings.Logging.FileLogRetentionDays = fileLogRetentionDays;
            localConfig.AppSettings.Logging.DatabaseLogRetentionDays = databaseLogRetentionDays;
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("Logging configuration saved: ExtendedLogging={Extended}, RequestLogging={Request}, PerformanceLogging={Perf}, UploadDiagnostics={Upload}",
                enableExtendedLogging, enableRequestLogging, enablePerformanceLogging, enableUploadDiagnostics);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveChunkedUploadConfigAsync(
        bool enabled,
        int chunkSizeBytes,
        long chunkedThresholdBytes,
        int maxConcurrentUploadsPerUser,
        int maxConcurrentUploadsGlobal,
        int maxConcurrentChunksPerUpload,
        int sessionExpirationHours,
        int expirationWarningMinutes,
        int maxChunkRetries)
    {
        await _fileLock.WaitAsync();
        try
        {
            var localConfig = await LoadConfigFileAsync() ?? new LocalConfigFile();
            localConfig.AppSettings.ChunkedUpload = new ChunkedUploadFileConfig
            {
                Enabled = enabled,
                ChunkSizeBytes = chunkSizeBytes,
                ChunkedThresholdBytes = chunkedThresholdBytes,
                MaxConcurrentUploadsPerUser = maxConcurrentUploadsPerUser,
                MaxConcurrentUploadsGlobal = maxConcurrentUploadsGlobal,
                MaxConcurrentChunksPerUpload = maxConcurrentChunksPerUpload,
                SessionExpirationHours = sessionExpirationHours,
                ExpirationWarningMinutes = expirationWarningMinutes,
                MaxChunkRetries = maxChunkRetries
            };
            await SaveConfigFileAsync(localConfig);
            _logger.LogInformation("Chunked upload configuration saved: Enabled={Enabled}, ChunkSize={ChunkSize}MB, Threshold={Threshold}MB",
                enabled, chunkSizeBytes / (1024 * 1024), chunkedThresholdBytes / (1024 * 1024));
        }
        finally
        {
            _fileLock.Release();
        }
    }

    [SupportedOSPlatform("windows")]
    public async Task<(bool Success, string Message)> TestSqlConnectionAsync(SqlServerFileConfig config, string? plainTextPassword = null)
    {
        if (string.IsNullOrWhiteSpace(config.Server))
        {
            return (false, "Server name is required.");
        }

        if (string.IsNullOrWhiteSpace(config.Database))
        {
            return (false, "Database name is required.");
        }

        try
        {
            // Use provided plain text password, or try to decrypt existing, or fall back to legacy
            var password = plainTextPassword;
            if (string.IsNullOrEmpty(password) && !config.UseWindowsAuth)
            {
                // Try to get password from encrypted storage or legacy plain text
                if (!string.IsNullOrEmpty(config.EncryptedPassword))
                {
                    try
                    {
                        password = DecryptWithDpapi(config.EncryptedPassword);
                    }
                    catch
                    {
                        // Fall through to legacy password
                    }
                }
                password ??= config.Password;
            }

            var connectionString = config.BuildConnectionString(password);
            await using var connection = new Microsoft.Data.SqlClient.SqlConnection(connectionString);
            await connection.OpenAsync();

            // Test we can query
            await using var command = connection.CreateCommand();
            command.CommandText = "SELECT 1";
            await command.ExecuteScalarAsync();

            return (true, $"Successfully connected to {config.Server}/{config.Database}");
        }
        catch (Microsoft.Data.SqlClient.SqlException ex)
        {
            _logger.LogWarning(ex, "SQL connection test failed");
            return (false, $"Connection failed: {ex.Message}");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "SQL connection test failed with unexpected error");
            return (false, $"Connection failed: {ex.Message}");
        }
    }

    private async Task<LocalConfigFile?> LoadConfigFileAsync()
    {
        if (!File.Exists(_configFilePath))
        {
            return null;
        }

        try
        {
            var json = await File.ReadAllTextAsync(_configFilePath);
            return JsonSerializer.Deserialize<LocalConfigFile>(json, _jsonOptions);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to load config file {Path}", _configFilePath);
            return null;
        }
    }

    private LocalConfigFile? LoadConfigFileSync()
    {
        if (!File.Exists(_configFilePath))
        {
            return null;
        }

        try
        {
            var json = File.ReadAllText(_configFilePath);
            return JsonSerializer.Deserialize<LocalConfigFile>(json, _jsonOptions);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to load config file {Path}", _configFilePath);
            return null;
        }
    }

    private async Task SaveConfigFileAsync(LocalConfigFile config)
    {
        var json = JsonSerializer.Serialize(config, _jsonOptions);
        await File.WriteAllTextAsync(_configFilePath, json);
    }
}
