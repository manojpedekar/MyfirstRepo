using Hangfire;
using Hangfire.Dashboard;
using Hangfire.SqlServer;
using Microsoft.AspNetCore.Authentication.Negotiate;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using CLAWS.Core.Configuration;
using CLAWS.Core.Import;
using CLAWS.Core.Services;
using CLAWS.Core.Validation;
using CLAWS.Data.Context;
using CLAWS.Data.Repositories;
using CLAWS.Jobs;
using CLAWS.Jobs.Filters;
using CLAWS.Web.Hubs;
using CLAWS.Web.Services;
using Serilog;
using Serilog.Events;
using Serilog.Sinks.MSSqlServer;
using System.Data;
using System.Reflection;

var builder = WebApplication.CreateBuilder(args);

// Add local configuration file (for web UI configuration)
builder.Configuration.AddJsonFile("appsettings.local.json", optional: true, reloadOnChange: true);

// Load configuration early so we can configure logging properly
var appSettings = new AppSettings();
builder.Configuration.GetSection("AppSettings").Bind(appSettings);

// Decrypt SQL Server password if encrypted with DPAPI (Windows-only)
#pragma warning disable CA1416 // Platform compatibility - this app is Windows/IIS only
if (!string.IsNullOrEmpty(appSettings.SqlServer.EncryptedPassword) && string.IsNullOrEmpty(appSettings.SqlServer.Password))
{
    try
    {
        var encryptedBytes = Convert.FromBase64String(appSettings.SqlServer.EncryptedPassword);
        var decryptedBytes = System.Security.Cryptography.ProtectedData.Unprotect(
            encryptedBytes,
            null,
            System.Security.Cryptography.DataProtectionScope.LocalMachine);
        appSettings.SqlServer.Password = System.Text.Encoding.UTF8.GetString(decryptedBytes);
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Warning: Failed to decrypt SQL Server password: {ex.Message}");
        // Password decryption failed - will use null password (may cause connection failures)
    }
}
#pragma warning restore CA1416

// Configure Serilog - file logging always enabled
var logPath = Path.Combine(
    builder.Environment.ContentRootPath,
    "Logs",
    "CLAWS-.log");

// Enable Serilog self-logging for diagnostics
var selfLogPath = Path.Combine(builder.Environment.ContentRootPath, "Logs", "serilog-selflog.txt");
Serilog.Debugging.SelfLog.Enable(msg => File.AppendAllText(selfLogPath, $"{DateTime.UtcNow:o} {msg}{Environment.NewLine}"));

