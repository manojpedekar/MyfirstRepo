#pragma once

#include <vector>
#include <string>
#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include <windows.h>

namespace FixedDiskEnumerator {

/**
 * @brief Information about a scannable fixed disk volume
 *
 * Contains all relevant metadata about a fixed disk volume including
 * its mount points, file system information, and size.
 */
struct FixedDiskInfo {
    std::wstring volumeGuid;               // e.g., L"\\\\?\\Volume{GUID}\\"
    std::vector<std::wstring> mountPoints; // All mount points (drive letters + folder mounts)
    std::wstring primaryPath;              // Best path to use for scanning
    std::wstring volumeLabel;              // e.g., L"Windows"
    std::wstring fileSystem;               // e.g., L"NTFS"
    int64_t totalSize = 0;                 // Total size in bytes
    int64_t freeSpace = 0;                 // Free space in bytes
    bool isSystem = false;                 // Is this the system drive?
    bool hasMountPoint = false;            // Does this volume have any accessible path?
    bool isRootVolume = true;              // True if this volume should be scanned as a root (not nested)
};

/**
 * @brief Context for mount point traversal during AllFixedDisks scanning
 *
 * Tracks which volume GUIDs are targets for traversal and provides
 * lookup from mount point paths to volume information.
 */
struct MountPointTraversalContext {
    // Set of volume GUIDs that are fixed disk targets (for quick lookup)
    std::unordered_set<std::wstring> targetVolumeGuids;

    // Map from volume GUID to FixedDiskInfo for volume boundary tracking
    std::unordered_map<std::wstring, FixedDiskInfo> volumeInfoByGuid;

    // Set of fixed disk drive letter roots (e.g., L"C:\\", L"D:\\")
    std::unordered_set<std::wstring> fixedDiskRoots;
};

/**
 * @brief Enumerate all fixed (non-removable) disk volumes on the system
 *
 * Uses FindFirstVolumeW() to find ALL volumes (not just drive letters).
 * Handles:
 * - Traditional drive letters (C:\, D:\)
 * - Folder mount points (C:\Mount\DataDrive\)
 * - Volumes with multiple mount points
 * - Volumes with NO mount points (flagged but not scannable)
 *
 * Excludes:
 * - CD/DVD drives (DRIVE_CDROM)
 * - Removable media (DRIVE_REMOVABLE) - USB drives, SD cards
 * - Network drives (DRIVE_REMOTE)
 * - RAM disks (DRIVE_RAMDISK)
 *
 * @return Vector of FixedDiskInfo for each fixed volume
 */
std::vector<FixedDiskInfo> EnumerateFixedDisks();

/**
 * @brief Get only scannable fixed disks (those with at least one mount point)
 *
 * Filters out volumes that have no mount points since they cannot be
 * directly accessed for scanning.
 *
 * @return Vector of FixedDiskInfo excluding volumes with no mount points
 */
std::vector<FixedDiskInfo> EnumerateScannableFixedDisks();

/**
 * @brief Check if a specific path is on a fixed disk
 * @param path Path to check
 * @return true if path is on a DRIVE_FIXED volume
 */
bool IsFixedDisk(const std::wstring& path);

/**
 * @brief Get volume mount points for a volume GUID path
 *
 * Uses GetVolumePathNamesForVolumeNameW to get all paths where the
 * volume is accessible, including drive letters and folder mount points.
 *
 * @param volumeGuid Volume GUID path (e.g., \\?\Volume{GUID}\)
 * @return Vector of mount point paths
 */
std::vector<std::wstring> GetVolumeMountPointsForGuid(const std::wstring& volumeGuid);

/**
 * @brief Enumerate fixed disks and identify root volumes for scanning
 *
 * This is the optimized approach for --AllFixedDisks mode:
 * 1. Enumerates all fixed disk volumes
 * 2. Identifies which volumes are "nested" (mounted under another fixed disk's path)
 * 3. Marks nested volumes so they won't be scanned separately
 * 4. Returns all volumes, but only root volumes should be used as scan starting points
 *
 * Example: If E:\ is a fixed disk and E:\Data1\WMSI is a mount point for another
 * fixed disk volume, E:\Data1\WMSI is marked as "not root" because it will be
 * reached when scanning E:\ and traversing through the mount point.
 *
 * @return Vector of FixedDiskInfo with isRootVolume set appropriately
 */
std::vector<FixedDiskInfo> EnumerateFixedDisksWithNesting();

/**
 * @brief Build traversal context for mount point handling during scan
 *
 * Creates a context object that the folder scanner can use to:
 * - Identify if a mount point targets a fixed disk volume we want to scan
 * - Look up volume information when crossing volume boundaries
 *
 * @param allDisks All fixed disk volumes (from EnumerateFixedDisksWithNesting)
 * @return MountPointTraversalContext for use during scanning
 */
MountPointTraversalContext BuildTraversalContext(const std::vector<FixedDiskInfo>& allDisks);

/**
 * @brief Get volume GUID for a mount point path
 *
 * Uses GetVolumeNameForVolumeMountPointW to determine which volume
 * is mounted at the given path.
 *
 * @param mountPointPath Path to check (e.g., L"E:\\Data1\\WMSI\\")
 * @return Volume GUID if successful, empty string otherwise
 */
std::wstring GetVolumeGuidForMountPoint(const std::wstring& mountPointPath);

/**
 * @brief Check if a path is a volume mount point (not a junction/symlink)
 *
 * Uses GetVolumeNameForVolumeMountPointW to distinguish true volume
 * mount points from directory junctions (both have IO_REPARSE_TAG_MOUNT_POINT).
 *
 * @param path Path to check
 * @return true if path is a volume mount point, false if junction/symlink/other
 */
bool IsVolumeMountPoint(const std::wstring& path);

} // namespace FixedDiskEnumerator
