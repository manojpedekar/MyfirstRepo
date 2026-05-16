#include "../collectors/SMBShare.h"
#include "../utils/utils.h"
#include "../utils/security_utils.h"
#include "../utils/folderutils.h"
#include "../database/transaction.h"

#include <iostream>
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <memory>
#include <chrono>
#include <regex>

#include <windows.h>
#include <lm.h>
#include <sddl.h>
#include <aclapi.h>

#pragma comment(lib, "netapi32.lib")
#pragma comment(lib, "advapi32.lib")

// Helper function to convert wide string to UTF-8
std::string WideToUtf8(const std::wstring& wide) {
    if (wide.empty()) return "";

    // FIX NEW-013: Check return value from WideCharToMultiByte
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()), nullptr, 0, nullptr, nullptr);
    if (size_needed <= 0) {
        throw std::runtime_error("WideCharToMultiByte size query failed: " + std::to_string(GetLastError()));
    }

    std::string utf8(size_needed, 0);
    int bytesWritten = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()), &utf8[0], size_needed, nullptr, nullptr);
    if (bytesWritten <= 0) {
        throw std::runtime_error("WideCharToMultiByte conversion failed: " + std::to_string(GetLastError()));
    }
    return utf8;
}

// Helper function to convert UTF-8 to wide string
std::wstring Utf8ToWide(const std::string& utf8) {
    if (utf8.empty()) return L"";
    
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), nullptr, 0);
    std::wstring wide(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), &wide[0], size_needed);
    return wide;
}

// Helper class for NET_API_STATUS cleanup
class NetApiBufferGuard {
public:
    explicit NetApiBufferGuard(LPVOID buffer) : buffer_(buffer) {}
    ~NetApiBufferGuard() {
        if (buffer_) {
            NetApiBufferFree(buffer_);
        }
    }
    
private:
    LPVOID buffer_;
};

// Helper class for PSECURITY_DESCRIPTOR cleanup
class SecurityDescriptorGuard {
public:
    explicit SecurityDescriptorGuard(PSECURITY_DESCRIPTOR sd) : sd_(sd) {}
    ~SecurityDescriptorGuard() {
        if (sd_) {
            LocalFree(sd_);
        }
    }
    
private:
    PSECURITY_DESCRIPTOR sd_;
};

// Constructor definition with proper qualification
SMBShareCollector::SMBShareCollector(DatabaseContext& dbCtx, FolderIndex& folderIndex)
    : dbCtx_(dbCtx),
      folderIndex_(folderIndex),  // No const_cast needed - proper non-const reference
      shareCount_(0),
      accessCount_(0)
{
    // Constructor implementation
}

SMBShareCollector::~SMBShareCollector() {
}

bool SMBShareCollector::DiscoverShares(int* shareCount) {
    // Get start time
    auto startTime = std::chrono::high_resolution_clock::now();

    // Get shares (using safe copy structure)
    std::vector<ShareInfoCopy> shares;
    if (!EnumerateShares(false, shares)) {
        std::cerr << "Failed to enumerate shares" << std::endl;

        // Log the error
        LogEvent(
            dbCtx_,
            Logging::Severity::ERR,
            "SMBShareDiscovery",
            "Failed to enumerate shares",
            "",
            GetLastError(),
            GetCurrentThreadId(),
            "",
            dbCtx_.inventoryID
        );

        return false;
    }

    std::cout << "Discovered " << shares.size() << " shares" << std::endl;

    // Process each share
    int successCount = 0;
    for (const auto& share : shares) {
        if (ProcessShare(share, false)) {
            successCount++;
        } else {
            std::cerr << "Failed to process share: " << FolderUtils::toUtf8(share.netname) << std::endl;

            // Log the error
            LogEvent(
                dbCtx_,
                Logging::Severity::WARNING,
                "SMBShareDiscovery",
                "Failed to process share",
                FolderUtils::toUtf8(share.netname),
                GetLastError(),
                GetCurrentThreadId(),
                "",
                dbCtx_.inventoryID
            );
            // Continue with next share
        }
    }

    // If shareCount pointer is provided, store the count
    if (shareCount != nullptr) {
        *shareCount = successCount;
    }

    // Get end time
    auto endTime = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();

    std::cout << "Share discovery completed in " << duration << "ms" << std::endl;
    std::cout << "Successfully processed " << successCount << " out of " << shares.size() << " shares" << std::endl;

    return true;
}

bool SMBShareCollector::CollectShares() {
    // Get start time
    auto startTime = std::chrono::high_resolution_clock::now();

    if (AppGlobals::DebugMode.load()) {
        std::cout << "[DEBUG] CollectShares: Starting share collection\n";
    }

    // Get shares (using safe copy structure)
    std::vector<ShareInfoCopy> shares;
    if (!EnumerateShares(true, shares)) {  // Pass true for collectData and the vector to store shares
        std::cerr << "Failed to enumerate shares" << std::endl;
        return false;
    }

    if (AppGlobals::DebugMode.load()) {
        std::cout << "[DEBUG] CollectShares: Enumerated " << shares.size() << " shares\n";
        std::cout << "[DEBUG] CollectShares: About to process shares\n";
    }

    // Process each share
    int shareIndex = 0;
    for (const auto& share : shares) {
        if (AppGlobals::DebugMode.load()) {
            std::cout << "[DEBUG] CollectShares: Processing share " << (shareIndex + 1)
                      << "/" << shares.size() << ": " << FolderUtils::toUtf8(share.netname) << "\n";
        }

        if (!ProcessShare(share, true)) {
            std::cerr << "Failed to process share: " << FolderUtils::toUtf8(share.netname) << std::endl;
            if (AppGlobals::DebugMode.load()) {
                std::cerr << "[DEBUG] CollectShares: Failed at share index " << shareIndex << "\n";
            }
            // Continue with next share
        }
        shareIndex++;
    }

    if (AppGlobals::DebugMode.load()) {
        std::cout << "[DEBUG] CollectShares: All shares processed successfully\n";
    }

    // Get end time
    auto endTime = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();

    return true;
}

