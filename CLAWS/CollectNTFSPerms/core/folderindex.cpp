#include "../core/folderindex.h"
#include "../utils/utils.h"
#include <iostream>
#include <sstream>

FolderIndex::FolderIndex(FolderIndex&& other) noexcept
{
    // Lock the source to prevent data races during move
    std::unique_lock<std::shared_mutex> otherLock(other.mutex);
    pathToId = std::move(other.pathToId);
    nextId.store(other.nextId.load());
}

FolderIndex& FolderIndex::operator=(FolderIndex&& other) noexcept {
    if (this != &other) {
        // Acquire both mutexes for exclusive access during move
        std::unique_lock<std::shared_mutex> lock1(mutex, std::defer_lock);
        std::unique_lock<std::shared_mutex> lock2(other.mutex, std::defer_lock);
        std::lock(lock1, lock2);  // Deadlock-free locking
        pathToId = std::move(other.pathToId);
        nextId.store(other.nextId.load());
    }
    return *this;
}

int64_t FolderIndex::getOrAssignId(const std::wstring& path) {
    std::unique_lock<std::shared_mutex> lock(mutex);  // Exclusive lock for write operation

    // FC-001 FIX: Lock guard protects entire operation to prevent race conditions
    // First check if this exact path already exists
    auto it = pathToId.find(path);
    if (it != pathToId.end()) {
        return it->second;
    }
    
    // Add all ancestor paths first
    std::wstring currentPath = path;
    std::vector<std::wstring> ancestors;
    
    // Build list of ancestors (from deepest to root)
    while (true) {
        size_t pos = currentPath.find_last_of(L"\\/");
        if (pos == std::wstring::npos || pos == 0) {
            // We've reached the root or beginning
            break;
        }

        // Get parent path
        currentPath = currentPath.substr(0, pos);

        // Check if we've reached a root path
        bool isRoot = false;

        // Check for local drive root (e.g., "C:")
        if (currentPath.length() == 2 &&
            iswalpha(currentPath[0]) &&
            currentPath[1] == L':') {
            // Add drive root with backslash (e.g., "C:\")
            ancestors.push_back(currentPath + L"\\");
            isRoot = true;
        }
        // Check for UNC share root (e.g., "\\server\share")
        else if (currentPath.length() >= 3 &&
                 currentPath[0] == L'\\' &&
                 currentPath[1] == L'\\') {
            // Find server name end
            size_t serverEnd = currentPath.find_first_of(L"\\/", 2);
            if (serverEnd != std::wstring::npos) {
                // Find share name end
                size_t shareEnd = currentPath.find_first_of(L"\\/", serverEnd + 1);
                // If no more slashes, this is the share root
                if (shareEnd == std::wstring::npos) {
                    // This is "\\server\share", add with trailing backslash
                    ancestors.push_back(currentPath + L"\\");
                    isRoot = true;
                } else {
                    // Still has subfolders, continue
                    ancestors.push_back(currentPath);
                }
            } else {
                // Just "\\server", incomplete UNC path
                break;
            }
        } else {
            // Regular path component
            ancestors.push_back(currentPath);
        }

        // Stop if we've reached a root
        if (isRoot) {
            break;
        }
    }

    // Add ancestors from root to leaf (if they don't exist)
    // FC-001 FIX: Use fetch_add(1) for explicit atomic increment
    for (auto it = ancestors.rbegin(); it != ancestors.rend(); ++it) {
        if (pathToId.find(*it) == pathToId.end()) {
            pathToId[*it] = nextId.fetch_add(1);
        }
    }

    // FIX: Check if the original path was already added as an ancestor
    // This happens when the input is a drive root like "C:\" - the ancestor
    // detection adds "C:\" to the list, so we shouldn't assign a new ID
    auto existingIt = pathToId.find(path);
    if (existingIt != pathToId.end()) {
        return existingIt->second;  // Already added as ancestor
    }

    // Add the original path (only if not already in map)
    int64_t id = nextId.fetch_add(1);
    pathToId[path] = id;
    return id;
}

