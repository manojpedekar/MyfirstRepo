#include "../core/folderscanner.h"
#include "../utils/folderutils.h"
#include "../database/database.h"
#include "../utils/SnapshotExclusions.h"
#include "../collectors/fixed_disk_enumerator.h"
#include <filesystem>
#include <algorithm>
#include <iostream>
#include <iomanip>
#include <chrono>
#include <functional>
#include <sstream>
#include "../utils/utils.h" // For FormatNumberWithLocale


#ifdef _WIN32
#   include <windows.h>
#endif


/**
 * @brief Constructs a FolderScanner for concurrent folder scanning and indexing.
 *
 * Initializes the scanner with the specified root path, inventory ID, thread count, and database context.
 * If the provided thread count is invalid or less than 1, it defaults to one less than the number of hardware threads, with a minimum of 1.
 *
 * @param rootPath The root directory to begin scanning.
 * @param inventoryId Identifier for the inventory session.
 * @param threadCount Number of worker threads to use for scanning.
 */

FolderScanner::FolderScanner(const std::wstring& rootPath,
    const std::string& inventoryId,
    int threadCount,
    DatabaseContext& dbCtx,
    int64_t startingFolderId)
    : rootPath(rootPath)
    , inventoryId(inventoryId)
    , threadCount(threadCount > 0 ? threadCount : static_cast<int>(std::thread::hardware_concurrency()) - 1)
    , dbCtx(dbCtx)
{
    if (this->threadCount < 1) this->threadCount = 1;

    // Set starting ID for folder assignment (used in AllFixedDisks mode
    // to ensure unique IDs across volume scans)
    if (startingFolderId > 1) {
        folderIndex.setNextId(startingFolderId);
    }
}

/**
 * @brief Cleans up the FolderScanner by stopping worker threads and ensuring all resources are released.
 *
 * Signals all worker threads to stop, notifies any waiting threads, and joins all worker threads to guarantee a clean shutdown.
 */
FolderScanner::~FolderScanner() {
    shouldStop = true;
    queueCondition.notify_all();
    
    for (auto& worker : workers) {
        if (worker.joinable()) {
            worker.join();
        }
    }
}

/**
 * @brief Starts the folder scanning process from the root path using multiple threads.
 *
 * Initializes locale and console output, begins a database transaction, and launches worker threads to process folders concurrently. Displays real-time progress in the console, waits for all folder processing tasks to complete, and then finalizes the scan by committing the transaction. Outputs a summary of scanning statistics and logs folder index memory usage.
 *
 * @return true if the scan and transaction commit succeed; false otherwise.
 */