var logConfig = new LoggerConfiguration()
    .MinimumLevel.Information()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
    .MinimumLevel.Override("Microsoft.Hosting.Lifetime", LogEventLevel.Information)
    .MinimumLevel.Override("Hangfire", LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .Enrich.WithMachineName()
    .Enrich.WithProcessId()
    .WriteTo.Console()
    .WriteTo.File(
        logPath,
        rollingInterval: RollingInterval.Day,
        retainedFileCountLimit: appSettings.Logging.FileLogRetentionDays,
        fileSizeLimitBytes: 100 * 1024 * 1024);

// Add SQL Server logging if database is configured
if (appSettings.SqlServer.IsConfigured)
{
    var columnOptions = new ColumnOptions();
    columnOptions.Store.Add(StandardColumn.LogEvent); // Store structured log data as JSON
    columnOptions.TimeStamp.ConvertToUtc = true;

    // Add custom columns for context data
    columnOptions.AdditionalColumns = new List<SqlColumn>
    {
        new SqlColumn { ColumnName = "MachineName", DataType = SqlDbType.NVarChar, DataLength = 100, AllowNull = true },
        new SqlColumn { ColumnName = "SourceContext", DataType = SqlDbType.NVarChar, DataLength = 256, AllowNull = true },
        new SqlColumn { ColumnName = "UploadId", DataType = SqlDbType.UniqueIdentifier, AllowNull = true },
        new SqlColumn { ColumnName = "UserId", DataType = SqlDbType.NVarChar, DataLength = 256, AllowNull = true }
    };

    var sinkOptions = new MSSqlServerSinkOptions
    {
        TableName = "SerilogLogs",
        SchemaName = "app",
        AutoCreateSqlTable = true,
        BatchPostingLimit = 10,
        BatchPeriod = TimeSpan.FromSeconds(1)
    };

    logConfig.WriteTo.MSSqlServer(
        connectionString: appSettings.SqlServer.BuildConnectionString(),
        sinkOptions: sinkOptions,
        columnOptions: columnOptions,
        restrictedToMinimumLevel: LogEventLevel.Information);
}

Log.Logger = logConfig.CreateLogger();

builder.Host.UseSerilog();

// Set default storage paths if not configured
if (string.IsNullOrEmpty(appSettings.Storage.ImportBasePath))
{
    appSettings.Storage.ImportBasePath = Path.Combine(builder.Environment.ContentRootPath, "ImportData");
}
if (string.IsNullOrEmpty(appSettings.Logging.LogDirectory))
{
    appSettings.Logging.LogDirectory = Path.Combine(builder.Environment.ContentRootPath, "Logs");
}

// Register configuration
builder.Services.AddSingleton(appSettings);
builder.Services.AddSingleton(appSettings.SqlServer);
builder.Services.AddSingleton(appSettings.Authorization);
builder.Services.AddSingleton(appSettings.Storage);
builder.Services.AddSingleton(appSettings.UploadLimits);
builder.Services.AddSingleton(appSettings.Cleanup);
builder.Services.AddSingleton(appSettings.Import);
builder.Services.AddSingleton(appSettings.Logging);
builder.Services.AddSingleton(appSettings.DiskSpace);
builder.Services.AddSingleton(appSettings.DatabasePerformance);
builder.Services.AddSingleton(appSettings.Ldap);
builder.Services.AddSingleton(appSettings.ChunkedUpload);

// Register IOptions<AppSettings> for services that use the Options pattern
builder.Services.Configure<AppSettings>(builder.Configuration.GetSection("AppSettings"));

// Add DbContext - only if SQL Server is configured
if (appSettings.SqlServer.IsConfigured)
{
    builder.Services.AddDbContext<ApplicationDbContext>(options =>
        options.UseSqlServer(appSettings.SqlServer.BuildConnectionString()));

    // Add Hangfire with SQL Server storage
    // UseTypeResolver maps old NTFSPermsUploader types to new CLAWS types for backwards compatibility
    builder.Services.AddHangfire(config => config
        .SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
        .UseSimpleAssemblyNameTypeSerializer()
        .UseRecommendedSerializerSettings()
        .UseTypeResolver(LegacyTypeResolver.ResolveType)
        .UseSqlServerStorage(appSettings.SqlServer.BuildConnectionString(), new SqlServerStorageOptions
        {
            CommandBatchMaxTimeout = TimeSpan.FromMinutes(5),
            SlidingInvisibilityTimeout = TimeSpan.FromMinutes(5),
            QueuePollInterval = TimeSpan.Zero,
            UseRecommendedIsolationLevel = true,
            DisableGlobalLocks = true
        }));

    // Configure Hangfire server with upload-processing and default queues
    // The upload-processing queue uses DisableConcurrentExecution to ensure
    // only one upload is processed at a time, preventing disk I/O contention
    builder.Services.AddHangfireServer(options =>
    {
        options.ServerName = $"main-{Environment.MachineName}";
        options.Queues = new[] { "upload-processing", "default" };
        options.WorkerCount = Environment.ProcessorCount;
    });

    // Separate server for deletion queue with single worker
    // This serializes all deletion jobs to prevent database contention
    // when multiple collections are deleted simultaneously
    builder.Services.AddHangfireServer(options =>
    {
        options.ServerName = $"deletion-{Environment.MachineName}";
        options.Queues = new[] { "deletion" };
        options.WorkerCount = 1;
    });

    // Separate server for AD deletion queue with single worker
    // AD deletions use CASCADE and may take longer, isolated from NTFS deletions
    builder.Services.AddHangfireServer(options =>
    {
        options.ServerName = $"ad-deletion-{Environment.MachineName}";
        options.Queues = new[] { "ad-deletion" };
        options.WorkerCount = 1;
    });

    // Server for validation jobs - single worker to avoid concurrent validation
    builder.Services.AddHangfireServer(options =>
    {
        options.ServerName = $"validation-{Environment.MachineName}";
        options.Queues = new[] { "validation" };
        options.WorkerCount = 1;
    });

    // Server for migration jobs - single worker to prevent concurrent schema changes
    builder.Services.AddHangfireServer(options =>
    {
        options.ServerName = $"migration-{Environment.MachineName}";
        options.Queues = new[] { "migration" };
        options.WorkerCount = 1;
    });

    // Configure Data Protection to persist keys to SQL Server
    // This prevents antiforgery token errors when the app restarts
    builder.Services.AddDataProtection()
        .SetApplicationName("CLAWS")
        .PersistKeysToDbContext<ApplicationDbContext>();
}

// Add MVC with Razor views
builder.Services.AddControllersWithViews();

// Add memory cache for banner message caching
builder.Services.AddMemoryCache();

// Add SignalR
builder.Services.AddSignalR();

// Configure Authentication based on LDAP settings
if (appSettings.Ldap.Enabled)
{
    // LDAP mode: use cookie authentication
    builder.Services.AddAuthentication(Microsoft.AspNetCore.Authentication.Cookies.CookieAuthenticationDefaults.AuthenticationScheme)
        .AddCookie(options =>
        {
            options.LoginPath = "/Account/Login";
            options.LogoutPath = "/Account/Logout";
            options.AccessDeniedPath = "/Account/AccessDenied";
            options.ExpireTimeSpan = TimeSpan.FromHours(8);
            options.SlidingExpiration = true;
            options.Cookie.HttpOnly = true;
            options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
            options.Cookie.SameSite = SameSiteMode.Lax;
        });

    builder.Services.AddAuthorization(options =>
    {
        options.FallbackPolicy = options.DefaultPolicy;

        // SiteAdminOnly policy - requires Site Administrator role or Keymaster authentication
        options.AddPolicy("SiteAdminOnly", policy =>
        {
            policy.RequireAuthenticatedUser();
            policy.RequireAssertion(context =>
            {
                // Keymaster always has admin access (emergency "break glass" account)
                var authType = context.User.Claims
                    .FirstOrDefault(c => c.Type == "AuthenticationType")?.Value;
                if (authType == "Keymaster")
                    return true;

                // If no site admin group is configured, allow access (but warning banner will be shown)
                if (string.IsNullOrEmpty(appSettings.Authorization.SiteAdminGroup))
                    return true;

                // Check if user is in the site admin group
                return context.User.IsInRole(appSettings.Authorization.SiteAdminGroup);
            });
        });

        // NtfsPermsAdminOrSiteAdmin policy - requires NTFS Perms Admin or Site Admin role
        options.AddPolicy("NtfsPermsAdminOrSiteAdmin", policy =>
        {
            policy.RequireAuthenticatedUser();
            policy.RequireAssertion(context =>
            {
                // Keymaster always has admin access
                var authType = context.User.Claims
                    .FirstOrDefault(c => c.Type == "AuthenticationType")?.Value;
                if (authType == "Keymaster")
                    return true;

                // If authorization is not configured, allow access
                if (!appSettings.Authorization.IsConfigured)
                    return true;

                // Check NTFS Perms Admin group
                if (!string.IsNullOrEmpty(appSettings.Authorization.NtfsPermsAdminGroup) &&
                    context.User.IsInRole(appSettings.Authorization.NtfsPermsAdminGroup))
                    return true;

                // Check Site Admin group
                if (!string.IsNullOrEmpty(appSettings.Authorization.SiteAdminGroup) &&
                    context.User.IsInRole(appSettings.Authorization.SiteAdminGroup))
                    return true;

                return false;
            });
        });

        // AdAdminOrSiteAdmin policy - requires AD Admin or Site Admin role
        options.AddPolicy("AdAdminOrSiteAdmin", policy =>
        {
            policy.RequireAuthenticatedUser();
            policy.RequireAssertion(context =>
            {
                // Keymaster always has admin access
                var authType = context.User.Claims
                    .FirstOrDefault(c => c.Type == "AuthenticationType")?.Value;
                if (authType == "Keymaster")
                    return true;

                // If authorization is not configured, allow access
                if (!appSettings.Authorization.IsConfigured)
                    return true;

                // Check AD Admin group
                if (!string.IsNullOrEmpty(appSettings.Authorization.AdAdminGroup) &&
                    context.User.IsInRole(appSettings.Authorization.AdAdminGroup))
                    return true;

                // Check Site Admin group
                if (!string.IsNullOrEmpty(appSettings.Authorization.SiteAdminGroup) &&
                    context.User.IsInRole(appSettings.Authorization.SiteAdminGroup))
                    return true;

                return false;
            });
        });
    });

    Log.Information("LDAP authentication enabled. Users will authenticate via login page.");
}
else
{
    // Windows Authentication mode
    builder.Services.AddAuthentication(NegotiateDefaults.AuthenticationScheme)
        .AddNegotiate();

    builder.Services.AddAuthorization(options =>
    {
        options.FallbackPolicy = options.DefaultPolicy;

        // SiteAdminOnly policy - requires Site Administrator role
        options.AddPolicy("SiteAdminOnly", policy =>
        {
            policy.RequireAuthenticatedUser();
            policy.RequireAssertion(context =>
            {
                // If no site admin group is configured, allow access (but warning banner will be shown)
                if (string.IsNullOrEmpty(appSettings.Authorization.SiteAdminGroup))
                    return true;

                // Check if user is in the site admin group
                return context.User.IsInRole(appSettings.Authorization.SiteAdminGroup);
            });
        });

        // NtfsPermsAdminOrSiteAdmin policy - requires NTFS Perms Admin or Site Admin role
        options.AddPolicy("NtfsPermsAdminOrSiteAdmin", policy =>
        {
            policy.RequireAuthenticatedUser();
            policy.RequireAssertion(context =>
            {
                // If authorization is not configured, allow access
                if (!appSettings.Authorization.IsConfigured)
                    return true;

                // Check NTFS Perms Admin group
                if (!string.IsNullOrEmpty(appSettings.Authorization.NtfsPermsAdminGroup) &&
                    context.User.IsInRole(appSettings.Authorization.NtfsPermsAdminGroup))
                    return true;

                // Check Site Admin group
                if (!string.IsNullOrEmpty(appSettings.Authorization.SiteAdminGroup) &&
                    context.User.IsInRole(appSettings.Authorization.SiteAdminGroup))
                    return true;

                return false;
            });
        });

        // AdAdminOrSiteAdmin policy - requires AD Admin or Site Admin role
        options.AddPolicy("AdAdminOrSiteAdmin", policy =>
        {
            policy.RequireAuthenticatedUser();
            policy.RequireAssertion(context =>
            {
                // If authorization is not configured, allow access
                if (!appSettings.Authorization.IsConfigured)
                    return true;

                // Check AD Admin group
                if (!string.IsNullOrEmpty(appSettings.Authorization.AdAdminGroup) &&
                    context.User.IsInRole(appSettings.Authorization.AdAdminGroup))
                    return true;

                // Check Site Admin group
                if (!string.IsNullOrEmpty(appSettings.Authorization.SiteAdminGroup) &&
                    context.User.IsInRole(appSettings.Authorization.SiteAdminGroup))
                    return true;

                return false;
            });
        });
    });

    Log.Information("Windows Integrated Authentication enabled.");
}

// Register services
builder.Services.AddScoped<IZipValidator, ZipValidator>();
builder.Services.AddScoped<IDatabaseValidator, DatabaseValidator>();
#pragma warning disable CA1416 // This is a Windows-only application (NTFS permissions, Windows Auth)
builder.Services.AddScoped<ISqliteImporter, SqliteImporter>();
#pragma warning restore CA1416
builder.Services.AddScoped<IDiskSpaceService, DiskSpaceService>();
builder.Services.AddScoped<IVersionService, VersionService>();
builder.Services.AddScoped<IUploadService, UploadService>();
builder.Services.AddScoped<IChunkedUploadService, ChunkedUploadService>();
builder.Services.AddScoped<IApiKeyService, ApiKeyService>();
builder.Services.AddScoped<IConfigurationFileService, ConfigurationFileService>();
builder.Services.AddScoped<IMigrationService, MigrationService>();
builder.Services.AddScoped<IProductionDataService, ProductionDataService>();
builder.Services.AddScoped<IAppLogService, AppLogService>();
builder.Services.AddScoped<IBannerMessageService, BannerMessageService>();
builder.Services.AddScoped<IStreamingUploadHelper, StreamingUploadHelper>();
builder.Services.AddScoped<ICollectionLogService, CollectionLogService>();
builder.Services.AddScoped<IUploadTypeDetector, UploadTypeDetector>();
builder.Services.AddScoped<ILdapAuthenticationService, LdapAuthenticationService>();
builder.Services.AddScoped<IDomainMasterListService, DomainMasterListService>();
builder.Services.AddScoped<CLAWS.Core.Services.ICloudIntegrationService, CloudIntegrationService>();
builder.Services.AddScoped<CLAWS.Core.Services.ISecureCredentialService, SecureCredentialService>();

// Register filters
builder.Services.AddScoped<CLAWS.Web.Filters.ApiKeyAuthFilter>();

// Register repositories
if (appSettings.SqlServer.IsConfigured)
{
    builder.Services.AddScoped<IUploadRepository, UploadRepository>();
    builder.Services.AddScoped<IConfigurationRepository, ConfigurationRepository>();
    builder.Services.AddScoped<IApiKeyRepository, ApiKeyRepository>();
    builder.Services.AddScoped<IBannerMessageRepository, BannerMessageRepository>();
}
else
{
    // Use stub repositories when database is not configured
    builder.Services.AddScoped<IUploadRepository, StubUploadRepository>();
    builder.Services.AddScoped<IConfigurationRepository, StubConfigurationRepository>();
    builder.Services.AddScoped<IApiKeyRepository, StubApiKeyRepository>();
    builder.Services.AddScoped<IBannerMessageRepository, StubBannerMessageRepository>();
}

// Register jobs
builder.Services.AddScoped<IImportJob, ImportJob>();
builder.Services.AddScoped<IUploadProcessingJob, UploadProcessingJob>();
builder.Services.AddScoped<ICleanupJob, CleanupJob>();
builder.Services.AddScoped<IDiskMonitorJob, DiskMonitorJob>();
builder.Services.AddScoped<ILogPruningJob, LogPruningJob>();
builder.Services.AddScoped<IProductionDeletionJob, ProductionDeletionJob>();
builder.Services.AddScoped<ISchemaTruncateJob, SchemaTruncateJob>();
builder.Services.AddScoped<IValidationMigrationJob, ValidationMigrationJob>();
builder.Services.AddScoped<IOrphanedDataCleanupJob, OrphanedDataCleanupJob>();
builder.Services.AddScoped<IUploadDeletionJob, UploadDeletionJob>();
builder.Services.AddScoped<IImportDataCleanupJob, ImportDataCleanupJob>();
builder.Services.AddScoped<ICloudIntegrationValidationJob, CloudIntegrationValidationJob>();
builder.Services.AddScoped<IAdCollectionCleanupJob, AdCollectionCleanupJob>();
builder.Services.AddScoped<IChunkedUploadCleanupJob, ChunkedUploadCleanupJob>();

// Register hub notifier as singleton - required for Hangfire jobs which run in separate scopes
builder.Services.AddSingleton<IHubNotifier, SignalRHubNotifier>();

// Configure Kestrel for large uploads
builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = appSettings.UploadLimits.MaxUploadSizeBytes;
    options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(appSettings.HttpServer.KeepAliveTimeoutMinutes);
    options.Limits.RequestHeadersTimeout = TimeSpan.FromMinutes(appSettings.HttpServer.RequestHeadersTimeoutMinutes);
});