int64_t FolderIndex::getId(const std::wstring& path) const {
    static std::atomic<int> getIdCallCount{0};
    int callNum = ++getIdCallCount;

    // Debug logging for ACL processing phase (calls after folder scanning)
    // Unconditional logging for ALL calls > 500 to capture entire ACL phase
    if (AppGlobals::DebugMode.load() && callNum > 500) {
        size_t pathLen = path.length();
        std::wstringstream msg;
        msg << L"[DEBUG-ACL] FolderIndex::getId #" << callNum << L": >>> BEFORE mutex acquisition <<< for path: "
            << path.substr(0, (pathLen < 100) ? pathLen : 100) << L"...\n";
        AppGlobals::WriteDebug(msg.str());
    }

    std::shared_lock<std::shared_mutex> lock(mutex);  // Shared lock allows concurrent reads

    // Debug logging after mutex acquisition
    if (AppGlobals::DebugMode.load() && callNum > 500) {
        std::wstringstream msg;
        msg << L"[DEBUG-ACL] FolderIndex::getId #" << callNum << L": >>> SHARED LOCK ACQUIRED, calling find() <<< \n";
        AppGlobals::WriteDebug(msg.str());
    }

    auto it = pathToId.find(path);

    // Debug logging after find() returns
    if (AppGlobals::DebugMode.load() && callNum > 500) {
        std::wstringstream msg;
        msg << L"[DEBUG-ACL] FolderIndex::getId #" << callNum << L": >>> find() RETURNED <<< result="
            << (it != pathToId.end() ? L"found" : L"not found") << L"\n";
        AppGlobals::WriteDebug(msg.str());
    }

    return (it != pathToId.end()) ? it->second : 0;
}

/**
 * @brief Marks a folder as scanned (actually processed during folder enumeration).
 *
 * @param folderId The LocalFolderID to mark as scanned.
 */
void FolderIndex::markAsScanned(int64_t folderId) {
    std::unique_lock<std::shared_mutex> lock(mutex);  // Exclusive lock for write operation
    scannedFolders.insert(folderId);
}

/**
 * @brief Checks if a folder was actually scanned vs. only indexed as an ancestor.
 *
 * @param folderId The LocalFolderID to check.
 * @return true if the folder was scanned, false if only indexed as ancestor.
 */
bool FolderIndex::isScanned(int64_t folderId) const {
    std::shared_lock<std::shared_mutex> lock(mutex);  // Shared lock for read operation
    return scannedFolders.count(folderId) > 0;
}

/**
 * @brief Returns the number of folder paths currently indexed.
 *
 * @return The count of unique folder paths stored in the index.
 */
size_t FolderIndex::size() const {
    std::shared_lock<std::shared_mutex> lock(mutex);  // Shared lock for read operation
    return pathToId.size();
}

/**
  * @brief Estimates the total memory usage of the FolderIndex instance in bytes.
  *
  * Calculates an approximate memory footprint by summing the size of the FolderIndex object, per-node overhead for each entry in the internal map, the memory used by the string buffers of all stored paths, and the estimated memory used by the map's bucket array.
  *
  * @return Estimated memory usage in bytes.
  */
 size_t FolderIndex::estimateMemoryUsage() const {
     std::shared_lock<std::shared_mutex> lock(mutex);  // Shared lock for read operation
     size_t total = sizeof(*this);
    
    // More conservative node overhead estimate (typically 48-64 bytes per node)
    total += pathToId.size() * (sizeof(std::wstring) + sizeof(int64_t) + 32); // conservative node overhead
    
     for (const auto& pair : pathToId) {
         total += pair.first.capacity() * sizeof(wchar_t); // string buffer
     }
    
    // Conservative bucket array estimate
    total += pathToId.bucket_count() * 8; // assume 8 bytes per bucket (64-bit pointers)
    
     return total;
 }
