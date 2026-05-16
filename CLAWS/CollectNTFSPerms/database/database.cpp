#include "../database/database.h"
#include "../utils/folderutils.h"
#include "../utils/utils.h"
#include "../core/folderindex.h"
#include <fstream>
#include <sstream>
#include <iostream>
#include <memory>
#include <SetupAPI.h>


// Link with SQLite library
#pragma comment(lib, "../sqlite/sqlite3.lib")

/**
 * @brief Initializes the SQLite database and creates the required application schema.
 *
 * Opens or creates the SQLite database at the specified path, sets recommended PRAGMA options, and atomically creates all tables, indexes, and default data within a transaction. Inserts the schema version and prepares a reusable statement for folder inserts. Returns false if any step fails.
 *
 * @param dbPath Absolute or relative path to the SQLite database file.
 * @return true if initialization and schema creation succeed; false otherwise.
 */
bool InitializeDatabase(DatabaseContext& ctx, const std::string& dbPath) {
    try {
        ctx.db = std::make_shared<DatabaseConnection>(dbPath);  // FIX NEW-002: shared_ptr for thread safety
    } catch (const std::exception& e) {
        std::cerr << "Failed to open database: " << e.what() << std::endl;
        return false;
    }

    // OPT-001: Optimized PRAGMA settings for maximum performance
    // These settings balance safety, concurrency, and speed for bulk data collection
    char* errMsg = nullptr;
    int rc = sqlite3_exec(ctx.db->get(),
        "PRAGMA journal_mode = WAL;"        // Write-Ahead Logging for better concurrency
        "PRAGMA synchronous = NORMAL;"      // Balance safety/speed (full durability not critical during collection)
        "PRAGMA cache_size = -64000;"       // 64MB cache (negative = KB, positive = pages)
        "PRAGMA temp_store = MEMORY;"       // Store temp tables/indexes in RAM
        "PRAGMA mmap_size = 2147483648;"    // 2GB memory-mapped I/O for fast reads
        "PRAGMA page_size = 4096;"          // Larger page size for better I/O efficiency
        "PRAGMA busy_timeout = 5000;"       // Wait up to 5 seconds on locks before failing
        "PRAGMA locking_mode = NORMAL;"     // Release locks after transactions (allow concurrent readers)
        "PRAGMA wal_autocheckpoint = 10000;", // Checkpoint every 10000 pages to manage WAL file size
        nullptr, nullptr, &errMsg);
    if (rc != SQLITE_OK) {
        std::cerr << "Failed to set optimized PRAGMAs: " << errMsg << std::endl;
        sqlite3_free(errMsg);
        return false;
    }

    // Begin transaction for atomic schema creation
    rc = sqlite3_exec(ctx.db->get(), "BEGIN TRANSACTION;", nullptr, nullptr, &errMsg);
    if (rc != SQLITE_OK) {
        std::cerr << "Failed to begin schema transaction: " << errMsg << std::endl;
        sqlite3_free(errMsg);
        return false;
    }

     // Create tables and indexes (split into two parts to avoid MSVC 16KB string limit)
     rc = sqlite3_exec(ctx.db->get(), CREATE_SCHEMA_TABLES_SQL_PART1, nullptr, nullptr, &errMsg);
     if (rc != SQLITE_OK) {
         std::cerr << "Failed to create tables (part 1): " << errMsg << std::endl;
         sqlite3_free(errMsg);
         sqlite3_exec(ctx.db->get(), "ROLLBACK;", nullptr, nullptr, nullptr);
         return false;
     }

     rc = sqlite3_exec(ctx.db->get(), CREATE_SCHEMA_TABLES_SQL_PART2, nullptr, nullptr, &errMsg);
     if (rc != SQLITE_OK) {
         std::cerr << "Failed to create tables (part 2): " << errMsg << std::endl;
         sqlite3_free(errMsg);
         sqlite3_exec(ctx.db->get(), "ROLLBACK;", nullptr, nullptr, nullptr);
         return false;
     }

     // Create views
     rc = sqlite3_exec(ctx.db->get(), CREATE_SCHEMA_VIEWS_SQL, nullptr, nullptr, &errMsg);
     if (rc != SQLITE_OK) {
         std::cerr << "Failed to create views: " << errMsg << std::endl;
         sqlite3_free(errMsg);
         sqlite3_exec(ctx.db->get(), "ROLLBACK;", nullptr, nullptr, nullptr);
         return false;
     }

     // Insert default/lookup data (split into two parts to avoid MSVC 16KB string limit)
     rc = sqlite3_exec(ctx.db->get(), CREATE_SCHEMA_INSERTS_SQL_PART1, nullptr, nullptr, &errMsg);
     if (rc != SQLITE_OK) {
         std::cerr << "Failed to insert default data (part 1): " << errMsg << std::endl;
         sqlite3_free(errMsg);
         sqlite3_exec(ctx.db->get(), "ROLLBACK;", nullptr, nullptr, nullptr);
         return false;
     }

     rc = sqlite3_exec(ctx.db->get(), CREATE_SCHEMA_INSERTS_SQL_PART2, nullptr, nullptr, &errMsg);
     if (rc != SQLITE_OK) {
         std::cerr << "Failed to insert default data (part 2): " << errMsg << std::endl;
         sqlite3_free(errMsg);
         sqlite3_exec(ctx.db->get(), "ROLLBACK;", nullptr, nullptr, nullptr);
         return false;
     }

    // Commit the schema transaction
    rc = sqlite3_exec(ctx.db->get(), "COMMIT;", nullptr, nullptr, &errMsg);
    if (rc != SQLITE_OK) {
        std::cerr << "Failed to commit schema transaction: " << errMsg << std::endl;
        sqlite3_free(errMsg);
        return false;
    }

    // Insert version into app__Version table
    const char* insertVersionSql = "INSERT INTO app__Version (PropertyName, PropertyValue) VALUES ('DBVersion', ?);";
    PreparedStatement versionStmt(ctx.db->get(), insertVersionSql);
    sqlite3_bind_text(versionStmt.get(), 1, DB_SCHEMA_VERSION, -1, SQLITE_STATIC);
    rc = sqlite3_step(versionStmt.get());
    if (rc != SQLITE_DONE) {
        std::cerr << "Failed to insert version: " << sqlite3_errmsg(ctx.db->get()) << std::endl;
        return false;
    }

    // Prepare reusable insert statement (OPT-002: Use INSERT OR IGNORE to avoid redundant duplicate checks)
    const char* insertSql = "INSERT OR IGNORE INTO app__Folders (InventoryID, LocalFolderID, ParentFolderID, Path, VolumeID, CreationTime, LastWriteTime, LastAccessTime, Attributes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);";
    ctx.insertFolderStmt = std::make_unique<PreparedStatement>(ctx.db->get(), insertSql);

    return true;
}

