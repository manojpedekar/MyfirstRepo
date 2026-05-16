using Hangfire;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Core.Services;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for monitoring disk space.
/// </summary>
public interface IDiskMonitorJob
{
    /// <summary>
    /// Checks disk space and logs warnings/critical alerts.
    /// </summary>
    [JobDisplayName("Monitor: Disk Space")]
    Task CheckDiskSpaceAsync(CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of the disk monitor job.
/// </summary>
public class DiskMonitorJob : IDiskMonitorJob
{
    private readonly ILogger<DiskMonitorJob> _logger;
    private readonly IDiskSpaceService _diskSpaceService;
    private readonly IAppLogService _appLogService;
    private readonly StorageSettings _storageSettings;
    private readonly UploadLimitSettings _uploadLimits;
    private readonly DiskSpaceSettings _diskSpaceSettings;

    public DiskMonitorJob(
        ILogger<DiskMonitorJob> logger,
        IDiskSpaceService diskSpaceService,
        IAppLogService appLogService,
        StorageSettings storageSettings,
        UploadLimitSettings uploadLimits,
        DiskSpaceSettings diskSpaceSettings)
    {
        _logger = logger;
        _diskSpaceService = diskSpaceService;
        _appLogService = appLogService;
        _storageSettings = storageSettings;
        _uploadLimits = uploadLimits;
        _diskSpaceSettings = diskSpaceSettings;
    }

    /// <inheritdoc/>
    public async Task CheckDiskSpaceAsync(CancellationToken cancellationToken)
    {
        var status = _diskSpaceService.GetDiskSpaceStatus(
            _storageSettings.ImportBasePath,
            _uploadLimits.MinFreeDiskSpaceBytes,
            _diskSpaceSettings.WarningThresholdPercent,
            _diskSpaceSettings.CriticalThresholdPercent);

        if (status.TotalBytes == 0)
        {
            _logger.LogWarning("Unable to determine disk space for {Path}", _storageSettings.ImportBasePath);
            return;
        }

        if (status.IsCritical)
        {
            _logger.LogCritical(
                "DISK SPACE CRITICAL: {Free} free on {Drive} (minimum: {Min}). Uploads will be rejected.",
                status.FreeFormatted,
                status.DriveName,
                FormatBytes(status.MinimumFreeBytes));

            // Log to app.Logs
            await _appLogService.LogDiskCriticalAsync(
                status.DriveName ?? "Unknown",
                status.FreePercent,
                status.FreeFormatted,
                cancellationToken);
        }
        else if (status.IsWarning)
        {
            _logger.LogWarning(
                "DISK SPACE WARNING: {Free} free on {Drive} ({Percent:F1}% free). Consider cleaning up.",
                status.FreeFormatted,
                status.DriveName,
                status.FreePercent);

            // Log to app.Logs
            await _appLogService.LogDiskWarningAsync(
                status.DriveName ?? "Unknown",
                status.FreePercent,
                status.FreeFormatted,
                cancellationToken);
        }
        else
        {
            _logger.LogInformation(
                "Disk space OK: {Free} free on {Drive} ({Percent:F1}% free)",
                status.FreeFormatted,
                status.DriveName,
                status.FreePercent);
        }
    }

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
}
