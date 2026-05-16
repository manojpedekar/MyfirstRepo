
#include <iostream>
#include <iomanip>
#include <chrono>
#include <sstream>
#include <windows.h>  // For GetLastError
#include <aclapi.h>   // For GetNamedSecurityInfoW
#include <sddl.h>     // For ConvertSidToStringSidW
#include "../database/database.h"  // Assuming this contains DatabaseContext and other necessary declarations
#include "../core/ACLInfo.h"  // Assuming this contains the AclInfo structure definition
#include <tuple>
#include <variant>
#include "../core/AclProcessor.h"
#include "../utils/utils.h" // For FormatNumberWithLocale
#include <algorithm>
#include <cctype>
#include <locale>
#include <cwctype>  // For towlower
#include "../utils/folderutils.h"
#include "../core/folderindex.h"

// Add these definitions if they're not already in your Windows headers
#ifndef ACCESS_ALLOWED_CALLBACK_ACE_TYPE
#define ACCESS_ALLOWED_CALLBACK_ACE_TYPE 9
#endif

#ifndef ACCESS_DENIED_CALLBACK_ACE_TYPE
#define ACCESS_DENIED_CALLBACK_ACE_TYPE 10
#endif

#undef min
#undef max

// ACE Type Processing Optimization
// Lookup table for fast ACE type processing to avoid switch statement overhead
namespace {
    struct AceTypeInfo {
        AceType type;
        size_t sidOffset;  // Offset to SID in ACE structure
        bool isSupported;
    };

    // Pre-computed lookup table indexed by Windows ACE type
    // This avoids switch statement overhead for common ACE types
    constexpr size_t ACE_TYPE_TABLE_SIZE = 32;
    static const AceTypeInfo aceTypeTable[ACE_TYPE_TABLE_SIZE] = {
        // Index 0: ACCESS_ALLOWED_ACE_TYPE
        {AceType::Allow, offsetof(ACCESS_ALLOWED_ACE, SidStart), true},
        // Index 1: ACCESS_DENIED_ACE_TYPE
        {AceType::Deny, offsetof(ACCESS_DENIED_ACE, SidStart), true},
        // Index 2: SYSTEM_AUDIT_ACE_TYPE
        {AceType::Audit, offsetof(SYSTEM_AUDIT_ACE, SidStart), true},
        // Index 3: SYSTEM_ALARM_ACE_TYPE
        {AceType::Alarm, offsetof(SYSTEM_ALARM_ACE, SidStart), true},
        // Index 4-8: Reserved/unsupported
        {AceType::Unknown, 0, false}, {AceType::Unknown, 0, false},
        {AceType::Unknown, 0, false}, {AceType::Unknown, 0, false},
        {AceType::Unknown, 0, false},
        // Index 9: ACCESS_ALLOWED_CALLBACK_ACE_TYPE
        {AceType::AllowCallback, offsetof(ACCESS_ALLOWED_ACE, SidStart), true},
        // Index 10: ACCESS_DENIED_CALLBACK_ACE_TYPE
        {AceType::DenyCallback, offsetof(ACCESS_DENIED_ACE, SidStart), true},
        // Index 11-31: Remaining entries unsupported (21 entries)
        {AceType::Unknown, 0, false}, {AceType::Unknown, 0, false},
        {AceType::Unknown, 0, false}, {AceType::Unknown, 0, false},
        {AceType::Unknown, 0, false}, {AceType::Unknown, 0, false},
        {AceType::Unknown, 0, false}, {AceType::Unknown, 0, false},
        {AceType::Unknown, 0, false}, {AceType::Unknown, 0, false},
        {AceType::Unknown, 0, false}, {AceType::Unknown, 0, false},
        {AceType::Unknown, 0, false}, {AceType::Unknown, 0, false},
        {AceType::Unknown, 0, false}, {AceType::Unknown, 0, false},
        {AceType::Unknown, 0, false}, {AceType::Unknown, 0, false},
        {AceType::Unknown, 0, false}, {AceType::Unknown, 0, false},
        {AceType::Unknown, 0, false}
    };

    // Fast ACE type lookup - replaces switch statement
    inline const AceTypeInfo& GetAceTypeInfo(BYTE aceType) {
        if (aceType < ACE_TYPE_TABLE_SIZE) {
            return aceTypeTable[aceType];
        }
        static const AceTypeInfo unknown = {AceType::Unknown, 0, false};
        return unknown;
    }
}

// Helper class for SQLite operations
class SqliteHelper {
public:
    static int Step(sqlite3_stmt* stmt) {
        return sqlite3_step(stmt);
    }
    static void Exec(sqlite3_stmt* stmt) {
        int rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            throw std::runtime_error(std::string("SQLite Exec failed: ") + sqlite3_errstr(rc));
        }
    }
    static int64_t GetInt64(sqlite3_stmt* stmt, int col) {
        return sqlite3_column_int64(stmt, col);
    }
    static std::wstring GetWString(sqlite3_stmt* stmt, int col) {
        // FIX FC-012: Properly convert UTF-8 to UTF-16 using MultiByteToWideChar
        const unsigned char* text = sqlite3_column_text(stmt, col);
        if (!text) return L"";

        // Use FolderUtils::toWide() for proper UTF-8 to UTF-16 conversion
        const char* utf8Text = reinterpret_cast<const char*>(text);
        return FolderUtils::toWide(std::string(utf8Text));
    }
    static std::string GetString(sqlite3_stmt* stmt, int col) {
        const unsigned char* text = sqlite3_column_text(stmt, col);
        return text ? std::string(reinterpret_cast<const char*>(text)) : "";
    }
    static void Bind(sqlite3_stmt* stmt, int param, const std::string& value) {
        // FIX: Use SQLITE_TRANSIENT to copy the string data, since the source
        // string may be a temporary that gets destroyed before Exec() is called.
        // Using SQLITE_STATIC with temporaries causes corrupted data (BLOBs).
        sqlite3_bind_text(stmt, param, value.c_str(), -1, SQLITE_TRANSIENT);
    }
    static void Bind(sqlite3_stmt* stmt, int param, const std::wstring& value) {
        // FIX: Convert wstring to UTF-8 for proper TEXT storage in SQLite.
        // Using sqlite3_bind_text16 with SQLITE_STATIC caused BLOB storage
        // because the temporary wstring was destroyed before Exec().
        std::string utf8Value = FolderUtils::toUtf8(value);
        sqlite3_bind_text(stmt, param, utf8Value.c_str(), -1, SQLITE_TRANSIENT);
    }
    static void Bind(sqlite3_stmt* stmt, int param, int64_t value) {
        sqlite3_bind_int64(stmt, param, value);
    }
    static void Bind(sqlite3_stmt* stmt, int param, int value) {
        sqlite3_bind_int(stmt, param, value);
    }
    static void Reset(sqlite3_stmt* stmt) {
        sqlite3_reset(stmt);
    }
};

AclProcessor::AclProcessor(DatabaseContext& dbCtx, const FolderIndex& folderIndex, int numThreads)
    : dbCtx_(dbCtx), folderIndex_(folderIndex), lastUpdateTime_(std::chrono::steady_clock::now()) {
    // No need to copy the folder index - we now store a reference

    // Initialize well-known SIDs map
    wellKnownSids = {
        {L"S-1-0-0", L"NULL SID"},
        {L"S-1-1-0", L"Everyone"},
        {L"S-1-2-0", L"LOCAL"},
        {L"S-1-2-1", L"CONSOLE LOGON"},
        {L"S-1-3-0", L"CREATOR OWNER"},
        {L"S-1-3-1", L"CREATOR GROUP"},
        {L"S-1-3-4", L"OWNER RIGHTS"},
        {L"S-1-5-1", L"DIALUP"},
        {L"S-1-5-2", L"NETWORK"},
        {L"S-1-5-3", L"BATCH"},
        {L"S-1-5-4", L"INTERACTIVE"},
        {L"S-1-5-6", L"SERVICE"},
        {L"S-1-5-7", L"ANONYMOUS"},
        {L"S-1-5-8", L"PROXY"},
        {L"S-1-5-9", L"ENTERPRISE DOMAIN CONTROLLERS"},
        {L"S-1-5-10", L"PRINCIPAL SELF"},
        {L"S-1-5-11", L"Authenticated Users"},
        {L"S-1-5-12", L"RESTRICTED CODE"},
        {L"S-1-5-13", L"TERMINAL SERVER USERS"},
        {L"S-1-5-14", L"REMOTE INTERACTIVE LOGON"},
        {L"S-1-5-15", L"THIS ORGANIZATION"},
        {L"S-1-5-17", L"IUSR"},
        {L"S-1-5-18", L"SYSTEM"},
        {L"S-1-5-19", L"LOCAL SERVICE"},
        {L"S-1-5-20", L"NETWORK SERVICE"},
        {L"S-1-5-32-544", L"BUILTIN\\Administrators"},
        {L"S-1-5-32-545", L"BUILTIN\\Users"},
        {L"S-1-5-32-546", L"BUILTIN\\Guests"},
        {L"S-1-5-32-547", L"BUILTIN\\Power Users"},
        {L"S-1-5-32-548", L"BUILTIN\\Account Operators"},
        {L"S-1-5-32-549", L"BUILTIN\\Server Operators"},
        {L"S-1-5-32-550", L"BUILTIN\\Print Operators"},
        {L"S-1-5-32-551", L"BUILTIN\\Backup Operators"},
        {L"S-1-5-32-552", L"BUILTIN\\Replicators"},
        {L"S-1-5-32-554", L"BUILTIN\\Pre-Windows 2000 Compatible Access"},
        {L"S-1-5-32-555", L"BUILTIN\\Remote Desktop Users"},
        {L"S-1-5-32-556", L"BUILTIN\\Network Configuration Operators"},
        {L"S-1-5-32-557", L"BUILTIN\\Incoming Forest Trust Builders"},
        {L"S-1-5-32-558", L"BUILTIN\\Performance Monitor Users"},
        {L"S-1-5-32-559", L"BUILTIN\\Performance Log Users"},
        {L"S-1-5-32-560", L"BUILTIN\\Windows Authorization Access Group"},
        {L"S-1-5-32-561", L"BUILTIN\\Terminal Server License Servers"},
        {L"S-1-5-32-562", L"BUILTIN\\Distributed COM Users"},
        {L"S-1-5-32-568", L"BUILTIN\\IIS_IUSRS"},
        {L"S-1-5-32-569", L"BUILTIN\\Cryptographic Operators"},
        {L"S-1-5-32-573", L"BUILTIN\\Event Log Readers"},
        {L"S-1-5-32-574", L"BUILTIN\\Certificate Service DCOM Access"},
        {L"S-1-5-32-575", L"BUILTIN\\RDS Remote Access Servers"},
        {L"S-1-5-32-576", L"BUILTIN\\RDS Endpoint Servers"},
        {L"S-1-5-32-577", L"BUILTIN\\RDS Management Servers"},
        {L"S-1-5-32-578", L"BUILTIN\\Hyper-V Administrators"},
        {L"S-1-5-32-579", L"BUILTIN\\Access Control Assistance Operators"},
        {L"S-1-5-32-580", L"BUILTIN\\Remote Management Users"}
    };
    
    for (int i = 0; i < numThreads; ++i)
        workers_.emplace_back(&AclProcessor::WorkerThread, this);
}

