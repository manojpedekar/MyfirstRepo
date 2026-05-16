#ifndef FOLDERINDEX_H
#define FOLDERINDEX_H

#include <string>
#include <unordered_map>
#include <unordered_set>
#include <mutex>
#include <shared_mutex>  // For read-write lock during ACL processing
#include <atomic>

/**
 * @brief Manages a thread-safe mapping between folder paths and sequential integer IDs.
 *
 * Provides atomic assignment and retrieval of unique IDs for folder paths using an in-memory hash table.
 * Ensures thread safety for concurrent access and supports memory usage estimation.
 */
class FolderIndex {
public:
    FolderIndex() : nextId(1) {}
    
    // Add move constructor and assignment operator
    FolderIndex(FolderIndex&& other) noexcept;
    FolderIndex& operator=(FolderIndex&& other) noexcept;
    
    // Delete copy constructor and assignment operator
    FolderIndex(const FolderIndex&) = delete;
    FolderIndex& operator=(const FolderIndex&) = delete;

    /**
     * @brief Gets or assigns a LocalFolderID for a given path.
     *
     * Thread-safe method that returns existing ID or assigns a new one atomically.
     * FC-001 FIX: Uses int64_t to prevent overflow and ensure consistency with database schema.
     *
     * @param path The folder path to look up or insert.
     * @return int64_t The LocalFolderID for the path.
     */
    int64_t getOrAssignId(const std::wstring& path);

    /**
     * @brief Gets the LocalFolderID for a path if it exists.
     *
     * @param path The folder path to look up.
     * @return int64_t The LocalFolderID if found, or 0 if not found.
     */
    int64_t getId(const std::wstring& path) const;

    /**
     * @brief Gets the total number of folders indexed.
     * 
     * @return size_t The number of folders in the index.
     */
    size_t size() const;

    /**
     * @brief Estimates the memory usage of the hash table in bytes.
     *
     * @return size_t Estimated memory usage in bytes.
     */
    size_t estimateMemoryUsage() const;

    /**
     * @brief Gets the memory usage of the hash table in kilobytes.
     *
     * @return size_t Memory usage in KB.
     */
    size_t getMemoryUsageKB() const {
        return static_cast<size_t>(estimateMemoryUsage() / 1024.0);
    }

    /**
     * @brief Sets the starting ID for new folder assignments.
     *
     * Used in AllFixedDisks mode to ensure unique IDs across multiple volume scans.
     * Each volume's FolderIndex should start from where the previous one left off.
     *
     * @param startId The ID to start assigning from (typically getNextId() from previous scan).
     */
    void setNextId(int64_t startId) {
        nextId.store(startId);
    }

    /**
     * @brief Gets the next ID that would be assigned.
     *
     * Used to pass the ID counter to the next FolderIndex in multi-volume scanning.
     *
     * @return int64_t The next ID that would be assigned.
     */
    int64_t getNextId() const {
        return nextId.load();
    }

    /**
     * @brief Marks a folder as scanned (actually processed during folder enumeration).
     *
     * @param folderId The LocalFolderID to mark as scanned.
     */
    void markAsScanned(int64_t folderId);

    /**
     * @brief Checks if a folder was actually scanned vs. only indexed as an ancestor.
     *
     * @param folderId The LocalFolderID to check.
     * @return true if the folder was scanned, false if only indexed as ancestor.
     */
    bool isScanned(int64_t folderId) const;

    /**
     * @brief Iterates over all folders and calls the provided function for each one.
     *
     * @param callback Function to call for each folder, taking path and localFolderId as parameters.
     */
    template<typename Func>
    void forEach(Func callback) const {
        std::shared_lock<std::shared_mutex> lock(mutex);  // Shared lock for read operation
        for (const auto& pair : pathToId) {
            callback(pair.first, pair.second);
        }
    }

    /**
     * @brief Iterates over only scanned folders (excludes ancestors that were not directly processed).
     *
     * @param callback Function to call for each scanned folder, taking path and localFolderId as parameters.
     */
    template<typename Func>
    void forEachScanned(Func callback) const {
        std::shared_lock<std::shared_mutex> lock(mutex);  // Shared lock for read operation
        for (const auto& pair : pathToId) {
            if (scannedFolders.count(pair.second) > 0) {
                callback(pair.first, pair.second);
            }
        }
    }

    /**
     * @brief Returns a copy of the internal path-to-ID map (for backward compatibility).
     * @deprecated Use forEach() instead to avoid memory copying.
     */
    std::unordered_map<std::wstring, int64_t> getAll() const
    {
        std::shared_lock<std::shared_mutex> lock(mutex);  // Shared lock for read operation

        // Return copy of pathToId map (no conversion needed now)
        return pathToId;
    }

private:
    std::unordered_map<std::wstring, int64_t> pathToId;
    std::unordered_set<int64_t> scannedFolders;  // Track folders that were actually scanned
    mutable std::shared_mutex mutex;  // Read-write lock: allows concurrent reads during ACL processing
    std::atomic<int64_t> nextId;
};

#endif // FOLDERINDEX_H 
