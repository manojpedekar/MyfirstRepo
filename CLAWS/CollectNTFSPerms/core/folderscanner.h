#pragma once
#include <string>
#include <queue>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <vector>
#include <windows.h>
#include "../core/folderindex.h"
#include "../utils/security_utils.h"
#include <functional>

struct DatabaseContext; // Forward declaration to avoid including database.h

/**
 * @brief Represents a folder to be processed.
 */
struct FolderEntry {
    std::wstring path;
    int64_t parentId = -1;  // Updated for FC-001 type consistency
    int recursionDepth = 0;
};

/**
 * @brief Statistics about the folder scanning process.
 */
struct ScannerStats {
    std::atomic<int> foldersProcessed{ 0 };
    std::atomic<int> foldersWithErrors{ 0 };
    std::atomic<int> accessDeniedFolders{ 0 };
    // FIX FC-003: Use size_t for queue sizes to prevent integer overflow
    std::atomic<size_t> currentQueueSize{ 0 };
    std::atomic<size_t> peakQueueSize{ 0 };
    std::atomic<int> tasksInFlight{ 0 };  // Track number of folders being processed
    std::atomic<int> foldersFound{ 0 };   // Total folders found (alias for foldersProcessed)
};

/**
 * @brief Handles threaded folder enumeration and database insertion.
 *
 * This class manages a pool of worker threads that process folders
 * from a queue and insert them into the database. It uses a producer-consumer
 * pattern with a thread-safe queue.
 */
class FolderScanner {
public:
    /**
     * @brief Constructs a FolderScanner.
     *
     * @param rootPath The root folder to start scanning.
     * @param inventoryId The database inventory session ID.
     * @param threadCount Number of worker threads to use (0 = auto).
     * @param dbCtx Reference to the database context (for logging and inserts).
     * @param startingFolderId Starting ID for folder assignment (used in AllFixedDisks mode
     *                         to ensure unique IDs across volume scans). Default is 1.
     */
    FolderScanner(const std::wstring& rootPath,
        const std::string& inventoryId,
        int threadCount,
        DatabaseContext& dbCtx,
        int64_t startingFolderId = 1);
    ~FolderScanner();

    /**
     * @brief Starts the folder scanning process.
     *
     * @return true if scanning completed successfully, false otherwise.
     */
    bool start();

    /**
     * @brief Gets the current scanning statistics.
     *
     * @return const ScannerStats& The current statistics.
     */
    const ScannerStats& getStats() const { return stats; }

    /**
     * @brief Gets a reference to the folder index.
     *
     * @return const FolderIndex& Reference to the folder index.
     */
    const FolderIndex& getFolderIndex() const {
        return folderIndex;
    }

    /**
     * @brief Gets a non-const reference to the folder index.
     *
     * @return FolderIndex& Reference to the folder index.
     */
    FolderIndex& getFolderIndex() {
        return folderIndex;
    }

    /**
     * @brief Iterates over all folders in the index and calls the provided function for each one.
     *
     * @param callback Function to call for each folder, taking path and localFolderId as parameters.
     */
    void forEachFolder(std::function<void(const std::wstring&, int64_t)> callback) const {
        folderIndex.forEach(callback);
    }

    /**
     * @brief Iterates over only scanned folders (excludes ancestors) and calls the provided function for each one.
     *
     * This should be used for ACL processing to avoid processing folders that were only indexed
     * as ancestors but never actually scanned/enumerated.
     *
     * @param callback Function to call for each scanned folder, taking path and localFolderId as parameters.
     */
    void forEachScannedFolder(std::function<void(const std::wstring&, int64_t)> callback) const {
        folderIndex.forEachScanned(callback);
    }

private:
    void workerThread();
    void processFolder(const std::wstring& path, int64_t parentId, int recursionDepth = 0);
    void enqueueFolder(const std::wstring& path, int64_t parentId, int recursionDepth = 0);
    bool isDirectory(const WIN32_FIND_DATAW& findData) const;
    bool isTraversableMountPoint(const WIN32_FIND_DATAW& findData, const std::wstring& fullPath) const;
    std::wstring makeLongPath(const std::wstring& path) const;
    int64_t getOrAssignFolderId(const std::wstring& path);  // Updated for FC-001 type consistency

    std::wstring rootPath;
    std::string inventoryId;
    int threadCount;
    std::vector<std::thread> workers;
    std::queue<FolderEntry> folderQueue;
    std::timed_mutex queueMutex;
    std::condition_variable_any queueCondition;
    std::atomic<bool> shouldStop{ false };
    ScannerStats stats;
    FolderIndex folderIndex;
    std::mutex dbMutex;
    std::mutex folderIndexMutex;
    std::mutex statsMutex;
    static constexpr int QUEUE_TIMEOUT_MS = 1000;
    static constexpr int DB_OPERATION_TIMEOUT_MS = 5000;
    static constexpr int MAX_RECURSION_DEPTH = 1000;
    void updateStats(const std::function<void(ScannerStats&)>& updateFunc);
    bool tryEnqueueFolder(const std::wstring& path, int64_t parentId, int recursionDepth = 0, int timeoutMs = QUEUE_TIMEOUT_MS);
    void processFolderWithRetry(const std::wstring& path, int64_t parentId);
    DatabaseContext& dbCtx;
};