AclProcessor::~AclProcessor() {
    {
        std::lock_guard<std::mutex> lock(queueMutex_);
        shouldStop_ = true;
    }
    queueCv_.notify_all();          // Wake up all worker threads
    queueNotFullCv_.notify_all();   // MEM-001: Wake up all blocked producers
    for (auto& worker : workers_)
        if (worker.joinable())
            worker.join();
}

void AclProcessor::AddFolder(const std::wstring& path, int64_t folderId) {
    static std::atomic<int> addCount{0};
    int count = ++addCount;

    try {
        {
            std::unique_lock<std::mutex> lock(queueMutex_);

            // MEM-001 FIX: Block if queue is full (backpressure mechanism)
            // This prevents unbounded memory growth by throttling folder scanning
            size_t queueSize = folderQueue_.size();
            if (AppGlobals::DebugMode.load() && queueSize >= MAX_QUEUE_SIZE) {
                std::cout << "[DEBUG] AddFolder #" << count << ": Queue FULL (" << queueSize
                          << "/" << MAX_QUEUE_SIZE << "), BLOCKING for workers to consume...\n";
            }

            // Wake periodically so we can detect stalled consumers
            queueNotFullCv_.wait_for(lock, std::chrono::seconds(5), [this] {
                return folderQueue_.size() < MAX_QUEUE_SIZE || shouldStop_;
            });

            // Detect potential deadlock when queue stays full but workers are gone
            if (folderQueue_.size() >= MAX_QUEUE_SIZE && activeWorkers_.load() == 0) {
                std::cerr << "[ERROR] AddFolder: Queue is full and no active workers remain."
                          << " Aborting enqueue to avoid deadlock.\n";
                shouldStop_ = true;
                queueCv_.notify_all();
                queueNotFullCv_.notify_all();
                return;
            }

            if (AppGlobals::DebugMode.load() && queueSize >= MAX_QUEUE_SIZE) {
                std::cout << "[DEBUG] AddFolder #" << count << ": Queue has space ("
                          << folderQueue_.size() << "), resuming\n";
            }

            // If stopping, don't add more items
            if (shouldStop_) {
                return;
            }

            folderQueue_.emplace(path, folderId);
        }
        queueCv_.notify_one();  // Notify a worker that work is available
    }
    catch (const std::exception& e) {
        std::cerr << "Exception in AddFolder: " << e.what() << std::endl;
        LogError(path, std::string("Exception in AddFolder: ") + e.what(), GetLastError());
    }
}

void AclProcessor::WorkerThread() {
    static std::atomic<int> workerIdCounter{0};
    int workerId = ++workerIdCounter;
    static std::atomic<int> processedCount{0};

    // Track liveness for producer stall detection
    activeWorkers_.fetch_add(1);
    struct WorkerGuard {
        AclProcessor* self;
        ~WorkerGuard() {
            self->activeWorkers_.fetch_sub(1);
            self->queueNotFullCv_.notify_all();
        }
    } guard{this};

    if (AppGlobals::DebugMode.load()) {
        std::cout << "[DEBUG] Worker #" << workerId << ": Thread started\n";
    }

    try {
        while (true) {
            std::pair<std::wstring, int64_t> folder;
            bool shouldExit = false;
            bool itemPopped = false;

            {
                std::unique_lock<std::mutex> lock(queueMutex_);

                if (AppGlobals::DebugMode.load() && processedCount.load() < 5) {
                    std::cout << "[DEBUG] Worker #" << workerId << ": Waiting for work (queue size="
                              << folderQueue_.size() << ")\n";
                }

                queueCv_.wait(lock, [this] {
                    return !folderQueue_.empty() || shouldStop_;
                });

                if (folderQueue_.empty() && shouldStop_) {
                    shouldExit = true;
                }
                else if (!folderQueue_.empty()) {
                    folder = folderQueue_.front();
                    folderQueue_.pop();
                    itemPopped = true;

                    int count = ++processedCount;
                    if (AppGlobals::DebugMode.load() && count <= 5) {
                        std::cout << "[DEBUG] Worker #" << workerId << ": Got folder #" << count
                                  << " from queue (remaining=" << folderQueue_.size() << ")\n";
                    }
                }
                // lock is automatically released when the scope ends
            }

            // MEM-001 FIX: Notify producers that queue has space now
            // Do this after lock is released to avoid unnecessary contention
            if (itemPopped) {
                queueNotFullCv_.notify_one();
            }

            if (shouldExit) {
                if (AppGlobals::DebugMode.load()) {
                    std::cout << "[DEBUG] Worker #" << workerId << ": Exiting\n";
                }
                break;
            }

            try {
                if (AppGlobals::DebugMode.load() && processedCount.load() <= 10) {
                    std::wcout << L"[DEBUG] Worker #" << workerId << ": About to call GetAclInfo for: "
                               << folder.first << std::endl;
                }

                //std::wcout << L"Getting ACL info for: " << folder.first << std::endl;
                AclInfo aclInfo = GetAclInfo(folder.first);

                if (AppGlobals::DebugMode.load() && processedCount.load() <= 10) {
                    std::wcout << L"[DEBUG] Worker #" << workerId << ": GetAclInfo returned, calling ProcessAcl" << std::endl;
                }

                //std::wcout << L"Processing ACL for: " << folder.first << std::endl;
                ProcessAcl(folder.first, folder.second, aclInfo);
                stats_.processedFolders++;
            }
            catch (const std::exception& e) {
                // FIX FC-015: Don't call GetLastError() after exception handling
                // Exception handling may have called other Windows APIs that reset GetLastError()
                // The exception message (e.what()) already contains the error description
                //std::cerr << "Error processing folder: " << e.what() << std::endl;
                LogError(folder.first, e.what(), 0);
                stats_.failedFolders++;
            }
            UpdateProgress();
        }
    }
    catch (const std::exception& e) {
        std::cerr << "Fatal exception in worker thread #" << workerId << ": " << e.what() << std::endl;
    }
}

