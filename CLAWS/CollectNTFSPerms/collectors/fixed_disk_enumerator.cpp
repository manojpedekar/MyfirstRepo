#include "fixed_disk_enumerator.h"
#include "../utils/stringutils.h"
#include <iostream>
#include <algorithm>

namespace FixedDiskEnumerator {

std::vector<std::wstring> GetVolumeMountPointsForGuid(const std::wstring& volumeGuid) {
    std::vector<std::wstring> mountPoints;

    // First call to get required buffer size
    wchar_t mountPath[MAX_PATH] = L"";
    DWORD returnLength = 0;

    if (!GetVolumePathNamesForVolumeNameW(
        volumeGuid.c_str(),
        mountPath,
        ARRAYSIZE(mountPath),
        &returnLength
    )) {
        DWORD error = GetLastError();
        if (error != ERROR_MORE_DATA) {
            return mountPoints;
        }
    }

    // Allocate buffer of required size
    std::vector<wchar_t> buffer(returnLength);

    // Get the actual mount points
    if (!GetVolumePathNamesForVolumeNameW(
        volumeGuid.c_str(),
        buffer.data(),
        static_cast<DWORD>(buffer.size()),
        &returnLength
    )) {
        return mountPoints;
    }

    // Parse the multi-string buffer with bounds checking
    for (DWORD i = 0; i < buffer.size();) {
        if (buffer[i] == L'\0') {
            break;
        }

        // Calculate remaining buffer size
        DWORD remaining = static_cast<DWORD>(buffer.size()) - i;
        // Find null terminator within remaining buffer
        DWORD len = 0;
        while (len < remaining && buffer[i + len] != L'\0') {
            len++;
        }

        // If no null terminator found, buffer is malformed
        if (len >= remaining) {
            break;
        }

        std::wstring mountPoint(&buffer[i], len);
        if (!mountPoint.empty()) {
            mountPoints.push_back(mountPoint);
        }

        // Move to the next string (skip past null terminator)
        i += len + 1;
    }

    return mountPoints;
}

std::vector<FixedDiskInfo> EnumerateFixedDisks() {
    std::vector<FixedDiskInfo> fixedDisks;

    std::cout << "\nEnumerating fixed disk volumes..." << std::endl;

    // Use FindFirstVolumeW to enumerate ALL volumes (including those without drive letters)
    wchar_t volumeGuid[MAX_PATH] = {0};
    HANDLE hFindVolume = FindFirstVolumeW(volumeGuid, MAX_PATH);

    if (hFindVolume == INVALID_HANDLE_VALUE) {
        std::cerr << "Failed to enumerate volumes. Error: " << GetLastError() << std::endl;
        return fixedDisks;
    }

    do {
        // Ensure trailing backslash for API calls
        std::wstring volumePath = volumeGuid;
        if (!volumePath.empty() && volumePath.back() != L'\\') {
            volumePath += L'\\';
        }

        // Get drive type for this volume
        UINT driveType = GetDriveTypeW(volumePath.c_str());

        // Only include fixed drives
        if (driveType != DRIVE_FIXED) {
            continue;
        }

        FixedDiskInfo info;
        info.volumeGuid = volumePath;

        // Get ALL mount points for this volume (drive letters + folder mounts)
        info.mountPoints = GetVolumeMountPointsForGuid(volumePath);
        info.hasMountPoint = !info.mountPoints.empty();

        // Determine the best path to use for scanning
        if (info.hasMountPoint) {
            // Prefer drive letter over folder mount point (shorter, more recognizable)
            info.primaryPath = info.mountPoints[0];
            for (const auto& mp : info.mountPoints) {
                // Drive letters are typically 3 chars: "C:\"
                if (mp.length() == 3 && mp[1] == L':') {
                    info.primaryPath = mp;
                    break;
                }
            }
        } else {
            // No mount point - use volume GUID (may not be scannable)
            info.primaryPath = volumePath;
        }

        // Get volume information
        wchar_t volumeLabel[MAX_PATH + 1] = L"";
        wchar_t fileSystem[MAX_PATH + 1] = L"";

        if (GetVolumeInformationW(
            volumePath.c_str(),
            volumeLabel, ARRAYSIZE(volumeLabel),
            nullptr,  // Serial number
            nullptr,  // Max component length
            nullptr,  // File system flags
            fileSystem, ARRAYSIZE(fileSystem)
        )) {
            info.volumeLabel = volumeLabel;
            info.fileSystem = fileSystem;
        }

        // Get size information
        ULARGE_INTEGER totalBytes = {}, freeBytes = {};
        if (GetDiskFreeSpaceExW(volumePath.c_str(), nullptr, &totalBytes, &freeBytes)) {
            info.totalSize = static_cast<int64_t>(totalBytes.QuadPart);
            info.freeSpace = static_cast<int64_t>(freeBytes.QuadPart);
        }

        // Check if system drive
        wchar_t systemPath[MAX_PATH];
        GetSystemDirectoryW(systemPath, ARRAYSIZE(systemPath));
        info.isSystem = false;
        for (const auto& mp : info.mountPoints) {
            if (mp.length() >= 1 && towupper(mp[0]) == towupper(systemPath[0])) {
                info.isSystem = true;
                break;
            }
        }

        fixedDisks.push_back(info);

        // Log what we found
        std::wcout << L"  Found fixed volume: " << info.volumeGuid << std::endl;
        if (info.hasMountPoint) {
            std::wcout << L"    Mount points: ";
            for (size_t i = 0; i < info.mountPoints.size(); i++) {
                if (i > 0) std::wcout << L", ";
                std::wcout << info.mountPoints[i];
            }
            std::wcout << std::endl;
            std::wcout << L"    Primary path: " << info.primaryPath << std::endl;
        } else {
            std::wcout << L"    WARNING: No mount point (volume not directly scannable)" << std::endl;
        }
        std::wcout << L"    Label: " << info.volumeLabel
                   << L", FileSystem: " << info.fileSystem
                   << L", Size: " << (info.totalSize / (1024LL*1024LL*1024LL)) << L" GB"
                   << (info.isSystem ? L" (System)" : L"")
                   << std::endl;

    } while (FindNextVolumeW(hFindVolume, volumeGuid, MAX_PATH));

    FindVolumeClose(hFindVolume);

    std::cout << "Found " << fixedDisks.size() << " fixed volume(s)" << std::endl;
    return fixedDisks;
}

std::vector<FixedDiskInfo> EnumerateScannableFixedDisks() {
    auto allDisks = EnumerateFixedDisks();

    // Filter to only volumes with mount points
    std::vector<FixedDiskInfo> scannableDisks;
    for (const auto& disk : allDisks) {
        if (disk.hasMountPoint) {
            scannableDisks.push_back(disk);
        } else {
            std::wcout << L"  Skipping volume without mount point: "
                       << disk.volumeGuid << std::endl;
        }
    }

    std::cout << "Found " << scannableDisks.size() << " scannable fixed disk(s)" << std::endl;
    return scannableDisks;
}

bool IsFixedDisk(const std::wstring& path) {
    if (path.empty()) return false;

    std::wstring rootPath = path;
    // Ensure it's a root path for GetDriveTypeW
    if (rootPath.length() >= 2 && rootPath[1] == L':') {
        rootPath = rootPath.substr(0, 2) + L"\\";
    }

    return GetDriveTypeW(rootPath.c_str()) == DRIVE_FIXED;
}

std::wstring GetVolumeGuidForMountPoint(const std::wstring& mountPointPath) {
    std::wstring path = mountPointPath;
    // Ensure trailing backslash (required by API)
    if (!path.empty() && path.back() != L'\\') {
        path += L'\\';
    }

    wchar_t volumeGuid[MAX_PATH] = {0};
    if (GetVolumeNameForVolumeMountPointW(path.c_str(), volumeGuid, MAX_PATH)) {
        return std::wstring(volumeGuid);
    }
    return L"";
}

bool IsVolumeMountPoint(const std::wstring& path) {
    // GetVolumeNameForVolumeMountPointW returns the volume GUID only for
    // true volume mount points, not for directory junctions
    return !GetVolumeGuidForMountPoint(path).empty();
}

// Helper: Check if a mount point path is nested under any of the fixed disk roots
static bool IsMountPointNested(const std::wstring& mountPoint,
                                const std::unordered_set<std::wstring>& fixedDiskRoots) {
    // Drive letters (length 3 like "C:\") are never nested
    if (mountPoint.length() == 3 && mountPoint[1] == L':' && mountPoint[2] == L'\\') {
        return false;
    }

    // For folder mount points, check if they start with a fixed disk root
    // e.g., "E:\Data1\WMSI\" starts with "E:\" which is a fixed disk root
    for (const auto& root : fixedDiskRoots) {
        // Case-insensitive prefix match
        if (mountPoint.length() > root.length()) {
            bool match = true;
            for (size_t i = 0; i < root.length() && match; i++) {
                if (towupper(mountPoint[i]) != towupper(root[i])) {
                    match = false;
                }
            }
            if (match) {
                return true;  // This mount point is under a fixed disk root
            }
        }
    }

    return false;
}

std::vector<FixedDiskInfo> EnumerateFixedDisksWithNesting() {
    // First, get all fixed disks
    auto allDisks = EnumerateScannableFixedDisks();

    if (allDisks.empty()) {
        return allDisks;
    }

    // Build set of drive letter roots from fixed disks
    std::unordered_set<std::wstring> fixedDiskRoots;
    for (const auto& disk : allDisks) {
        for (const auto& mp : disk.mountPoints) {
            // Drive letters are 3 chars: "C:\"
            if (mp.length() == 3 && mp[1] == L':' && mp[2] == L'\\') {
                // Normalize to uppercase for consistent matching
                std::wstring root = mp;
                root[0] = towupper(root[0]);
                fixedDiskRoots.insert(root);
            }
        }
    }

    std::cout << "\nAnalyzing mount point nesting..." << std::endl;
    std::cout << "Fixed disk drive roots: ";
    for (const auto& root : fixedDiskRoots) {
        std::wcout << root << L" ";
    }
    std::cout << std::endl;

    // For each volume, determine if it's a root or nested
    int rootCount = 0;
    int nestedCount = 0;

    for (auto& disk : allDisks) {
        // A volume is a root if it has at least one mount point that is NOT nested
        bool hasNonNestedMount = false;

        for (const auto& mp : disk.mountPoints) {
            if (!IsMountPointNested(mp, fixedDiskRoots)) {
                hasNonNestedMount = true;
                break;
            }
        }

        disk.isRootVolume = hasNonNestedMount;

        if (disk.isRootVolume) {
            rootCount++;
            std::wcout << L"  ROOT: " << disk.primaryPath << std::endl;
        } else {
            nestedCount++;
            std::wcout << L"  NESTED: " << disk.primaryPath;
            // Show which root it's under
            for (const auto& mp : disk.mountPoints) {
                if (mp.length() >= 3 && mp[1] == L':') {
                    std::wstring parentRoot = mp.substr(0, 3);
                    parentRoot[0] = towupper(parentRoot[0]);
                    std::wcout << L" (under " << parentRoot << L")";
                    break;
                }
            }
            std::wcout << std::endl;
        }
    }

    std::cout << "\nMount point analysis complete: "
              << rootCount << " root volume(s), "
              << nestedCount << " nested volume(s)" << std::endl;
    std::cout << "Only root volumes will be scanned as starting points." << std::endl;
    std::cout << "Nested volumes will be reached via mount point traversal." << std::endl;

    return allDisks;
}

MountPointTraversalContext BuildTraversalContext(const std::vector<FixedDiskInfo>& allDisks) {
    MountPointTraversalContext ctx;

    for (const auto& disk : allDisks) {
        // Add to target GUIDs (all fixed disks, not just roots)
        ctx.targetVolumeGuids.insert(disk.volumeGuid);

        // Add to volume info map
        ctx.volumeInfoByGuid[disk.volumeGuid] = disk;

        // Add drive letter roots
        for (const auto& mp : disk.mountPoints) {
            if (mp.length() == 3 && mp[1] == L':' && mp[2] == L'\\') {
                std::wstring root = mp;
                root[0] = towupper(root[0]);
                ctx.fixedDiskRoots.insert(root);
            }
        }
    }

    std::cout << "Built traversal context: "
              << ctx.targetVolumeGuids.size() << " target volumes, "
              << ctx.fixedDiskRoots.size() << " drive letter roots" << std::endl;

    return ctx;
}

} // namespace FixedDiskEnumerator