// Add Swagger for API documentation
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new() { Title = "CLAWS API", Version = "v1" });
    c.AddSecurityDefinition("ApiKey", new()
    {
        Type = Microsoft.OpenApi.Models.SecuritySchemeType.ApiKey,
        Name = "X-API-Key",
        In = Microsoft.OpenApi.Models.ParameterLocation.Header,
        Description = "API Key authentication"
    });
    c.AddSecurityRequirement(new()
    {
        {
            new Microsoft.OpenApi.Models.OpenApiSecurityScheme
            {
                Reference = new Microsoft.OpenApi.Models.OpenApiReference
                {
                    Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme,
                    Id = "ApiKey"
                }
            },
            Array.Empty<string>()
        }
    });

    // Add operation filter for file upload documentation
    c.OperationFilter<CLAWS.Web.Filters.FileUploadOperationFilter>();
});

var app = builder.Build();

// Register job timeout settings accessor for Hangfire filter
// This allows the ConfigurableDisableConcurrentExecution filter to read timeout values at runtime
ConfigurableJobTimeoutFilter.RegisterSettingsAccessor(() => appSettings.JobTimeouts);

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

// Configure forwarded headers for reverse proxy support
// This must be called early so that HTTPS is detected correctly from X-Forwarded-Proto
app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
});