void CloseDatabase(DatabaseContext& ctx) {
    ctx.insertFolderStmt.reset();
    ctx.db.reset();
}

bool DatabaseContext::beginTransaction() {
    std::lock_guard<std::mutex> lock(transactionMutex);  // ARCH-001 FIX: Use separate mutex
    if (inTransaction.load()) return true;

    char* errMsg = nullptr;
    int rc = sqlite3_exec(this->db->get(), "BEGIN TRANSACTION;", nullptr, nullptr, &errMsg);
    if (rc != SQLITE_OK) {
        std::cerr << "Failed to begin transaction: " << errMsg << std::endl;
        sqlite3_free(errMsg);
        return false;
    }

    inTransaction.store(true);
    return true;
}

bool DatabaseContext::commitTransaction() {
    std::lock_guard<std::mutex> lock(transactionMutex);  // ARCH-001 FIX: Use separate mutex
    if (!inTransaction.load()) return true;

    char* errMsg = nullptr;
    int rc = sqlite3_exec(this->db->get(), "COMMIT;", nullptr, nullptr, &errMsg);
    if (rc != SQLITE_OK) {
        std::cerr << "Failed to commit transaction: " << errMsg << std::endl;
        if (errMsg) {
            std::cerr << "SQLite error: " << errMsg << std::endl;
            sqlite3_free(errMsg);
        }

        // ARCH-003 FIX: If commit fails, rollback and clear state
        // SQLite may have auto-rolled back, but we ensure it's clean
        char* rollbackErr = nullptr;
        sqlite3_exec(this->db->get(), "ROLLBACK;", nullptr, nullptr, &rollbackErr);
        if (rollbackErr) {
            sqlite3_free(rollbackErr);
        }

        inTransaction.store(false);  // Clear flag even on failure
        return false;
    }

    inTransaction.store(false);
    return true;
}

bool DatabaseContext::rollbackTransaction() {
    std::lock_guard<std::mutex> lock(transactionMutex);  // ARCH-001 FIX: Use separate mutex
    if (!inTransaction.load()) return true;

    char* errMsg = nullptr;
    int rc = sqlite3_exec(this->db->get(), "ROLLBACK;", nullptr, nullptr, &errMsg);
    if (rc != SQLITE_OK) {
        std::cerr << "Failed to rollback transaction: " << errMsg << std::endl;
        if (errMsg) {
            sqlite3_free(errMsg);
        }
    }

    // ARCH-003 FIX: Always clear transaction flag, even if rollback fails
    // If rollback fails, the transaction is already in an error state
    inTransaction.store(false);
    return (rc == SQLITE_OK);
}