void AclProcessor::ProcessAcl(const std::wstring& path, int64_t localFolderId, const AclInfo& aclInfo) {
    static std::atomic<int> processAclCount{0};
    int callNum = ++processAclCount;

    if (AppGlobals::DebugMode.load() && callNum <= 20) {
        std::wcout << L"[DEBUG] ProcessAcl #" << callNum << ": Called for path: " << path << std::endl;
    }

    try {
        // Use a local batch to avoid contention
        BatchData localBatch;

        // Get or create SID IDs for owner and group
        int64_t ownerSidId = 0;
        int64_t groupSidId = 0;

        if (!aclInfo.owner.empty()) {
            ownerSidId = GetOrCreateSidId(aclInfo.owner, L"");
        }

        if (!aclInfo.group.empty()) {
            groupSidId = GetOrCreateSidId(aclInfo.group, L"");
        }

        // Create ACL record
        int64_t aclId = nextAclId_++;
        localBatch.acls.emplace_back(
            dbCtx_.inventoryID,
            aclId,
            localFolderId,
            ownerSidId,
            groupSidId,
            aclInfo.areAccessRulesProtected,
            aclInfo.areAuditRulesProtected,
            aclInfo.areAccessRulesCanonical,
            aclInfo.areAuditRulesCanonical
        );

        // Process ACEs
        static std::atomic<int> aceProcessCount{0};
        int aceLoopStart = aceProcessCount.load();

        if (AppGlobals::DebugMode.load() && callNum <= 20) {
            std::wcout << L"[DEBUG] ProcessAcl #" << callNum << L": Starting ACE loop with "
                       << aclInfo.aces.size() << L" ACEs\n";
        }

        for (size_t aceIndex = 0; aceIndex < aclInfo.aces.size(); ++aceIndex) {
            const auto& ace = aclInfo.aces[aceIndex];
            int aceNum = ++aceProcessCount;

            if (AppGlobals::DebugMode.load() && callNum <= 20) {
                std::wcout << L"[DEBUG] ProcessAcl #" << callNum << L": Processing ACE #"
                           << (aceIndex + 1) << L" of " << aclInfo.aces.size()
                           << L" (global ACE #" << aceNum << L")\n";
            }

            // Skip inherited ACEs if explicitOnly is true
            if (g_explicitOnly && ace.isInherited) {
                if (AppGlobals::DebugMode.load() && callNum <= 20) {
                    std::wcout << L"[DEBUG] ProcessAcl #" << callNum << L": Skipping inherited ACE (explicitOnly=true)\n";
                }
                continue;
            }

            // Skip ACEs with empty SID strings
            if (ace.sidString.empty()) {
                if (AppGlobals::DebugMode.load() && callNum <= 20) {
                    std::wcout << L"[DEBUG] ProcessAcl #" << callNum << L": Skipping ACE with empty SID\n";
                }
                // Only log to file, not console
                LogError(path, "Skipping ACE with empty SID", 0);

                // Use a counter and only show summary
                stats_.skippedEmptySids++;
                continue;
            }

            if (AppGlobals::DebugMode.load() && callNum <= 20) {
                std::wcout << L"[DEBUG] ProcessAcl #" << callNum << L": About to call GetOrCreateSidId for ACE #"
                           << (aceIndex + 1) << L"\n";
            }

            // Get or create SID ID for the identity
            int64_t sidId = GetOrCreateSidId(ace.sidString, ace.trustee);

            if (AppGlobals::DebugMode.load() && callNum <= 20) {
                std::wcout << L"[DEBUG] ProcessAcl #" << callNum << L": GetOrCreateSidId returned sidId="
                           << sidId << L" for ACE #" << (aceIndex + 1) << L"\n";
            }

            // Get inherited from folder ID
            int64_t inheritedFromId = 0;
            if (ace.isInherited && !ace.inheritedFrom.empty()) {
                if (AppGlobals::DebugMode.load() && callNum <= 20) {
                    std::wstringstream msg;
                    msg << L"[DEBUG] ProcessAcl #" << callNum << L": ACE is inherited, about to call folderIndex_.getId for path: "
                        << ace.inheritedFrom.substr(0, (ace.inheritedFrom.length() < 60) ? ace.inheritedFrom.length() : 60) << L"...\n";
                    AppGlobals::WriteDebug(msg.str());

                    msg.str(L"");
                    msg << L"[DEBUG] ProcessAcl #" << callNum << L": folderIndex_ address=" << &folderIndex_ << L"\n";
                    AppGlobals::WriteDebug(msg.str());

                    msg.str(L"");
                    msg << L"[DEBUG] ProcessAcl #" << callNum << L": Calling getId() NOW...\n";
                    AppGlobals::WriteDebug(msg.str());
                }

                // Look up the folder ID for the inherited from path using FolderIndex
                int64_t folderId = folderIndex_.getId(ace.inheritedFrom);

                if (AppGlobals::DebugMode.load() && callNum <= 20) {
                    std::wstringstream msg;
                    msg << L"[DEBUG] ProcessAcl #" << callNum << L": folderIndex_.getId returned folderId="
                        << folderId << L" for ACE #" << (aceIndex + 1) << L"\n";
                    AppGlobals::WriteDebug(msg.str());
                }

                if (folderId != 0) {
                    inheritedFromId = folderId;  // No cast needed - both int64_t
                }
            } else if (AppGlobals::DebugMode.load() && callNum <= 20) {
                std::wcout << L"[DEBUG] ProcessAcl #" << callNum << L": ACE is not inherited or inheritedFrom is empty\n";
            }

            // Create ACE record
            int64_t aceId = nextAceId_++;
            localBatch.aces.emplace_back(
                dbCtx_.inventoryID,
                aceId,
                localFolderId,
                ace.accessMask,
                static_cast<int>(ace.accessType),
                sidId,
                ace.isInherited,
                ace.inheritanceMask,
                ace.propagationMask,
                inheritedFromId
            );

            if (AppGlobals::DebugMode.load() && callNum <= 20) {
                std::wcout << L"[DEBUG] ProcessAcl #" << callNum << L": Completed ACE #"
                           << (aceIndex + 1) << L", created aceId=" << aceId << L"\n";
            }
        }

        if (AppGlobals::DebugMode.load() && callNum <= 20) {
            std::wcout << L"[DEBUG] ProcessAcl #" << callNum << L": Completed ACE loop, processed "
                       << aclInfo.aces.size() << L" ACEs\n";
        }

        // Update statistics
        stats_.totalAcls++;
        stats_.totalAces += aclInfo.aces.size();

        // Add local batch to the global batch under lock
        if (AppGlobals::DebugMode.load() && callNum <= 100) {
            std::cout << "[DEBUG] ProcessAcl #" << callNum << ": About to acquire batchMutex_\n";
        }

        {
            std::lock_guard<std::mutex> lock(batchMutex_);

            if (AppGlobals::DebugMode.load() && callNum <= 100) {
                std::cout << "[DEBUG] ProcessAcl #" << callNum << ": Acquired batchMutex_\n";
            }
            currentBatch_.acls.insert(currentBatch_.acls.end(), localBatch.acls.begin(), localBatch.acls.end());
            currentBatch_.aces.insert(currentBatch_.aces.end(), localBatch.aces.begin(), localBatch.aces.end());

            // Make sure all SIDs are properly added to the batch
            for (const auto& sid : localBatch.sids) {
                bool found = false;
                for (const auto& existingSid : currentBatch_.sids) {
                    if (std::get<0>(sid) == std::get<0>(existingSid)) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    currentBatch_.sids.push_back(sid);
                }
            }

            // ARCH-003: Track total folders processed for periodic commits
            int64_t totalProcessed = ++totalFoldersProcessed_;
            int64_t lastCommit = lastPeriodicCommitCount_.load();

            // DatabaseInsertHang.md Recommendation #1: Periodic status logging (every 10k folders)
            if (AppGlobals::DebugMode.load() && totalProcessed % 10000 == 0) {
                std::cout << "[DEBUG] Periodic status at " << totalProcessed
                          << " folders: Batch sizes - ACLs=" << currentBatch_.acls.size()
                          << ", ACEs=" << currentBatch_.aces.size()
                          << ", SIDs=" << currentBatch_.sids.size()
                          << ", lastCommit=" << lastCommit << "\n";
            }

            // Commit batch if it's large enough OR periodic interval reached
            static std::atomic<int> batchCheckCount{0};
            int checkNum = ++batchCheckCount;

            if (AppGlobals::DebugMode.load() && checkNum <= 20) {
                std::cout << "[DEBUG] ProcessAcl check #" << checkNum << ": Batch sizes - ACLs="
                          << currentBatch_.acls.size() << ", ACEs=" << currentBatch_.aces.size()
                          << ", SIDs=" << currentBatch_.sids.size() << " (BATCH_SIZE=" << BATCH_SIZE << ")\n";
            }

            // DatabaseInsertHang.md Recommendation #2: Pre-condition debug
            if (AppGlobals::DebugMode.load() && totalProcessed <= 100) {
                std::cout << "[DEBUG] About to check commit conditions: totalProcessed="
                          << totalProcessed << ", lastCommit=" << lastCommit
                          << ", batchACLs=" << currentBatch_.acls.size()
                          << ", batchACEs=" << currentBatch_.aces.size() << "\n";
            }

            // ARCH-003: Check for periodic commit (every 50k folders)
            bool periodicCommitNeeded = (totalProcessed - lastCommit) >= PERIODIC_COMMIT_INTERVAL;
            bool batchSizeReached = (currentBatch_.acls.size() >= BATCH_SIZE ||
                                    currentBatch_.aces.size() >= BATCH_SIZE ||
                                    currentBatch_.sids.size() >= BATCH_SIZE);

            // DatabaseInsertHang.md Recommendation #2: Post-condition debug
            if (AppGlobals::DebugMode.load() && totalProcessed <= 100) {
                std::cout << "[DEBUG] Commit conditions: periodicCommitNeeded="
                          << (periodicCommitNeeded ? "true" : "false")
                          << ", batchSizeReached=" << (batchSizeReached ? "true" : "false") << "\n";
            }

            if (batchSizeReached || periodicCommitNeeded) {
                if (AppGlobals::DebugMode.load()) {
                    if (batchSizeReached) {
                        std::cout << "[DEBUG] ProcessAcl: Batch size threshold reached, calling CommitBatch\n";
                    }
                    if (periodicCommitNeeded) {
                        std::cout << "[DEBUG] ProcessAcl: Periodic commit needed (processed=" << totalProcessed
                                  << ", last_commit=" << lastCommit << "), calling CommitBatch\n";
                    }
                }

                CommitBatch();
                lastPeriodicCommitCount_.store(totalProcessed);
            }
        }  // ← batchMutex_ lock released here

        // DatabaseInsertHang.md: Debug to confirm we exited critical section
        if (AppGlobals::DebugMode.load() && callNum <= 100) {
            std::cout << "[DEBUG] ProcessAcl #" << callNum << ": Exited batchMutex_ critical section\n";
        }
    }
    catch (const std::exception& e) {
        if (AppGlobals::DebugMode.load()) {
            std::cerr << "[DEBUG] ProcessAcl EXCEPTION for " << FolderUtils::toUtf8(path)
                      << ": " << e.what() << std::endl;
        }
        std::cerr << "Error processing ACL for " << FolderUtils::toUtf8(path) << ": " << e.what() << std::endl;
        LogError(path, "Failed to process ACL", GetLastError());
    }
}

