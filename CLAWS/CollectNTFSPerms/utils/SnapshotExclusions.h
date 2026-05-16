#pragma once

#include <string>

/**
 * @brief Checks if a path represents a snapshot, replication, or system metadata directory.
 *
 * This function identifies directories used by major NAS vendors for snapshots, replication,
 * and system metadata, as well as Windows system folders that should be excluded from scanning
 * to avoid duplicate ACL data and unnecessary processing.
 *
 * IMPORTANT: Uses context-aware matching to prevent false positives. Windows system folders
 * are ONLY excluded when they appear at drive roots (e.g., C:\Recovery) and NOT on UNC paths
 * (e.g., \\server\Recovery) or in nested locations (e.g., C:\Data\Recovery), where they
 * represent legitimate business folders.
 *
 * Supported NAS patterns (excluded anywhere in path):
 * - NetApp: ~snapshot, .snapshot, snapmirror, snapvault
 * - Isilon/PowerScale: .snapshot, .sync, .ifsvar, .ifsquota
 * - Pure Storage: .snapshot, .pgroup-snap-*
 * - HPE/Nimble: .copy, .vvclone
 * - Synology: #snapshot, #recycle, @GMT-YYYY.MM.DD-HH.MM.SS
 * - QNAP: @Snapshot, @Recycle, @Recently-Snapshot
 * - Windows VSS: \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy*
 *
 * Supported Windows Recycle Bin folders (excluded ANYWHERE in path):
 * - $Recycle.Bin (Windows Vista+)
 * - RECYCLER (Windows XP and earlier)
 * - Recycled (older Windows versions)
 * These names are never legitimate business folders and should always be excluded.
 *
 * Supported Windows system folders (excluded ONLY at drive root or specific paths):
 * - Drive root only: Recovery, PerfLogs, MSOCache, $WinREAgent,
 *   Windows.old, $Windows.~BT, $Windows.~WS, System Volume Information
 * - Under C:\Windows\: Config.Msi
 * - Under C:\ProgramData\: Microsoft\Windows\WER, Package Cache
 *
 * Examples:
 * - C:\Recovery                                    -> EXCLUDED (Windows system folder at root)
 * - \\server\Disaster Recovery                     -> INCLUDED (business folder on UNC path)
 * - C:\Data\Recovery                               -> INCLUDED (nested folder, not at root)
 * - \\?\UNC\cifs1\capacityteam\TSM\Recovery        -> INCLUDED (business folder on UNC path)
 * - \\server\share\.snapshot                       -> EXCLUDED (NAS snapshot directory)
 * - H:\USERS\user\RECYCLER                         -> EXCLUDED (recycle bin in user profile)
 * - H:\Data\folder\$Recycle.Bin                    -> EXCLUDED (recycle bin anywhere)
 *
 * @param path The full path to check.
 * @return true if the path matches a known snapshot/replication/system pattern, false otherwise.
 * @note This function is thread-safe and non-throwing.
 * @note Version 1.1.1+ uses improved context-aware patterns to eliminate false positives.
 */
bool IsExcludedSnapshotPath(const std::wstring& path);
