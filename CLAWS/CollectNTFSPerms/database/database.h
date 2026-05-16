#pragma once
#include "../core/folderindex.h"
#include <string>
#include <string_view>  // CODE-001: Added for const correctness with string_view
#include <memory>
#include <mutex>
#include <atomic>
#include <functional>
#include <queue>
#include <thread>
#include <condition_variable>
#include <stdexcept>
#include <unordered_map>
#include <unordered_set>
#include "../../sqlite/sqlite3.h"
#include "../utils/utils.h"
#include <vector>
   

// External declarations (split to avoid MSVC 16KB string literal limit)
extern const char* CREATE_SCHEMA_TABLES_SQL_PART1;
extern const char* CREATE_SCHEMA_TABLES_SQL_PART2;
extern const char* CREATE_SCHEMA_VIEWS_SQL;
extern const char* CREATE_SCHEMA_INSERTS_SQL_PART1;
extern const char* CREATE_SCHEMA_INSERTS_SQL_PART2;
extern const char* DB_SCHEMA_VERSION;

// Forward declarations
struct sqlite3_stmt;

namespace FixedDiskEnumerator {
    struct MountPointTraversalContext;
}

namespace Logging {
    /**
     * @brief Severity levels for logging.
     */
    enum class Severity {
        DEBUG,
        INFO,
        WARNING,
        ERR
    };

    // Declaration of the conversion function
    const char* SeverityToString(Severity severity);
}

// RAII wrapper for SQLite database connection
class DatabaseConnection {
public:
    explicit DatabaseConnection(const std::string& dbPath);
    ~DatabaseConnection() {
        if (db) {
            sqlite3_close_v2(db);
        }
    }
    DatabaseConnection(const DatabaseConnection&) = delete;
    DatabaseConnection& operator=(const DatabaseConnection&) = delete;
    DatabaseConnection(DatabaseConnection&& other) noexcept : db(other.db) { other.db = nullptr; }
    DatabaseConnection& operator=(DatabaseConnection&& other) noexcept {
        if (this != &other) {
            if (db) sqlite3_close_v2(db);
            db = other.db;
            other.db = nullptr;
        }
        return *this;
    }
    sqlite3* get() const { return db; }
    operator sqlite3*() const { return db; }
private:
    sqlite3* db = nullptr;
};

class PreparedStatement {
public:
    PreparedStatement() = default;
    PreparedStatement(sqlite3* db, const std::string& sql) { prepare(db, sql); }
    ~PreparedStatement() { finalize(); }
    void prepare(sqlite3* db, const std::string& sql) {
        finalize();
        int rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);
        if (rc != SQLITE_OK) {
            throw std::runtime_error("Failed to prepare statement: " + std::string(sqlite3_errmsg(db)));
        }
    }
    void finalize() {
        if (stmt) {
            sqlite3_finalize(stmt);
            stmt = nullptr;
        }
    }
    sqlite3_stmt* get() const { return stmt; }
    operator sqlite3_stmt*() const { return stmt; }
private:
    sqlite3_stmt* stmt = nullptr;
};

class DatabaseError : public std::runtime_error {
public:
    explicit DatabaseError(const std::string& message, int errorCode = 0)
        : std::runtime_error(message), errorCode_(errorCode) {}
    int getErrorCode() const { return errorCode_; }
private:
    int errorCode_;
};

/**
 * @brief Allowlist of valid table/column pairs for GetNextId()
 *
 * This prevents SQL injection attacks by validating that only known
 * schema tables and their ID columns can be accessed.
 *
 * Security: SEC-003 mitigation
 */