bool SMBShareCollector::EnumerateShares(bool collectData, std::vector<ShareInfoCopy>& shares) {
    DWORD entriesRead = 0;
    DWORD totalEntries = 0;
    DWORD resumeHandle = 0;
    SHARE_INFO_502* pShareInfo = nullptr;
    NET_API_STATUS nStatus;

    do {
        // Call NetShareEnum to get share information
        nStatus = NetShareEnum(
            nullptr,                // Local computer
            502,                    // Level 502 for detailed share info
            (LPBYTE*)&pShareInfo,   // Buffer to receive data
            MAX_PREFERRED_LENGTH,   // Preferred maximum length
            &entriesRead,           // Number of entries read
            &totalEntries,          // Total number of entries
            &resumeHandle           // Resume handle
        );

        // Check if the call was successful or partially successful
        if (nStatus == NERR_Success || nStatus == ERROR_MORE_DATA) {
            // Deep copy each share BEFORE freeing the buffer
            // This fixes SEC-002: Use-After-Free vulnerability
            for (DWORD i = 0; i < entriesRead; i++) {
                shares.emplace_back(pShareInfo[i]);  // Constructs ShareInfoCopy with deep copy
            }

            // Now safe to free the NetAPI buffer
            NetApiBufferFree(pShareInfo);
        } else {
            std::cerr << "NetShareEnum failed with error: " << nStatus << std::endl;
            return false;
        }
    } while (nStatus == ERROR_MORE_DATA);

    return true;
}

