#include "SnapshotExclusions.h"
#include <regex>

/**
 * @brief Checks if a path represents a snapshot, replication, or system metadata directory.
 *
 * Uses precompiled regex patterns with context-aware matching to distinguish between:
 * - Local drive paths (C:\, D:\, etc.) where Windows system folders may legitimately exist
 * - UNC paths (\\server\share) where Windows system folders never exist
 *
 * This prevents false positives where business folders (e.g., "\\server\Disaster Recovery")
 * are incorrectly excluded due to containing words like "Recovery" or "PerfLogs".
 *
 * The function is thread-safe (static regex is initialized once) and non-throwing.
 *
 * @param path The full path to check.
 * @return true if the path matches a known snapshot/replication pattern, false otherwise.
 */
bool IsExcludedSnapshotPath(const std::wstring& path) {
    // Thread-safe: static variables are initialized once in a thread-safe manner (C++11+)

    // NAS snapshot patterns - can appear anywhere in path hierarchy
    // These use vendor-specific naming conventions unlikely to collide with business folders
    // Vendors: NetApp, Isilon/PowerScale, Pure Storage, HPE Nimble, Synology, QNAP
    static const std::wregex nasSnapshotPattern(
        LR"((^|[\\/])(~snapshot|\.snapshot|#snapshot|@Snapshot|@Recycle|#recycle|@GMT-[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]{2}\.[0-9]{2}\.[0-9]{2}|\.sync|\.ifs|@Recently-Snapshot|\.vvclone|\.copy|\.ifsvar|\.ifsquota)([\\/]|$))",
        std::regex_constants::icase
    );

    // NetApp SnapMirror/SnapVault patterns - only match complete folder names (not prefixes)
    // This prevents excluding folders like "snapmirror-config" or "snapvault_procedures"
    static const std::wregex netappPattern(
        LR"((^|[\\/])(snapmirror|snapvault)([\\/]|$))",
        std::regex_constants::icase
    );

    // Windows Recycle Bin folders - can appear ANYWHERE in path
    // These folder names are NEVER legitimate business folders - always recycle bins
    // Includes: $Recycle.Bin (Vista+), RECYCLER (XP), Recycled (older Windows)
    // Common locations: drive root, user profiles (h:\USERS\user\RECYCLER), redirected folders
    static const std::wregex recycleBinPattern(
        LR"((^|[\\/])(\$Recycle\.Bin|RECYCLER|Recycled)([\\/]|$))",
        std::regex_constants::icase
    );

    // Windows system folders - ONLY at drive root (C:\, D:\, etc.)
    // This prevents matching on UNC paths or nested folders like "\\server\Recovery" or "C:\Data\Recovery"
    // Pattern: Drive letter + colon + backslash + folder name
    // Note: Recycle bin folders are handled separately above (can appear anywhere)
    static const std::wregex windowsSystemRootFolders(
        LR"(^[A-Z]:\\(Recovery|PerfLogs|MSOCache|\$WinREAgent|Windows\.old|\$Windows\.~BT|\$Windows\.~WS|System Volume Information)([\\/]|$))",
        std::regex_constants::icase
    );

    // Windows system folders - under C:\Windows\ directory
    // Pattern: Drive letter + Windows directory + subfolder
    static const std::wregex windowsSubfolders(
        LR"(^[A-Z]:\\Windows[\\/](Config\.Msi)([\\/]|$))",
        std::regex_constants::icase
    );

    // Windows system folders - under C:\ProgramData\ directory
    // Pattern: Drive letter + ProgramData + Microsoft\Windows path
    static const std::wregex programDataFolders(
        LR"(^[A-Z]:\\ProgramData[\\/](Microsoft[\\/]Windows[\\/]WER|Package Cache)([\\/]|$))",
        std::regex_constants::icase
    );

    // VSS snapshot device paths - Windows Volume Shadow Copy Service
    // Pattern: Very specific device path format
    static const std::wregex vssPattern(
        LR"(GLOBALROOT\\Device\\HarddiskVolumeShadowCopy)",
        std::regex_constants::icase
    );

    try {
        // Check all patterns with short-circuit evaluation
        // Most paths will match zero or one pattern, rarely multiple
        return std::regex_search(path, nasSnapshotPattern) ||
               std::regex_search(path, netappPattern) ||
               std::regex_search(path, recycleBinPattern) ||
               std::regex_search(path, windowsSystemRootFolders) ||
               std::regex_search(path, windowsSubfolders) ||
               std::regex_search(path, programDataFolders) ||
               std::regex_search(path, vssPattern);
    }
    catch (...) {
        // Non-throwing guarantee: if regex fails for any reason, assume it's not excluded
        return false;
    }
}