// Enable Swagger in all environments
app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "CLAWS API v1");
    c.RoutePrefix = "swagger";
});

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

// Security headers
app.Use(async (context, next) =>
{
    context.Response.Headers.Append("X-Content-Type-Options", "nosniff");
    context.Response.Headers.Append("X-Frame-Options", "DENY");
    context.Response.Headers.Append("X-XSS-Protection", "1; mode=block");
    context.Response.Headers.Append("Referrer-Policy", "strict-origin-when-cross-origin");
    await next();
});

app.UseAuthentication();
app.UseAuthorization();

// Map SignalR hub
app.MapHub<UploadHub>("/hubs/upload");

// Map Hangfire dashboard (admin only)
if (appSettings.SqlServer.IsConfigured)
{
    app.MapHangfireDashboard("/hangfire", new DashboardOptions
    {
        Authorization = new[] { new HangfireDashboardAuthorizationFilter() }
    });

    // Configure recurring jobs - wrapped in try/catch in case Hangfire schema isn't created yet
    try
    {
        RecurringJob.AddOrUpdate<ICleanupJob>(
            "cleanup-completed",
            job => job.CleanupCompletedAsync(CancellationToken.None),
            appSettings.Cleanup.PruneSchedule);

        if (appSettings.Cleanup.ErrorRetentionDays > 0)
        {
            RecurringJob.AddOrUpdate<ICleanupJob>(
                "cleanup-errors",
                job => job.CleanupErrorsAsync(CancellationToken.None),
                appSettings.Cleanup.PruneSchedule);
        }

        if (appSettings.Cleanup.ExtractionRetentionDays > 0)
        {
            RecurringJob.AddOrUpdate<ICleanupJob>(
                "cleanup-extraction",
                job => job.CleanupExtractionAsync(CancellationToken.None),
                appSettings.Cleanup.PruneSchedule);
        }

        if (appSettings.Cleanup.UploadRecordRetentionDays > 0)
        {
            RecurringJob.AddOrUpdate<ICleanupJob>(
                "cleanup-upload-records",
                job => job.CleanupUploadRecordsAsync(CancellationToken.None),
                appSettings.Cleanup.PruneSchedule);
        }

        RecurringJob.AddOrUpdate<IDiskMonitorJob>(
            "disk-monitor",
            job => job.CheckDiskSpaceAsync(CancellationToken.None),
            "*/15 * * * *"); // Every 15 minutes

        RecurringJob.AddOrUpdate<ILogPruningJob>(
            "log-pruning",
            job => job.PruneLogsAsync(CancellationToken.None),
            "0 3 * * *"); // 3 AM daily

        // Cloud Integration Validation - uses configured schedule (default: 4 AM daily)
        if (appSettings.CloudIntegration.IsConfigured)
        {
            RecurringJob.AddOrUpdate<ICloudIntegrationValidationJob>(
                "cloud-integration-validation",
                job => job.ValidateCloudIntegrationAsync(CancellationToken.None),
                appSettings.CloudIntegration.Schedule);
        }

        // AD Collection Cleanup - uses configured schedule (default: every 6 hours)
        if (appSettings.Cleanup.AutoPruneAdCollections && appSettings.Cleanup.AdCollectionsToKeepPerDomain > 0)
        {
            RecurringJob.AddOrUpdate<IAdCollectionCleanupJob>(
                "ad-collection-cleanup",
                job => job.CleanupOldCollectionsAsync(CancellationToken.None),
                appSettings.Cleanup.AdCollectionPruneSchedule);
        }

        // Chunked Upload Cleanup - every hour
        if (appSettings.ChunkedUpload.Enabled)
        {
            RecurringJob.AddOrUpdate<IChunkedUploadCleanupJob>(
                "chunked-upload-cleanup",
                job => job.ExecuteAsync(CancellationToken.None),
                "0 * * * *"); // Every hour at minute 0
        }
    }
    catch (Exception ex)
    {
        Log.Warning(ex, "Failed to configure Hangfire recurring jobs. Ensure the database user has CREATE SCHEMA permission.");
    }
}