bool FolderScanner::start() {
    // Check if root path is a snapshot directory
    if (IsExcludedSnapshotPath(rootPath)) {
        LogEvent(dbCtx, Logging::Severity::WARNING, "FolderScanner",
                "[Skip] Root path is a snapshot/replication folder - scanning aborted",
                FolderUtils::toUtf8(rootPath), 0);
        std::cout << "\nWarning: Root path appears to be a snapshot/replication folder.\n"
                  << "Scanning aborted to avoid processing duplicate data.\n\n";
        return false;
    }

    // Create worker threads
    for (int i = 0; i < threadCount; i++) {
        workers.emplace_back(&FolderScanner::workerThread, this);
    }

    // Start with the root path
    int64_t rootId = getOrAssignFolderId(rootPath);
    enqueueFolder(rootPath, 0);  // Root has no parent
    
    // Wait for all tasks to complete
    {
        std::unique_lock<std::timed_mutex> lock(queueMutex);
        
        while (stats.tasksInFlight.load() > 0) {
            queueCondition.wait_for(lock, std::chrono::seconds(1), [this] {
                return stats.tasksInFlight.load() == 0;
            });

            int cols = GetConsoleWidth();

            std::vector<std::string> parts;
            parts.emplace_back("Scanning...");
            parts.emplace_back("Folders: "     + FormatNumberWithLocale(stats.foldersProcessed.load()));
            parts.emplace_back("Queue: "       + FormatNumberWithLocale(stats.currentQueueSize.load()));
            parts.emplace_back("In Flight: "   + FormatNumberWithLocale(stats.tasksInFlight.load()));
            if (cols > 60) parts.emplace_back("Errors: "        + FormatNumberWithLocale(stats.foldersWithErrors.load()));
            if (cols > 75) parts.emplace_back("Access Denied: "+ FormatNumberWithLocale(stats.accessDeniedFolders.load()));
            if (cols > 90) parts.emplace_back("Peak Queue: "   + FormatNumberWithLocale(stats.peakQueueSize.load()));

            // Create progress message
            std::string progressMsg = "";
            for (size_t i = 0; i < parts.size(); i++) {
                progressMsg += parts[i];
                if (i < parts.size() - 1) {
                    progressMsg += " | ";
                }
            }

            // Update console with progress using reliable line clearing
            PrintProgressLine(progressMsg);
        }

        // Clear the progress line and print "Done!"
        ClearConsoleLine();
        std::cout << "Done!" << std::endl;
    }
    
    // Signal threads to stop and join them
    shouldStop = true;
    queueCondition.notify_all();
    
    for (auto& worker : workers) {
        if (worker.joinable()) {
            worker.join();
        }
    }
    
    // Set foldersFound to match foldersProcessed for backward compatibility
    stats.foldersFound.store(stats.foldersProcessed.load());
    
    // Calculate the memory used for the folder hashtable in KB
    size_t folderIndexBytes = folderIndex.estimateMemoryUsage();
    double folderIndexKB = static_cast<double>(folderIndexBytes) / 1024.0;

    AppGlobals::FoldersWithErrors = stats.foldersWithErrors + stats.accessDeniedFolders;
    // FIX: Explicit cast from size_t to int32_t (safe - queue sizes don't exceed 2.1B in practice)
    AppGlobals::PeakQueueSize = static_cast<std::int32_t>(stats.peakQueueSize.load());
    AppGlobals::FoldersProcessed = stats.foldersProcessed;

    std::cout << "\nFolder inventory scan summary:\n"
              << "--------------------------------------------------\n"
              << "Total Folders Found    : " << std::setw(10) << FormatNumberWithLocale(stats.foldersProcessed.load()) << "\n"
              << "Folders With Errors    : " << std::setw(10) << FormatNumberWithLocale(stats.foldersWithErrors.load()) << "\n"
              << "Folders Access Denied  : " << std::setw(10) << FormatNumberWithLocale(stats.accessDeniedFolders.load()) << "\n"
              << "Total Folders in Index : " << std::setw(10) << FormatNumberWithLocale(folderIndex.size()) << "\n"
              << "Peak Queue Size        : " << std::setw(10) << FormatNumberWithLocale(stats.peakQueueSize.load()) << "\n"
              << "Folder Index Memory    : " << std::setw(10) << FormatNumberWithLocale(static_cast<size_t>(folderIndexKB)) << " KB\n"
              << "--------------------------------------------------\n\n";

    // Write folder scan summary to debug file
    AppGlobals::WriteDebug("\nFolder inventory scan summary:\n");
    AppGlobals::WriteDebug("--------------------------------------------------\n");
    AppGlobals::WriteDebug("Total Folders Found    :          " + FormatNumberWithLocale(stats.foldersProcessed.load()) + "\n");
    AppGlobals::WriteDebug("Folders With Errors    :          " + FormatNumberWithLocale(stats.foldersWithErrors.load()) + "\n");
    AppGlobals::WriteDebug("Folders Access Denied  :          " + FormatNumberWithLocale(stats.accessDeniedFolders.load()) + "\n");
    AppGlobals::WriteDebug("Total Folders in Index :          " + FormatNumberWithLocale(folderIndex.size()) + "\n");
    AppGlobals::WriteDebug("Peak Queue Size        :          " + FormatNumberWithLocale(stats.peakQueueSize.load()) + "\n");
    AppGlobals::WriteDebug("Folder Index Memory    :          " + FormatNumberWithLocale(static_cast<size_t>(folderIndexKB)) + " KB\n");
    AppGlobals::WriteDebug("--------------------------------------------------\n\n");
    
    LogEvent(
        dbCtx,
        Logging::Severity::INFO,
        "FolderScanner", 
        "Folder index hashtable memory usage (KB)", 
        "",
        0,
        GetCurrentThreadId(),
        std::to_string(static_cast<size_t>(folderIndexKB)),
        dbCtx.inventoryID
    );

    return true;
}