namespace DatabaseSecurity {
    // Map of table names to their valid ID column names
    static const std::unordered_map<std::string, std::unordered_set<std::string>> VALID_ID_COLUMNS = {
        {"app__Folders", {"LocalFolderID"}},
        {"app__SIDs", {"SidID"}},
        {"app__ACL", {"ACL_ID"}},
        {"app__ACE", {"ACE_ID"}},
        {"app__Disks", {"DiskID"}},
        {"app__Volumes", {"VolumeID"}},
        {"app__VolumeMounts", {"MountID"}},
        {"app__VolumeExtents", {"ExtentID"}},
        {"app__Partitions", {"PartitionID"}},
        {"app__SMBShares", {"ShareID"}},
        {"app__SMBShareAccess", {"AccessID"}},
        {"app__EventLog", {"EventID"}},
        {"app__CollectionInfo", {"InventoryID"}},
    };
}

/**
 * @brief Context for database operations.
 */
struct DatabaseContext {
    std::string inventoryID;
    std::shared_ptr<DatabaseConnection> db;  // FIX NEW-002: shared_ptr for thread safety
    std::unique_ptr<PreparedStatement> insertFolderStmt;
    std::recursive_mutex dbMutex;  // FIX ARCH-003: Recursive mutex to allow nested PrepareStatement calls (e.g., GetNextId -> PrepareStatement)
    std::mutex transactionMutex;  // ARCH-001 FIX: Separate mutex for transaction state
    std::atomic<int> pendingInserts{0};  // Track number of pending inserts
    static constexpr int BATCH_SIZE = 25000;  // OPT-001: Increased from 10k to 25k for better performance
    static constexpr int MAX_RETRIES = 3;
    static constexpr int RETRY_DELAY_MS = 100;

    // Mount point traversal context for AllFixedDisks mode
    // When set, the FolderScanner will traverse into mount points that target fixed disk volumes
    const FixedDiskEnumerator::MountPointTraversalContext* mountPointContext = nullptr;

    // Enable traversal into ALL volume mount points (not junctions/symlinks)
    // When true, scanner will enter mount points regardless of target volume type
    // Default true: scanning E:\ will include E:\MountedVolume\ contents
    bool traverseMountPoints = true;

    // OPT-007: Prepared statement cache for performance
    std::unordered_map<std::string, std::shared_ptr<PreparedStatement>> stmtCache_;

    // Transaction management
    bool beginTransaction();
    bool commitTransaction();
    bool rollbackTransaction();
    bool isInTransaction() const { return inTransaction.load(); }
    void setInTransaction(bool value) { inTransaction.store(value); }

    // New error handling methods
    bool retryOperation(const std::function<bool()>& operation);
    void handleError(const std::string& operation, int errorCode);

    // OPT-007: Cached prepared statement retrieval
    std::shared_ptr<PreparedStatement> GetCachedStatement(const std::string& sql) {
        std::lock_guard<std::recursive_mutex> lock(dbMutex);
        auto it = stmtCache_.find(sql);
        if (it == stmtCache_.end()) {
            auto stmt = std::make_shared<PreparedStatement>(db->get(), sql);
            stmtCache_[sql] = stmt;
            return stmt;
        }
        // Reset statement for reuse
        sqlite3_reset(it->second->get());
        sqlite3_clear_bindings(it->second->get());
        return it->second;
    }

    // Legacy method for AclProcessor (creates new statement each time)
    PreparedStatement PrepareStatement(const std::string& sql) {
        std::lock_guard<std::recursive_mutex> lock(dbMutex);
        return PreparedStatement(db->get(), sql);
    }