int64_t AclProcessor::GetOrCreateSidId(const std::wstring& sidString, const std::wstring& accountName) {
    static std::atomic<int> sidCallCount{0};
    int callNum = ++sidCallCount;

    // Check if SID is empty
    if (sidString.empty()) {
        stats_.skippedEmptySids++;
        return 0; // Return 0 for empty SIDs
    }

    // DatabaseInsertHang.md: Debug sidCacheMutex_ acquisition
    if (AppGlobals::DebugMode.load() && callNum <= 200) {
        std::wcout << L"[DEBUG] GetOrCreateSidId #" << callNum << L": About to acquire sidCacheMutex_ for SID: "
                   << sidString.substr(0, std::min(sidString.length(), size_t(20))) << L"...\n";
    }

    // Use a single lock for both cache and collectedSids to prevent TOCTOU race and deadlock
    // This fixes both FC-010 (TOCTOU race) and FC-011 (lock ordering violation)
    std::lock_guard<std::mutex> lock(sidCacheMutex_);

    if (AppGlobals::DebugMode.load() && callNum <= 200) {
        std::wcout << L"[DEBUG] GetOrCreateSidId #" << callNum << L": Acquired sidCacheMutex_\n";
    }

    // Check cache first
    auto cacheIt = sidCache_.find(sidString);
    if (cacheIt != sidCache_.end()) {
        if (AppGlobals::DebugMode.load() && callNum <= 200) {
            std::wcout << L"[DEBUG] GetOrCreateSidId #" << callNum << L": Found in cache, returning\n";
        }
        return cacheIt->second;
    }

    // Check collected SIDs
    auto collectedIt = collectedSids_.find(sidString);
    if (collectedIt != collectedSids_.end()) {
        if (AppGlobals::DebugMode.load() && callNum <= 200) {
            std::wcout << L"[DEBUG] GetOrCreateSidId #" << callNum << L": Found in collected, returning\n";
        }
        return collectedIt->second.sidId;
    }

    // Not found anywhere, create new entry
    if (AppGlobals::DebugMode.load() && callNum <= 200) {
        std::wcout << L"[DEBUG] GetOrCreateSidId #" << callNum << L": Creating new SID entry\n";
    }

    int64_t sidId = nextSidId_++;
    SidInfo info;
    info.sidString = sidString;
    info.accountName = accountName;
    info.accountType = DetermineAccountType(accountName);
    info.sidId = sidId;

    // Add to both structures atomically
    collectedSids_[sidString] = info;
    sidCache_[sidString] = sidId;

    stats_.newSids++;

    if (AppGlobals::DebugMode.load() && callNum <= 200) {
        std::wcout << L"[DEBUG] GetOrCreateSidId #" << callNum << L": Created new SID, returning\n";
    }

    return sidId;
}

// Helper method to determine account type based on account name
std::wstring AclProcessor::DetermineAccountType(const std::wstring& accountName) {
    // Default to User
    if (accountName.empty()) {
        return L"User";
    }

    // Check for common group indicators in the account name
    std::wstring lowerName = accountName;
    std::transform(lowerName.begin(), lowerName.end(), lowerName.begin(),
        [](wchar_t c) { return ::towlower(c); });  // Use ::towlower instead of std::towlower

    // Common group indicators
    if (lowerName.find(L"group") != std::wstring::npos ||
        lowerName.find(L"administrators") != std::wstring::npos ||
        lowerName.find(L"users") != std::wstring::npos ||
        lowerName.find(L"guests") != std::wstring::npos ||
        lowerName.find(L"operators") != std::wstring::npos ||
        lowerName.find(L"authenticated users") != std::wstring::npos ||
        lowerName.find(L"everyone") != std::wstring::npos) {
        return L"Group";
    }

    // Special cases for "Other" type
    if (lowerName.find(L"creator owner") != std::wstring::npos ||
        lowerName.find(L"owner rights") != std::wstring::npos) {
        return L"Other";
    }

    return L"User";
}

