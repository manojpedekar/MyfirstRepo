using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;

namespace CLAWS.Core.Services;

/// <summary>
/// Provides disk space monitoring capabilities.
/// </summary>
public interface IDiskSpaceService
{
    /// <summary>
    /// Gets the free space on the drive containing the specified path.
    /// </summary>
    /// <param name="path">Path on the drive to check.</param>
    /// <returns>Free space in bytes, or -1 if unable to determine.</returns>
    long GetFreeSpace(string path);

    /// <summary>
    /// Gets the total space on the drive containing the specified path.
    /// </summary>
    /// <param name="path">Path on the drive to check.</param>
    /// <returns>Total space in bytes, or -1 if unable to determine.</returns>
    long GetTotalSpace(string path);

    /// <summary>
    /// Checks if there is sufficient free space for an upload.
    /// </summary>
    /// <param name="path">Path on the drive to check.</param>
    /// <param name="requiredBytes">Required bytes of free space.</param>
    /// <returns>True if sufficient space is available.</returns>
    bool HasSufficientSpace(string path, long requiredBytes);

    /// <summary>
    /// Gets the disk space status for the import drive.
    /// </summary>
    /// <param name="importBasePath">Base path for imports.</param>
    /// <param name="minFreeSpaceBytes">Minimum required free space.</param>
    /// <param name="warningThresholdPercent">Warning threshold percentage (default 20%).</param>
    /// <param name="criticalThresholdPercent">Critical threshold percentage (default 10%).</param>
    /// <returns>Disk space status information.</returns>
    DiskSpaceStatus GetDiskSpaceStatus(
        string importBasePath,
        long minFreeSpaceBytes,
        double warningThresholdPercent = 20.0,
        double criticalThresholdPercent = 10.0);
}

/// <summary>
/// Status information about disk space.
/// </summary>
public class DiskSpaceStatus
{
    /// <summary>
    /// Total space on the drive in bytes.
    /// </summary>
    public long TotalBytes { get; set; }

    /// <summary>
    /// Free space on the drive in bytes.
    /// </summary>
    public long FreeBytes { get; set; }

    /// <summary>
    /// Used space on the drive in bytes.
    /// </summary>
    public long UsedBytes => TotalBytes - FreeBytes;

    /// <summary>
    /// Percentage of space used.
    /// </summary>
    public double UsedPercent => TotalBytes > 0 ? (double)UsedBytes / TotalBytes * 100 : 0;

    /// <summary>
    /// Percentage of space free.
    /// </summary>
    public double FreePercent => TotalBytes > 0 ? (double)FreeBytes / TotalBytes * 100 : 0;

    /// <summary>
    /// Minimum required free space in bytes.
    /// </summary>
    public long MinimumFreeBytes { get; set; }

    /// <summary>
    /// Warning threshold as percentage of free space (0-100).
    /// </summary>
    public double WarningThresholdPercent { get; set; } = 20.0;

    /// <summary>
    /// Critical threshold as percentage of free space (0-100).
    /// </summary>
    public double CriticalThresholdPercent { get; set; } = 10.0;

    /// <summary>
    /// Whether the disk space is critical.
    /// Critical when: free space is below minimum bytes OR below critical percentage threshold.
    /// </summary>
    public bool IsCritical =>
        FreeBytes < MinimumFreeBytes ||
        (CriticalThresholdPercent > 0 && FreePercent < CriticalThresholdPercent);

    /// <summary>
    /// Whether the disk space is low (warning level).
    /// Warning when: free space is below warning percentage threshold (but not critical).
    /// </summary>
    public bool IsWarning =>
        !IsCritical &&
        WarningThresholdPercent > 0 &&
        FreePercent < WarningThresholdPercent;

    /// <summary>
    /// Drive or volume name.
    /// </summary>
    public string? DriveName { get; set; }

    /// <summary>
    /// Drive label if available.
    /// </summary>
    public string? DriveLabel { get; set; }

    /// <summary>
    /// Gets a formatted string of total space.
    /// </summary>
    public string TotalFormatted => FormatBytes(TotalBytes);

    /// <summary>
    /// Gets a formatted string of free space.
    /// </summary>
    public string FreeFormatted => FormatBytes(FreeBytes);

    /// <summary>
    /// Gets a formatted string of used space.
    /// </summary>
    public string UsedFormatted => FormatBytes(UsedBytes);

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

/// <summary>
/// Implementation of disk space monitoring.
/// </summary>
public class DiskSpaceService : IDiskSpaceService
{
    private readonly ILogger<DiskSpaceService> _logger;

    public DiskSpaceService(ILogger<DiskSpaceService> logger)
    {
        _logger = logger;
    }

    /// <inheritdoc/>
    public long GetFreeSpace(string path)
    {
        try
        {
            var driveInfo = GetDriveInfo(path);
            return driveInfo?.AvailableFreeSpace ?? -1;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting free space for {Path}", path);
            return -1;
        }
    }

    /// <inheritdoc/>
    public long GetTotalSpace(string path)
    {
        try
        {
            var driveInfo = GetDriveInfo(path);
            return driveInfo?.TotalSize ?? -1;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting total space for {Path}", path);
            return -1;
        }
    }

    /// <inheritdoc/>
    public bool HasSufficientSpace(string path, long requiredBytes)
    {
        var freeSpace = GetFreeSpace(path);
        if (freeSpace < 0)
        {
            _logger.LogWarning("Unable to determine free space for {Path}, assuming sufficient", path);
            return true;
        }
        return freeSpace >= requiredBytes;
    }

    /// <inheritdoc/>
    public DiskSpaceStatus GetDiskSpaceStatus(
        string importBasePath,
        long minFreeSpaceBytes,
        double warningThresholdPercent = 20.0,
        double criticalThresholdPercent = 10.0)
    {
        try
        {
            var driveInfo = GetDriveInfo(importBasePath);
            if (driveInfo == null)
            {
                return new DiskSpaceStatus
                {
                    TotalBytes = 0,
                    FreeBytes = 0,
                    MinimumFreeBytes = minFreeSpaceBytes,
                    WarningThresholdPercent = warningThresholdPercent,
                    CriticalThresholdPercent = criticalThresholdPercent
                };
            }

            return new DiskSpaceStatus
            {
                TotalBytes = driveInfo.TotalSize,
                FreeBytes = driveInfo.AvailableFreeSpace,
                MinimumFreeBytes = minFreeSpaceBytes,
                WarningThresholdPercent = warningThresholdPercent,
                CriticalThresholdPercent = criticalThresholdPercent,
                DriveName = driveInfo.Name,
                DriveLabel = driveInfo.VolumeLabel
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting disk space status for {Path}", importBasePath);
            return new DiskSpaceStatus
            {
                TotalBytes = 0,
                FreeBytes = 0,
                MinimumFreeBytes = minFreeSpaceBytes,
                WarningThresholdPercent = warningThresholdPercent,
                CriticalThresholdPercent = criticalThresholdPercent
            };
        }
    }

    private static DriveInfo? GetDriveInfo(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
            return null;

        var fullPath = Path.GetFullPath(path);
        var root = Path.GetPathRoot(fullPath);

        if (string.IsNullOrEmpty(root))
            return null;

        return new DriveInfo(root);
    }
}
