using CLAWS.Core.Services;
using CLAWS.Data.Context;
using CLAWS.Data.Entities;

namespace CLAWS.Web.Services;

/// <summary>
/// Implementation of structured logging to app.Logs table.
/// </summary>
public class AppLogService : IAppLogService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<AppLogService> _logger;
    private readonly string _hostname;

    public AppLogService(IServiceScopeFactory scopeFactory, ILogger<AppLogService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
        _hostname = Environment.MachineName;
    }

    public async Task LogUploadStartAsync(Guid uploadId, string filename, long fileSize, string? userId, string? sourceIp, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Upload,
            LogSeverity.Info,
            MessageIds.UploadStart,
            $"Upload started: {filename} ({FormatBytes(fileSize)})",
            uploadId, userId, sourceIp,
            properties: new { Filename = filename, FileSize = fileSize },
            cancellationToken: cancellationToken);
    }

    public async Task LogUploadCompleteAsync(Guid uploadId, string filename, string? userId, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Upload,
            LogSeverity.Info,
            MessageIds.UploadComplete,
            $"Upload completed: {filename}",
            uploadId, userId,
            properties: new { Filename = filename },
            cancellationToken: cancellationToken);
    }

    public async Task LogUploadFailedAsync(Guid uploadId, string filename, string error, string? userId, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Upload,
            LogSeverity.Error,
            MessageIds.UploadFailed,
            $"Upload failed: {filename} - {error}",
            uploadId, userId,
            properties: new { Filename = filename, Error = error },
            cancellationToken: cancellationToken);
    }

    public async Task LogImportQueuedAsync(Guid uploadId, string filename, string? userId, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Import,
            LogSeverity.Info,
            MessageIds.ImportQueued,
            $"Import queued: {filename}",
            uploadId, userId,
            properties: new { Filename = filename },
            cancellationToken: cancellationToken);
    }

    public async Task LogImportStartAsync(Guid uploadId, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Import,
            LogSeverity.Info,
            MessageIds.ImportStart,
            "Import started",
            uploadId,
            cancellationToken: cancellationToken);
    }

    public async Task LogImportCompleteAsync(Guid uploadId, long recordsImported, TimeSpan duration, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Import,
            LogSeverity.Info,
            MessageIds.ImportComplete,
            $"Import completed: {recordsImported:N0} records in {duration.TotalSeconds:F1}s",
            uploadId,
            properties: new { RecordsImported = recordsImported, DurationSeconds = duration.TotalSeconds },
            cancellationToken: cancellationToken);
    }

    public async Task LogImportFailedAsync(Guid uploadId, string error, string? exception, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Import,
            LogSeverity.Error,
            MessageIds.ImportFailed,
            $"Import failed: {error}",
            uploadId,
            exception: exception,
            properties: new { Error = error },
            cancellationToken: cancellationToken);
    }

    public async Task LogValidationPassAsync(Guid uploadId, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Validation,
            LogSeverity.Info,
            MessageIds.ValidationPass,
            "Validation passed",
            uploadId,
            cancellationToken: cancellationToken);
    }

    public async Task LogValidationFailAsync(Guid uploadId, string error, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Validation,
            LogSeverity.Warning,
            MessageIds.ValidationFail,
            $"Validation failed: {error}",
            uploadId,
            properties: new { Error = error },
            cancellationToken: cancellationToken);
    }

    public async Task LogMergeStartAsync(Guid uploadId, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Import,
            LogSeverity.Info,
            "MERGE_START",
            "Merge started",
            uploadId,
            cancellationToken: cancellationToken);
    }

    public async Task LogMergeCompleteAsync(Guid uploadId, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Import,
            LogSeverity.Info,
            "MERGE_COMPLETE",
            "Merge completed",
            uploadId,
            cancellationToken: cancellationToken);
    }

    public async Task LogMergeFailedAsync(Guid uploadId, string error, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Import,
            LogSeverity.Error,
            "MERGE_FAILED",
            $"Merge failed: {error}",
            uploadId,
            properties: new { Error = error },
            cancellationToken: cancellationToken);
    }

    public async Task LogDiskWarningAsync(string driveName, double freePercent, string freeFormatted, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.System,
            LogSeverity.Warning,
            MessageIds.DiskWarning,
            $"Low disk space on {driveName}: {freeFormatted} ({freePercent:F1}% free)",
            properties: new { Drive = driveName, FreePercent = freePercent, FreeFormatted = freeFormatted },
            cancellationToken: cancellationToken);
    }

    public async Task LogDiskCriticalAsync(string driveName, double freePercent, string freeFormatted, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.System,
            LogSeverity.Critical,
            MessageIds.DiskCritical,
            $"Critical disk space on {driveName}: {freeFormatted} ({freePercent:F1}% free)",
            properties: new { Drive = driveName, FreePercent = freePercent, FreeFormatted = freeFormatted },
            cancellationToken: cancellationToken);
    }

    public async Task LogConfigChangeAsync(string setting, string? userId, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Configuration,
            LogSeverity.Notice,
            MessageIds.ConfigChange,
            $"Configuration changed: {setting}",
            userId: userId,
            properties: new { Setting = setting },
            cancellationToken: cancellationToken);
    }

    public async Task LogApiRequestAsync(string endpoint, string? apiKeyId, string? sourceIp, bool success, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Api,
            success ? LogSeverity.Info : LogSeverity.Warning,
            MessageIds.ApiRequest,
            $"API request: {endpoint}",
            userId: apiKeyId,
            sourceIp: sourceIp,
            properties: new { Endpoint = endpoint, Success = success },
            cancellationToken: cancellationToken);
    }

    public async Task LogApiAuthFailAsync(string endpoint, string? sourceIp, string reason, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Security,
            LogSeverity.Warning,
            MessageIds.ApiAuthFail,
            $"API authentication failed: {endpoint} - {reason}",
            sourceIp: sourceIp,
            properties: new { Endpoint = endpoint, Reason = reason },
            cancellationToken: cancellationToken);
    }

    public async Task LogSecurityEventAsync(string message, string? userId, string? sourceIp, CancellationToken cancellationToken = default)
    {
        await LogEventAsync(
            LogFacility.Security,
            LogSeverity.Notice,
            MessageIds.SecurityEvent,
            message,
            userId: userId,
            sourceIp: sourceIp,
            cancellationToken: cancellationToken);
    }

    public async Task LogEventAsync(
        byte facility,
        byte severity,
        string messageId,
        string message,
        Guid? uploadId = null,
        string? userId = null,
        string? sourceIp = null,
        string? exception = null,
        object? properties = null,
        CancellationToken cancellationToken = default)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

            var logEntry = new LogEntry
            {
                Timestamp = DateTime.UtcNow,
                Facility = facility,
                Severity = severity,
                SeverityName = GetSeverityName(severity),
                Hostname = _hostname,
                AppName = "CLAWS",
                ProcessId = Environment.ProcessId,
                MessageId = messageId,
                UploadId = uploadId,
                UserId = userId,
                SourceIP = sourceIp,
                Category = GetCategoryName(facility),
                Message = message,
                Exception = exception,
                Properties = properties != null ? System.Text.Json.JsonSerializer.Serialize(properties) : null
            };

            dbContext.Set<LogEntry>().Add(logEntry);
            await dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            // Don't throw - just log to Serilog as fallback
            _logger.LogError(ex, "Failed to write to app.Logs: {Message}", message);
        }
    }

    private static string GetSeverityName(byte severity) => severity switch
    {
        LogSeverity.Emergency => "EMERGENCY",
        LogSeverity.Alert => "ALERT",
        LogSeverity.Critical => "CRITICAL",
        LogSeverity.Error => "ERROR",
        LogSeverity.Warning => "WARNING",
        LogSeverity.Notice => "NOTICE",
        LogSeverity.Info => "INFO",
        LogSeverity.Debug => "DEBUG",
        _ => "UNKNOWN"
    };

    private static string GetCategoryName(byte facility) => facility switch
    {
        LogFacility.Upload => "Upload",
        LogFacility.Validation => "Validation",
        LogFacility.Import => "Import",
        LogFacility.Api => "API",
        LogFacility.ScheduledTask => "ScheduledTask",
        LogFacility.Security => "Security",
        LogFacility.Configuration => "Configuration",
        LogFacility.System => "System",
        _ => "General"
    };

    private static string FormatBytes(long bytes)
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

    public async Task LogAsync(Guid? uploadId, string category, string severity, string message, string? userId = null, string? exception = null, CancellationToken cancellationToken = default)
    {
        var severityByte = severity.ToUpperInvariant() switch
        {
            "EMERGENCY" => LogSeverity.Emergency,
            "ALERT" => LogSeverity.Alert,
            "CRITICAL" => LogSeverity.Critical,
            "ERROR" => LogSeverity.Error,
            "WARNING" => LogSeverity.Warning,
            "NOTICE" => LogSeverity.Notice,
            "INFO" => LogSeverity.Info,
            "DEBUG" => LogSeverity.Debug,
            _ => LogSeverity.Info
        };

        try
        {
            using var scope = _scopeFactory.CreateScope();
            var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

            var logEntry = new LogEntry
            {
                Timestamp = DateTime.UtcNow,
                Facility = LogFacility.ScheduledTask,
                Severity = severityByte,
                SeverityName = severity.ToUpperInvariant(),
                Hostname = _hostname,
                AppName = "CLAWS",
                ProcessId = Environment.ProcessId,
                MessageId = category.ToUpperInvariant(),
                UploadId = uploadId,
                UserId = userId,
                Category = category,
                Message = message,
                Exception = exception
            };

            dbContext.Set<LogEntry>().Add(logEntry);
            await dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            // Don't throw - just log to Serilog as fallback
            _logger.LogError(ex, "Failed to write to app.Logs: {Message}", message);
        }
    }
}