// Map controllers
app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

// Ensure storage directories exist
Directory.CreateDirectory(appSettings.Storage.GetUploadPath());
Directory.CreateDirectory(appSettings.Storage.GetExtractionPath());
Directory.CreateDirectory(appSettings.Storage.GetCompletedPath());
Directory.CreateDirectory(appSettings.Storage.GetErrorsPath());
Directory.CreateDirectory(appSettings.Logging.LogDirectory);

// Create chunked upload directory if enabled
if (appSettings.ChunkedUpload.Enabled)
{
    Directory.CreateDirectory(Path.Combine(appSettings.Storage.GetUploadPath(), "chunks"));
}

// Log startup
Log.Information("CLAWS starting up");
if (appSettings.SqlServer.IsConfigured)
{
    Log.Information("Database logging enabled. Logs will be written to file and database (app.SerilogLogs table).");
}
else
{
    Log.Warning("SQL Server is not configured. Database features are disabled. Logs written to file only.");
}
if (!appSettings.Authorization.IsConfigured)
{
    Log.Warning("Authorization groups not configured. Any authenticated user has full access.");
}
if (appSettings.Storage.IsUsingApplicationDirectory(app.Environment.ContentRootPath))
{
    Log.Warning("Import storage is using the application installation directory. Configure a dedicated volume for production.");
}