/**
 * @brief Executes a worker thread loop to process folder entries from the queue.
 *
 * Continuously waits for folder entries to become available in the queue, processes each folder, and updates task statistics. Exits when signaled to stop and the queue is empty.
 */
void FolderScanner::workerThread() {
    while (!shouldStop) {
        FolderEntry entry;
        {
            std::unique_lock<std::timed_mutex> lock(queueMutex);
            queueCondition.wait(lock, [this] {
                return !folderQueue.empty() || shouldStop;
            });

            if (shouldStop && folderQueue.empty()) {
                return;
            }

            entry = folderQueue.front();
            folderQueue.pop();
            // FIX FC-003, FC-016: Read size before releasing lock, no cast needed (size_t)
            stats.currentQueueSize = folderQueue.size();
        }

        processFolder(entry.path, entry.parentId, entry.recursionDepth);

        // Decrement tasks in flight and notify
        stats.tasksInFlight--;
        queueCondition.notify_all();
    }
}

void FolderScanner::processFolder(const std::wstring& path, int64_t parentId, int recursionDepth) {
    // FC-002 FOLLOW-UP: Remove long path prefix for database storage
    // The path parameter may have \\?\ prefix from FC-002 fix (line 375 in enumeration loop)
    // We need to store normalized paths without the prefix to avoid duplicate folder IDs
    std::wstring storagePath = FolderUtils::removeLongPathPrefix(path);

    // Check recursion depth to prevent stack overflow
    if (recursionDepth > MAX_RECURSION_DEPTH) {
        std::string errorMsg = "Maximum recursion depth (" + std::to_string(MAX_RECURSION_DEPTH) + ") exceeded";
        LogEvent(dbCtx, Logging::Severity::ERR, "FolderScanner", errorMsg, FolderUtils::toUtf8(storagePath));
        // FIX FC-006: Use direct atomic increment for consistency (no mutex needed)
        stats.foldersWithErrors++;
        return;
    }

    // Ensure path doesn't end with backslash unless it's a root drive or UNC share root
    std::wstring normalizedPath = storagePath;
    if (normalizedPath.length() >= 3 &&
        (normalizedPath.back() == L'\\' || normalizedPath.back() == L'/')) {
        // Check if this is a root path that should keep the trailing backslash
        bool isRoot = false;

        // Check for local drive root (e.g., "C:\")
        if (normalizedPath.length() == 3 &&
            iswalpha(normalizedPath[0]) &&
            normalizedPath[1] == L':') {
            isRoot = true;
        }
        // Check for UNC share root (e.g., "\\server\share\")
        else if (normalizedPath.length() >= 5 &&
                 normalizedPath[0] == L'\\' &&
                 normalizedPath[1] == L'\\') {
            // Find the share name end (third backslash)
            size_t firstSlash = normalizedPath.find(L'\\', 2);
            if (firstSlash != std::wstring::npos) {
                size_t secondSlash = normalizedPath.find(L'\\', firstSlash + 1);
                // If the trailing backslash is the share root, keep it
                if (secondSlash == normalizedPath.length() - 1) {
                    isRoot = true;
                }
            }
        }

        // Remove trailing backslash only if not a root
        if (!isRoot) {
            normalizedPath.pop_back();
        }
    }
    
    // Use proper path separator for search pattern
    std::wstring searchPath;
    if (normalizedPath.back() == L'\\') {
        // It's a root drive (e.g., "C:\")
        searchPath = normalizedPath + L"*";
    } else {
        searchPath = normalizedPath + L"\\*";
    }
    
    std::wstring longPath = FolderUtils::toLongPath(searchPath);
    
    WIN32_FIND_DATAW findData;
    HANDLE hFind = FindFirstFileExW(
        longPath.c_str(),
        FindExInfoBasic,
        &findData,
        FindExSearchLimitToDirectories,
        nullptr,
        FIND_FIRST_EX_LARGE_FETCH
    );
    
    if (hFind == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        std::string errorMsg;

        // UNC-FIX: Provide detailed error messages for common network errors
        // This helps diagnose UNC path issues that previously failed silently
        std::string errorDetail;
        switch (error) {
            case ERROR_BAD_NETPATH:       errorDetail = "Network path not found (server unreachable or doesn't exist)"; break;
            case ERROR_BAD_NET_NAME:      errorDetail = "Invalid network share name"; break;
            case ERROR_NETWORK_UNREACHABLE: errorDetail = "Network is unreachable"; break;
            case ERROR_INVALID_NAME:      errorDetail = "Invalid path name format"; break;
            case ERROR_PATH_NOT_FOUND:    errorDetail = "Path does not exist"; break;
            case ERROR_FILE_NOT_FOUND:    errorDetail = "Folder not found"; break;
            case ERROR_LOGON_FAILURE:     errorDetail = "Logon failure (authentication issue)"; break;
            case ERROR_ACCESS_DENIED:     errorDetail = "Access denied"; break;
            default:                      errorDetail = "Error code " + std::to_string(error); break;
        }

        if (error == ERROR_ACCESS_DENIED) {
            // FC-003 FIX: Collect ACL even when enumeration fails
            // We can't enumerate this folder's children, but we can still:
            // 1. Add the folder to the index
            // 2. Insert it into the database
            // 3. Mark it as scanned so ACL processing will occur

            errorMsg = "Access denied to folder - will still collect ACL";
            LogEvent(dbCtx, Logging::Severity::WARNING, "FolderScanner", errorMsg,
                    FolderUtils::toUtf8(storagePath), error);
            stats.accessDeniedFolders++;

            // Get or assign folder ID
            int64_t folderId = getOrAssignFolderId(storagePath);

            // FC-003: Mark as scanned so ACL processing will happen later
            folderIndex.markAsScanned(folderId);

            // Try to insert folder into database (best effort)
            try {
                // Ensure ancestors are inserted first
                bool ancestorsOk = EnsureAncestorsInserted(dbCtx, inventoryId, folderIndex, storagePath);
                if (ancestorsOk) {
                    int64_t actualParentId = GetParentFolderId(folderIndex, storagePath);
                    int volumeId = GetVolumeIdFromPath(dbCtx, storagePath);

                    // Try to get folder attributes (may also fail with ACCESS_DENIED)
                    WIN32_FILE_ATTRIBUTE_DATA folderAttribs = {};
                    BOOL attribSuccess = GetFileAttributesExW(
                        FolderUtils::toLongPath(storagePath).c_str(),
                        GetFileExInfoStandard,
                        &folderAttribs
                    );

                    // Insert folder (with or without attributes)
                    if (attribSuccess) {
                        InsertFolderBatch(dbCtx, inventoryId, folderId, storagePath, actualParentId, volumeId,
                                         &folderAttribs.ftCreationTime,
                                         &folderAttribs.ftLastWriteTime,
                                         &folderAttribs.ftLastAccessTime,
                                         folderAttribs.dwFileAttributes);
                    } else {
                        InsertFolderBatch(dbCtx, inventoryId, folderId, storagePath, actualParentId, volumeId,
                                         nullptr, nullptr, nullptr, 0);
                    }

                    // Count as processed even though we couldn't enumerate
                    stats.foldersProcessed++;
                }
            } catch (const std::exception& e) {
                // Log but don't fail - we still want ACL processing to happen
                std::string errMsg = "Exception inserting ACCESS_DENIED folder: " + std::string(e.what());
                LogEvent(dbCtx, Logging::Severity::ERR, "FolderScanner", errMsg, FolderUtils::toUtf8(storagePath));
            }

            // Return - can't enumerate children, but folder is queued for ACL processing
            return;
        } else {
            // UNC-FIX: Check if this is the root path (recursionDepth == 0) and provide
            // detailed error message to help diagnose UNC path issues
            if (recursionDepth == 0) {
                // This is the root folder - failure here means no folders will be found!
                errorMsg = "CRITICAL: Failed to enumerate ROOT folder: " + errorDetail;
                std::cerr << "\nERROR: Cannot enumerate root folder: " << FolderUtils::toUtf8(storagePath) << "\n";
                std::cerr << "       Reason: " << errorDetail << "\n";

                // For UNC paths, provide additional guidance
                if (storagePath.length() >= 2 && storagePath[0] == L'\\' && storagePath[1] == L'\\') {
                    std::cerr << "\nUNC Path Troubleshooting:\n";
                    std::cerr << "  1. Verify the server name is correct and reachable (ping "
                              << FolderUtils::toUtf8(storagePath.substr(2, storagePath.find(L'\\', 2) - 2)) << ")\n";
                    std::cerr << "  2. Verify the share name exists on the remote server\n";
                    std::cerr << "  3. Verify you have permissions to access the share\n";
                    std::cerr << "  4. If using --RemoteComputer, ensure the path is accessible from this machine\n\n";
                }
            } else {
                errorMsg = "Failed to enumerate folder: " + errorDetail;
            }
            LogEvent(dbCtx, Logging::Severity::ERR, "FolderScanner", errorMsg,
                    FolderUtils::toUtf8(storagePath), error);
            // FIX FC-006: Use direct atomic increment for consistency (no mutex needed)
            stats.foldersWithErrors++;
            return;
        }
    }

    // Count this folder
    stats.foldersProcessed++;

    // FC-002 FOLLOW-UP: Use storagePath (without \\?\ prefix) for FolderIndex and database
    // Get or assign folder ID
    int64_t folderId = getOrAssignFolderId(storagePath);

    // Mark this folder as scanned (vs. only indexed as ancestor)
    // This ensures ACL processing only happens for folders that were actually enumerated
    folderIndex.markAsScanned(folderId);

    // FIX FC-007: Ensure all ancestors are in the database before inserting folder
    // If ancestor insertion fails, skip folder insertion to prevent foreign key violations
    bool ancestorsOk = false;
    try {
        ancestorsOk = EnsureAncestorsInserted(dbCtx, inventoryId, folderIndex, storagePath);
        if (!ancestorsOk) {
            std::string errorMsg = "Failed to insert ancestor folders for: " + FolderUtils::toUtf8(storagePath);
            LogEvent(dbCtx, Logging::Severity::ERR, "FolderScanner", errorMsg, FolderUtils::toUtf8(storagePath));
            stats.foldersWithErrors++;
            return; // Skip this folder to prevent foreign key constraint violation
        }
    } catch (const std::exception& e) {
        std::string errorMsg = "Exception during ancestor insertion: " + std::string(e.what());
        LogEvent(dbCtx, Logging::Severity::ERR, "FolderScanner", errorMsg, FolderUtils::toUtf8(storagePath));
        stats.foldersWithErrors++;
        return; // Skip this folder to prevent foreign key constraint violation
    }

    // Get actual parent ID from FolderIndex (after ancestors are inserted)
    // This ensures scan root gets correct parent even if enqueued with parentId=0
    int64_t actualParentId = GetParentFolderId(folderIndex, storagePath);

    // Add this folder to the database using batched insert
    // We only reach here if ancestors were successfully inserted
    bool insertSuccess = false;
    try {
        // Determine volume ID for this folder
        int volumeId = GetVolumeIdFromPath(dbCtx, storagePath);

        // Get folder attributes and timestamps for this folder
        WIN32_FILE_ATTRIBUTE_DATA folderAttribs = {};
        BOOL attribSuccess = GetFileAttributesExW(
            FolderUtils::toLongPath(storagePath).c_str(),
            GetFileExInfoStandard,
            &folderAttribs
        );

        // Insert folder with parent, volume, and metadata information
        // Use actualParentId (from FolderIndex) instead of parentId (from queue)
        if (attribSuccess) {
            insertSuccess = InsertFolderBatch(dbCtx, inventoryId, folderId, storagePath, actualParentId, volumeId,
                                             &folderAttribs.ftCreationTime,
                                             &folderAttribs.ftLastWriteTime,
                                             &folderAttribs.ftLastAccessTime,
                                             folderAttribs.dwFileAttributes);
        } else {
            // Fallback without attributes if GetFileAttributesExW fails
            insertSuccess = InsertFolderBatch(dbCtx, inventoryId, folderId, storagePath, actualParentId, volumeId,
                                             nullptr, nullptr, nullptr, 0);
        }
    } catch (const std::exception& e) {
        std::string errorMsg = "Exception during folder insert: " + std::string(e.what());
        LogEvent(dbCtx, Logging::Severity::ERR, "FolderScanner", errorMsg, FolderUtils::toUtf8(storagePath));
        stats.foldersWithErrors++;
    }

    if (!insertSuccess) {
        std::string errorMsg = "Failed to insert folder into database: " + FolderUtils::toUtf8(storagePath);
        LogEvent(dbCtx, Logging::Severity::ERR, "FolderScanner", errorMsg, FolderUtils::toUtf8(storagePath));
        stats.foldersWithErrors++;
    }
    
    // Process subfolders
    do {
        // Check if this is a directory we should process:
        // 1. Regular directories (not reparse points), OR
        // 2. Reparse points that are mount points targeting fixed disk volumes we want to scan
        std::wstring folderName = findData.cFileName;
        if (folderName == L"." || folderName == L"..") {
            continue;
        }

        // Build the full path first (needed for mount point check)
        std::wstring fullPath;
        if (normalizedPath.back() == L'\\') {
            // It's a root drive (e.g., "C:\")
            fullPath = normalizedPath + folderName;
        } else {
            fullPath = normalizedPath + L"\\" + folderName;
        }

        // Determine if this is a directory we should traverse
        bool shouldProcess = false;
        if (isDirectory(findData)) {
            // Regular directory (not a reparse point)
            shouldProcess = true;
        } else if (isTraversableMountPoint(findData, fullPath)) {
            // Mount point that targets a fixed disk volume we want to scan
            shouldProcess = true;
        }

        if (shouldProcess) {
            // Check if this is a snapshot/replication folder that should be excluded
            // IMPORTANT: Check BEFORE adding long path prefix, as exclusion patterns expect
            // unprefixed paths (e.g., "C:\$Recycle.Bin" not "\\?\C:\$Recycle.Bin")
            if (IsExcludedSnapshotPath(fullPath)) {
                // Log the exclusion
                LogEvent(dbCtx, Logging::Severity::DEBUG, "FolderScanner",
                        "[Skip] Snapshot/replication folder excluded",
                        FolderUtils::toUtf8(fullPath), 0);
                continue; // Skip this folder and its descendants
            }

            // FC-002 FIX: Apply long path prefix to child paths to support paths > 260 characters
            // Without this, deeply nested folder structures fail even if parent was accessed correctly
            fullPath = FolderUtils::toLongPath(fullPath);

            if (!tryEnqueueFolder(fullPath, folderId, recursionDepth + 1, QUEUE_TIMEOUT_MS)) {
                // If we can't enqueue, process it directly
                processFolder(fullPath, folderId, recursionDepth + 1);
            }
        }
    } while (FindNextFileW(hFind, &findData));
    
    FindClose(hFind);
}