void AclProcessor::CommitBatch() {
    static std::atomic<int> batchCount{0};
    int currentBatchNum = ++batchCount;

    if (AppGlobals::DebugMode.load()) {
        std::cout << "[DEBUG] CommitBatch #" << currentBatchNum
                  << ": Called with ACLs=" << currentBatch_.acls.size()
                  << ", ACEs=" << currentBatch_.aces.size() << "\n";
    }

    if (currentBatch_.acls.empty() && currentBatch_.aces.empty()) {
        return;
    }

    try {
        if (AppGlobals::DebugMode.load()) {
            std::cout << "[DEBUG] CommitBatch #" << currentBatchNum << ": Calling beginTransaction\n";
        }

        // Begin transaction
        if (!dbCtx_.beginTransaction()) {
            LogError(L"Batch commit", "Failed to begin transaction", GetLastError());
            if (AppGlobals::DebugMode.load()) {
                std::cerr << "[DEBUG] CommitBatch #" << currentBatchNum << ": beginTransaction FAILED\n";
            }
            return;
        }

        if (AppGlobals::DebugMode.load()) {
            std::cout << "[DEBUG] CommitBatch #" << currentBatchNum << ": Transaction begun successfully\n";
        }

        // Insert ACLs
        if (!currentBatch_.acls.empty()) {
            auto stmt = dbCtx_.PrepareStatement(
                "INSERT INTO app__ACL (InventoryID, LocalACLID, LocalFolderID, \"Owner\", \"Group\", "
                "AreAccessRulesProtected, AreAuditRulesProtected, AreAccessRulesCanonical, AreAuditRulesCanonical) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
            );

            for (const auto& acl : currentBatch_.acls) {
                SqliteHelper::Bind(stmt.get(), 1, std::get<0>(acl));  // InventoryID (string)
                SqliteHelper::Bind(stmt.get(), 2, std::get<1>(acl));  // LocalACLID (int64_t)
                SqliteHelper::Bind(stmt.get(), 3, std::get<2>(acl));  // LocalFolderID (int64_t)
                SqliteHelper::Bind(stmt.get(), 4, std::get<3>(acl));  // Owner (int64_t)
                SqliteHelper::Bind(stmt.get(), 5, std::get<4>(acl));  // Group (int64_t)
                SqliteHelper::Bind(stmt.get(), 6, static_cast<int>(std::get<5>(acl) ? 1 : 0));  // AreAccessRulesProtected (bool)
                SqliteHelper::Bind(stmt.get(), 7, static_cast<int>(std::get<6>(acl) ? 1 : 0));  // AreAuditRulesProtected (bool)
                SqliteHelper::Bind(stmt.get(), 8, static_cast<int>(std::get<7>(acl) ? 1 : 0));  // AreAccessRulesCanonical (bool)
                SqliteHelper::Bind(stmt.get(), 9, static_cast<int>(std::get<8>(acl) ? 1 : 0));  // AreAuditRulesCanonical (bool)

                try {
                    SqliteHelper::Exec(stmt.get());
                }
                catch (const std::exception& e) {
                    std::cerr << "Error inserting ACL: " << e.what() << std::endl;
                }

                SqliteHelper::Reset(stmt.get());
            }
        }

        // Insert ACEs
        if (!currentBatch_.aces.empty()) {
            auto stmt = dbCtx_.PrepareStatement(
                "INSERT INTO app__ACE (InventoryID, LocalACEID, LocalFolderID, FileSystemRightsMask, AccessControlType, "
                "IdentitySID, IsInherited, InheritanceFlags, PropagationFlags, InheritedFromLocalID) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            );

            for (const auto& ace : currentBatch_.aces) {
                SqliteHelper::Bind(stmt.get(), 1, std::get<0>(ace));  // InventoryID (string)
                SqliteHelper::Bind(stmt.get(), 2, std::get<1>(ace));  // LocalACEID (int64_t)
                SqliteHelper::Bind(stmt.get(), 3, std::get<2>(ace));  // LocalFolderID (int64_t)
                SqliteHelper::Bind(stmt.get(), 4, static_cast<int64_t>(std::get<3>(ace)));  // FileSystemRightsMask (int64_t)
                SqliteHelper::Bind(stmt.get(), 5, std::get<4>(ace));  // AccessControlType (int)
                SqliteHelper::Bind(stmt.get(), 6, std::get<5>(ace));  // IdentitySID (int64_t)
                SqliteHelper::Bind(stmt.get(), 7, std::get<6>(ace));  // IsInherited (bool)
                SqliteHelper::Bind(stmt.get(), 8, static_cast<int>(std::get<7>(ace)));  // InheritanceFlags (BYTE -> int)
                SqliteHelper::Bind(stmt.get(), 9, static_cast<int>(std::get<8>(ace)));  // PropagationFlags (BYTE -> int)

                // InheritedFromLocalID: Convert 0 to NULL
                int64_t inheritedFromId = std::get<9>(ace);
                if (inheritedFromId == 0) {
                    sqlite3_bind_null(stmt.get(), 10);
                } else {
                    SqliteHelper::Bind(stmt.get(), 10, inheritedFromId);
                }

                try {
                    SqliteHelper::Exec(stmt.get());
                }
                catch (const std::exception& e) {
                    std::cerr << "Error inserting ACE: " << e.what() << std::endl;
                    std::cerr << "  ACE details - LocalFolderID: " << std::get<2>(ace)
                              << ", IdentitySID: " << std::get<5>(ace)
                              << ", InheritedFromLocalID: " << std::get<9>(ace) << std::endl;
                }

                SqliteHelper::Reset(stmt.get());
            }
        }

        // Commit transaction
        if (AppGlobals::DebugMode.load()) {
            std::cout << "[DEBUG] CommitBatch #" << currentBatchNum << ": Calling commitTransaction\n";
        }

        if (!dbCtx_.commitTransaction()) {
            LogError(L"Batch commit", "Failed to commit transaction", GetLastError());
            if (AppGlobals::DebugMode.load()) {
                std::cerr << "[DEBUG] CommitBatch #" << currentBatchNum << ": commitTransaction FAILED\n";
            }
            return;
        }

        if (AppGlobals::DebugMode.load()) {
            std::cout << "[DEBUG] CommitBatch #" << currentBatchNum << ": Commit successful, clearing batch\n";
        }

        // Clear the batch
        currentBatch_.acls.clear();
        currentBatch_.aces.clear();
        // Note: We don't clear sids anymore as they're handled separately

        if (AppGlobals::DebugMode.load()) {
            std::cout << "[DEBUG] CommitBatch #" << currentBatchNum << ": Completed successfully\n";
        }
    }
    catch (const std::exception& e) {
        std::cerr << "Error committing batch: " << e.what() << std::endl;
        if (AppGlobals::DebugMode.load()) {
            std::cerr << "[DEBUG] CommitBatch #" << currentBatchNum << ": Exception caught: " << e.what() << "\n";
        }
        dbCtx_.rollbackTransaction();
    }
}

void AclProcessor::UpdateProgress()
{
    auto now = std::chrono::steady_clock::now();

    // Use a mutex to protect the lastUpdateTime_ member variable
    std::lock_guard<std::mutex> lock(progressMutex_);

    if (now - lastUpdateTime_ < std::chrono::seconds(1)) return;
    lastUpdateTime_ = now;

    auto total = stats_.totalFolders.load();
    auto processed = stats_.processedFolders.load();
    auto failed = stats_.failedFolders.load();
    auto sids = stats_.newSids.load();
    auto acls = stats_.totalAcls.load();
    auto aces = stats_.totalAces.load();

    // FIX NEW-005: Check stall detection using instance variables (protected by progressMutex_)
    // This ensures consistent stall detection regardless of which thread calls UpdateProgress()
    int currentProcessed = static_cast<int>(processed);

    if (currentProcessed == lastProcessedCount_) {
        stallCounter_++;
        // If no progress for 10 updates (10 seconds), log a warning
        if (stallCounter_ >= 10) {
            std::cout << "\nWarning: Processing appears to be stalled. "
                << "Queue size: " << folderQueue_.size()
                << ", Threads: " << workers_.size() << std::endl;
            stallCounter_ = 0; // Reset counter to avoid spamming
        }
    }
    else {
        lastProcessedCount_ = currentProcessed;
        stallCounter_ = 0;
    }

    // Get console width
    int cols = GetConsoleWidth();

    // Build status parts based on available width with locale-formatted numbers
    std::vector<std::string> parts;
    parts.emplace_back("Processing ACLs...");
    parts.emplace_back("Progress: " + FormatNumberWithLocale(processed) + "/" + FormatNumberWithLocale(total));
    parts.emplace_back("Failed: " + FormatNumberWithLocale(failed));
    if (cols > 60) parts.emplace_back("SIDs: " + FormatNumberWithLocale(sids));
    if (cols > 75) parts.emplace_back("ACLs: " + FormatNumberWithLocale(acls));
    if (cols > 90) parts.emplace_back("ACEs: " + FormatNumberWithLocale(aces));

    // Build the status line with separators
    std::string line;
    for (auto& seg : parts) {
        std::string sep = line.empty() ? "" : " | ";
        if ((int)(line.size() + sep.size() + seg.size()) > cols) {
            break;
        }
        line += sep + seg;
    }

    // Update console with progress using reliable line clearing
    PrintProgressLine(line);
}

void AclProcessor::LogError(const std::wstring& path, const std::string& description, int errorCode) {
    try {
        // Use Message column instead of Description
        auto stmt = dbCtx_.PrepareStatement(
            "INSERT INTO app__EventLog (InventoryID, Severity, Source, Message, Path, ErrorCode, ThreadID, AdditionalData, Timestamp) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))"
        );

        SqliteHelper::Bind(stmt.get(), 1, dbCtx_.inventoryID);
        SqliteHelper::Bind(stmt.get(), 2, std::string("ERROR"));
        SqliteHelper::Bind(stmt.get(), 3, std::string("AclProcessor"));
        SqliteHelper::Bind(stmt.get(), 4, description);

        // Convert wide string path to UTF-8 using FolderUtils
        std::string utf8Path = FolderUtils::toUtf8(path);

        SqliteHelper::Bind(stmt.get(), 5, utf8Path);
        SqliteHelper::Bind(stmt.get(), 6, static_cast<int64_t>(errorCode));
        SqliteHelper::Bind(stmt.get(), 7, static_cast<int64_t>(GetCurrentThreadId()));
        SqliteHelper::Bind(stmt.get(), 8, std::string(""));

        SqliteHelper::Exec(stmt.get());
    }
    catch (const std::exception& e) {
        std::cerr << "Error logging to database: " << e.what() << std::endl;
    }
}

void AclProcessor::InitializeSidLookup() {
    std::cout << "Loading existing SIDs from database..." << std::endl;

    try {
        // Load SIDs from both the current inventory and the default inventory
        auto stmt = dbCtx_.PrepareStatement(
            "SELECT SidID, Sid FROM app__SIDs WHERE InventoryID = ? OR InventoryID = '00000000-0000-0000-0000-000000000000'"
        );

        SqliteHelper::Bind(stmt.get(), 1, dbCtx_.inventoryID);

        int count = 0;
        std::lock_guard<std::mutex> lock(sidCacheMutex_);

        // Debug output to see what's happening
        std::cout << "Starting to load SIDs..." << std::endl;
        
        // Make sure we're using the correct loop condition
        int result;
        while ((result = sqlite3_step(stmt.get())) == SQLITE_ROW) {
            int64_t sidId = SqliteHelper::GetInt64(stmt.get(), 0);
            std::wstring sid = SqliteHelper::GetWString(stmt.get(), 1);

            // Only add to cache if not already present
            auto it = sidCache_.find(sid);
            if (it == sidCache_.end()) {
                sidCache_[sid] = sidId;
                count++;
            }

            // Update nextSidId_ to be greater than any existing SID ID
            if (sidId >= nextSidId_) {
                nextSidId_ = sidId + 1;
            }
            
            // Debug output every 1000 SIDs
            if (count % 1000 == 0) {
                std::cout << "Loaded " << count << " SIDs so far..." << std::endl;
            }
        }

        // FIX NEW-020: Throw exception on database error instead of just logging
        if (result != SQLITE_DONE) {
            throw std::runtime_error("SQLite error in InitializeSidLookup: " +
                std::string(sqlite3_errmsg(sqlite3_db_handle(stmt.get()))));
        }

        // Also check for the highest SID ID in the database to ensure we don't have gaps
        auto maxStmt = dbCtx_.PrepareStatement(
            "SELECT MAX(SidID) FROM app__SIDs"
        );

        if (sqlite3_step(maxStmt.get()) == SQLITE_ROW) {
            int64_t maxSidId = SqliteHelper::GetInt64(maxStmt.get(), 0);
            if (maxSidId >= nextSidId_) {
                nextSidId_ = maxSidId + 1;
            }
        }

        std::cout << "Loaded " << count << " SIDs into cache. Next SID ID will be " << nextSidId_ << std::endl;
        if (AppGlobals::DebugMode.load()) {
            std::cout << "[DEBUG] InitializeSidLookup about to return (inside try block)\n";
        }
    }
    catch (const std::exception& e) {
        std::cerr << "Error loading SIDs: " << e.what() << std::endl;
    }
    if (AppGlobals::DebugMode.load()) {
        std::cout << "[DEBUG] InitializeSidLookup returning\n";
    }
}

void AclProcessor::WaitForCompletion() {
    // Signal all worker threads that no more folders will be added
    {
        std::lock_guard<std::mutex> lock(queueMutex_);
        shouldStop_ = true;
    }
    queueCv_.notify_all();

    // Wait for all worker threads to finish
    for (auto& worker : workers_) {
        if (worker.joinable()) {
            worker.join();
        }
    }

    // ARCH-003: Commit any remaining batch items (final commit)
    {
        std::lock_guard<std::mutex> lock(batchMutex_);
        if (AppGlobals::DebugMode.load()) {
            std::cout << "[DEBUG] WaitForCompletion: Final commit - ACLs=" << currentBatch_.acls.size()
                      << ", ACEs=" << currentBatch_.aces.size() << ", SIDs=" << currentBatch_.sids.size() << "\n";
        }
        CommitBatch();
    }

    // Now process all collected SIDs in bulk
    ResolveSidsAndBulkInsert();

    // Final progress update
    UpdateProgress();
    std::cout << "\nProcessing complete!" << std::endl;
}

AclInfo AclProcessor::GetAclInfo(const std::wstring& path) {
    AclInfo aclInfo;
    
    try {
        PSECURITY_DESCRIPTOR pSD = nullptr;
        PACL pDacl = nullptr;
        PSID pOwner = nullptr;
        PSID pGroup = nullptr;
        BOOL daclPresent = FALSE;
        BOOL daclDefaulted = FALSE;
        
        // Trim trailing spaces and dots (Windows API compatibility issue)
        // GetNamedSecurityInfo may fail on paths with trailing spaces/dots
        std::wstring trimmedPath = FolderUtils::TrimPathEnd(path);

        // Prepare path with long path prefix if needed
        std::wstring longPath = trimmedPath;
        if (trimmedPath.length() > MAX_PATH - 12) { // Leave some buffer for filenames
            // Add \\?\ prefix for local paths
            if (trimmedPath.substr(0, 2) != L"\\\\") {
                longPath = L"\\\\?\\" + trimmedPath;
            }
            // Add \\?\UNC\ prefix for network paths (replacing leading \\)
            else {
                longPath = L"\\\\?\\UNC\\" + trimmedPath.substr(2);
            }
        }

        // Log warning if path was modified (trailing spaces/dots detected)
        if (trimmedPath != path) {
            // Only log to event log, not console (to avoid spam)
            LogError(path, "Path has trailing spaces or dots - normalized for API compatibility", 0);
        }

        if (AppGlobals::DebugMode.load()) {
            static std::atomic<int> getAclCallCount{0};
            int callNum = ++getAclCallCount;
            if (callNum <= 10) {
                std::wcout << L"[DEBUG] GetAclInfo call #" << callNum << ": About to call GetNamedSecurityInfoW for: "
                           << longPath << std::endl;
            }
        }

        // Get the security descriptor for the file
        DWORD result = GetNamedSecurityInfoW(
            longPath.c_str(),
            SE_FILE_OBJECT,
            OWNER_SECURITY_INFORMATION | GROUP_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
            &pOwner, &pGroup, &pDacl, nullptr, &pSD
        );

        if (AppGlobals::DebugMode.load()) {
            static std::atomic<int> getAclReturnCount{0};
            int returnNum = ++getAclReturnCount;
            if (returnNum <= 10) {
                std::wcout << L"[DEBUG] GetAclInfo call #" << returnNum << ": GetNamedSecurityInfoW returned with result="
                           << result << std::endl;
            }
        }

        if (result != ERROR_SUCCESS) {
            throw std::runtime_error("Failed to get security info: " + std::to_string(result));
        }
        
        // Use a unique_ptr with custom deleter for PSECURITY_DESCRIPTOR
        std::unique_ptr<void, decltype(&LocalFree)> sdPtr(pSD, LocalFree);
        
        // Get owner SID
        if (pOwner) {
            LPWSTR ownerSid = nullptr;
            if (ConvertSidToStringSidW(pOwner, &ownerSid)) {
                aclInfo.owner = ownerSid;
                LocalFree(ownerSid);
            }
        }
        
        // Get group SID
        if (pGroup) {
            LPWSTR groupSid = nullptr;
            if (ConvertSidToStringSidW(pGroup, &groupSid)) {
                aclInfo.group = groupSid;
                LocalFree(groupSid);
            }
        }

        // Get security descriptor control flags (Protected, Canonical, etc.)
        {
            SECURITY_DESCRIPTOR_CONTROL ctrl = 0;
            DWORD rev = 0;
            if (GetSecurityDescriptorControl(pSD, &ctrl, &rev)) {
                aclInfo.areAccessRulesProtected = (ctrl & SE_DACL_PROTECTED) != 0;
                aclInfo.areAuditRulesProtected = (ctrl & SE_SACL_PROTECTED) != 0;
                aclInfo.areAccessRulesCanonical = (ctrl & SE_DACL_AUTO_INHERITED) != 0;
                aclInfo.areAuditRulesCanonical = (ctrl & SE_SACL_AUTO_INHERITED) != 0;
            }
        }

        // Get DACL information
        if (GetSecurityDescriptorDacl(pSD, &daclPresent, &pDacl, &daclDefaulted) && daclPresent && pDacl) {
            // Get ACL control information
            ACL_SIZE_INFORMATION aclSizeInfo = {0};
            if (GetAclInformation(pDacl, &aclSizeInfo, sizeof(aclSizeInfo), AclSizeInformation)) {

                // Get inheritance source information using GetInheritanceSourceW
                // This tells us exactly which ancestor each ACE was inherited from
                std::vector<INHERITED_FROMW> inheritArray;
                bool haveInheritanceInfo = false;

                if (aclSizeInfo.AceCount > 0 && pOwner != nullptr) {
                    inheritArray.resize(aclSizeInfo.AceCount);
                    memset(inheritArray.data(), 0, aclSizeInfo.AceCount * sizeof(INHERITED_FROMW));

                    GENERIC_MAPPING mapping = {
                        FILE_GENERIC_READ,
                        FILE_GENERIC_WRITE,
                        FILE_GENERIC_EXECUTE,
                        FILE_ALL_ACCESS
                    };

                    // Check if path is a directory
                    DWORD attrs = GetFileAttributesW(longPath.c_str());
                    BOOL isContainer = (attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY));

                    DWORD inheritResult = GetInheritanceSourceW(
                        const_cast<LPWSTR>(longPath.c_str()),
                        SE_FILE_OBJECT,
                        DACL_SECURITY_INFORMATION,
                        isContainer,
                        nullptr,
                        0,
                        pDacl,
                        nullptr,
                        &mapping,
                        inheritArray.data()
                    );

                    if (inheritResult == ERROR_SUCCESS) {
                        haveInheritanceInfo = true;
                    }
                    // Note: Don't log failure - GetInheritanceSourceW can fail on some paths
                    // and that's okay, we'll fall back to parent heuristic
                }

                // Process each ACE in the ACL
                for (DWORD i = 0; i < aclSizeInfo.AceCount; i++) {
                    LPVOID ace = nullptr;
                    if (GetAce(pDacl, i, &ace)) {
                        ACE_HEADER* aceHeader = (ACE_HEADER*)ace;

                        AceInfo aceInfo;
                        aceInfo.isInherited = (aceHeader->AceFlags & INHERITED_ACE) != 0;
                        aceInfo.inheritanceMask = aceHeader->AceFlags & (CONTAINER_INHERIT_ACE | OBJECT_INHERIT_ACE);
                        aceInfo.propagationMask = aceHeader->AceFlags & (INHERIT_ONLY_ACE | NO_PROPAGATE_INHERIT_ACE);

                        // Process different ACE types using optimized lookup table
                        const AceTypeInfo& aceTypeInfo = GetAceTypeInfo(aceHeader->AceType);

                        // Check if ACE type is supported
                        if (!aceTypeInfo.isSupported) {
                            stats_.skippedUnsupportedAceTypes++;
                            std::cerr << "Unsupported ACE type: " << static_cast<int>(aceHeader->AceType) << std::endl;
                            continue;
                        }

                        // FC-005 FIX: Extract access mask using type-safe approach
                        // All standard ACE types (ALLOW, DENY, AUDIT) have Mask at same offset after ACE_HEADER
                        // Using offsetof ensures we read from correct memory location regardless of ACE type
                        DWORD* pMask = (DWORD*)((BYTE*)ace + sizeof(ACE_HEADER));
                        aceInfo.accessMask = *pMask;
                        aceInfo.accessType = aceTypeInfo.type;

                        // FIX NEW-004: Validate sidOffset is within ACE bounds before pointer arithmetic
                        if (aceTypeInfo.sidOffset >= aceHeader->AceSize) {
                            std::cerr << "SID offset exceeds ACE size" << std::endl;
                            stats_.invalidSids++;
                            continue;
                        }

                        // Calculate SID pointer using pre-computed offset
                        PSID sidPtr = (PSID)((BYTE*)ace + aceTypeInfo.sidOffset);

                        // FIX NEW-017: Validate minimum ACE size for SID
                        DWORD minSidSize = sizeof(ACE_HEADER) + sizeof(DWORD) + GetSidLengthRequired(1);
                        if (aceHeader->AceSize < minSidSize) {
                            std::cerr << "ACE too small to contain valid SID, size: " << aceHeader->AceSize << std::endl;
                            stats_.invalidSids++;
                            continue;
                        }

                        // Validate actual SID fits within ACE bounds
                        if (IsValidSid(sidPtr)) {
                            DWORD actualSidLength = GetLengthSid(sidPtr);
                            // FIX: Explicit cast from size_t to DWORD (safe - ACE sizes are small)
                            DWORD requiredAceSize = static_cast<DWORD>(aceTypeInfo.sidOffset) + actualSidLength;
                            if (requiredAceSize > aceHeader->AceSize) {
                                std::cerr << "SID extends beyond ACE bounds" << std::endl;
                                stats_.invalidSids++;
                                continue;
                            }
                        } else {
                            std::cerr << "Invalid SID structure" << std::endl;
                            stats_.invalidSids++;
                            continue;
                        }

                        // Get SID string
                        if (IsValidSid(sidPtr)) {
                            LPWSTR sidString = nullptr;
                            if (ConvertSidToStringSidW(sidPtr, &sidString)) {
                                aceInfo.sidString = sidString;
                                aceInfo.trustee = ResolveSidToAccountName(sidPtr, aceInfo.sidString);
                                LocalFree(sidString);
                            }
                            else {
                                // Handle conversion failure with detailed error info
                                DWORD error = GetLastError();
                                char errorMsg[256] = {0};
                                FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM, NULL, error, 0, errorMsg, sizeof(errorMsg), NULL);
                                
                                std::cerr << "SID conversion failed: " << errorMsg << " (Error " << error << ")" << std::endl;
                                stats_.sidConversionFailures++;
                                
                                // Try alternative approach - manual SID conversion
                                aceInfo.sidString = ManualSidToString(sidPtr);
                                aceInfo.trustee = aceInfo.sidString;
                            }
                            
                            // FIX FC-014: If inherited, determine the path it was inherited from
                            if (aceInfo.isInherited) {
                                // Use GetInheritanceSourceW result if available
                                if (haveInheritanceInfo && i < inheritArray.size() && inheritArray[i].AncestorName != nullptr) {
                                    // GetInheritanceSourceW gives us the exact ancestor path
                                    // Normalize it to match folder index format (no \\?\ prefix, no trailing backslash)
                                    std::wstring ancestorPath = inheritArray[i].AncestorName;
                                    ancestorPath = FolderUtils::removeLongPathPrefix(ancestorPath);

                                    // Remove trailing backslash unless it's a root path
                                    if (ancestorPath.length() > 3 &&
                                        (ancestorPath.back() == L'\\' || ancestorPath.back() == L'/')) {
                                        ancestorPath.pop_back();
                                    }

                                    aceInfo.inheritedFrom = ancestorPath;
                                } else {
                                    // Fallback: Use immediate parent as best-effort heuristic
                                    // This can happen if GetInheritanceSourceW failed or returned no data
                                    std::wstring parentPath = path;
                                    size_t pos = parentPath.find_last_of(L"\\/");
                                    if (pos != std::wstring::npos) {
                                        parentPath = parentPath.substr(0, pos);
                                        aceInfo.inheritedFrom = parentPath;
                                    }
                                }
                            }
                            
                            // Add the ACE to the ACL info
                            aclInfo.aces.push_back(aceInfo);
                        }
                        else {
                            // Log the invalid SID
                            DWORD error = GetLastError();
                            std::cerr << "Invalid SID encountered, error: " << error << std::endl;
                            stats_.invalidSids++;
                            
                            // Use a placeholder or skip
                            aceInfo.sidString = L"S-1-0-0"; // NULL SID as placeholder
                            aceInfo.trustee = L"INVALID_SID";
                            
                            // Add the ACE with placeholder SID
                            aclInfo.aces.push_back(aceInfo);
                        }
                    }
                }

                // Free the inheritance source array if we allocated it
                if (haveInheritanceInfo && !inheritArray.empty()) {
                    FreeInheritedFromArray(inheritArray.data(), static_cast<USHORT>(inheritArray.size()), nullptr);
                }
            }
        }

        // No need to free pSD here as it's managed by the unique_ptr sdPtr
        // LocalFree(pSD); <- REMOVE THIS LINE to avoid double-free

        return aclInfo;
    }
    catch (const std::exception&) {
        //std::wcout << L"[DEBUG] Error getting ACL info for " << path << L": " << e.what() << std::endl;
        throw;
    }
}