try
{
    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
}
finally
{
    Log.Information("Application shutting down");
    Log.CloseAndFlush();
}

/// <summary>
/// Hangfire dashboard authorization filter.
/// Requires Site Admin group membership or Keymaster authentication.
/// </summary>
public class HangfireDashboardAuthorizationFilter : Hangfire.Dashboard.IDashboardAuthorizationFilter
{
    public bool Authorize(Hangfire.Dashboard.DashboardContext context)
    {
        var httpContext = context.GetHttpContext();

        // Must be authenticated
        if (!(httpContext.User.Identity?.IsAuthenticated ?? false))
            return false;

        // Keymaster always has admin access (emergency "break glass" account)
        var authType = httpContext.User.Claims
            .FirstOrDefault(c => c.Type == "AuthenticationType")?.Value;
        if (authType == "Keymaster")
            return true;

        // Get app settings from DI
        var appSettings = httpContext.RequestServices.GetService<AppSettings>();
        if (appSettings == null)
            return false;

        // If no site admin group is configured, allow access (but warning banner will be shown)
        if (string.IsNullOrEmpty(appSettings.Authorization.SiteAdminGroup))
            return true;

        // Check if user is in the site admin group
        return httpContext.User.IsInRole(appSettings.Authorization.SiteAdminGroup);
    }
}

