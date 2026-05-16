#include "access_test_scanner.h"
#include "../utils/folderutils.h"
#include "../utils/SnapshotExclusions.h"
#include <iostream>
#include <algorithm>

AccessTestScanner::AccessTestScanner(const std::wstring& rootPath, int threadCount)
    : rootPath_(rootPath)
    , threadCount_(threadCount > 0 ? threadCount : 4)
{
}

AccessTestScanner::~AccessTestScanner() {
    shouldStop_.store(true);

    // Wake up any waiting workers
    queueCv_.notify_all();

    // Join all worker threads
    for (auto& worker : workers_) {
        if (worker.joinable()) {
            worker.join();
        }
    }
}

void AccessTestScanner::setAccessDeniedCallback(AccessDeniedCallback callback) {
    callback_ = std::move(callback);
}

AccessTestResults AccessTestScanner::run() {
    isRunning_.store(true);
    shouldStop_.store(false);
    results_ = AccessTestResults{};
    foldersScanned_.store(0);

    std::cout << "Starting access test scan with " << threadCount_ << " threads..." << std::endl;

    // Start worker threads
    workers_.clear();
    for (int i = 0; i < threadCount_; i++) {
        workers_.emplace_back(&AccessTestScanner::workerThread, this);
    }

    // Enqueue root path
    {
        std::lock_guard<std::mutex> lock(queueMutex_);
        folderQueue_.push(rootPath_);
        tasksInFlight_.fetch_add(1);
    }
    queueCv_.notify_one();

    // Wait for completion
    // Poll until queue is empty and no tasks in flight
    while (true) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));

        size_t queueSize;
        {
            std::lock_guard<std::mutex> lock(queueMutex_);
            queueSize = folderQueue_.size();
        }

        size_t inFlight = tasksInFlight_.load();

        // Display progress
        size_t scanned = foldersScanned_.load();
        std::cout << "\r  Folders scanned: " << scanned
                  << " | Queue: " << queueSize
                  << " | In-flight: " << inFlight
                  << " | Access denied: " << results_.accessDeniedFolders
                  << "     " << std::flush;

        if (queueSize == 0 && inFlight == 0) {
            break;
        }

        if (shouldStop_.load()) {
            break;
        }
    }

    std::cout << std::endl;

    // Signal workers to stop
    shouldStop_.store(true);
    queueCv_.notify_all();

    // Wait for workers to finish
    for (auto& worker : workers_) {
        if (worker.joinable()) {
            worker.join();
        }
    }
    workers_.clear();

    isRunning_.store(false);
    return results_;
}

void AccessTestScanner::workerThread() {
    while (!shouldStop_.load()) {
        std::wstring path;

        // Get next folder from queue
        {
            std::unique_lock<std::mutex> lock(queueMutex_);

            queueCv_.wait_for(lock, std::chrono::milliseconds(100), [this] {
                return !folderQueue_.empty() || shouldStop_.load();
            });

            if (shouldStop_.load() && folderQueue_.empty()) {
                return;
            }

            if (folderQueue_.empty()) {
                continue;
            }

            path = folderQueue_.front();
            folderQueue_.pop();
        }

        // Process the folder
        processFolder(path);

        // Decrement tasks in flight
        tasksInFlight_.fetch_sub(1);
    }
}

void AccessTestScanner::processFolder(const std::wstring& path) {
    foldersScanned_.fetch_add(1);

    {
        std::lock_guard<std::mutex> lock(resultsMutex_);
        results_.totalFolders++;
    }

    // Build search path
    std::wstring searchPath = path;
    if (!searchPath.empty() && searchPath.back() != L'\\') {
        searchPath += L'\\';
    }
    searchPath += L'*';

    // Use long path prefix for deep paths
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

        if (error == ERROR_ACCESS_DENIED) {
            AccessDeniedEntry entry;
            entry.path = path;
            entry.errorCode = error;
            entry.errorMessage = "Access denied";

            {
                std::lock_guard<std::mutex> lock(resultsMutex_);
                results_.accessDeniedFolders++;
                results_.deniedPaths.push_back(entry);
            }

            // Real-time callback
            if (callback_) {
                callback_(entry);
            }
        } else if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) {
            std::lock_guard<std::mutex> lock(resultsMutex_);
            results_.otherErrors++;
        }
        return;
    }

    {
        std::lock_guard<std::mutex> lock(resultsMutex_);
        results_.accessibleFolders++;
    }

    // Enumerate subdirectories
    do {
        if ((findData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) &&
            wcscmp(findData.cFileName, L".") != 0 &&
            wcscmp(findData.cFileName, L"..") != 0) {

            std::wstring childPath = path;
            if (!childPath.empty() && childPath.back() != L'\\') {
                childPath += L'\\';
            }
            childPath += findData.cFileName;

            // Check if this path should be excluded
            if (shouldExcludePath(childPath)) {
                continue;
            }

            // Skip reparse points (mount points, symlinks) to avoid infinite loops
            // and duplicate scanning
            if (findData.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
                continue;
            }

            // Enqueue for processing
            {
                std::lock_guard<std::mutex> lock(queueMutex_);
                folderQueue_.push(childPath);
                tasksInFlight_.fetch_add(1);
            }
            queueCv_.notify_one();
        }
    } while (FindNextFileW(hFind, &findData) && !shouldStop_.load());

    FindClose(hFind);
}

std::string AccessTestScanner::errorCodeToMessage(DWORD errorCode) {
    switch (errorCode) {
        case ERROR_ACCESS_DENIED: return "Access denied";
        case ERROR_PATH_NOT_FOUND: return "Path not found";
        case ERROR_FILE_NOT_FOUND: return "File not found";
        case ERROR_BAD_NETPATH: return "Network path not found";
        case ERROR_BAD_NET_NAME: return "Invalid network share name";
        case ERROR_NETWORK_UNREACHABLE: return "Network unreachable";
        case ERROR_INVALID_NAME: return "Invalid path name";
        case ERROR_LOGON_FAILURE: return "Logon failure";
        default: return "Error code " + std::to_string(errorCode);
    }
}

bool AccessTestScanner::shouldExcludePath(const std::wstring& path) {
    // Use the existing snapshot exclusion logic
    return IsExcludedSnapshotPath(path);
}
