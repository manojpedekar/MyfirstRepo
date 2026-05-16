#pragma once

#include <string>
#include <vector>
#include <queue>
#include <mutex>
#include <thread>
#include <atomic>
#include <condition_variable>
#include <unordered_map>
#include <windows.h>
#include "../database/database.h"
#include "../core/ACLInfo.h"
#include "../core/folderindex.h"

/**
 * @brief Thread-safe ACL (Access Control List) processor for Windows NTFS permissions.
 *
 * DOC-001: This class manages multi-threaded collection and processing of Windows
 * ACLs and ACEs (Access Control Entries). It extracts security descriptors from
 * folders, resolves SIDs to account names, and stores permission data in the database.
 *
 * @thread_safety All public methods are thread-safe. Internal queues and database
 * operations are protected by mutexes.
 */
class AclProcessor {
public:
    /**
     * @brief Constructs an ACL processor with the specified number of worker threads.
     *
     * DOC-001: Initializes the thread pool and prepares for ACL collection.
     * Worker threads start immediately and wait for folders to be queued.
     *
     * @param dbCtx Reference to database context for storing ACL data
     * @param folderIndex Reference to folder index for path-to-ID mapping
     * @param numThreads Number of worker threads (default: 4)
     *
     * @note The processor maintains references to dbCtx and folderIndex, so they
     * must remain valid for the lifetime of this object.
     */
    AclProcessor(DatabaseContext& dbCtx, const FolderIndex& folderIndex, int numThreads = 4);

    /**
     * @brief Destructor that ensures all worker threads complete before destruction.
     *
     * DOC-001: Signals worker threads to stop and waits for them to finish.
     * Any pending ACLs in the queue will be processed before shutdown.
     */
    ~AclProcessor();

    // Delete copy constructor and assignment operator
    AclProcessor(const AclProcessor&) = delete;
    AclProcessor& operator=(const AclProcessor&) = delete;

    // Delete move constructor and assignment operator
    AclProcessor(AclProcessor&&) = delete;
    AclProcessor& operator=(AclProcessor&&) = delete;

    /**
     * @brief Queues a folder for ACL processing.
     *
     * DOC-001: Adds the folder path and its ID to the processing queue.
     * Worker threads will pick up the folder asynchronously and extract its
     * security descriptor, parse ACEs, resolve SIDs, and store results in the database.
     *
     * @param path Full path to the folder (can be long path format)
     * @param folderId LocalFolderID from FolderIndex
     *
     * @thread_safety Thread-safe. Can be called concurrently from multiple threads.
     */
    void AddFolder(const std::wstring& path, int64_t folderId);

    /**
     * @brief Initializes SID lookup cache from existing database records.
     *
     * DOC-001: Loads previously resolved SIDs from app__SIDs table into memory
     * to avoid redundant lookups and resolution. Call this after database is opened
     * and before processing folders.
     *
     * @thread_safety Should be called once before AddFolder() calls begin.
     */
    void InitializeSidLookup();

    /**
     * @brief Blocks until all queued folders have been processed.
     *
     * DOC-001: Waits for the processing queue to drain and all worker threads
     * to become idle. Use this to ensure all ACL collection completes before
     * moving to the next phase of data collection.
     *
     * @thread_safety Thread-safe. Can be called from any thread.
     */
    void WaitForCompletion();

    /**
     * @brief Sets the total number of folders for progress calculation.
     *
     * DOC-001: Used to calculate percentage complete in progress displays.
     * Typically called after folder scanning completes.
     *
     * @param count Total number of folders to be processed
     *
     * @thread_safety Thread-safe (uses atomic operation).
     */
    void SetTotalFolders(int64_t count) { stats_.totalFolders = count; }