std::wstring AclProcessor::ResolveSid(const std::wstring& sidString) {
    // First check the cache
    {
        std::lock_guard<std::mutex> lock(resolvedSidCacheMutex_);
        auto it = resolvedSidCache_.find(sidString);
        if (it != resolvedSidCache_.end()) {
            return it->second;
        }
    }

    // Check well-known SIDs
    auto it = wellKnownSids.find(sidString);
    if (it != wellKnownSids.end()) {
        // Cache the result
        {
            std::lock_guard<std::mutex> lock(resolvedSidCacheMutex_);
            resolvedSidCache_[sidString] = it->second;
        }
        return it->second;
    }

    // Try to convert string SID to binary SID
    PSID sid = nullptr;
    if (!ConvertStringSidToSidW(sidString.c_str(), &sid)) {
        return L"UNKNOWN_" + sidString;
    }

    // Use unique_ptr with custom deleter for PSID
    std::unique_ptr<void, decltype(&LocalFree)> sidPtr(sid, LocalFree);

    // Try to look up the account name
    WCHAR name[256] = { 0 };
    WCHAR domain[256] = { 0 };
    DWORD nameLen = 255;
    DWORD domainLen = 255;
    SID_NAME_USE use;

    if (LookupAccountSidW(nullptr, sid, name, &nameLen, domain, &domainLen, &use)) {
        std::wstring result;
        if (domain[0] != L'\0') {
            result = std::wstring(domain) + L"\\" + std::wstring(name);
        } else {
            result = std::wstring(name);
        }

        // Cache the result
        {
            std::lock_guard<std::mutex> lock(resolvedSidCacheMutex_);
            resolvedSidCache_[sidString] = result;
        }
        return result;
    }

    // If lookup fails, return the SID string
    return sidString;
}

