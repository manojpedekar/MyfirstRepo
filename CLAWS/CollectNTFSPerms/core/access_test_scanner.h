#pragma once

#include <string>
#include <vector>
#include <functional>
#include <atomic>
#include <thread>
#include <mutex>
#include <queue>
#include <condition_variable>
#include <windows.h>

/**
 * @brief Entry for a folder with access denied
 */
struct AccessDeniedEntry {
    std::wstring path;
    DWORD errorCode;
    std::string errorMessage;
};

/**
 * @brief Results from an access test scan
 */
struct AccessTestResults {
    size_t totalFolders = 0;
    size_t accessibleFolders = 0;
    size_t accessDeniedFolders = 0;
    size_t otherErrors = 0;
    std::vector<AccessDeniedEntry> deniedPaths;
};

/**
 * @brief Lightweight scanner for testing folder access permissions
 *
 * This scanner is designed for the --testaccess mode. It:
 * - Does NOT write to any database
 * - Does NOT collect ACL information
 * - Does NOT store folder metadata
 *
 * It DOES:
 * - Recursively enumerate folders using FindFirstFileEx
 * - Track access denied paths
 * - Output denied paths to console in real-time
 * - Provide summary statistics
 */
class AccessTestScanner {
public:
    /**
     * @brief Callback for real-time reporting of access denied paths
     */
    using AccessDeniedCallback = std::function<void(const AccessDeniedEntry&)>;

    /**
     * @brief Construct scanner for access testing
     * @param rootPath Root folder to test
     * @param threadCount Number of worker threads (default: 4)
     */
    AccessTestScanner(const std::wstring& rootPath, int threadCount = 4);

    /**
     * @brief Destructor - ensures threads are stopped
     */
    ~AccessTestScanner();

    /**
     * @brief Run the access test scan
     * @return AccessTestResults with all access denied paths and statistics
     */
    AccessTestResults run();

    /**
     * @brief Set callback for real-time access denied notifications
     * @param callback Function to call when access is denied
     */
    void setAccessDeniedCallback(AccessDeniedCallback callback);

    /**
     * @brief Check if scanner is currently running
     * @return true if scan is in progress
     */
    bool isRunning() const { return isRunning_.load(); }

    /**
     * @brief Request the scanner to stop
     */
    void requestStop() { shouldStop_.store(true); }

private:
    std::wstring rootPath_;
    int threadCount_;
    AccessDeniedCallback callback_;

    std::atomic<bool> shouldStop_{false};
    std::atomic<bool> isRunning_{false};
    std::mutex resultsMutex_;
    AccessTestResults results_;

    // Thread pool members
    std::vector<std::thread> workers_;
    std::queue<std::wstring> folderQueue_;
    std::mutex queueMutex_;
    std::condition_variable queueCv_;
    std::atomic<size_t> tasksInFlight_{0};

    // Progress tracking
    std::atomic<size_t> foldersScanned_{0};

    /**
     * @brief Worker thread function
     */
    void workerThread();

    /**
     * @brief Process a single folder for access testing
     * @param path Folder path to test
     */
    void processFolder(const std::wstring& path);

    /**
     * @brief Convert error code to human-readable message
     * @param errorCode Windows error code
     * @return Error message string
     */
    static std::string errorCodeToMessage(DWORD errorCode);

    /**
     * @brief Check if a path should be excluded (snapshots, recycle bin, etc.)
     * @param path Path to check
     * @return true if path should be skipped
     */
    static bool shouldExcludePath(const std::wstring& path);
};