/// <summary>
/// Custom type resolver for Hangfire that maps old NTFSPermsUploader assembly/namespace
/// references to the new CLAWS names. This provides backwards compatibility for jobs
/// that were serialized before the rename.
/// </summary>
public static class LegacyTypeResolver
{
    private static readonly Dictionary<string, Assembly> _assemblyCache = new();
    private static readonly object _lock = new();

    /// <summary>
    /// Resolves a type name, mapping old NTFSPermsUploader references to CLAWS.
    /// </summary>
    public static Type? ResolveType(string typeName)
    {
        // Map old assembly and namespace names to new ones
        var mappedTypeName = typeName
            .Replace("NTFSPermsUploader.Jobs", "CLAWS.Jobs")
            .Replace("NTFSPermsUploader.Core", "CLAWS.Core")
            .Replace("NTFSPermsUploader.Data", "CLAWS.Data")
            .Replace("NTFSPermsUploader.Web", "CLAWS.Web");

        // Try to resolve the mapped type using the standard resolver first
        var type = Type.GetType(mappedTypeName, throwOnError: false, ignoreCase: true);
        if (type != null)
            return type;

        // If that fails, try to load the assembly explicitly
        // Parse the type name to extract assembly name (format: "Namespace.Type, AssemblyName")
        var parts = mappedTypeName.Split(',');
        if (parts.Length >= 2)
        {
            var assemblyName = parts[1].Trim();
            var fullTypeName = parts[0].Trim();

            // Try to get or load the assembly
            var assembly = GetOrLoadAssembly(assemblyName);
            if (assembly != null)
            {
                type = assembly.GetType(fullTypeName, throwOnError: false, ignoreCase: true);
                if (type != null)
                    return type;
            }
        }

        // Last resort: search all loaded assemblies
        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            if (assembly.IsDynamic)
                continue;

            var fullTypeName = parts.Length >= 1 ? parts[0].Trim() : mappedTypeName;
            type = assembly.GetType(fullTypeName, throwOnError: false, ignoreCase: true);
            if (type != null)
                return type;
        }

        return null;
    }

    private static Assembly? GetOrLoadAssembly(string assemblyName)
    {
        lock (_lock)
        {
            if (_assemblyCache.TryGetValue(assemblyName, out var cached))
                return cached;

            // Check if already loaded
            var loaded = AppDomain.CurrentDomain.GetAssemblies()
                .FirstOrDefault(a => !a.IsDynamic && a.GetName().Name == assemblyName);

            if (loaded != null)
            {
                _assemblyCache[assemblyName] = loaded;
                return loaded;
            }

            // Try to load the assembly
            try
            {
                var assembly = Assembly.Load(assemblyName);
                _assemblyCache[assemblyName] = assembly;
                return assembly;
            }
            catch
            {
                return null;
            }
        }
    }
}