void AclProcessor::ResolveSidsAndBulkInsert() {
    // Copy the collected SIDs to a local vector for processing
    std::vector<SidInfo> sidsToProcess;
    {
        // Use sidCacheMutex_ since it now protects both sidCache_ and collectedSids_
        std::lock_guard<std::mutex> lock(sidCacheMutex_);
        sidsToProcess.reserve(collectedSids_.size());
        for (const auto& pair : collectedSids_) {
            sidsToProcess.push_back(pair.second);
        }
        collectedSids_.clear();
    }

    if (sidsToProcess.empty()) {
        return;
    }

    std::cout << "\nBulk processing " << sidsToProcess.size() << " SIDs..." << std::endl;

    // Resolve account names for SIDs
    for (auto& sidInfo : sidsToProcess) {
        if (sidInfo.accountName.empty()) {
            // Check if it's a well-known SID first
            auto it = wellKnownSids.find(sidInfo.sidString);
            if (it != wellKnownSids.end()) {
                sidInfo.accountName = it->second;
                sidInfo.isResolved = true;
                sidInfo.resolutionSource = L"WellKnown";
            }
            else {
                // Try to resolve via Windows API
                sidInfo.accountName = ResolveSid(sidInfo.sidString);

                // Determine if resolution succeeded
                if (sidInfo.accountName != sidInfo.sidString &&
                    sidInfo.accountName.find(L"UNKNOWN_") == std::wstring::npos) {
                    sidInfo.isResolved = true;
                    // Determine if it's from local SAM or domain
                    if (sidInfo.accountName.find(L"\\") != std::wstring::npos) {
                        std::wstring domain = sidInfo.accountName.substr(0, sidInfo.accountName.find(L"\\"));
                        // Check if it's a domain (not BUILTIN, NT AUTHORITY, etc.)
                        if (domain != L"BUILTIN" && domain != L"NT AUTHORITY" &&
                            domain != L"NT SERVICE" && domain != L"Window Manager") {
                            sidInfo.resolutionSource = L"Domain";
                        }
                        else {
                            sidInfo.resolutionSource = L"Local";
                        }
                    }
                    else {
                        sidInfo.resolutionSource = L"Local";
                    }
                }
                else {
                    sidInfo.isResolved = false;
                    sidInfo.resolutionSource = L"Failed";
                }
            }
        }
        else {
            // Account name was already provided, assume it was resolved locally
            sidInfo.isResolved = true;
            sidInfo.resolutionSource = L"Local";
        }

        // Always recalculate account type based on the final account name
        sidInfo.accountType = DetermineAccountType(sidInfo.accountName);
    }

    int successCount = 0;
    int errorCount = 0;
    int ignoreCount = 0;

    try {
        // Only check schema once, and only in debug mode
        #ifdef _DEBUG
        static bool schemaChecked = false;
        if (!schemaChecked) {
            // First, let's check the database schema to understand constraints
            auto schemaStmt = dbCtx_.PrepareStatement(
                "PRAGMA table_info(app__SIDs)"
            );

            std::cout << "app__SIDs table schema:" << std::endl;
            while (sqlite3_step(schemaStmt.get()) == SQLITE_ROW) {
                std::string colName = SqliteHelper::GetString(schemaStmt.get(), 1);
                std::string colType = SqliteHelper::GetString(schemaStmt.get(), 2);
                int notNull = static_cast<int>(SqliteHelper::GetInt64(schemaStmt.get(), 3));
                std::string defaultVal = SqliteHelper::GetString(schemaStmt.get(), 4);
                int pk = static_cast<int>(SqliteHelper::GetInt64(schemaStmt.get(), 5));

                std::cout << "  " << colName << " (" << colType << ")"
                          << (notNull ? " NOT NULL" : "")
                          << (pk ? " PRIMARY KEY" : "")
                          << (!defaultVal.empty() ? " DEFAULT " + defaultVal : "")
                          << std::endl;
            }

            // Check for indexes/unique constraints
            auto indexStmt = dbCtx_.PrepareStatement(
                "SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='app__SIDs'"
            );

            std::cout << "app__SIDs indexes:" << std::endl;
            while (sqlite3_step(indexStmt.get()) == SQLITE_ROW) {
                std::string indexName = SqliteHelper::GetString(indexStmt.get(), 0);
                std::string indexSql = SqliteHelper::GetString(indexStmt.get(), 1);

                std::cout << "  " << indexName << ": " << indexSql << std::endl;
            }

            schemaChecked = true;
        }
        #endif

        // OPT-001 & OPT-007 FIX: Use INSERT OR IGNORE to avoid redundant SELECT queries
        // This eliminates the SELECT COUNT(*) for each SID, improving performance by 30-50%
        auto stmt = dbCtx_.PrepareStatement(
            "INSERT OR IGNORE INTO app__SIDs (SidID, InventoryID, Sid, AccountName, AccountType, IsResolved, ResolutionSource) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)"
        );

        // Process in larger batches
        const size_t BATCH_SIZE = 1000;
        for (size_t i = 0; i < sidsToProcess.size(); i += BATCH_SIZE) {
            // Begin transaction for this batch
            if (!dbCtx_.beginTransaction()) {
                std::cerr << "Failed to begin transaction for batch starting at index " << i << std::endl;
                continue;  // Skip this batch and try the next one
            }

            // Process batch
            size_t end = std::min(i + BATCH_SIZE, sidsToProcess.size());
            for (size_t j = i; j < end; j++) {
                const auto& sidInfo = sidsToProcess[j];

                // OPT-001: Direct insert with OR IGNORE clause - no need to check existence first
                // If SID already exists (UNIQUE constraint), INSERT OR IGNORE skips it silently
                // This avoids the previous SELECT COUNT(*) + INSERT pattern

                SqliteHelper::Bind(stmt.get(), 1, static_cast<int64_t>(sidInfo.sidId));
                SqliteHelper::Bind(stmt.get(), 2, dbCtx_.inventoryID);
                SqliteHelper::Bind(stmt.get(), 3, sidInfo.sidString);
                SqliteHelper::Bind(stmt.get(), 4, sidInfo.accountName);
                SqliteHelper::Bind(stmt.get(), 5, sidInfo.accountType);
                SqliteHelper::Bind(stmt.get(), 6, static_cast<int>(sidInfo.isResolved ? 1 : 0));
                SqliteHelper::Bind(stmt.get(), 7, sidInfo.resolutionSource);

                try {
                    SqliteHelper::Exec(stmt.get());
                    // Check if row was actually inserted by checking sqlite3_changes()
                    int changes = sqlite3_changes(dbCtx_.db->get());
                    if (changes > 0) {
                        successCount++;
                    } else {
                        // SID already existed, INSERT OR IGNORE skipped it
                        ignoreCount++;
                    }
                }
                catch (const std::exception& e) {
                    std::cerr << "Error inserting SID: " << e.what() << std::endl;
                    std::wcerr << L"  SID: " << sidInfo.sidString << std::endl;
                    std::wcerr << L"  Account: " << sidInfo.accountName << std::endl;
                    std::wcerr << L"  Type: " << sidInfo.accountType << std::endl;
                    std::wcerr << L"  IsResolved: " << (sidInfo.isResolved ? L"true" : L"false") << std::endl;
                    std::wcerr << L"  ResolutionSource: " << sidInfo.resolutionSource << std::endl;
                    errorCount++;
                }

                SqliteHelper::Reset(stmt.get());

                // Show progress periodically
                // if (j % 10 == 0 && j > 0) {
                //     std::cout << "Processed " << j << " of " << sidsToProcess.size() << " SIDs..." << std::endl;
                // }
            }

            // Commit this batch
            if (!dbCtx_.commitTransaction()) {
                std::cerr << "Failed to commit batch starting at index " << i << std::endl;
                dbCtx_.rollbackTransaction();
            }
        }

        std::cout << "SID insertion results: " << std::endl;
        std::cout << "  Successfully inserted: " << successCount << std::endl;
        std::cout << "  Already existed: " << ignoreCount << std::endl;
        std::cout << "  Errors: " << errorCount << std::endl;
    }
    catch (const std::exception& e) {
        std::cerr << "Error during SID bulk insert: " << e.what() << std::endl;
        // Note: Each batch transaction is self-contained, so no rollback needed here
    }
}

