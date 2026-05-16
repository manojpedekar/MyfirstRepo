#pragma once

/**
 * @file PathValidator.h
 * @brief Path validation functions for testing NTFS path accessibility.
 *
 * This module provides functions to validate NTFS paths before or during
 * scanning operations. It can verify:
 * - Path existence and type (file vs directory)
 * - Read access (directory enumeration)
 * - Security descriptor access (ACL retrieval)
 * - Long path support (\\?\ prefix functionality)
 * - Detailed ACL analysis with inheritance information
 *
 * Originally from TestNTFSPath project, now shared with CollectNTFSPerms.
 */

#include <string>
#include <vector>
#include <windows.h>
#include <aclapi.h>

namespace PathUtils {

// ============================================================================
// Exit Codes for TestNTFSPath
// ============================================================================

enum class ExitCode {
    Success = 0,           // No issues detected
    PathNotFound = 1,      // Path does not exist
    AccessDenied = 2,      // Cannot access path (directory listing failed)
    AclAccessDenied = 3,   // Cannot read ACL/security descriptor
    SystemMissing = 4,     // SYSTEM account missing from ACL
    NonCanonical = 5,      // ACL is not in canonical order
    InheritanceIssue = 6,  // Inheritance inconsistency detected
    FixFailed = 7,         // Fix operation failed
    ArgumentError = 10,    // Invalid command-line arguments
    UnknownError = 99      // Unexpected error
};

// ============================================================================
// File Attribute Structures
// ============================================================================

/**
 * @brief Parsed file attributes for easy access.
 */
struct FileAttributes {
    bool readonly = false;
    bool hidden = false;
    bool system = false;
    bool directory = false;
    bool archive = false;
    bool compressed = false;
    bool encrypted = false;
    bool reparsePoint = false;
    bool offline = false;
    bool notContentIndexed = false;
    bool sparse = false;

    /// Raw Windows attribute flags
    DWORD raw = 0;

    /**
     * @brief Parse Windows file attributes into structured format.
     * @param attrs Raw DWORD from GetFileAttributesW.
     * @return Parsed FileAttributes structure.
     */
    static FileAttributes fromDword(DWORD attrs);
};

// ============================================================================
// Reparse Point Information
// ============================================================================

enum class ReparsePointType {
    None,
    MountPoint,     // Volume mount point (junction to volume)
    Junction,       // Directory junction
    Symlink,        // Symbolic link
    Other           // Unknown reparse point type
};

/**
 * @brief Get string representation of reparse point type.
 */
std::wstring getReparsePointTypeString(ReparsePointType type);

/**
 * @brief Detect the type of reparse point for a path.
 */
ReparsePointType getReparsePointType(const std::wstring& path);

// ============================================================================
// File System Information
// ============================================================================

struct FileSystemInfo {
    std::wstring fileSystemName;    // NTFS, ReFS, FAT32, etc.
    std::wstring volumeName;        // Volume label
    DWORD serialNumber = 0;
    DWORD maxComponentLength = 0;
    DWORD flags = 0;                // FILE_CASE_SENSITIVE_SEARCH, etc.
    bool supportsAcls = false;
    bool supportsEncryption = false;
    bool supportsCompression = false;
    bool supportsSparseFiles = false;
};

/**
 * @brief Get file system information for a path.
 */
FileSystemInfo getFileSystemInfo(const std::wstring& path);

// ============================================================================
// Validation Result Structures
// ============================================================================

/**
 * @brief Result of a path access test (directory enumeration).
 */
struct PathAccessResult {
    bool success = false;
    DWORD errorCode = 0;
    std::wstring errorMessage;