    /**
     * @brief Statistics structure with atomic counters for thread-safe updates.
     *
     * DOC-001: All counters are atomic to allow safe concurrent increments
     * from multiple worker threads without locks.
     */
    struct Stats {
        std::atomic<int64_t> processedFolders{0};        ///< Successfully processed folders
        std::atomic<int64_t> failedFolders{0};           ///< Folders that failed ACL extraction
        std::atomic<int64_t> newSids{0};                 ///< Newly discovered SIDs
        std::atomic<int64_t> totalAcls{0};               ///< Total ACLs (DACLs) processed
        std::atomic<int64_t> totalAces{0};               ///< Total ACEs (access control entries)
        std::atomic<int64_t> totalFolders{0};            ///< Total folders to process (for percentage)
        std::atomic<int64_t> skippedEmptySids{0};        ///< Empty/NULL SIDs skipped
        std::atomic<int64_t> invalidSids{0};             ///< Invalid SID structures
        std::atomic<int64_t> sidConversionFailures{0};   ///< SID-to-string conversion failures
        std::atomic<int64_t> skippedUnsupportedAceTypes{0}; ///< Unsupported ACE types skipped
    };

    /**
     * @brief Non-atomic snapshot of statistics for safe copying.
     *
     * DOC-001: Use this structure when you need to copy stats values
     * (e.g., for serialization or display) to avoid issues with atomic types.
     */
    struct StatsSnapshot {
        int64_t processedFolders{0};        ///< Successfully processed folders
        int64_t failedFolders{0};           ///< Folders that failed ACL extraction
        int64_t newSids{0};                 ///< Newly discovered SIDs
        int64_t totalAcls{0};               ///< Total ACLs (DACLs) processed
        int64_t totalAces{0};               ///< Total ACEs (access control entries)
        int64_t totalFolders{0};            ///< Total folders to process (for percentage)
        int64_t skippedEmptySids{0};        ///< Empty/NULL SIDs skipped
        int64_t invalidSids{0};             ///< Invalid SID structures
        int64_t sidConversionFailures{0};   ///< SID-to-string conversion failures
        int64_t skippedUnsupportedAceTypes{0}; ///< Unsupported ACE types skipped
    };

    /**
     * @brief Gets a const reference to the atomic statistics.
     *
     * DOC-001: Use this for real-time monitoring of progress.
     * Atomic counters can be read directly without locks.
     *
     * @return Const reference to internal Stats structure
     *
     * @note Do NOT attempt to copy the Stats structure - use GetStatsSnapshot() instead.
     */
    const Stats& GetStats() const { return stats_; }

    /**
     * @brief Gets a non-atomic snapshot of current statistics.
     *
     * DOC-001: Creates a point-in-time copy of all statistics.
     * Use this when you need to serialize or store stats values.
     *
     * @return StatsSnapshot containing current values of all counters
     *
     * @thread_safety Thread-safe. Reads atomic counters without locks.
     */
    StatsSnapshot GetStatsSnapshot() const;

    /**
     * @brief Sets the starting ACL ID for new ACL assignments.
     *
     * Used in AllFixedDisks mode to ensure unique ACL IDs across multiple volume scans.
     * Each volume's AclProcessor should start from where the previous one left off.
     *
     * @param startId The ID to start assigning from (typically getNextAclId() from previous scan).
     */
    void setNextAclId(int64_t startId) {
        nextAclId_.store(startId);
    }

    /**
     * @brief Gets the next ACL ID that would be assigned.
     *
     * Used to pass the ID counter to the next AclProcessor in multi-volume scanning.
     *
     * @return int64_t The next ACL ID that would be assigned.
     */
    int64_t getNextAclId() const {
        return nextAclId_.load();
    }

    /**
     * @brief Sets the starting ACE ID for new ACE assignments.
     *
     * Used in AllFixedDisks mode to ensure unique ACE IDs across multiple volume scans.
     * Each volume's AclProcessor should start from where the previous one left off.
     *
     * @param startId The ID to start assigning from (typically getNextAceId() from previous scan).
     */
    void setNextAceId(int64_t startId) {
        nextAceId_.store(startId);
    }

    /**
     * @brief Gets the next ACE ID that would be assigned.
     *
     * Used to pass the ID counter to the next AclProcessor in multi-volume scanning.
     *
     * @return int64_t The next ACE ID that would be assigned.
     */
    int64_t getNextAceId() const {
        return nextAceId_.load();
    }

private:
    // Worker thread function
    void WorkerThread();

    // Process a single ACL and its ACEs
    void ProcessAcl(const std::wstring& path, int64_t localFolderId, const AclInfo& acl);

    // Get ACL information for a folder
    AclInfo GetAclInfo(const std::wstring& path);