// Manual SID to string conversion as fallback
std::wstring AclProcessor::ManualSidToString(PSID sid) {
    if (!sid || !IsValidSid(sid)) {
        return L"";
    }
    
    // Get SID identifier authority
    SID_IDENTIFIER_AUTHORITY* authority = GetSidIdentifierAuthority(sid);
    
    // Start building the SID string
    std::wstringstream ss;
    ss << L"S-" << static_cast<int>(SID_REVISION);
    
    // Add identifier authority
    if (authority->Value[0] || authority->Value[1]) {
        ss << L"-0x";
        for (int i = 0; i < 6; i++) {
            ss << std::hex << std::setw(2) << std::setfill(L'0') 
               << static_cast<int>(authority->Value[i]);
        }
    }
    else {
        ULONG authorityValue = 0;
        for (int i = 2; i < 6; i++) {
            authorityValue = (authorityValue << 8) | authority->Value[i];
        }
        ss << L"-" << authorityValue;
    }
    
    // Add sub-authorities
    UCHAR subAuthorityCount = *GetSidSubAuthorityCount(sid);
    for (UCHAR i = 0; i < subAuthorityCount; i++) {
        DWORD* subAuthority = GetSidSubAuthority(sid, i);
        ss << L"-" << *subAuthority;
    }
    
    return ss.str();
}

// Implement the ResolveSidToAccountName function
std::wstring AclProcessor::ResolveSidToAccountName(PSID sid, const std::wstring& sidString) {
    // Try multiple approaches to resolve the SID
    WCHAR name[256] = { 0 };
    WCHAR domain[256] = { 0 };
    DWORD nameLen = 255;
    DWORD domainLen = 255;
    SID_NAME_USE use;
    
    // Try with different server names
    const wchar_t* serverNames[] = { nullptr, L".", L"localhost", NULL };
    
    for (const wchar_t* server : serverNames) {
        if (server == NULL) break;
        
        nameLen = 255;
        domainLen = 255;
        ZeroMemory(name, sizeof(name));
        ZeroMemory(domain, sizeof(domain));
        
        if (LookupAccountSidW(server, sid, name, &nameLen, domain, &domainLen, &use)) {
            if (domain[0] != L'\0') {
                return std::wstring(domain) + L"\\" + std::wstring(name);
            } else {
                return std::wstring(name);
            }
        }
    }
    
    // If all lookups fail, use our fallback resolver
    return ResolveSid(sidString);
}

// Implementation of GetStatsSnapshot
AclProcessor::StatsSnapshot AclProcessor::GetStatsSnapshot() const {
    AclProcessor::StatsSnapshot snapshot;
    snapshot.processedFolders = stats_.processedFolders.load();
    snapshot.failedFolders = stats_.failedFolders.load();
    snapshot.newSids = stats_.newSids.load();
    snapshot.totalAcls = stats_.totalAcls.load();
    snapshot.totalAces = stats_.totalAces.load();
    snapshot.totalFolders = stats_.totalFolders.load();
    snapshot.skippedEmptySids = stats_.skippedEmptySids.load();
    snapshot.invalidSids = stats_.invalidSids.load();
    snapshot.sidConversionFailures = stats_.sidConversionFailures.load();
    snapshot.skippedUnsupportedAceTypes = stats_.skippedUnsupportedAceTypes.load();
    return snapshot;
}