int64_t FolderScanner::getOrAssignFolderId(const std::wstring& path) {
    return folderIndex.getOrAssignId(path);
}

void FolderScanner::enqueueFolder(const std::wstring& path, int64_t parentId, int recursionDepth) {
    std::unique_lock<std::timed_mutex> lock(queueMutex);
    folderQueue.push({path, parentId, recursionDepth});
    // FIX FC-003: Use size_t directly, no cast needed
    size_t currentSize = folderQueue.size();
    stats.currentQueueSize = currentSize;
    stats.tasksInFlight++;  // Increment tasks in flight before enqueueing

    // Update peak queue size atomically
    size_t currentPeak = stats.peakQueueSize.load();
    while (currentSize > currentPeak) {
        if (stats.peakQueueSize.compare_exchange_weak(currentPeak, currentSize)) {
            break;
        }
    }

    queueCondition.notify_all();
}

bool FolderScanner::isDirectory(const WIN32_FIND_DATAW& findData) const {
    // Check if it's a directory but NOT a reparse point (junction, symlink, mount point)
    // This prevents infinite loops from circular references
    return (findData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0 &&
           (findData.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
}

bool FolderScanner::isTraversableMountPoint(const WIN32_FIND_DATAW& findData, const std::wstring& fullPath) const {
    // Must be a directory with reparse point attribute
    if ((findData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
        (findData.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0) {
        return false;
    }

    // Check if mount point traversal is enabled at all
    if (!dbCtx.traverseMountPoints && dbCtx.mountPointContext == nullptr) {
        return false;
    }

    // Get the volume GUID for this mount point
    // This also distinguishes true volume mount points from directory junctions
    std::wstring volumeGuid = FixedDiskEnumerator::GetVolumeGuidForMountPoint(fullPath);
    if (volumeGuid.empty()) {
        // Not a volume mount point (could be a junction or symlink)
        return false;
    }

    // If we have a specific target list (AllFixedDisks mode), check against it
    if (dbCtx.mountPointContext != nullptr) {
        if (dbCtx.mountPointContext->targetVolumeGuids.find(volumeGuid) !=
            dbCtx.mountPointContext->targetVolumeGuids.end()) {
            LogEvent(dbCtx, Logging::Severity::INFO, "FolderScanner",
                    "[MountPoint] Traversing into fixed disk volume mount point",
                    FolderUtils::toUtf8(fullPath), 0);
            return true;
        }
        // In AllFixedDisks mode with context, only traverse target volumes
        return false;
    }

    // Normal mode with traverseMountPoints=true: traverse all volume mount points
    if (dbCtx.traverseMountPoints) {
        LogEvent(dbCtx, Logging::Severity::INFO, "FolderScanner",
                "[MountPoint] Traversing into volume mount point",
                FolderUtils::toUtf8(fullPath), 0);
        return true;
    }

    return false;
}

std::wstring FolderScanner::makeLongPath(const std::wstring& path) const {
    return FolderUtils::toLongPath(path);
}

void FolderScanner::updateStats(const std::function<void(ScannerStats&)>& updateFunc) {
    std::lock_guard<std::mutex> lock(statsMutex);
    updateFunc(stats);
}

bool FolderScanner::tryEnqueueFolder(const std::wstring& path, int64_t parentId, int recursionDepth, int timeoutMs) {
    std::unique_lock<std::timed_mutex> lock(queueMutex, std::defer_lock);
    if (!lock.try_lock_for(std::chrono::milliseconds(timeoutMs))) {
        return false; // Could not acquire lock within timeout
    }

    folderQueue.push({path, parentId, recursionDepth});
    // FIX FC-003: Use size_t directly, no cast needed
    size_t currentSize = folderQueue.size();
    stats.currentQueueSize = currentSize;
    stats.tasksInFlight++;

    // Update peak queue size atomically
    size_t currentPeak = stats.peakQueueSize.load();
    while (currentSize > currentPeak) {
        if (stats.peakQueueSize.compare_exchange_weak(currentPeak, currentSize)) {
            break;
        }
    }

    queueCondition.notify_one();
    return true;
}

void FolderScanner::processFolderWithRetry(const std::wstring& path, int64_t parentId) {
    int attempts = 0;
    const int maxAttempts = 3;
    
    while (attempts < maxAttempts) {
        try {
            processFolder(path, parentId);
            return; // Success
        } catch (const std::exception& e) {
            attempts++;
            std::string errorMsg = "Failed to process folder (attempt " + std::to_string(attempts) + 
                                  "): " + FolderUtils::toUtf8(path) + " - " + e.what();
            LogEvent(dbCtx, Logging::Severity::WARNING, "FolderScanner", errorMsg,
                   FolderUtils::toUtf8(path));
            
            if (attempts >= maxAttempts) {
                // Log final failure
                errorMsg = "Failed to process folder after " + std::to_string(maxAttempts) +
                          " attempts: " + FolderUtils::toUtf8(path);
                LogEvent(dbCtx, Logging::Severity::ERR, "FolderScanner", errorMsg,
                       FolderUtils::toUtf8(path));

                // FIX FC-006: Use direct atomic increment for consistency (no mutex needed)
                stats.foldersWithErrors++;
                return;
            }
            
            // Wait with exponential backoff before retrying
            std::this_thread::sleep_for(std::chrono::milliseconds(100 * (1 << attempts)));
        }
    }
} 