    bool isAccessDenied() const { return errorCode == ERROR_ACCESS_DENIED; }
    bool isNotFound() const {
        return errorCode == ERROR_PATH_NOT_FOUND ||
               errorCode == ERROR_FILE_NOT_FOUND;
    }
    bool isInvalidName() const { return errorCode == ERROR_INVALID_NAME; }
    bool isNetworkError() const {
        return errorCode == ERROR_BAD_NETPATH ||
               errorCode == ERROR_BAD_NET_NAME ||
               errorCode == ERROR_NETWORK_UNREACHABLE;
    }
};

/**
 * @brief Result of an ACL retrieval test.
 */
struct AclAccessResult {
    bool success = false;
    DWORD errorCode = 0;
    std::wstring errorMessage;
    std::wstring sddl;
    bool daclPresent = false;
    bool daclDefaulted = false;
    int aceCount = 0;
};

// ============================================================================
// ACL Analysis Structures
// ============================================================================

/**
 * @brief Information about a single Access Control Entry (ACE).
 */
struct AceInfo {
    BYTE aceType = 0;
    BYTE aceFlags = 0;
    ACCESS_MASK accessMask = 0;
    std::wstring sidString;
    std::wstring accountName;
    bool isInherited = false;

    // Parsed inheritance flags
    bool containerInherit = false;   // CI - Applies to child containers
    bool objectInherit = false;      // OI - Applies to child objects
    bool inheritOnly = false;        // IO - Does not apply to this object
    bool noPropagateInherit = false; // NP - Do not propagate to grandchildren

    std::wstring getTypeString() const;
    std::wstring getAccessMaskString() const;
    std::wstring getInheritanceFlagsString() const;
    std::wstring getDisplayName() const;  // Returns accountName or well-known SID name
};

/**
 * @brief Result of detailed ACL analysis.
 */
struct AclAnalysisResult {
    bool success = false;
    DWORD errorCode = 0;
    std::wstring errorMessage;

    // Owner and Group
    std::wstring ownerSid;
    std::wstring ownerName;
    std::wstring groupSid;
    std::wstring groupName;

    // Protection Flags
    bool areAccessRulesProtected = false;
    bool areAuditRulesProtected = false;

    // Canonical Order
    bool areAccessRulesCanonical = true;
    bool areAuditRulesCanonical = true;

    // ACE Counts
    int totalAceCount = 0;
    int inheritedAceCount = 0;
    int explicitAceCount = 0;

    // Special checks
    bool systemHasAccess = false;       // Does SYSTEM (S-1-5-18) have access?
    bool isNullDacl = false;            // NULL DACL = everyone full control

    // ACE Details
    std::vector<AceInfo> aces;

    bool allAcesInherited() const { return explicitAceCount == 0 && inheritedAceCount > 0; }
    bool hasExplicitAces() const { return explicitAceCount > 0; }
};

/**
 * @brief Result of parent comparison for inherited ACLs.
 */
struct ParentComparisonResult {
    bool success = false;
    std::wstring parentPath;
    std::wstring errorMessage;
    std::vector<AceInfo> missingAces;
    std::vector<AceInfo> additionalAces;

    bool hasMissingAces() const { return !missingAces.empty(); }
    bool hasAdditionalAces() const { return !additionalAces.empty(); }
};

/**
 * @brief Result of inheritance consistency check.
 *
 * Detects situations where:
 * - Inheritance is enabled (AreAccessRulesProtected = False)
 * - ACEs are marked as inherited (ID flag in SDDL)
 * - But the ACEs don't match what the parent actually has
 *
 * This indicates ACL corruption, typically from backup/restore or folder moves.
 */
struct InheritanceConsistencyResult {
    bool success = false;
    std::wstring errorMessage;
    std::wstring parentPath;

    // Is inheritance enabled on the child?
    bool inheritanceEnabled = false;

    // Is there a consistency issue?
    bool isConsistent = true;

    // ACEs marked as inherited in child but NOT actually inheritable from parent
    // These would be DROPPED on recalculation
    std::vector<AceInfo> orphanedInheritedAces;

    // ACEs in parent that should inherit but are MISSING in child
    // These would be ADDED on recalculation
    std::vector<AceInfo> missingInheritedAces;

