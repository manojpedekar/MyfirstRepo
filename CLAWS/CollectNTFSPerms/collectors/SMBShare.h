#pragma once

#include <string>
#include <vector>
#include <memory>
#include <atomic>
#include <mutex>
#include <unordered_map>
#include <optional>
#include <windows.h>
#include <lm.h>
#include <sddl.h>

#include "../database/database.h"
#include "../core/folderindex.h"
#include <map>

// Forward declarations
struct DatabaseContext;

/**
 * @brief Structure to hold SMB share information
 */
struct SMBShareInfo {
    std::wstring name;
    std::wstring path;
    std::wstring description;
    std::wstring type;
    bool allowMaximum = false;
    int maximumAllowed = 0;
    bool isHidden = false;
    bool isSpecial = false;
    std::wstring status;
    // FC-009: Advanced SMB fields use std::optional to indicate unknown values
    std::optional<bool> isEncrypted;          // NULL = unknown (requires PowerShell Get-SmbShare)
    std::optional<bool> isContinuous;         // NULL = unknown (cluster feature)
    std::wstring scopeName;
    std::wstring owningNode;
    std::optional<std::wstring> folderEnumerationMode;  // NULL = unknown
    std::optional<std::wstring> cachingMode;            // NULL = unknown
    std::optional<bool> branchCacheEnabled;             // NULL = unknown
    std::optional<std::wstring> leasingMode;            // NULL = unknown
    int volumeId = 0;
    std::wstring createdDate;
    std::wstring modifiedDate;
    std::wstring securityDescriptor;
    std::optional<int> currentUsers;                    // NULL = unknown (snapshot from Get-SmbSession)
    std::optional<bool> isBranchCacheEnabled;           // NULL = unknown (duplicate of branchCacheEnabled)
};

/**
 * @brief Structure to hold SMB share access information
 */
struct SMBShareAccessInfo {
    std::wstring sid;
    std::wstring accessType;
    DWORD accessMask = 0;
    bool isInherited = false;
};

/**
 * @brief Safe copy structure for SHARE_INFO_502 data
 *
 * This structure owns its string data to avoid use-after-free vulnerabilities
 * when copying data from NetShareEnum buffers that will be freed.
 */
struct ShareInfoCopy {
    std::wstring netname;
    std::wstring path;
    std::wstring remark;
    DWORD type = 0;
    DWORD permissions = 0;
    DWORD max_uses = 0;
    DWORD current_uses = 0;
    std::vector<BYTE> security_descriptor;

    /**
     * @brief Default constructor
     */
    ShareInfoCopy() = default;

    /**
     * @brief Construct from SHARE_INFO_502 with deep copy of all pointer data
     *
     * @param src Source SHARE_INFO_502 structure from NetShareEnum
     */
    explicit ShareInfoCopy(const SHARE_INFO_502& src)
        : netname(src.shi502_netname ? src.shi502_netname : L""),
          path(src.shi502_path ? src.shi502_path : L""),
          remark(src.shi502_remark ? src.shi502_remark : L""),
          type(src.shi502_type),
          permissions(src.shi502_permissions),
          max_uses(src.shi502_max_uses),
          current_uses(src.shi502_current_uses)
    {
        // Deep copy security descriptor if present
        if (src.shi502_security_descriptor) {
            DWORD sdLength = GetSecurityDescriptorLength(src.shi502_security_descriptor);
            if (sdLength > 0) {
                security_descriptor.resize(sdLength);
                memcpy(security_descriptor.data(), src.shi502_security_descriptor, sdLength);
            }
        }
    }
};

/**
 * @brief Class to discover and collect SMB share information
 */
class SMBShareCollector {
public:
    /**
     * @brief Constructor
     *
     * @param dbCtx Database context
     * @param folderIndex Reference to the folder index (non-const because it will be modified)
     */
    SMBShareCollector(DatabaseContext& dbCtx, FolderIndex& folderIndex);
    
    /**
     * @brief Destructor
     */
    ~SMBShareCollector();
    
    /**
     * @brief Discover SMB shares and add their paths to folder index
     * 
     * @return True if successful, false otherwise
     */
    bool DiscoverShares();
    