bool InsertFolderBatch(DatabaseContext& ctx, const std::string& inventoryId, int64_t folderId, const std::wstring& path, int64_t parentFolderId, int volumeId, const FILETIME* creationTime, const FILETIME* lastWriteTime, const FILETIME* lastAccessTime, DWORD attributes) {
    // Keep entire operation inside lock to prevent race conditions on pendingInserts
    std::lock_guard<std::recursive_mutex> lock(ctx.dbMutex);

    // OPT-002: Removed redundant duplicate check
    // The INSERT OR IGNORE statement relies on the PRIMARY KEY constraint
    // on (InventoryID, LocalFolderID) to handle duplicates efficiently

    // Reset the statement for reuse
    sqlite3_reset(ctx.insertFolderStmt->get());

    int rc;  // Variable for sqlite3 return codes

    // Bind parameters (InventoryID, LocalFolderID, ParentFolderID, Path, VolumeID)
    sqlite3_bind_text(ctx.insertFolderStmt->get(), 1, inventoryId.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(ctx.insertFolderStmt->get(), 2, folderId);  // Use int64 for 64-bit folder IDs

    // Bind ParentFolderID - use NULL if 0
    if (parentFolderId > 0) {
        sqlite3_bind_int64(ctx.insertFolderStmt->get(), 3, parentFolderId);  // Use int64 for 64-bit folder IDs
    } else {
        sqlite3_bind_null(ctx.insertFolderStmt->get(), 3);
    }

    sqlite3_bind_text16(ctx.insertFolderStmt->get(), 4, path.c_str(), -1, SQLITE_TRANSIENT);

    // Bind VolumeID - use NULL if 0
    if (volumeId > 0) {
        sqlite3_bind_int(ctx.insertFolderStmt->get(), 5, volumeId);
    } else {
        sqlite3_bind_null(ctx.insertFolderStmt->get(), 5);
    }

    // Bind CreationTime
    if (creationTime) {
        std::string creationTimeStr = FileTimeToIso8601(*creationTime);
        if (!creationTimeStr.empty()) {
            sqlite3_bind_text(ctx.insertFolderStmt->get(), 6, creationTimeStr.c_str(), -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(ctx.insertFolderStmt->get(), 6);
        }
    } else {
        sqlite3_bind_null(ctx.insertFolderStmt->get(), 6);
    }

    // Bind LastWriteTime
    if (lastWriteTime) {
        std::string lastWriteTimeStr = FileTimeToIso8601(*lastWriteTime);
        if (!lastWriteTimeStr.empty()) {
            sqlite3_bind_text(ctx.insertFolderStmt->get(), 7, lastWriteTimeStr.c_str(), -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(ctx.insertFolderStmt->get(), 7);
        }
    } else {
        sqlite3_bind_null(ctx.insertFolderStmt->get(), 7);
    }

    // Bind LastAccessTime
    if (lastAccessTime) {
        std::string lastAccessTimeStr = FileTimeToIso8601(*lastAccessTime);
        if (!lastAccessTimeStr.empty()) {
            sqlite3_bind_text(ctx.insertFolderStmt->get(), 8, lastAccessTimeStr.c_str(), -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(ctx.insertFolderStmt->get(), 8);
        }
    } else {
        sqlite3_bind_null(ctx.insertFolderStmt->get(), 8);
    }

    // Bind Attributes
    sqlite3_bind_int(ctx.insertFolderStmt->get(), 9, static_cast<int>(attributes));

    // Execute the statement
    rc = sqlite3_step(ctx.insertFolderStmt->get());
    if (rc != SQLITE_DONE) {
        std::cerr << "Failed to insert folder: " << sqlite3_errmsg(ctx.db->get()) << std::endl;
        return false;
    }

    ctx.pendingInserts++;

    // Check if we need to commit and start a new transaction
    // Keep this inside the lock to prevent race conditions
    if (ctx.pendingInserts >= ctx.BATCH_SIZE) {
        // ARCH-001 FIX: Now that transaction methods use a separate mutex,
        // we can safely call them from code that holds dbMutex
        if (!ctx.commitTransaction()) {
            std::cerr << "Failed to commit transaction batch" << std::endl;
            return false;
        }

        if (!ctx.beginTransaction()) {
            std::cerr << "Failed to begin new transaction batch" << std::endl;
            return false;
        }

        // Reset pending inserts counter
        ctx.pendingInserts = 0;
    }

    return true;
}

bool LogEvent(DatabaseContext& ctx,
             Logging::Severity severity,
             const std::string& source,
             const std::string& message,
             const std::string& path,
             int errorCode,
             int threadId,
             const std::string& additionalData,
             const std::string& inventoryId) {
    
    if (!ctx.db) {
        std::cerr << "Database not initialized" << std::endl;
        return false;
    }

    try {
        // Prepare the SQL statement
        const char* sql = R"(
            INSERT INTO app__EventLog (
                InventoryID,
                Timestamp,
                Severity,
                Source,
                Message,
                Path,
                ErrorCode,
                ThreadID,
                AdditionalData
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        )";

        PreparedStatement stmt(ctx.db->get(), sql);

        // Bind parameters
        std::string timestamp = FormatTime();  // Current UTC time
        std::string severityStr = Logging::SeverityToString(severity);
        std::string invId = inventoryId.empty() ? ctx.inventoryID : inventoryId;  // Use provided ID or context ID

        sqlite3_bind_text(stmt.get(), 1, invId.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt.get(), 2, timestamp.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt.get(), 3, severityStr.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt.get(), 4, source.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt.get(), 5, message.c_str(), -1, SQLITE_TRANSIENT);
        
        if (path.empty()) {
            sqlite3_bind_null(stmt.get(), 6);
        } else {
            sqlite3_bind_text(stmt.get(), 6, path.c_str(), -1, SQLITE_TRANSIENT);
        }

        if (errorCode == 0) {
            sqlite3_bind_null(stmt.get(), 7);
        } else {
            sqlite3_bind_int(stmt.get(), 7, errorCode);
        }

        if (threadId == 0) {
            sqlite3_bind_null(stmt.get(), 8);
        } else {
            sqlite3_bind_int(stmt.get(), 8, threadId);
        }

        if (additionalData.empty()) {
            sqlite3_bind_null(stmt.get(), 9);
        } else {
            sqlite3_bind_text(stmt.get(), 9, additionalData.c_str(), -1, SQLITE_TRANSIENT);
        }

        // Execute the statement
        int result = sqlite3_step(stmt.get());
        if (result != SQLITE_DONE) {
            std::cerr << "Failed to insert event log: " << sqlite3_errmsg(ctx.db->get()) << std::endl;
            return false;
        }

        return true;
    } catch (const std::exception& e) {
        std::cerr << "Exception in LogEvent: " << e.what() << std::endl;
        return false;
    }
}

/**
 * @brief Opens an existing SQLite database and verifies its schema version.
 *
 * Attempts to open the database at the specified path and checks that its schema version matches the expected version. Returns false if the database cannot be opened, the version is missing or invalid, or if the version does not match the required schema.
 *
 * @param dbPath Path to the SQLite database file.
 * @return true if the database is opened successfully and the schema version matches; false otherwise.
 */
bool OpenExistingDatabase(DatabaseContext& ctx, const std::string& dbPath) {
    // FIX NEW-003: Convert to absolute path using dynamic allocation to prevent buffer overflow
    // Query required buffer size first
    DWORD requiredSize = GetFullPathNameA(dbPath.c_str(), 0, nullptr, nullptr);
    std::string absPath;

    if (requiredSize == 0) {
        // Error getting path size - use original path as fallback
        absPath = dbPath;
    } else {
        // Allocate buffer of correct size to handle long paths
        std::vector<char> absolutePath(requiredSize);
        DWORD result = GetFullPathNameA(dbPath.c_str(), requiredSize, absolutePath.data(), nullptr);
        absPath = (result > 0 && result < requiredSize) ? absolutePath.data() : dbPath;
    }

    // Create database connection using RAII wrapper
    try {
        ctx.db = std::make_shared<DatabaseConnection>(absPath);  // FIX NEW-002: shared_ptr for thread safety
    } catch (const std::exception& e) {
        std::cerr << "Failed to open existing database: " << e.what() << std::endl;
        return false;
    }

    // OPT-001: Optimized PRAGMA settings for maximum performance
    // These settings balance safety, concurrency, and speed for bulk data collection
    char* errMsg = nullptr;
    int rc = sqlite3_exec(ctx.db->get(),
        "PRAGMA journal_mode = WAL;"        // Write-Ahead Logging for better concurrency
        "PRAGMA synchronous = NORMAL;"      // Balance safety/speed (full durability not critical during collection)
        "PRAGMA cache_size = -64000;"       // 64MB cache (negative = KB, positive = pages)
        "PRAGMA temp_store = MEMORY;"       // Store temp tables/indexes in RAM
        "PRAGMA mmap_size = 2147483648;"    // 2GB memory-mapped I/O for fast reads
        "PRAGMA page_size = 4096;"          // Larger page size for better I/O efficiency
        "PRAGMA busy_timeout = 5000;"       // Wait up to 5 seconds on locks before failing
        "PRAGMA locking_mode = NORMAL;"     // Release locks after transactions (allow concurrent readers)
        "PRAGMA wal_autocheckpoint = 10000;", // Checkpoint every 10000 pages to manage WAL file size
        nullptr, nullptr, &errMsg);

    if (rc != SQLITE_OK) {
        std::cerr << "Failed to set optimized PRAGMAs: " << errMsg << std::endl;
        sqlite3_free(errMsg);
        return false;
    }

    // Check schema version
    const char* checkVersionSQL = "SELECT PropertyValue FROM app__Version WHERE PropertyName = 'DBVersion';";
    try {
        PreparedStatement stmt(ctx.db->get(), checkVersionSQL);
        if (sqlite3_step(stmt.get()) != SQLITE_ROW) {
            std::cerr << "Database version not found - database may be invalid or corrupted" << std::endl;
            return false;
        }

        // Get the version string and ensure it's properly terminated
        const unsigned char* dbVersion = sqlite3_column_text(stmt.get(), 0);
        if (!dbVersion) {
            std::cerr << "Invalid database version format" << std::endl;
            return false;
        }

        std::string versionStr(reinterpret_cast<const char*>(dbVersion));
        if (versionStr != DB_SCHEMA_VERSION) {
            std::cerr << "Database version mismatch. Expected: " << DB_SCHEMA_VERSION 
                    << ", Found: " << versionStr << std::endl;
            return false;
        }
    } catch (const std::exception& e) {
        std::cerr << "Exception checking database version: " << e.what() << std::endl;
        return false;
    }

    // Prepare reusable insert statement (OPT-002: Use INSERT OR IGNORE to avoid redundant duplicate checks)
    const char* insertSql = "INSERT OR IGNORE INTO app__Folders (InventoryID, LocalFolderID, ParentFolderID, Path, VolumeID, CreationTime, LastWriteTime, LastAccessTime, Attributes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);";
    try {
        ctx.insertFolderStmt = std::make_unique<PreparedStatement>(ctx.db->get(), insertSql);
    } catch (const std::exception& e) {
        std::cerr << "Failed to prepare insert statement: " << e.what() << std::endl;
        return false;
    }

    std::cout << "Database opened successfully (Version: " << DB_SCHEMA_VERSION << ")" << std::endl;
    return true;
}

/**
 * @brief Inserts a new collection record into the app__CollectionInfo table.
 *
 * Adds detailed metadata about a collection session, including inventory ID, computer and domain names, collection timestamps (in UTC and local time), application version and build, administrative status, user identity, hardware concurrency, thread count, output and scan paths, and flags for remote computer and explicit-only scan.
 *
 * @param inventoryId Unique identifier for the inventory session.
 * @param computerName Name of the computer where the collection is performed.
 * @param domainName Domain name of the computer.
 * @param collectionTime Time point representing when the collection started.
 * @param appVersion Application version string.
 * @param appBuild Application build string.
 * @param isAdmin Indicates if the session is running with administrative privileges.
 * @param who User identity performing the collection.
 * @param hardwareConcurrency Number of hardware threads available.
 * @param threadCount Number of threads used during collection.
 * @param outputPath Path where output is stored.
 * @param scanPath Path that was scanned.
 * @param isRemoteComputer True if the collection targets a remote computer.
 * @param explicitOnly True if only explicitly specified items were scanned.
 * @return true if the record was successfully inserted; false otherwise.
 */
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
                        bool explicitOnly) {
    
    if (!ctx.db) {
        std::cerr << "Database not initialized" << std::endl;
        return false;
    }

    try {
        const char* sql = R"(
            INSERT INTO app__CollectionInfo (
                InventoryID,
                ComputerName,
                DomainName,
                CollectionDateTime,
                ApplicationVersion,
                ApplicationBuild,
                IsAdmin,
                Who,
                HardwareConcurrency,
                ThreadCount,
                StartTime,
                OutputPath,
                ScanPath,
                RemoteComputer,
                ExplicitOnly
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        )";

        PreparedStatement stmt(ctx.db->get(), sql);

        // Convert times to appropriate formats
        std::string collectionTimeUtc = FormatTime(collectionTime, false);  // UTC for CollectionDateTime
        std::string startTimeLocal = FormatTime(collectionTime, true);      // Local for StartTime

        // Bind parameters
        sqlite3_bind_text(stmt.get(), 1, inventoryId.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt.get(), 2, computerName.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt.get(), 3, domainName.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt.get(), 4, collectionTimeUtc.c_str(), -1, SQLITE_TRANSIENT);  // UTC
        sqlite3_bind_text(stmt.get(), 5, appVersion.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt.get(), 6, appBuild.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt.get(), 7, isAdmin ? 1 : 0);
        sqlite3_bind_text(stmt.get(), 8, who.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt.get(), 9, hardwareConcurrency);
        sqlite3_bind_int(stmt.get(), 10, threadCount);
        sqlite3_bind_text(stmt.get(), 11, startTimeLocal.c_str(), -1, SQLITE_TRANSIENT);  // Local
        sqlite3_bind_text(stmt.get(), 12, outputPath.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt.get(), 13, scanPath.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt.get(), 14, isRemoteComputer ? 1 : 0);
        sqlite3_bind_int(stmt.get(), 15, explicitOnly ? 1 : 0);

        int result = sqlite3_step(stmt.get());
        if (result != SQLITE_DONE) {
            std::cerr << "Failed to insert collection info: " << sqlite3_errmsg(ctx.db->get()) << std::endl;
            return false;
        }

        return true;
    } catch (const std::exception& e) {
        std::cerr << "Exception in InsertCollectionInfo: " << e.what() << std::endl;
        return false;
    }
}

/**
 * @brief Updates an existing collection record in the database with completion details and statistics.
 *
 * Updates the `app__CollectionInfo` table for the specified inventory ID, setting the end time, calculating total runtime, and recording statistics such as folders processed, folders with errors, peak queue size, and memory usage.
 *
 * @param inventoryId Unique identifier for the collection session to update.
 * @param endTime Time point marking the end of the collection (used for both end time and runtime calculation).
 * @param foldersProcessed Number of folders processed during the collection.
 * @param foldersWithErrors Number of folders that encountered errors.
 * @param peakQueueSize Maximum size of the processing queue during the collection.
 * @param memoryUsageMB Peak memory usage in megabytes.
 * @return true if the update succeeds; false if the database is uninitialized or an error occurs.
 */
bool UpdateCollectionInfo(
    DatabaseContext& dbCtx,
    const std::string& inventoryID,
    const std::chrono::system_clock::time_point& endTime,
    int64_t foldersProcessed,  // Change to int64_t
    int foldersWithErrors,
    int peakQueueSize,
    int peakMemoryUsageMB
) {
    
    if (!dbCtx.db) {
        std::cerr << "Database not initialized" << std::endl;
        return false;
    }

    try {
        const char* sql = R"(
            UPDATE app__CollectionInfo 
            SET EndTime = ?,
                TotalRuntime = strftime('%s', ?) - strftime('%s', CollectionDateTime),
                FoldersProcessed = ?,
                FoldersWithErrors = ?,
                PeakQueueSize = ?,
                MemoryUsageMB = ?
            WHERE InventoryID = ?;
        )";

        PreparedStatement stmt(dbCtx.db->get(), sql);

        // Convert end time to appropriate formats
        std::string endTimeLocal = FormatTime(endTime, true);  // Local time for EndTime
        std::string endTimeUtc = FormatTime(endTime, false);   // UTC for runtime calculation

        // Bind parameters
        sqlite3_bind_text(stmt.get(), 1, endTimeLocal.c_str(), -1, SQLITE_TRANSIENT);  // Local
        sqlite3_bind_text(stmt.get(), 2, endTimeUtc.c_str(), -1, SQLITE_TRANSIENT);    // UTC for runtime
        sqlite3_bind_int64(stmt.get(), 3, foldersProcessed);  // Use bind_int64 for int64_t
        sqlite3_bind_int(stmt.get(), 4, foldersWithErrors);
        sqlite3_bind_int(stmt.get(), 5, peakQueueSize);
        sqlite3_bind_int(stmt.get(), 6, peakMemoryUsageMB);
        sqlite3_bind_text(stmt.get(), 7, inventoryID.c_str(), -1, SQLITE_TRANSIENT);

        int result = sqlite3_step(stmt.get());
        if (result != SQLITE_DONE) {
            std::cerr << "Failed to update collection info: " << sqlite3_errmsg(dbCtx.db->get()) << std::endl;
            return false;
        }

        return true;
    } catch (const std::exception& e) {
        std::cerr << "Exception in UpdateCollectionInfo: " << e.what() << std::endl;
        return false;
    }
}

// Folder management functions

bool DatabaseContext::retryOperation(const std::function<bool()>& operation) {
    int attempts = 0;
    bool success = false;
    
    while (attempts < MAX_RETRIES && !success) {
        try {
            success = operation();
            if (success) {
                return true;
            }
        } catch (const std::exception& e) {
            std::cerr << "Attempt " << (attempts + 1) << " failed: " << e.what() << std::endl;
        }
        
        // Increase delay with each retry attempt (exponential backoff)
        std::this_thread::sleep_for(std::chrono::milliseconds(RETRY_DELAY_MS * (1 << attempts)));
        attempts++;
    }
    
    return false;
}

void DatabaseContext::handleError(const std::string& operation, int errorCode) {
    std::string errorMessage;
    
    switch (errorCode) {
        case SQLITE_BUSY:
            errorMessage = "Database is busy";
            break;
        case SQLITE_LOCKED:
            errorMessage = "Database is locked";
            break;
        case SQLITE_INTERRUPT:
            errorMessage = "Operation interrupted";
            break;
        case SQLITE_IOERR:
            errorMessage = "I/O error occurred";
            break;
        case SQLITE_CORRUPT:
            errorMessage = "Database is corrupt";
            break;
        case SQLITE_CONSTRAINT:
            errorMessage = "Constraint violation";
            break;
        default:
            errorMessage = "SQLite error code: " + std::to_string(errorCode);
            break;
    }
    
    std::string logMessage = "Database error during " + operation + ": " + errorMessage;
    std::cerr << logMessage << std::endl;
    
    // If we have a valid db connection, log the event to the database
    if (db) {
        try {
            LogEvent(*this, Logging::Severity::ERR, "Database", logMessage, "", errorCode);
        } catch (...) {
            // Silently ignore errors during error logging to avoid recursion
        }
    }
}

DatabaseConnection::DatabaseConnection(const std::string& dbPath) {
    int rc = sqlite3_open_v2(
        dbPath.c_str(),
        &db,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
        nullptr /* vfs */
    );
    if (rc != SQLITE_OK) {
        throw std::runtime_error("Failed to open database: " + std::string(sqlite3_errmsg(db)));
    }
}

// Implementation of Logging namespace functions
namespace Logging {
    const char* SeverityToString(Severity severity) {
        switch (severity) {
            case Severity::DEBUG:   return "DEBUG";
            case Severity::INFO:    return "INFO";
            case Severity::WARNING: return "WARNING";
            case Severity::ERR:     return "ERROR";
            default:               return "UNKNOWN";
        }
    }
}

/**
 * @brief Ensures all ancestor folders are inserted into the database
 *
 * When a folder path is processed, this function identifies all ancestor paths,
 * gets their IDs from the FolderIndex, and inserts them into the database if needed.
 *
 * @param ctx Database context
 * @param inventoryId The inventory ID for the current scan
 * @param folderIndex Reference to the folder index containing path IDs
 * @param path The folder path whose ancestors should be inserted
 * @return true if all ancestors were successfully inserted; false otherwise
 */
bool EnsureAncestorsInserted(DatabaseContext& ctx, 
                            const std::string& inventoryId,
                            FolderIndex& folderIndex,
                            const std::wstring& path) {
    // Extract all ancestor paths
    std::wstring currentPath = path;
    std::vector<std::wstring> ancestors;
    
    // Build list of ancestors (from deepest to root)
    while (true) {
        size_t pos = currentPath.find_last_of(L"\\/");
        if (pos == std::wstring::npos || pos == 0) {
            // We've reached the root or drive letter
            if (currentPath.length() >= 2 && currentPath[1] == L':') {
                // Add drive root (e.g., "D:\") - MUST include backslash to match FolderIndex format
                ancestors.push_back(currentPath + L"\\");
            }
            break;
        }

        // Get parent path
        currentPath = currentPath.substr(0, pos);

        // Check if we've reached a root path - must match FolderIndex logic
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
    
    // Insert ancestors from root to leaf
    bool success = true;
    int64_t previousAncestorId = 0; // Track parent ID for the next ancestor

    for (auto it = ancestors.rbegin(); it != ancestors.rend(); ++it) {
        int64_t ancestorId = folderIndex.getId(*it);
        if (ancestorId > 0) {
            // Determine parent folder ID (0 for root, otherwise previous ancestor)
            int64_t parentFolderId = previousAncestorId;

            // Determine volume ID for this ancestor
            int volumeId = GetVolumeIdFromPath(ctx, *it);

            // Get folder attributes and timestamps for this ancestor
            WIN32_FILE_ATTRIBUTE_DATA ancestorAttribs = {};
            BOOL attribSuccess = GetFileAttributesExW(
                FolderUtils::toLongPath(*it).c_str(),
                GetFileExInfoStandard,
                &ancestorAttribs
            );

            // Insert this ancestor into the database
            if (attribSuccess) {
                if (!InsertFolderBatch(ctx, inventoryId, ancestorId, *it, parentFolderId, volumeId,
                                      &ancestorAttribs.ftCreationTime,
                                      &ancestorAttribs.ftLastWriteTime,
                                      &ancestorAttribs.ftLastAccessTime,
                                      ancestorAttribs.dwFileAttributes)) {
                    success = false;
                }
            } else {
                // Fallback without attributes if GetFileAttributesExW fails
                if (!InsertFolderBatch(ctx, inventoryId, ancestorId, *it, parentFolderId, volumeId,
                                      nullptr, nullptr, nullptr, 0)) {
                    success = false;
                }
            }

            // Update previous ancestor ID for the next iteration
            previousAncestorId = ancestorId;
        }
    }

    return success;
}

// Helper function to get parent path from a folder path
std::wstring GetParentPath(std::wstring_view path) {
    if (path.empty()) return L"";

    // CODE-001: Handle paths ending with backslash
    std::wstring workingPath(path);
    while (!workingPath.empty() && (workingPath.back() == L'\\' || workingPath.back() == L'/')) {
        workingPath.pop_back();
    }

    // Find last path separator
    size_t pos = workingPath.find_last_of(L"\\/");
    if (pos == std::wstring::npos) {
        return L"";  // No parent
    }

    // Handle drive root (e.g., "C:\")
    if (pos == 2 && workingPath.length() >= 2 && workingPath[1] == L':') {
        return workingPath.substr(0, 3);  // Return "C:\"
    }

    // Handle UNC root (e.g., "\\server\share")
    if (pos < 2) {
        return L"";  // This is a root
    }

    return workingPath.substr(0, pos);
}

// Helper function to get parent folder ID from FolderIndex
int64_t GetParentFolderId(const FolderIndex& folderIndex, std::wstring_view path) {
    std::wstring parentPath = GetParentPath(path);
    if (parentPath.empty()) {
        return 0;  // No parent (root folder)
    }

    int64_t parentId = folderIndex.getId(parentPath);
    return parentId > 0 ? parentId : 0;
}

// Helper function to convert Windows FILETIME to ISO 8601 string (local time)
std::string FileTimeToIso8601(const FILETIME& ft) {
    SYSTEMTIME st, stLocal;

    // Convert FILETIME to SYSTEMTIME (UTC)
    if (!FileTimeToSystemTime(&ft, &st)) {
        return "";  // Return empty string on error
    }

    // Convert to local time
    if (!SystemTimeToTzSpecificLocalTime(nullptr, &st, &stLocal)) {
        return "";  // Return empty string on error
    }

    // Format as ISO 8601: YYYY-MM-DD HH:MM:SS
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "%04d-%02d-%02d %02d:%02d:%02d",
             stLocal.wYear, stLocal.wMonth, stLocal.wDay,
             stLocal.wHour, stLocal.wMinute, stLocal.wSecond);

    return std::string(buffer);
}

// Helper function to extract drive letter or root from path
std::wstring ExtractDriveLetterOrRoot(std::wstring_view path) {
    if (path.length() >= 2 && path[1] == L':') {
        // Drive letter path (e.g., "C:\..." or "c:\...")
        // Normalize to uppercase and add backslash to match mount point format in database
        wchar_t driveLetter = path[0];
        // Convert to uppercase if lowercase (a-z -> A-Z)
        if (driveLetter >= L'a' && driveLetter <= L'z') {
            driveLetter = driveLetter - L'a' + L'A';
        }
        return std::wstring(1, driveLetter) + L":\\";  // Return "C:\" with uppercase letter
    }

    // Handle UNC paths (e.g., "\\server\share\...")
    if (path.length() >= 2 && path[0] == L'\\' && path[1] == L'\\') {
        // Find the share name
        size_t serverStart = 2;
        size_t serverEnd = path.find(L'\\', serverStart);
        if (serverEnd != std::wstring_view::npos) {
            size_t shareEnd = path.find(L'\\', serverEnd + 1);
            if (shareEnd != std::wstring_view::npos) {
                return std::wstring(path.substr(0, shareEnd));  // Return "\\server\share"
            } else {
                return std::wstring(path);  // Just "\\server\share" with no subdirs
            }
        }
    }

    return L"";  // Unknown format
}

// Helper function to get VolumeID from path by looking up mount points
int GetVolumeIdFromPath(DatabaseContext& ctx, std::wstring_view path) {
    std::wstring driveRoot = ExtractDriveLetterOrRoot(path);
    if (driveRoot.empty()) {
        return 0;  // Unknown volume
    }

    // Convert to UTF-8 for database query
    std::string utf8DriveRoot = FolderUtils::toUtf8(driveRoot);

    // DEBUG: Log what we're looking for (only log first occurrence to avoid spam)
    if (AppGlobals::DebugMode.load()) {
        static bool firstLookup = true;
        if (firstLookup) {
            std::cout << "\n[DEBUG] Volume ID Lookup:" << std::endl;
            std::cout << "  Path: " << FolderUtils::toUtf8(path) << std::endl;
            std::cout << "  Extracted mount point: " << utf8DriveRoot << std::endl;
            std::cout << "  InventoryID: " << ctx.inventoryID << std::endl;
            firstLookup = false;
        }
    }

    try {
        std::lock_guard<std::recursive_mutex> lock(ctx.dbMutex);

        // DEBUG: First check what mount points exist in the database
        if (AppGlobals::DebugMode.load()) {
            static bool dbChecked = false;
            if (!dbChecked) {
                const char* checkSql = "SELECT VolumeID, MountPoint FROM app__VolumeMounts WHERE InventoryID = ? LIMIT 5";
                PreparedStatement checkStmt(ctx.db->get(), checkSql);
                sqlite3_bind_text(checkStmt.get(), 1, ctx.inventoryID.c_str(), -1, SQLITE_TRANSIENT);

                std::cout << "\n[DEBUG] Mount points in database:" << std::endl;
                int count = 0;
                while (sqlite3_step(checkStmt.get()) == SQLITE_ROW) {
                    int volId = sqlite3_column_int(checkStmt.get(), 0);
                    const char* mp = reinterpret_cast<const char*>(sqlite3_column_text(checkStmt.get(), 1));
                    std::cout << "  VolumeID " << volId << ": '" << (mp ? mp : "NULL") << "'" << std::endl;
                    count++;
                }
                if (count == 0) {
                    std::cout << "  WARNING: No mount points found in database!" << std::endl;
                }
                std::cout << std::endl;
                dbChecked = true;
            }
        }

        // Query the database for VolumeID based on mount point
        // Drive root now includes trailing backslash, so we can do exact match
        const char* sql = R"(
            SELECT VolumeID
            FROM app__VolumeMounts
            WHERE InventoryID = ?
              AND MountPoint = ?
            LIMIT 1
        )";

        PreparedStatement stmt(ctx.db->get(), sql);
        sqlite3_bind_text(stmt.get(), 1, ctx.inventoryID.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt.get(), 2, utf8DriveRoot.c_str(), -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt.get()) == SQLITE_ROW) {
            int volumeId = sqlite3_column_int(stmt.get(), 0);
            return volumeId;
        }
    } catch (const std::exception& e) {
        std::cerr << "Error looking up volume ID for path '" << FolderUtils::toUtf8(path)
                  << "' (mount point: " << utf8DriveRoot << "): " << e.what() << std::endl;
    }

    return 0;  // Volume not found
}