bool SMBShareCollector::ProcessShare(const ShareInfoCopy& shareInfo, bool collectData) {
    // Extract share name and path from safe copy
    std::wstring shareName = shareInfo.netname;
    std::wstring sharePath = shareInfo.path;

    // FIX: Skip IPC$ and ADMIN$ in BOTH discovery and collection modes
    // These special shares either have no filesystem path (IPC$) or point to
    // system directories that may cause validation issues (ADMIN$)
    if (shareName == L"IPC$" || shareName == L"ADMIN$") {
        if (AppGlobals::DebugMode.load()) {
            std::cout << "[DEBUG] Skipping special share: " << WideToUtf8(shareName) << "\n";
        }
        return true;  // Skip these shares entirely
    }

    if (!collectData) {
        // Discovery mode - add the path to the folder index and database
        if (sharePath.empty() || IsSpecialShare(shareName)) {
            // Skip empty paths or other special shares like C$, D$, etc.
            return true;
        }
        
        // Convert backslashes to forward slashes if needed
        std::replace(sharePath.begin(), sharePath.end(), L'/', L'\\');

        // Ensure path ends with backslash
        if (sharePath.back() != L'\\') {
            sharePath += L'\\';
        }

        // FC-010 FIX: Validate and sanitize share path before use
        // Share paths come from NetShareEnum API and could be malicious or malformed

        // 1. Check for excessive length (prevent DoS via memory exhaustion)
        constexpr size_t MAX_SHARE_PATH_LENGTH = 32767; // Windows maximum path length
        if (sharePath.length() > MAX_SHARE_PATH_LENGTH) {
            std::cerr << "FC-010: Share path rejected - exceeds maximum length: "
                      << FolderUtils::toUtf8(shareName) << std::endl;
            return true; // Non-fatal, skip this share
        }

        // 2. Check for path traversal sequences (..\\ or /../)
        if (SecurityUtils::isPathTraversal(sharePath)) {
            std::cerr << "FC-010: Share path rejected - contains path traversal: "
                      << FolderUtils::toUtf8(shareName) << std::endl;
            return true; // Non-fatal, skip this share
        }

        // 3. Check for invalid Windows path characters (except drive letter colon)
        // Invalid chars: < > " | ? *
        static const std::wregex invalidPathChars(L"[<>\"|?*]");
        if (std::regex_search(sharePath, invalidPathChars)) {
            std::cerr << "FC-010: Share path rejected - contains invalid characters: "
                      << FolderUtils::toUtf8(shareName) << std::endl;
            return true; // Non-fatal, skip this share
        }

        // 4. Sanitize the path (remove any remaining unsafe sequences)
        sharePath = SecurityUtils::sanitizePath(sharePath);

        // 5. Final validation - ensure path is not empty after sanitization
        if (sharePath.empty()) {
            std::cerr << "FC-010: Share path empty after sanitization: "
                      << FolderUtils::toUtf8(shareName) << std::endl;
            return true; // Non-fatal, skip this share
        }

        try {
            // Now safe to add the path to the folder index
            int64_t folderId = folderIndex_.getOrAssignId(sharePath);
            
            // Insert the folder path into the database
            if (!InsertFolderPath(folderId, sharePath)) {
                std::cerr << "Failed to insert folder path for share: " << FolderUtils::toUtf8(shareName) << std::endl;
                // Continue anyway - this is non-fatal
            }
            
            // Store the path for later reference
            sharePathMap_[sharePath] = 0; // We'll update the ID during collection
        }
        catch (const std::exception& e) {
            std::cerr << "Exception processing share path: " << FolderUtils::toUtf8(shareName) 
                      << " - " << e.what() << std::endl;
            // Continue anyway - this is non-fatal
        }
        
        return true;
    }
    
    // Collection mode - process the share and store in database
    
    // Create SMBShareInfo structure
    SMBShareInfo info;
    info.name = shareName;
    info.path = sharePath;
    info.description = shareInfo.remark;
    info.type = ShareTypeToString(shareInfo.type);
    info.allowMaximum = (shareInfo.max_uses == static_cast<DWORD>(-1));
    info.maximumAllowed = shareInfo.max_uses;
    info.isHidden = (shareName.back() == L'$');
    info.isSpecial = IsSpecialShare(shareName);
    info.status = L"Online"; // Default status
    
    // Get advanced share information using PowerShell
    if (!GetAdvancedShareInfo(shareName, info)) {
        // If we can't get advanced info, use defaults
        info.isEncrypted = false;
        info.isContinuous = false;
        info.scopeName = L"";
        info.owningNode = L"";
        info.folderEnumerationMode = L"AccessBased"; // Default
        info.cachingMode = L"Manual"; // Default
        info.branchCacheEnabled = false;
        info.leasingMode = L"None"; // Default
        // FIX FC-026: Look up actual volume ID from share path instead of hardcoding 0
        info.volumeId = GetVolumeIdFromPath(info.path);
        info.createdDate = L"";
        info.modifiedDate = L"";
        info.currentUsers = 0;
        info.isBranchCacheEnabled = false;
    }
    
    // Get security descriptor
    info.securityDescriptor = GetShareSecurityDescriptor(shareName);
    
    // Get folder ID from path
    int64_t folderId = GetFolderIdFromPath(info.path);
    if (folderId == -1) {
        std::cerr << "Warning: Could not find folder ID for path: " << WideToUtf8(info.path) << std::endl;
        // We'll still insert the share, but with a placeholder folder ID
    }

    if (AppGlobals::DebugMode.load()) {
        std::cout << "[DEBUG] ProcessShare: About to insert share '" << WideToUtf8(shareName)
                  << "' (folderId=" << folderId << ")\n";
    }

    // Insert share into database
    int shareId = shareCount_.fetch_add(1) + 1;
    if (!InsertShare(shareId, info)) {
        std::cerr << "Failed to insert share: " << WideToUtf8(shareName) << std::endl;
        if (AppGlobals::DebugMode.load()) {
            std::cerr << "[DEBUG] ProcessShare: InsertShare FAILED for '" << WideToUtf8(shareName) << "'\n";
        }
        return false;
    }

    if (AppGlobals::DebugMode.load()) {
        std::cout << "[DEBUG] ProcessShare: InsertShare succeeded for '" << WideToUtf8(shareName)
                  << "' (shareId=" << shareId << ")\n";
    }

    // Update the share path map with the actual share ID
    sharePathMap_[info.path] = shareId;

    if (AppGlobals::DebugMode.load()) {
        std::cout << "[DEBUG] ProcessShare: About to process security descriptor for '"
                  << WideToUtf8(shareName) << "' (length=" << info.securityDescriptor.length() << ")\n";
    }

    // Process security descriptor to extract permissions
    if (!info.securityDescriptor.empty()) {
        if (!ProcessShareSecurity(shareName, shareId, info.securityDescriptor)) {
            std::cerr << "Failed to process security for share: " << WideToUtf8(shareName) << std::endl;
            if (AppGlobals::DebugMode.load()) {
                std::cerr << "[DEBUG] ProcessShare: ProcessShareSecurity FAILED for '"
                          << WideToUtf8(shareName) << "'\n";
            }
            // Continue anyway, we at least have the share information
        } else {
            if (AppGlobals::DebugMode.load()) {
                std::cout << "[DEBUG] ProcessShare: ProcessShareSecurity succeeded for '"
                          << WideToUtf8(shareName) << "'\n";
            }
        }
    } else {
        if (AppGlobals::DebugMode.load()) {
            std::cout << "[DEBUG] ProcessShare: No security descriptor for '" << WideToUtf8(shareName) << "'\n";
        }
    }

    if (AppGlobals::DebugMode.load()) {
        std::cout << "[DEBUG] ProcessShare: Completed successfully for '" << WideToUtf8(shareName) << "'\n";
    }

    return true;
}

int SMBShareCollector::GetVolumeIdFromPath(const std::wstring& sharePath) {
    // FIX FC-026: Implement actual volume lookup instead of returning 0

    // Skip empty paths or special shares without paths
    if (sharePath.empty()) {
        return 0;
    }

    // Use GetVolumePathName to find the volume mount point for this path
    wchar_t volumePath[MAX_PATH];
    if (!GetVolumePathNameW(sharePath.c_str(), volumePath, MAX_PATH)) {
        std::cerr << "GetVolumePathNameW failed for path: " << WideToUtf8(sharePath)
                  << " Error: " << GetLastError() << std::endl;
        return 0;
    }

    // Ensure trailing backslash for consistency
    std::wstring volumePathStr = volumePath;
    if (!volumePathStr.empty() && volumePathStr.back() != L'\\') {
        volumePathStr += L'\\';
    }

    // Query database to find volume with matching mount point
    try {
        auto stmt = dbCtx_.PrepareStatement(
            "SELECT v.VolumeID FROM app__Volumes v "
            "INNER JOIN app__VolumeMounts mp ON v.VolumeID = mp.VolumeID "
            "WHERE v.InventoryID = ? AND mp.InventoryID = ? AND mp.MountPoint = ? "
            "LIMIT 1"
        );

        std::string utf8VolumePath = WideToUtf8(volumePathStr);
        sqlite3_bind_text(stmt.get(), 1, dbCtx_.inventoryID.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt.get(), 2, dbCtx_.inventoryID.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt.get(), 3, utf8VolumePath.c_str(), -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt.get()) == SQLITE_ROW) {
            return sqlite3_column_int(stmt.get(), 0);
        }
    }
    catch (const std::exception& e) {
        std::cerr << "Exception looking up volume ID for path: " << WideToUtf8(sharePath)
                  << " - " << e.what() << std::endl;
    }

    // Volume not found in database
    return 0;
}