    /**
     * @brief Get the next available ID for a table
     *
     * Security: Validates table and column names against allowlist to prevent SQL injection
     *
     * @param table Table name (must be in DatabaseSecurity::VALID_ID_COLUMNS)
     * @param idColumn ID column name (must be valid for the given table)
     * @return Next available ID (MAX(idColumn) + 1, or 1 if table is empty)
     * @throws DatabaseError if table or column is not in allowlist
     */
    int64_t GetNextId(const std::string& table, const std::string& idColumn) {
        std::lock_guard<std::recursive_mutex> lock(dbMutex);

        // SEC-003 FIX: Validate table name against allowlist
        auto tableIt = DatabaseSecurity::VALID_ID_COLUMNS.find(table);
        if (tableIt == DatabaseSecurity::VALID_ID_COLUMNS.end()) {
            throw DatabaseError(
                "Security: Invalid table name '" + table + "' rejected by allowlist. "
                "This may indicate an attempted SQL injection attack.",
                SQLITE_ERROR
            );
        }

        // SEC-003 FIX: Validate column name for this specific table
        if (tableIt->second.find(idColumn) == tableIt->second.end()) {
            throw DatabaseError(
                "Security: Invalid column '" + idColumn + "' for table '" + table + "' "
                "rejected by allowlist. This may indicate an attempted SQL injection attack.",
                SQLITE_ERROR
            );
        }

        // Now safe to construct query - both identifiers validated
        auto stmt = PrepareStatement("SELECT MAX(" + idColumn + ") FROM " + table);
        if (sqlite3_step(stmt.get()) == SQLITE_ROW) {
            return sqlite3_column_int64(stmt.get(), 0) + 1;
        }
        return 1;  // Start with 1 if table is empty
    }

    int64_t GetInventoryId() const {
        return std::stoll(inventoryID);
    }

private:
    std::atomic<bool> inTransaction{false};  // ARCH-001 FIX: Atomic for lock-free reads
};

// Core database functions
bool InitializeDatabase(DatabaseContext& ctx, const std::string& dbPath);
bool OpenExistingDatabase(DatabaseContext& ctx, const std::string& dbPath);
void CloseDatabase(DatabaseContext& ctx);
std::string GenerateGUID();

// Event logging
bool LogEvent(DatabaseContext& ctx, 
             Logging::Severity severity,
             const std::string& source,
             const std::string& message,
             const std::string& path = "",
             int errorCode = 0,
             int threadId = 0,
             const std::string& additionalData = "",
             const std::string& inventoryId = "");

// Collection info management
bool InsertCollectionInfo(DatabaseContext& ctx,
                        const std::string& inventoryId,
                        const std::string& computerName,
                        const std::string& domainName,
                        const std::chrono::system_clock::time_point& collectionTime,
                        const std::string& appVersion,
                        const std::string& appBuild,
                        bool isAdmin,
                        const std::string& who,
                        unsigned int hardwareConcurrency,
                        int threadCount,
                        const std::string& outputPath,
                        const std::string& scanPath,
                        bool isRemoteComputer,
                        bool explicitOnly);

bool UpdateCollectionInfo(
    DatabaseContext& dbCtx,
    const std::string& inventoryID,
    const std::chrono::system_clock::time_point& endTime,
    int64_t foldersProcessed,  // Change to int64_t
    int foldersWithErrors,
    int peakQueueSize,
    int peakMemoryUsageMB
);

// Folder management functions
bool InsertFolderBatch(DatabaseContext& ctx, const std::string& inventoryId, int64_t folderId, const std::wstring& path, int64_t parentFolderId = 0, int volumeId = 0, const FILETIME* creationTime = nullptr, const FILETIME* lastWriteTime = nullptr, const FILETIME* lastAccessTime = nullptr, DWORD attributes = 0);

bool EnsureAncestorsInserted(DatabaseContext& ctx,
                            const std::string& inventoryId,
                            FolderIndex& folderIndex,
                            const std::wstring& path);

// Helper functions for folder hierarchy and volume tracking
// CODE-001: Use string_view to avoid unnecessary allocations
std::wstring GetParentPath(std::wstring_view path);
int64_t GetParentFolderId(const FolderIndex& folderIndex, std::wstring_view path);
int GetVolumeIdFromPath(DatabaseContext& ctx, std::wstring_view path);
std::wstring ExtractDriveLetterOrRoot(std::wstring_view path);

// Helper function to convert Windows FILETIME to ISO 8601 string
std::string FileTimeToIso8601(const FILETIME& ft);