    /**
     * @brief Discover SMB shares on the local computer
     * 
     * @param shareCount Optional pointer to store the number of shares discovered
     * @return True if successful, false otherwise
     */
    bool DiscoverShares(int* shareCount = nullptr);
    
    /**
     * @brief Collect SMB shares and their permissions
     * 
     * @return True if successful, false otherwise
     */
    bool CollectShares();
    
    /**
     * @brief Get the number of shares collected
     * 
     * @return Number of shares
     */
    int GetShareCount() const { return shareCount_; }
    
    /**
     * @brief Get the number of share permissions collected
     * 
     * @return Number of share permissions
     */
    int GetShareAccessCount() const { return accessCount_; }

private:
    /**
     * @brief Enumerate SMB shares on the local computer
     *
     * @param collectData Whether to collect detailed share data
     * @param shares Vector to store share information (deep copies)
     * @return True if successful, false otherwise
     */
    bool EnumerateShares(bool collectData, std::vector<ShareInfoCopy>& shares);

    /**
     * @brief Process a single SMB share
     *
     * @param shareInfo Share information (safe copy)
     * @param collectData Whether to collect data or just discover paths
     * @return True if successful, false otherwise
     */
    bool ProcessShare(const ShareInfoCopy& shareInfo, bool collectData);
    
    /**
     * @brief Get additional share information using PowerShell
     * 
     * @param shareName Share name
     * @param shareInfo Share information structure to populate
     * @return True if successful, false otherwise
     */
    bool GetAdvancedShareInfo(const std::wstring& shareName, SMBShareInfo& info);
    
    /**
     * @brief Get share security descriptor
     * 
     * @param shareName Share name
     * @return Security descriptor as SDDL string
     */
    std::wstring GetShareSecurityDescriptor(const std::wstring& shareName);
    
    /**
     * @brief Process share security descriptor to extract permissions
     * 
     * @param shareName Share name
     * @param shareId Share ID
     * @param securityDescriptor Security descriptor
     * @return True if successful, false otherwise
     */
    bool ProcessShareSecurity(const std::wstring& shareName, int shareId, const std::wstring& securityDescriptor);
    
    /**
     * @brief Get or create SID ID from the database
     * 
     * @param sid SID string
     * @return SID ID
     */
    int64_t GetOrCreateSidId(const std::wstring& sid);
    
    /**
     * @brief Get folder ID from path
     *
     * @param path Folder path
     * @return Folder ID or -1 if not found
     */
    int64_t GetFolderIdFromPath(const std::wstring& path);

    /**
     * @brief Get volume ID from share path
     *
     * @param sharePath Share path
     * @return Volume ID or 0 if not found
     */
    int GetVolumeIdFromPath(const std::wstring& sharePath);

    /**
     * @brief Insert share into database
     *
     * @param shareId Share ID
     * @param shareInfo Share information
     * @return True if successful, false otherwise
     */
    bool InsertShare(int shareId, const SMBShareInfo& shareInfo);
    
    /**
     * @brief Insert share access into database
     * 
     * @param shareId Share ID
     * @param accessId Access ID
     * @param accessInfo Access information
     * @return True if successful, false otherwise
     */
    bool InsertShareAccess(int shareId, int accessId, const SMBShareAccessInfo& accessInfo);
    
    /**
     * @brief Convert share type to string
     * 
     * @param shareType Share type
     * @return String representation of share type
     */
    std::wstring ShareTypeToString(DWORD shareType);
    
    /**
     * @brief Check if share is special (ADMIN$, IPC$, etc.)
     * 
     * @param shareName Share name
     * @return True if special, false otherwise
     */
    bool IsSpecialShare(const std::wstring& shareName);

    /**
     * @brief Inserts a folder path and its ancestors into the app__Folders table
     * @param localFolderId The local folder ID to use
     * @param folderPath The folder path to insert
     * @return true if successful, false otherwise
     */
    bool InsertFolderPath(int64_t localFolderId, const std::wstring& folderPath);

    DatabaseContext& dbCtx_;
    FolderIndex& folderIndex_;  // Non-const because getOrAssignId() modifies it
    std::atomic<int> shareCount_;
    std::atomic<int> accessCount_;
    std::map<std::wstring, int> sharePathMap_;
    std::mutex sidCacheMutex_;
    std::unordered_map<std::wstring, int64_t> sidCache_;

};