bool SMBShareCollector::GetAdvancedShareInfo(const std::wstring& shareName, SMBShareInfo& shareInfo) {
    // FC-009 FIX: Return NULL for advanced SMB fields that require PowerShell Get-SmbShare
    //
    // Advanced SMB 3.x features (encryption, leasing, caching modes) are only available
    // through PowerShell's Get-SmbShare cmdlet or Windows Server storage management APIs.
    // Rather than hardcoding false/default values (which is misleading), we explicitly
    // leave these fields as NULL to indicate "unknown".
    //
    // To implement actual collection, one would need to:
    // 1. Use PowerShell COM automation (IWSMan) to call Get-SmbShare
    // 2. Parse PowerShell output (XML or JSON format)
    // 3. Populate fields with actual values
    //
    // For now, leave advanced fields as std::nullopt (NULL in database)

    // Basic fields that can be set from existing data
    shareInfo.scopeName = L"";       // DFS namespace scope (empty if not DFS)
    shareInfo.owningNode = L"";      // Cluster node name (empty if not clustered)

    // FIX FC-026: Look up actual volume ID from share path instead of hardcoding 0
    shareInfo.volumeId = GetVolumeIdFromPath(shareInfo.path);

    // Date fields (empty if not available from NetShareGetInfo)
    shareInfo.createdDate = L"";
    shareInfo.modifiedDate = L"";

    // FC-009: Advanced fields left as std::nullopt (NULL in database)
    // - isEncrypted: std::nullopt (unknown)
    // - isContinuous: std::nullopt (unknown)
    // - folderEnumerationMode: std::nullopt (unknown)
    // - cachingMode: std::nullopt (unknown)
    // - branchCacheEnabled: std::nullopt (unknown)
    // - leasingMode: std::nullopt (unknown)
    // - currentUsers: std::nullopt (unknown)
    // - isBranchCacheEnabled: std::nullopt (unknown)

    return true;
}

std::wstring SMBShareCollector::GetShareSecurityDescriptor(const std::wstring& shareName) {
    PSECURITY_DESCRIPTOR pSD = nullptr;
    DWORD sdSize = 0;
    PSID pOwner = nullptr;
    PSID pGroup = nullptr;
    PACL pDacl = nullptr;
    PACL pSacl = nullptr;
    
    // Format the share name properly for GetNamedSecurityInfoW
    // It needs to be in the format "\\ServerName\ShareName"
    std::wstring formattedShareName;
    if (shareName.find(L"\\\\") == 0) {
        // Already in UNC format
        formattedShareName = shareName;
    } else {
        // Local share, prepend with server name
        wchar_t computerName[MAX_COMPUTERNAME_LENGTH + 1];
        DWORD size = MAX_COMPUTERNAME_LENGTH + 1;
        if (GetComputerNameW(computerName, &size)) {
            // FIX NEW-014: Validate that size is within buffer bounds
            // GetComputerNameW sets size to the length (excluding null terminator)
            if (size <= MAX_COMPUTERNAME_LENGTH) {
                // Ensure null termination (should already be terminated by API, but be defensive)
                computerName[size] = L'\0';
                formattedShareName = L"\\\\" + std::wstring(computerName) + L"\\" + shareName;
            } else {
                // Size exceeds buffer (should never happen with correct API usage)
                std::cerr << "GetComputerNameW returned size larger than buffer: " << size << std::endl;
                formattedShareName = L"\\\\localhost\\" + shareName;
            }
        } else {
            // Fallback to localhost if computer name can't be retrieved
            formattedShareName = L"\\\\localhost\\" + shareName;
        }
    }
    
    // Get security descriptor
    DWORD result = GetNamedSecurityInfoW(
        formattedShareName.c_str(),
        SE_LMSHARE,
        DACL_SECURITY_INFORMATION | OWNER_SECURITY_INFORMATION | GROUP_SECURITY_INFORMATION,
        &pOwner,
        &pGroup,
        &pDacl,
        &pSacl,
        &pSD
    );
    
    if (result != ERROR_SUCCESS) {
        std::cerr << "GetNamedSecurityInfoW failed with error: " << result 
                  << " for share: " << FolderUtils::toUtf8(formattedShareName) << std::endl;
        return L"";
    }
    
    // Convert security descriptor to SDDL string
    LPWSTR sddlString = nullptr;
    if (!ConvertSecurityDescriptorToStringSecurityDescriptorW(
        pSD,
        SDDL_REVISION_1,
        OWNER_SECURITY_INFORMATION | GROUP_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
        &sddlString,
        nullptr
    )) {
        std::cerr << "ConvertSecurityDescriptorToStringSecurityDescriptorW failed with error: " << GetLastError() << std::endl;
        LocalFree(pSD);
        return L"";
    }
    
    // Copy SDDL string
    std::wstring securityDescriptor = sddlString;
    
    // Free resources
    LocalFree(sddlString);
    LocalFree(pSD);
    
    return securityDescriptor;
}