    // Summary flags
    bool hasOrphanedAces() const { return !orphanedInheritedAces.empty(); }
    bool hasMissingAces() const { return !missingInheritedAces.empty(); }
    bool needsRepair() const { return !isConsistent && (hasOrphanedAces() || hasMissingAces()); }
};

/**
 * @brief Result of attempting to fix inheritance.
 */
struct InheritanceFixResult {
    bool success = false;
    DWORD errorCode = 0;
    std::wstring errorMessage;
    std::wstring commandUsed;
};

/**
 * @brief Overall verdict for path validation.
 */
enum class ValidationVerdict {
    Pass,       // No issues
    Warning,    // Minor issues (non-canonical, etc.)
    Fail        // Critical issues (access denied, etc.)
};

/**
 * @brief Comprehensive path validation result.
 */
struct PathValidationResult {
    std::wstring path;
    std::wstring longPath;
    size_t pathLength = 0;
    bool exceedsMaxPath = false;

    bool exists = false;
    bool isDirectory = false;
    FileAttributes attributes;
    ReparsePointType reparseType = ReparsePointType::None;
    FileSystemInfo fsInfo;

    PathAccessResult accessResult;
    AclAccessResult aclResult;

    bool longPathWorks = false;
    DWORD longPathError = 0;
    std::wstring longPathErrorMsg;

    // Warnings collected during validation
    std::vector<std::wstring> warnings;

    bool isFullyAccessible() const {
        return exists && isDirectory && accessResult.success && aclResult.success;
    }

    std::vector<std::wstring> getRecommendations() const;
    ValidationVerdict getVerdict() const;
    ExitCode getExitCode() const;
};

// ============================================================================
// Well-Known SID Functions
// ============================================================================

/**
 * @brief Translate a SID string to a well-known name.
 * Returns empty string if not a well-known SID.
 */
std::wstring getWellKnownSidName(const std::wstring& sidString);

/**
 * @brief Check if a SID string represents the SYSTEM account.
 */
bool isSystemSid(const std::wstring& sidString);

// ============================================================================
// Validation Functions
// ============================================================================

PathAccessResult testPathAccess(const std::wstring& path);
PathAccessResult testFileAccess(const std::wstring& path);
AclAccessResult testAclRetrieval(const std::wstring& path);
PathValidationResult validatePath(const std::wstring& path);
bool pathExists(const std::wstring& path, FileAttributes* attrs = nullptr);
bool isDirectory(const std::wstring& path);
bool isFile(const std::wstring& path);

// ============================================================================
// ACL Analysis Functions
// ============================================================================

AclAnalysisResult analyzeAcl(const std::wstring& path);
std::wstring getParentPath(const std::wstring& path);
ParentComparisonResult compareWithParent(const std::wstring& path);

/**
 * @brief Check inheritance consistency between a path and its parent.
 *
 * Detects ACL corruption where inherited ACEs don't match parent's inheritable ACEs.
 * This can happen after backup/restore, folder moves, or manual SDDL manipulation.
 */
InheritanceConsistencyResult checkInheritanceConsistency(const std::wstring& path);

/**
 * @brief Fix inheritance by resetting the DACL to inherit from parent.
 *
 * Uses icacls /reset to force Windows to recalculate inheritance.
 * WARNING: This will drop any "orphaned" inherited ACEs and add missing ones.
 *
 * @param path Path to fix
 * @param recursive Apply recursively to all children
 * @return Result of the fix operation
 */
InheritanceFixResult fixInheritance(const std::wstring& path, bool recursive = false);

/**
 * @brief Result of attempting to add SYSTEM account to ACL.
 */
struct AddSystemAceResult {
    bool success = false;
    DWORD errorCode = 0;
    std::wstring errorMessage;
    bool inheritanceWasEnabled = false;  // If true, no action was taken
    bool systemAlreadyPresent = false;   // If true, SYSTEM was already in ACL
};

/**
 * @brief Add SYSTEM account with Full Control to a path's DACL.
 *
 * Only adds SYSTEM if:
 * - Inheritance is blocked (AreAccessRulesProtected = True)
 * - SYSTEM doesn't already have access
 *
 * Uses icacls to grant SYSTEM:(OI)(CI)F
 *
 * @param path Path to modify
 * @return Result of the operation
 */
AddSystemAceResult addSystemAce(const std::wstring& path);

// ============================================================================
// JSON Output Functions
// ============================================================================

std::wstring toJson(const PathValidationResult& result);
std::wstring toJsonCompact(const PathValidationResult& result);

} // namespace PathUtils