    // Get or create SID ID
    int64_t GetOrCreateSidId(const std::wstring& sidString, const std::wstring& accountName);

    // Log an error event
    void LogError(const std::wstring& path, const std::string& description, int errorCode);

    // Update progress display
    void UpdateProgress();

    // Commit batch to the database
    void CommitBatch();

    // Database context
    DatabaseContext& dbCtx_;

    // Thread management
    std::vector<std::thread> workers_;
    std::queue<std::pair<std::wstring, int64_t>> folderQueue_;
    std::mutex queueMutex_;
    std::condition_variable queueCv_;           // Notifies workers when queue has items
    std::condition_variable queueNotFullCv_;    // MEM-001: Notifies producers when queue has space
    std::atomic<bool> shouldStop_{false};

    // Track active workers so producers can detect stalls
    std::atomic<int> activeWorkers_{0};

    // Batch processing
    struct BatchData {
        using SidTuple = std::tuple<int64_t, std::string, std::wstring, std::wstring, std::wstring>;
        using AclTuple = std::tuple<std::string, int64_t, int64_t, int64_t, int64_t, bool, bool, bool, bool>;
        using AceTuple = std::tuple<std::string, int64_t, int64_t, DWORD, int, int64_t, bool, BYTE, BYTE, int64_t>;
        
        std::vector<SidTuple> sids;
        std::vector<AclTuple> acls;
        std::vector<AceTuple> aces;
    };
    
    BatchData currentBatch_;
    std::mutex batchMutex_;
    
    // SID cache
    std::unordered_map<std::wstring, int64_t> sidCache_;
    std::mutex sidCacheMutex_;
    std::atomic<int64_t> nextSidId_{1};

    // Folder index reference (no longer a copy)
    const FolderIndex& folderIndex_;
    
    // ID generators
    std::atomic<int64_t> nextAclId_{1};
    std::atomic<int64_t> nextAceId_{1};

    // ARCH-003: Periodic commit tracking
    std::atomic<int64_t> totalFoldersProcessed_{0};
    std::atomic<int64_t> lastPeriodicCommitCount_{0};

    // Progress tracking
    std::mutex progressMutex_;
    std::chrono::steady_clock::time_point lastUpdateTime_;
    // FIX NEW-005: Convert thread_local to instance variables for proper stall detection
    int lastProcessedCount_{0};
    int stallCounter_{0};

    // Statistics
    Stats stats_;
    
    // Constants
    static constexpr size_t BATCH_SIZE = 5000; // ARCH-003: Reduced from 25k to 5k for folders with minimal ACLs
    static constexpr size_t PERIODIC_COMMIT_INTERVAL = 50000; // ARCH-003: Force commit every 50k folders
    static constexpr int PROGRESS_UPDATE_MS = 1000;
    static constexpr size_t MAX_QUEUE_SIZE = 100000; // MEM-001: Prevent unbounded memory growth

    // Helper method to determine account type based on account name
    std::wstring DetermineAccountType(const std::wstring& accountName);
    
    // Helper method to resolve SIDs to account names
    std::wstring ResolveSid(const std::wstring& sidString);

    // SID collection for bulk processing
    struct SidInfo {
        std::wstring sidString;
        std::wstring accountName;
        std::wstring accountType;
        int64_t sidId = 0;
        bool isResolved = false;
        std::wstring resolutionSource;  // 'Local', 'Domain', 'WellKnown', 'Failed'
    };
    std::unordered_map<std::wstring, SidInfo> collectedSids_;
    std::mutex collectedSidsMutex_;
    
    // Bulk resolve and insert SIDs
    void ResolveSidsAndBulkInsert();

    // SID resolution cache
    std::unordered_map<std::wstring, std::wstring> resolvedSidCache_;
    std::mutex resolvedSidCacheMutex_;
    
    // Well-known SIDs map
    std::unordered_map<std::wstring, std::wstring> wellKnownSids;
    
    // Helper methods for SID processing
    std::wstring ManualSidToString(PSID sid);
    std::wstring ResolveSidToAccountName(PSID sid, const std::wstring& sidString);
};

// Global flag for explicit-only mode
extern bool g_explicitOnly;