bool SMBShareCollector::ProcessShareSecurity(const std::wstring& shareName, int shareId, const std::wstring& securityDescriptor) {
    PSECURITY_DESCRIPTOR pSD = nullptr;
    ULONG sdSize = 0;
    
    // Convert SDDL string to security descriptor
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
        securityDescriptor.c_str(),
        SDDL_REVISION_1,
        &pSD,
        &sdSize
    )) {
        std::cerr << "ConvertStringSecurityDescriptorToSecurityDescriptorW failed with error: " << GetLastError() << std::endl;
        return false;
    }
    
    // Create guard to ensure security descriptor is freed
    SecurityDescriptorGuard guard(pSD);
    
    // Get DACL from security descriptor
    PACL pDacl = nullptr;
    BOOL daclPresent = FALSE;
    BOOL daclDefaulted = FALSE;
    
    if (!GetSecurityDescriptorDacl(pSD, &daclPresent, &pDacl, &daclDefaulted)) {
        std::cerr << "GetSecurityDescriptorDacl failed with error: " << GetLastError() << std::endl;
        return false;
    }
    
    if (!daclPresent || !pDacl) {
        // No DACL present, nothing to process
        return true;
    }
    
    // Process each ACE in the DACL
    ACL_SIZE_INFORMATION aclInfo;
    if (!GetAclInformation(pDacl, &aclInfo, sizeof(aclInfo), AclSizeInformation)) {
        std::cerr << "GetAclInformation failed with error: " << GetLastError() << std::endl;
        return false;
    }
    
    for (DWORD i = 0; i < aclInfo.AceCount; i++) {
        LPVOID pAce = nullptr;
        if (!GetAce(pDacl, i, &pAce)) {
            std::cerr << "GetAce failed with error: " << GetLastError() << std::endl;
            continue;
        }
        
        ACCESS_ALLOWED_ACE* pAllowedAce = static_cast<ACCESS_ALLOWED_ACE*>(pAce);
        PSID pSid = reinterpret_cast<PSID>(&pAllowedAce->SidStart);
        
        // Convert SID to string
        LPWSTR sidString = nullptr;
        if (!ConvertSidToStringSidW(pSid, &sidString)) {
            std::cerr << "ConvertSidToStringSidW failed with error: " << GetLastError() << std::endl;
            continue;
        }
        
        // Create guard to ensure SID string is freed
        std::unique_ptr<wchar_t, decltype(&LocalFree)> sidGuard(sidString, LocalFree);
        
        // Create access info
        SMBShareAccessInfo accessInfo;
        accessInfo.sid = sidString;
        accessInfo.accessMask = pAllowedAce->Mask;
        accessInfo.isInherited = (pAllowedAce->Header.AceFlags & INHERITED_ACE) != 0;
        
        // Determine access type based on ACE type
        switch (pAllowedAce->Header.AceType) {
            case ACCESS_ALLOWED_ACE_TYPE:
                accessInfo.accessType = L"Allow";
                break;
            case ACCESS_DENIED_ACE_TYPE:
                accessInfo.accessType = L"Deny";
                break;
            default:
                accessInfo.accessType = L"Unknown";
                break;
        }
        
        // Insert share access
        int accessId = accessCount_.fetch_add(1) + 1;
        if (!InsertShareAccess(shareId, accessId, accessInfo)) {
            std::cerr << "Failed to insert share access for SID: " << WideToUtf8(accessInfo.sid) << std::endl;
            // Continue with next ACE
        }
    }
    
    return true;
}

int64_t SMBShareCollector::GetOrCreateSidId(const std::wstring& sid) {
    // Check cache first
    {
        std::lock_guard<std::mutex> lock(sidCacheMutex_);
        auto it = sidCache_.find(sid);
        if (it != sidCache_.end()) {
            return it->second;
        }
    }
    
    // FIX FC-025: Query database with InventoryID filter to prevent cross-inventory SID reuse
    std::string utf8Sid = WideToUtf8(sid);
    auto stmt = dbCtx_.PrepareStatement("SELECT SidID FROM app__SIDs WHERE Sid = ? AND InventoryID = ?");
    sqlite3_bind_text(stmt.get(), 1, utf8Sid.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt.get(), 2, dbCtx_.inventoryID.c_str(), -1, SQLITE_TRANSIENT);

    if (sqlite3_step(stmt.get()) == SQLITE_ROW) {
        int64_t sidId = sqlite3_column_int64(stmt.get(), 0);
        
        // Add to cache
        std::lock_guard<std::mutex> lock(sidCacheMutex_);
        sidCache_[sid] = sidId;
        
        return sidId;
    }
    
    // SID not found, create it
    int64_t newSidId = dbCtx_.GetNextId("app__SIDs", "SidID");
    
    auto insertStmt = dbCtx_.PrepareStatement(
        "INSERT INTO app__SIDs (InventoryID, SidID, Sid, AccountName, AccountType, IsResolved, ResolutionSource) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)"
    );

    sqlite3_bind_text(insertStmt.get(), 1, dbCtx_.inventoryID.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(insertStmt.get(), 2, newSidId);
    sqlite3_bind_text(insertStmt.get(), 3, utf8Sid.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(insertStmt.get(), 4, "", -1, SQLITE_STATIC);  // Empty account name
    sqlite3_bind_text(insertStmt.get(), 5, "Other", -1, SQLITE_STATIC);  // Default type
    sqlite3_bind_int(insertStmt.get(), 6, 0);  // Not resolved
    sqlite3_bind_text(insertStmt.get(), 7, "Failed", -1, SQLITE_STATIC);  // Failed resolution
    
    if (sqlite3_step(insertStmt.get()) != SQLITE_DONE) {
        std::cerr << "Failed to insert SID: " << utf8Sid << std::endl;
        return -1;
    }
    
    // Add to cache
    std::lock_guard<std::mutex> lock(sidCacheMutex_);
    sidCache_[sid] = newSidId;
    
    return newSidId;
}

int64_t SMBShareCollector::GetFolderIdFromPath(const std::wstring& path) {
    // Use folder index to get folder ID
    return folderIndex_.getId(path);
}

bool SMBShareCollector::InsertShare(int shareId, const SMBShareInfo& shareInfo) {
    try {
        // Get folder ID
        int64_t folderId = GetFolderIdFromPath(shareInfo.path);

        // FIX: getId() returns 0 for not found, not -1. Check for <= 0 and non-empty path
        // Also ensure we don't try to create a folder for an empty path
        if (folderId <= 0 && !shareInfo.path.empty()) {
            // Try to add it now
            folderId = folderIndex_.getOrAssignId(shareInfo.path);
            if (!InsertFolderPath(folderId, shareInfo.path)) {
                std::cerr << "Warning: Failed to insert folder path for share: "
                          << FolderUtils::toUtf8(shareInfo.name) << std::endl;
                // Continue anyway - use the folder ID we got
            }
        }

        // If path is empty or folder still not created, use NULL instead of 0
        // This prevents FK validation errors for shares without filesystem paths
        bool hasValidFolderId = (folderId > 0);

        // Prepare statement - ensure we have all 25 columns from the schema
        auto stmt = dbCtx_.PrepareStatement(
            "INSERT INTO app__SMBShares ("
            "InventoryID, ShareID, Name, Path, Description, Type, AllowMaximum, MaximumAllowed, "
            "IsHidden, IsSpecial, Status, IsEncrypted, IsContinuous, ScopeName, OwningNode, "
            "FolderEnumerationMode, CachingMode, BranchCacheEnabled, LeasingMode, VolumeID, "
            "CreatedDate, ModifiedDate, SecurityDescriptor, CurrentUsers, IsBranchCacheEnabled"
            ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        );
        
        // Bind all 25 parameters
        int paramIndex = 1;
        sqlite3_bind_text(stmt.get(), paramIndex++, dbCtx_.inventoryID.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt.get(), paramIndex++, shareId);
        sqlite3_bind_text16(stmt.get(), paramIndex++, shareInfo.name.c_str(), -1, SQLITE_TRANSIENT);
        // DB-001 FIX: Bind folderId (INTEGER) not path string to match schema
        // Schema defines Path as INTEGER with FK to app__Folders.LocalFolderID
        // FIX: Use NULL instead of 0 for shares without valid folder references
        if (hasValidFolderId) {
            sqlite3_bind_int64(stmt.get(), paramIndex++, folderId);
        } else {
            sqlite3_bind_null(stmt.get(), paramIndex++);
        }
        sqlite3_bind_text16(stmt.get(), paramIndex++, shareInfo.description.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text16(stmt.get(), paramIndex++, shareInfo.type.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt.get(), paramIndex++, shareInfo.allowMaximum ? 1 : 0);
        // Bind MaximumAllowed - use NULL if allowMaximum is true (unlimited) or value is 0
        if (shareInfo.allowMaximum || shareInfo.maximumAllowed == 0) {
            sqlite3_bind_null(stmt.get(), paramIndex++);
        } else {
            sqlite3_bind_int(stmt.get(), paramIndex++, shareInfo.maximumAllowed);
        }
        sqlite3_bind_int(stmt.get(), paramIndex++, shareInfo.isHidden ? 1 : 0);
        sqlite3_bind_int(stmt.get(), paramIndex++, shareInfo.isSpecial ? 1 : 0);
        sqlite3_bind_text16(stmt.get(), paramIndex++, shareInfo.status.c_str(), -1, SQLITE_TRANSIENT);

        // FC-009: Bind std::optional fields as NULL if not set
        if (shareInfo.isEncrypted.has_value()) {
            sqlite3_bind_int(stmt.get(), paramIndex++, shareInfo.isEncrypted.value() ? 1 : 0);
        } else {
            sqlite3_bind_null(stmt.get(), paramIndex++);
        }

        if (shareInfo.isContinuous.has_value()) {
            sqlite3_bind_int(stmt.get(), paramIndex++, shareInfo.isContinuous.value() ? 1 : 0);
        } else {
            sqlite3_bind_null(stmt.get(), paramIndex++);
        }

        sqlite3_bind_text16(stmt.get(), paramIndex++, shareInfo.scopeName.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text16(stmt.get(), paramIndex++, shareInfo.owningNode.c_str(), -1, SQLITE_TRANSIENT);

        if (shareInfo.folderEnumerationMode.has_value()) {
            sqlite3_bind_text16(stmt.get(), paramIndex++, shareInfo.folderEnumerationMode.value().c_str(), -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt.get(), paramIndex++);
        }

        if (shareInfo.cachingMode.has_value()) {
            sqlite3_bind_text16(stmt.get(), paramIndex++, shareInfo.cachingMode.value().c_str(), -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt.get(), paramIndex++);
        }

        if (shareInfo.branchCacheEnabled.has_value()) {
            sqlite3_bind_int(stmt.get(), paramIndex++, shareInfo.branchCacheEnabled.value() ? 1 : 0);
        } else {
            sqlite3_bind_null(stmt.get(), paramIndex++);
        }

        if (shareInfo.leasingMode.has_value()) {
            sqlite3_bind_text16(stmt.get(), paramIndex++, shareInfo.leasingMode.value().c_str(), -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt.get(), paramIndex++);
        }

        // FIX: Use NULL instead of 0 for shares without valid volume references
        if (shareInfo.volumeId > 0) {
            sqlite3_bind_int(stmt.get(), paramIndex++, shareInfo.volumeId);
        } else {
            sqlite3_bind_null(stmt.get(), paramIndex++);
        }
        sqlite3_bind_text16(stmt.get(), paramIndex++, shareInfo.createdDate.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text16(stmt.get(), paramIndex++, shareInfo.modifiedDate.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text16(stmt.get(), paramIndex++, shareInfo.securityDescriptor.c_str(), -1, SQLITE_TRANSIENT);

        if (shareInfo.currentUsers.has_value()) {
            sqlite3_bind_int(stmt.get(), paramIndex++, shareInfo.currentUsers.value());
        } else {
            sqlite3_bind_null(stmt.get(), paramIndex++);
        }

        if (shareInfo.isBranchCacheEnabled.has_value()) {
            sqlite3_bind_int(stmt.get(), paramIndex++, shareInfo.isBranchCacheEnabled.value() ? 1 : 0);
        } else {
            sqlite3_bind_null(stmt.get(), paramIndex++);
        }
        
        // Execute statement
        int result = sqlite3_step(stmt.get());
        if (result != SQLITE_DONE) {
            std::string errorMsg = "Error inserting share: ";
            errorMsg += sqlite3_errmsg(dbCtx_.db->get());
            throw std::runtime_error(errorMsg);
        }
        
        return true;
    }
    catch (const std::exception& e) {
        std::cerr << "Exception inserting share: " << e.what() << std::endl;
        return false;
    }
}

bool SMBShareCollector::InsertShareAccess(int shareId, int accessId, const SMBShareAccessInfo& accessInfo) {
    // Get or create SID ID for the trustee
    int64_t sidId = GetOrCreateSidId(accessInfo.sid);
    if (sidId < 0) {
        std::cerr << "Failed to get/create SID for share access" << std::endl;
        return false;
    }

    // Prepare statement
    auto stmt = dbCtx_.PrepareStatement(
        "INSERT INTO app__SMBShareAccess ("
        "InventoryID, ShareID, AccessID, Trustee, AccessType, AccessMask, IsInherited"
        ") VALUES (?, ?, ?, ?, ?, ?, ?)"
    );

    if (!stmt) {
        std::cerr << "Failed to prepare statement for share access insertion" << std::endl;
        return false;
    }

    // Bind parameters (Trustee is now SidID instead of SID string)
    if (sqlite3_bind_text(stmt.get(), 1, dbCtx_.inventoryID.c_str(), -1, SQLITE_TRANSIENT) != SQLITE_OK ||
        sqlite3_bind_int(stmt.get(), 2, shareId) != SQLITE_OK ||
        sqlite3_bind_int(stmt.get(), 3, accessId) != SQLITE_OK ||
        sqlite3_bind_int64(stmt.get(), 4, sidId) != SQLITE_OK ||
        sqlite3_bind_text16(stmt.get(), 5, accessInfo.accessType.c_str(), -1, SQLITE_TRANSIENT) != SQLITE_OK ||
        sqlite3_bind_int(stmt.get(), 6, accessInfo.accessMask) != SQLITE_OK ||
        sqlite3_bind_int(stmt.get(), 7, accessInfo.isInherited ? 1 : 0) != SQLITE_OK) {
        std::cerr << "Failed to bind parameters for share access insertion" << std::endl;
        return false;
    }

    // Execute statement
    if (sqlite3_step(stmt.get()) != SQLITE_DONE) {
        std::cerr << "Failed to insert share access: " << sqlite3_errmsg(dbCtx_.db->get()) << std::endl;
        return false;
    }

    return true;
}

std::wstring SMBShareCollector::ShareTypeToString(DWORD shareType) {
    switch (shareType) {
        case STYPE_DISKTREE:
            return L"DiskShare";
        case STYPE_PRINTQ:
            return L"PrintQueue";
        case STYPE_DEVICE:
            return L"DeviceShare";
        case STYPE_IPC:
            return L"IPCShare";
        case STYPE_SPECIAL:
            return L"SpecialShare";
        case STYPE_TEMPORARY:
            return L"TemporaryShare";
        default:
            return L"Unknown";
    }
}

bool SMBShareCollector::IsSpecialShare(const std::wstring& shareName) {
    // Check if this is a special administrative share
    static const std::vector<std::wstring> specialShares = {
        L"ADMIN$", L"IPC$", L"C$", L"D$", L"E$", L"F$", L"G$", L"H$", L"I$", L"J$", L"K$", L"L$", L"M$",
        L"N$", L"O$", L"P$", L"Q$", L"R$", L"S$", L"T$", L"U$", L"V$", L"W$", L"X$", L"Y$", L"Z$"
    };
    
    return std::find(specialShares.begin(), specialShares.end(), shareName) != specialShares.end();
}

// Helper to get parent path from a folder path
static std::wstring GetParentPathForShare(const std::wstring& path) {
    if (path.empty()) return L"";

    // FIX: Check if this is already a drive root (e.g., "C:\" or "C:")
    // Drive roots have no parent - return empty to terminate ancestor traversal
    if (path.length() == 3 && path[1] == L':' && (path[2] == L'\\' || path[2] == L'/')) {
        return L"";  // "C:\" has no parent
    }
    if (path.length() == 2 && path[1] == L':') {
        return L"";  // "C:" has no parent
    }

    // Find last backslash
    size_t pos = path.find_last_of(L"\\/");
    if (pos == std::wstring::npos || pos == 0) {
        return L"";  // No parent or at root
    }

    // Handle drive root case (e.g., "C:\folder" -> "C:\")
    if (pos == 2 && path.length() > 2 && path[1] == L':') {
        return path.substr(0, 3);  // Return "C:\"
    }

    return path.substr(0, pos);
}

// New method to insert folder path into database with full metadata
bool SMBShareCollector::InsertFolderPath(int64_t localFolderId, const std::wstring& folderPath) {
    try {
        // First, insert all ancestors (from root to parent) to ensure FK integrity
        std::vector<std::pair<std::wstring, int64_t>> ancestorsToInsert;
        std::wstring currentPath = folderPath;

        // Build list of ancestors (from deepest to root)
        while (true) {
            std::wstring parentPath = GetParentPathForShare(currentPath);
            if (parentPath.empty()) {
                // Check if current path is a drive root that needs to be added
                if (currentPath.length() >= 2 && currentPath[1] == L':') {
                    std::wstring driveRoot = currentPath.substr(0, 3);
                    if (driveRoot.back() != L'\\') driveRoot += L'\\';
                    int64_t rootId = folderIndex_.getOrAssignId(driveRoot);
                    ancestorsToInsert.push_back({driveRoot, rootId});
                }
                break;
            }

            int64_t ancestorId = folderIndex_.getOrAssignId(parentPath);
            ancestorsToInsert.push_back({parentPath, ancestorId});
            currentPath = parentPath;
        }

        // Insert ancestors from root to leaf (reverse order) to maintain FK integrity
        for (auto it = ancestorsToInsert.rbegin(); it != ancestorsToInsert.rend(); ++it) {
            const std::wstring& ancestorPath = it->first;
            int64_t ancestorId = it->second;

            // Get parent ID for this ancestor
            std::wstring ancestorParentPath = GetParentPathForShare(ancestorPath);
            int64_t ancestorParentId = 0;
            if (!ancestorParentPath.empty()) {
                ancestorParentId = folderIndex_.getId(ancestorParentPath);
            }

            // Get volume ID for this ancestor
            int volumeId = GetVolumeIdFromPath(ancestorPath);

            // Insert ancestor with full metadata
            auto ancestorStmt = dbCtx_.PrepareStatement(
                "INSERT OR IGNORE INTO app__Folders (InventoryID, LocalFolderID, ParentFolderID, Path, VolumeID) "
                "VALUES (?, ?, ?, ?, ?)"
            );

            sqlite3_bind_text(ancestorStmt.get(), 1, dbCtx_.inventoryID.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(ancestorStmt.get(), 2, ancestorId);
            if (ancestorParentId > 0) {
                sqlite3_bind_int64(ancestorStmt.get(), 3, ancestorParentId);
            } else {
                sqlite3_bind_null(ancestorStmt.get(), 3);  // Root folder has no parent
            }
            sqlite3_bind_text16(ancestorStmt.get(), 4, ancestorPath.c_str(), -1, SQLITE_TRANSIENT);
            if (volumeId > 0) {
                sqlite3_bind_int(ancestorStmt.get(), 5, volumeId);
            } else {
                sqlite3_bind_null(ancestorStmt.get(), 5);
            }

            sqlite3_step(ancestorStmt.get());
        }

        // Now insert the main folder path with full metadata
        // Get parent folder ID
        std::wstring parentPath = GetParentPathForShare(folderPath);
        int64_t parentFolderId = 0;
        if (!parentPath.empty()) {
            parentFolderId = folderIndex_.getId(parentPath);
        }

        // Get volume ID
        int volumeId = GetVolumeIdFromPath(folderPath);

        // Prepare statement to insert folder with full metadata
        auto stmt = dbCtx_.PrepareStatement(
            "INSERT OR IGNORE INTO app__Folders (InventoryID, LocalFolderID, ParentFolderID, Path, VolumeID) "
            "VALUES (?, ?, ?, ?, ?)"
        );

        // Bind parameters
        sqlite3_bind_text(stmt.get(), 1, dbCtx_.inventoryID.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt.get(), 2, localFolderId);
        if (parentFolderId > 0) {
            sqlite3_bind_int64(stmt.get(), 3, parentFolderId);
        } else {
            sqlite3_bind_null(stmt.get(), 3);  // Root folder has no parent
        }
        sqlite3_bind_text16(stmt.get(), 4, folderPath.c_str(), -1, SQLITE_TRANSIENT);
        if (volumeId > 0) {
            sqlite3_bind_int(stmt.get(), 5, volumeId);
        } else {
            sqlite3_bind_null(stmt.get(), 5);
        }

        // Execute statement
        int result = sqlite3_step(stmt.get());
        if (result != SQLITE_DONE) {
            std::cerr << "Error inserting folder path: " << sqlite3_errmsg(dbCtx_.db->get()) << std::endl;
            return false;
        }

        return true;
    } catch (const std::exception& e) {
        std::cerr << "Exception inserting folder path: " << e.what() << std::endl;
        return false;
    }
}

