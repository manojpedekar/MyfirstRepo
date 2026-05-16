/**
 * @file PathValidator.cpp
 * @brief Implementation of path validation functions.
 */

#include "PathValidator.h"
#include "PathUtils.h"
#include <sddl.h>
#include <sstream>
#include <iomanip>
#include <map>

namespace PathUtils {

// ============================================================================
// Well-Known SID Mappings
// ============================================================================

static const std::map<std::wstring, std::wstring> wellKnownSids = {
    {L"S-1-0-0", L"Nobody"},
    {L"S-1-1-0", L"Everyone"},
    {L"S-1-2-0", L"Local"},
    {L"S-1-3-0", L"Creator Owner"},
    {L"S-1-3-1", L"Creator Group"},
    {L"S-1-5-1", L"Dialup"},
    {L"S-1-5-2", L"Network"},
    {L"S-1-5-3", L"Batch"},
    {L"S-1-5-4", L"Interactive"},
    {L"S-1-5-6", L"Service"},
    {L"S-1-5-7", L"Anonymous"},
    {L"S-1-5-9", L"Enterprise Domain Controllers"},
    {L"S-1-5-10", L"Principal Self"},
    {L"S-1-5-11", L"Authenticated Users"},
    {L"S-1-5-12", L"Restricted Code"},
    {L"S-1-5-13", L"Terminal Server Users"},
    {L"S-1-5-14", L"Remote Interactive Logon"},
    {L"S-1-5-18", L"NT AUTHORITY\\SYSTEM"},
    {L"S-1-5-19", L"NT AUTHORITY\\LOCAL SERVICE"},
    {L"S-1-5-20", L"NT AUTHORITY\\NETWORK SERVICE"},
    {L"S-1-5-32-544", L"BUILTIN\\Administrators"},
    {L"S-1-5-32-545", L"BUILTIN\\Users"},
    {L"S-1-5-32-546", L"BUILTIN\\Guests"},
    {L"S-1-5-32-547", L"BUILTIN\\Power Users"},
    {L"S-1-5-32-548", L"BUILTIN\\Account Operators"},
    {L"S-1-5-32-549", L"BUILTIN\\Server Operators"},
    {L"S-1-5-32-550", L"BUILTIN\\Print Operators"},
    {L"S-1-5-32-551", L"BUILTIN\\Backup Operators"},
    {L"S-1-5-32-552", L"BUILTIN\\Replicators"}
};

std::wstring getWellKnownSidName(const std::wstring& sidString) {
    auto it = wellKnownSids.find(sidString);
    if (it != wellKnownSids.end()) {
        return it->second;
    }
    return L"";
}

bool isSystemSid(const std::wstring& sidString) {
    return sidString == L"S-1-5-18";
}

// ============================================================================
// FileAttributes Implementation
// ============================================================================

FileAttributes FileAttributes::fromDword(DWORD attrs) {
    FileAttributes result;
    result.raw = attrs;

    if (attrs == INVALID_FILE_ATTRIBUTES) {
        return result;
    }

    result.readonly = (attrs & FILE_ATTRIBUTE_READONLY) != 0;
    result.hidden = (attrs & FILE_ATTRIBUTE_HIDDEN) != 0;
    result.system = (attrs & FILE_ATTRIBUTE_SYSTEM) != 0;
    result.directory = (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
    result.archive = (attrs & FILE_ATTRIBUTE_ARCHIVE) != 0;
    result.compressed = (attrs & FILE_ATTRIBUTE_COMPRESSED) != 0;
    result.encrypted = (attrs & FILE_ATTRIBUTE_ENCRYPTED) != 0;
    result.reparsePoint = (attrs & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
    result.offline = (attrs & FILE_ATTRIBUTE_OFFLINE) != 0;
    result.notContentIndexed = (attrs & FILE_ATTRIBUTE_NOT_CONTENT_INDEXED) != 0;
    result.sparse = (attrs & FILE_ATTRIBUTE_SPARSE_FILE) != 0;

    return result;
}

// ============================================================================
// Reparse Point Functions
// ============================================================================

std::wstring getReparsePointTypeString(ReparsePointType type) {
    switch (type) {
        case ReparsePointType::None: return L"None";
        case ReparsePointType::MountPoint: return L"Mount Point";
        case ReparsePointType::Junction: return L"Junction";
        case ReparsePointType::Symlink: return L"Symbolic Link";
        case ReparsePointType::Other: return L"Other";
        default: return L"Unknown";
    }
}

ReparsePointType getReparsePointType(const std::wstring& path) {
    std::wstring longPath = toLongPath(path);
    DWORD attrs = GetFileAttributesW(longPath.c_str());

    if (attrs == INVALID_FILE_ATTRIBUTES) {
        return ReparsePointType::None;
    }

    if (!(attrs & FILE_ATTRIBUTE_REPARSE_POINT)) {
        return ReparsePointType::None;
    }

    HANDLE hFile = CreateFileW(
        longPath.c_str(),
        FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr,
        OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
        nullptr
    );

    if (hFile == INVALID_HANDLE_VALUE) {
        return ReparsePointType::Other;
    }

    BYTE buffer[MAXIMUM_REPARSE_DATA_BUFFER_SIZE];
    DWORD bytesReturned;

    BOOL success = DeviceIoControl(
        hFile,
        FSCTL_GET_REPARSE_POINT,
        nullptr, 0,
        buffer, sizeof(buffer),
        &bytesReturned,
        nullptr
    );

    CloseHandle(hFile);

    if (!success) {
        return ReparsePointType::Other;
    }

    DWORD reparseTag = *reinterpret_cast<DWORD*>(buffer);

    if (reparseTag == IO_REPARSE_TAG_MOUNT_POINT) {
        return ReparsePointType::MountPoint;
    } else if (reparseTag == IO_REPARSE_TAG_SYMLINK) {
        return ReparsePointType::Symlink;
    }

    return ReparsePointType::Other;
}

// ============================================================================
// File System Information
// ============================================================================

FileSystemInfo getFileSystemInfo(const std::wstring& path) {
    FileSystemInfo info;

    std::wstring rootPath;
    if (path.length() >= 2 && path[1] == L':') {
        rootPath = path.substr(0, 3);
        if (rootPath.back() != L'\\') {
            rootPath += L'\\';
        }
    } else if (path.length() >= 2 && path[0] == L'\\' && path[1] == L'\\') {
        size_t serverEnd = path.find(L'\\', 2);
        if (serverEnd != std::wstring::npos) {
            size_t shareEnd = path.find(L'\\', serverEnd + 1);
            if (shareEnd != std::wstring::npos) {
                rootPath = path.substr(0, shareEnd + 1);
            } else {
                rootPath = path + L'\\';
            }
        }
    }

    if (rootPath.empty()) {
        return info;
    }

    wchar_t volumeName[MAX_PATH + 1] = {0};
    wchar_t fileSystemName[MAX_PATH + 1] = {0};
    DWORD serialNumber = 0;
    DWORD maxComponentLength = 0;
    DWORD flags = 0;

    if (GetVolumeInformationW(
            rootPath.c_str(),
            volumeName, MAX_PATH,
            &serialNumber,
            &maxComponentLength,
            &flags,
            fileSystemName, MAX_PATH)) {
        info.volumeName = volumeName;
        info.fileSystemName = fileSystemName;
        info.serialNumber = serialNumber;
        info.maxComponentLength = maxComponentLength;
        info.flags = flags;
        info.supportsAcls = (flags & FILE_PERSISTENT_ACLS) != 0;
        info.supportsEncryption = (flags & FILE_SUPPORTS_ENCRYPTION) != 0;
        info.supportsCompression = (flags & FILE_FILE_COMPRESSION) != 0;
        info.supportsSparseFiles = (flags & FILE_SUPPORTS_SPARSE_FILES) != 0;
    }

    return info;
}

// ============================================================================
// PathValidationResult Implementation
// ============================================================================

std::vector<std::wstring> PathValidationResult::getRecommendations() const {
    std::vector<std::wstring> recommendations;

    if (!exists) {
        recommendations.push_back(
            L"The path does not exist. Verify the path is correct.");
        return recommendations;
    }

    if (!isDirectory) {
        recommendations.push_back(
            L"The path exists but is not a directory.");
        return recommendations;
    }

    if (!accessResult.success) {
        if (accessResult.isAccessDenied()) {
            recommendations.push_back(
                L"Access denied. Run with administrator privileges.");
            recommendations.push_back(
                L"Ensure Read & Execute permissions are granted.");
        } else if (accessResult.isNetworkError()) {
            recommendations.push_back(
                L"Network error. Verify server is reachable.");
        } else if (accessResult.isInvalidName()) {
            recommendations.push_back(
                L"Invalid path name. Check for illegal characters.");
        } else {
            recommendations.push_back(
                L"Failed to access directory: " + accessResult.errorMessage);
        }
    }

    if (!aclResult.success) {
        if (aclResult.errorCode == ERROR_ACCESS_DENIED) {
            recommendations.push_back(
                L"Cannot read security descriptor. Need 'Read Permissions' access.");
        } else {
            recommendations.push_back(
                L"Failed to retrieve ACL: " + aclResult.errorMessage);
        }
    }

    if (exceedsMaxPath && !longPathWorks) {
        recommendations.push_back(
            L"Path exceeds MAX_PATH limit. Enable long path support.");
    }

    for (const auto& warning : warnings) {
        recommendations.push_back(warning);
    }

    if (recommendations.empty()) {
        recommendations.push_back(L"No issues detected.");
    }

    return recommendations;
}

ValidationVerdict PathValidationResult::getVerdict() const {
    if (!exists || !accessResult.success || !aclResult.success) {
        return ValidationVerdict::Fail;
    }
    if (!warnings.empty()) {
        return ValidationVerdict::Warning;
    }
    return ValidationVerdict::Pass;
}

ExitCode PathValidationResult::getExitCode() const {
    if (!exists) {
        return ExitCode::PathNotFound;
    }
    if (!accessResult.success) {
        return ExitCode::AccessDenied;
    }
    if (!aclResult.success) {
        return ExitCode::AclAccessDenied;
    }
    return ExitCode::Success;
}

// ============================================================================
// Validation Functions
// ============================================================================

PathAccessResult testPathAccess(const std::wstring& path) {
    PathAccessResult result;

    std::wstring searchPath = path;
    if (!searchPath.empty() && searchPath.back() != L'\\') {
        searchPath += L'\\';
    }
    searchPath += L'*';

    WIN32_FIND_DATAW findData;
    HANDLE hFind = FindFirstFileW(searchPath.c_str(), &findData);

    if (hFind == INVALID_HANDLE_VALUE) {
        result.success = false;
        result.errorCode = GetLastError();
        result.errorMessage = formatErrorCode(result.errorCode);
    } else {
        result.success = true;
        result.errorCode = ERROR_SUCCESS;
        FindClose(hFind);
    }

    return result;
}

PathAccessResult testFileAccess(const std::wstring& path) {
    PathAccessResult result;
    DWORD attrs = GetFileAttributesW(path.c_str());

    if (attrs == INVALID_FILE_ATTRIBUTES) {
        result.success = false;
        result.errorCode = GetLastError();
        result.errorMessage = formatErrorCode(result.errorCode);
    } else {
        result.success = true;
        result.errorCode = ERROR_SUCCESS;
    }

    return result;
}

AclAccessResult testAclRetrieval(const std::wstring& path) {
    AclAccessResult result;
    PACL pDacl = nullptr;
    PSECURITY_DESCRIPTOR pSD = nullptr;

    DWORD secResult = GetNamedSecurityInfoW(
        path.c_str(),
        SE_FILE_OBJECT,
        DACL_SECURITY_INFORMATION | OWNER_SECURITY_INFORMATION | GROUP_SECURITY_INFORMATION,
        nullptr, nullptr,
        &pDacl,
        nullptr,
        &pSD
    );

    if (secResult != ERROR_SUCCESS) {
        result.success = false;
        result.errorCode = secResult;
        result.errorMessage = formatErrorCode(secResult);
        return result;
    }

    result.success = true;
    result.errorCode = ERROR_SUCCESS;

    BOOL daclPresent = FALSE;
    BOOL daclDefaulted = FALSE;
    PACL actualDacl = nullptr;

    if (GetSecurityDescriptorDacl(pSD, &daclPresent, &actualDacl, &daclDefaulted)) {
        result.daclPresent = (daclPresent != FALSE);
        result.daclDefaulted = (daclDefaulted != FALSE);

        if (result.daclPresent && actualDacl != nullptr) {
            ACL_SIZE_INFORMATION aclInfo;
            if (GetAclInformation(actualDacl, &aclInfo, sizeof(aclInfo), AclSizeInformation)) {
                result.aceCount = static_cast<int>(aclInfo.AceCount);
            }
        }
    }

    LPWSTR stringSD = nullptr;
    if (ConvertSecurityDescriptorToStringSecurityDescriptorW(
            pSD,
            SDDL_REVISION_1,
            OWNER_SECURITY_INFORMATION | GROUP_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
            &stringSD,
            nullptr)) {
        result.sddl = stringSD;
        LocalFree(stringSD);
    }

    LocalFree(pSD);
    return result;
}

PathValidationResult validatePath(const std::wstring& path) {
    PathValidationResult result;
    result.path = path;
    result.pathLength = path.length();
    result.exceedsMaxPath = exceedsMaxPath(path);

    if (isUncPath(path)) {
        result.longPath = toLongUncPath(path);
    } else {
        result.longPath = toLongPath(path);
    }

    DWORD attrs = GetFileAttributesW(path.c_str());
    result.exists = (attrs != INVALID_FILE_ATTRIBUTES);

    if (result.exists) {
        result.attributes = FileAttributes::fromDword(attrs);
        result.isDirectory = result.attributes.directory;

        if (result.attributes.reparsePoint) {
            result.reparseType = getReparsePointType(path);
        }

        result.fsInfo = getFileSystemInfo(path);
    }

    if (result.exists && result.isDirectory) {
        result.accessResult = testPathAccess(path);
    } else if (result.exists) {
        result.accessResult = testFileAccess(path);
    }

    if (result.exists) {
        result.aclResult = testAclRetrieval(path);
    }

    DWORD longAttrs = GetFileAttributesW(result.longPath.c_str());
    result.longPathWorks = (longAttrs != INVALID_FILE_ATTRIBUTES);
    if (!result.longPathWorks) {
        result.longPathError = GetLastError();
        result.longPathErrorMsg = formatErrorCode(result.longPathError);
    }

    return result;
}

bool pathExists(const std::wstring& path, FileAttributes* attrs) {
    DWORD rawAttrs = GetFileAttributesW(path.c_str());
    if (rawAttrs == INVALID_FILE_ATTRIBUTES) {
        return false;
    }
    if (attrs != nullptr) {
        *attrs = FileAttributes::fromDword(rawAttrs);
    }
    return true;
}

bool isDirectory(const std::wstring& path) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    return (attrs != INVALID_FILE_ATTRIBUTES) &&
           (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

bool isFile(const std::wstring& path) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    return (attrs != INVALID_FILE_ATTRIBUTES) &&
           (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

// ============================================================================
// ACL Analysis Functions
// ============================================================================

std::wstring AceInfo::getTypeString() const {
    switch (aceType) {
        case ACCESS_ALLOWED_ACE_TYPE: return L"Allow";
        case ACCESS_DENIED_ACE_TYPE: return L"Deny";
        case SYSTEM_AUDIT_ACE_TYPE: return L"Audit";
        case ACCESS_ALLOWED_OBJECT_ACE_TYPE: return L"AllowObject";
        case ACCESS_DENIED_OBJECT_ACE_TYPE: return L"DenyObject";
        case SYSTEM_AUDIT_OBJECT_ACE_TYPE: return L"AuditObject";
        default: return L"Unknown(" + std::to_wstring(aceType) + L")";
    }
}

std::wstring AceInfo::getAccessMaskString() const {
    // Check for full control FIRST
    if ((accessMask & 0x1F01FF) == 0x1F01FF) {
        return L"FullControl";
    }

    // Check for common combined permissions
    constexpr ACCESS_MASK MODIFY = 0x1301BF;
    constexpr ACCESS_MASK READ_EXECUTE = 0x1200A9;
    constexpr ACCESS_MASK READ = 0x120089;
    constexpr ACCESS_MASK WRITE = 0x120116;

    if ((accessMask & MODIFY) == MODIFY) {
        return L"Modify";
    }
    if ((accessMask & READ_EXECUTE) == READ_EXECUTE && (accessMask & ~READ_EXECUTE) == 0) {
        return L"ReadAndExecute";
    }
    if ((accessMask & READ) == READ && (accessMask & ~READ) == 0) {
        return L"Read";
    }
    if ((accessMask & WRITE) == WRITE && (accessMask & ~WRITE) == 0) {
        return L"Write";
    }

    std::wstring result;

    if (accessMask & FILE_READ_DATA) result += L"Read,";
    if (accessMask & FILE_WRITE_DATA) result += L"Write,";
    if (accessMask & FILE_APPEND_DATA) result += L"Append,";
    if (accessMask & FILE_READ_EA) result += L"ReadEA,";
    if (accessMask & FILE_WRITE_EA) result += L"WriteEA,";
    if (accessMask & FILE_EXECUTE) result += L"Execute,";
    if (accessMask & FILE_DELETE_CHILD) result += L"DeleteChild,";
    if (accessMask & FILE_READ_ATTRIBUTES) result += L"ReadAttr,";
    if (accessMask & FILE_WRITE_ATTRIBUTES) result += L"WriteAttr,";
    if (accessMask & DELETE) result += L"Delete,";
    if (accessMask & READ_CONTROL) result += L"ReadPerms,";
    if (accessMask & WRITE_DAC) result += L"WriteDAC,";
    if (accessMask & WRITE_OWNER) result += L"TakeOwnership,";
    if (accessMask & SYNCHRONIZE) result += L"Sync,";
    if (accessMask & GENERIC_ALL) result += L"GenericAll,";
    if (accessMask & GENERIC_EXECUTE) result += L"GenericExec,";
    if (accessMask & GENERIC_WRITE) result += L"GenericWrite,";
    if (accessMask & GENERIC_READ) result += L"GenericRead,";

    if (!result.empty() && result.back() == L',') {
        result.pop_back();
    }

    if (result.empty()) {
        wchar_t buf[32];
        swprintf_s(buf, L"0x%08X", accessMask);
        result = buf;
    }

    return result;
}

std::wstring AceInfo::getInheritanceFlagsString() const {
    if (!containerInherit && !objectInherit && !inheritOnly && !noPropagateInherit) {
        return L"None";
    }

    std::wstring result;
    if (containerInherit) result += L"CI,";
    if (objectInherit) result += L"OI,";
    if (inheritOnly) result += L"IO,";
    if (noPropagateInherit) result += L"NP,";

    if (!result.empty() && result.back() == L',') {
        result.pop_back();
    }

    return result;
}

std::wstring AceInfo::getDisplayName() const {
    if (!accountName.empty()) {
        return accountName;
    }
    std::wstring wellKnown = getWellKnownSidName(sidString);
    if (!wellKnown.empty()) {
        return wellKnown;
    }
    return sidString;
}

static bool isDaclCanonical(const std::vector<AceInfo>& aces) {
    int currentPhase = 0;

    for (const auto& ace : aces) {
        int acePhase;

        if (!ace.isInherited) {
            if (ace.aceType == ACCESS_DENIED_ACE_TYPE) {
                acePhase = 0;
            } else {
                acePhase = 1;
            }
        } else {
            if (ace.aceType == ACCESS_DENIED_ACE_TYPE) {
                acePhase = 2;
            } else {
                acePhase = 3;
            }
        }

        if (acePhase < currentPhase) {
            return false;
        }
        currentPhase = acePhase;
    }

    return true;
}

static std::wstring resolveSidToName(PSID pSid) {
    wchar_t accountName[256] = {0};
    wchar_t domainName[256] = {0};
    DWORD accountLen = 256;
    DWORD domainLen = 256;
    SID_NAME_USE sidUse;

    if (LookupAccountSidW(nullptr, pSid, accountName, &accountLen, domainName, &domainLen, &sidUse)) {
        std::wstring result;
        if (domainName[0] != L'\0') {
            result = domainName;
            result += L"\\";
        }
        result += accountName;
        return result;
    }

    return L"";
}

AclAnalysisResult analyzeAcl(const std::wstring& path) {
    AclAnalysisResult result;

    PSID pOwner = nullptr;
    PSID pGroup = nullptr;
    PACL pDacl = nullptr;
    PSECURITY_DESCRIPTOR pSD = nullptr;

    DWORD secResult = GetNamedSecurityInfoW(
        path.c_str(),
        SE_FILE_OBJECT,
        DACL_SECURITY_INFORMATION | OWNER_SECURITY_INFORMATION | GROUP_SECURITY_INFORMATION,
        &pOwner,
        &pGroup,
        &pDacl,
        nullptr,
        &pSD
    );

    if (secResult != ERROR_SUCCESS) {
        result.success = false;
        result.errorCode = secResult;
        result.errorMessage = formatErrorCode(secResult);
        return result;
    }

    result.success = true;

    // Get owner information
    if (pOwner != nullptr && IsValidSid(pOwner)) {
        LPWSTR ownerStr = nullptr;
        if (ConvertSidToStringSidW(pOwner, &ownerStr)) {
            result.ownerSid = ownerStr;
            LocalFree(ownerStr);
        }
        result.ownerName = resolveSidToName(pOwner);
        if (result.ownerName.empty()) {
            result.ownerName = getWellKnownSidName(result.ownerSid);
        }
    }

    // Get group information
    if (pGroup != nullptr && IsValidSid(pGroup)) {
        LPWSTR groupStr = nullptr;
        if (ConvertSidToStringSidW(pGroup, &groupStr)) {
            result.groupSid = groupStr;
            LocalFree(groupStr);
        }
        result.groupName = resolveSidToName(pGroup);
        if (result.groupName.empty()) {
            result.groupName = getWellKnownSidName(result.groupSid);
        }
    }

    // Get security descriptor control flags
    SECURITY_DESCRIPTOR_CONTROL sdControl;
    DWORD sdRevision;
    if (GetSecurityDescriptorControl(pSD, &sdControl, &sdRevision)) {
        result.areAccessRulesProtected = (sdControl & SE_DACL_PROTECTED) != 0;
        result.areAuditRulesProtected = (sdControl & SE_SACL_PROTECTED) != 0;
    }

    // Check for NULL DACL
    BOOL daclPresent = FALSE;
    BOOL daclDefaulted = FALSE;
    PACL actualDacl = nullptr;
    if (GetSecurityDescriptorDacl(pSD, &daclPresent, &actualDacl, &daclDefaulted)) {
        if (daclPresent && actualDacl == nullptr) {
            result.isNullDacl = true;
        }
    }

    // Analyze DACL
    if (pDacl != nullptr) {
        ACL_SIZE_INFORMATION aclInfo;
        if (GetAclInformation(pDacl, &aclInfo, sizeof(aclInfo), AclSizeInformation)) {
            result.totalAceCount = static_cast<int>(aclInfo.AceCount);

            for (DWORD i = 0; i < aclInfo.AceCount; i++) {
                LPVOID pAce = nullptr;
                if (GetAce(pDacl, i, &pAce)) {
                    ACE_HEADER* pAceHeader = static_cast<ACE_HEADER*>(pAce);

                    AceInfo aceInfo;
                    aceInfo.aceType = pAceHeader->AceType;
                    aceInfo.aceFlags = pAceHeader->AceFlags;
                    aceInfo.isInherited = (pAceHeader->AceFlags & INHERITED_ACE) != 0;
                    aceInfo.containerInherit = (pAceHeader->AceFlags & CONTAINER_INHERIT_ACE) != 0;
                    aceInfo.objectInherit = (pAceHeader->AceFlags & OBJECT_INHERIT_ACE) != 0;
                    aceInfo.inheritOnly = (pAceHeader->AceFlags & INHERIT_ONLY_ACE) != 0;
                    aceInfo.noPropagateInherit = (pAceHeader->AceFlags & NO_PROPAGATE_INHERIT_ACE) != 0;

                    if (aceInfo.isInherited) {
                        result.inheritedAceCount++;
                    } else {
                        result.explicitAceCount++;
                    }

                    PSID pSid = nullptr;
                    if (pAceHeader->AceType == ACCESS_ALLOWED_ACE_TYPE) {
                        ACCESS_ALLOWED_ACE* pAllowedAce = static_cast<ACCESS_ALLOWED_ACE*>(pAce);
                        aceInfo.accessMask = pAllowedAce->Mask;
                        pSid = &pAllowedAce->SidStart;
                    } else if (pAceHeader->AceType == ACCESS_DENIED_ACE_TYPE) {
                        ACCESS_DENIED_ACE* pDeniedAce = static_cast<ACCESS_DENIED_ACE*>(pAce);
                        aceInfo.accessMask = pDeniedAce->Mask;
                        pSid = &pDeniedAce->SidStart;
                    } else if (pAceHeader->AceType == SYSTEM_AUDIT_ACE_TYPE) {
                        SYSTEM_AUDIT_ACE* pAuditAce = static_cast<SYSTEM_AUDIT_ACE*>(pAce);
                        aceInfo.accessMask = pAuditAce->Mask;
                        pSid = &pAuditAce->SidStart;
                    }

                    if (pSid != nullptr && IsValidSid(pSid)) {
                        LPWSTR sidString = nullptr;
                        if (ConvertSidToStringSidW(pSid, &sidString)) {
                            aceInfo.sidString = sidString;
                            LocalFree(sidString);
                        }

                        aceInfo.accountName = resolveSidToName(pSid);

                        // Check if SYSTEM has access
                        if (isSystemSid(aceInfo.sidString) &&
                            pAceHeader->AceType == ACCESS_ALLOWED_ACE_TYPE) {
                            result.systemHasAccess = true;
                        }
                    }

                    result.aces.push_back(aceInfo);
                }
            }
        }
    }

    result.areAccessRulesCanonical = isDaclCanonical(result.aces);
    result.areAuditRulesCanonical = true;

    LocalFree(pSD);
    return result;
}

std::wstring getParentPath(const std::wstring& path) {
    if (path.empty()) {
        return L"";
    }

    std::wstring cleanPath = path;
    while (!cleanPath.empty() && (cleanPath.back() == L'\\' || cleanPath.back() == L'/')) {
        cleanPath.pop_back();
    }

    if (cleanPath.length() == 2 && cleanPath[1] == L':') {
        return L"";
    }

    if (cleanPath.length() >= 2 && cleanPath[0] == L'\\' && cleanPath[1] == L'\\') {
        size_t slashCount = 0;
        for (size_t i = 2; i < cleanPath.length(); i++) {
            if (cleanPath[i] == L'\\') {
                slashCount++;
            }
        }
        if (slashCount <= 1) {
            return L"";
        }
    }

    size_t lastSep = cleanPath.find_last_of(L"\\/");
    if (lastSep == std::wstring::npos) {
        return L"";
    }

    if (lastSep == 2 && cleanPath[1] == L':') {
        return cleanPath.substr(0, 3);
    }

    if (cleanPath[0] == L'\\' && cleanPath[1] == L'\\') {
        size_t serverEnd = cleanPath.find(L'\\', 2);
        if (serverEnd != std::wstring::npos && lastSep <= serverEnd) {
            size_t shareEnd = cleanPath.find(L'\\', serverEnd + 1);
            if (shareEnd == std::wstring::npos) {
                return L"";
            }
            return cleanPath.substr(0, shareEnd);
        }
    }

    return cleanPath.substr(0, lastSep);
}

ParentComparisonResult compareWithParent(const std::wstring& path) {
    ParentComparisonResult result;

    result.parentPath = getParentPath(path);
    if (result.parentPath.empty()) {
        result.success = false;
        result.errorMessage = L"Cannot determine parent path (may be a root folder)";
        return result;
    }

    AclAnalysisResult childAcl = analyzeAcl(path);
    if (!childAcl.success) {
        result.success = false;
        result.errorMessage = L"Failed to analyze child ACL: " + childAcl.errorMessage;
        return result;
    }

    AclAnalysisResult parentAcl = analyzeAcl(result.parentPath);
    if (!parentAcl.success) {
        result.success = false;
        result.errorMessage = L"Failed to analyze parent ACL: " + parentAcl.errorMessage;
        return result;
    }

    result.success = true;

    auto aceKey = [](const AceInfo& ace) {
        return ace.sidString + L"|" + std::to_wstring(ace.accessMask) + L"|" + std::to_wstring(ace.aceType);
    };

    std::vector<std::wstring> childKeys;
    for (const auto& ace : childAcl.aces) {
        childKeys.push_back(aceKey(ace));
    }

    std::vector<std::wstring> parentKeys;
    for (const auto& ace : parentAcl.aces) {
        parentKeys.push_back(aceKey(ace));
    }

    for (size_t i = 0; i < parentAcl.aces.size(); i++) {
        const auto& parentAce = parentAcl.aces[i];

        bool shouldInherit = (parentAce.containerInherit || parentAce.objectInherit) &&
                             !parentAce.noPropagateInherit;

        if (shouldInherit) {
            bool found = false;
            for (const auto& childKey : childKeys) {
                if (childKey == parentKeys[i]) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                result.missingAces.push_back(parentAce);
            }
        }
    }

    for (const auto& childAce : childAcl.aces) {
        if (!childAce.isInherited) {
            result.additionalAces.push_back(childAce);
        }
    }

    return result;
}

// ============================================================================
// Inheritance Consistency Check Functions
// ============================================================================

InheritanceConsistencyResult checkInheritanceConsistency(const std::wstring& path) {
    InheritanceConsistencyResult result;

    // Get parent path
    result.parentPath = getParentPath(path);
    if (result.parentPath.empty()) {
        result.success = false;
        result.errorMessage = L"Cannot determine parent path (may be a root folder)";
        return result;
    }

    // Analyze child ACL
    AclAnalysisResult childAcl = analyzeAcl(path);
    if (!childAcl.success) {
        result.success = false;
        result.errorMessage = L"Failed to analyze child ACL: " + childAcl.errorMessage;
        return result;
    }

    // Analyze parent ACL
    AclAnalysisResult parentAcl = analyzeAcl(result.parentPath);
    if (!parentAcl.success) {
        result.success = false;
        result.errorMessage = L"Failed to analyze parent ACL: " + parentAcl.errorMessage;
        return result;
    }

    result.success = true;
    result.inheritanceEnabled = !childAcl.areAccessRulesProtected;

    // If inheritance is blocked, there's nothing to check
    if (childAcl.areAccessRulesProtected) {
        result.isConsistent = true;  // Protected ACLs are consistent by definition
        return result;
    }

    // Build a key for comparing ACEs (SID + AccessMask + Type)
    auto aceKey = [](const AceInfo& ace) {
        return ace.sidString + L"|" + std::to_wstring(ace.accessMask) + L"|" + std::to_wstring(ace.aceType);
    };

    // Build set of parent's inheritable ACE keys
    std::vector<std::wstring> parentInheritableKeys;
    std::vector<const AceInfo*> parentInheritableAces;
    for (const auto& ace : parentAcl.aces) {
        // An ACE is inheritable if it has CI or OI flag (and not NP for grandchildren)
        // For immediate children, we just need CI or OI
        if (ace.containerInherit || ace.objectInherit) {
            parentInheritableKeys.push_back(aceKey(ace));
            parentInheritableAces.push_back(&ace);
        }
    }

    // Build set of child's inherited ACE keys
    std::vector<std::wstring> childInheritedKeys;
    std::vector<const AceInfo*> childInheritedAces;
    for (const auto& ace : childAcl.aces) {
        if (ace.isInherited) {
            childInheritedKeys.push_back(aceKey(ace));
            childInheritedAces.push_back(&ace);
        }
    }

    // Find orphaned inherited ACEs (in child as inherited, but not inheritable from parent)
    for (size_t i = 0; i < childInheritedAces.size(); i++) {
        bool foundInParent = false;
        for (const auto& parentKey : parentInheritableKeys) {
            if (childInheritedKeys[i] == parentKey) {
                foundInParent = true;
                break;
            }
        }
        if (!foundInParent) {
            result.orphanedInheritedAces.push_back(*childInheritedAces[i]);
        }
    }

    // Find missing inherited ACEs (inheritable from parent, but not in child)
    for (size_t i = 0; i < parentInheritableAces.size(); i++) {
        bool foundInChild = false;
        for (const auto& childKey : childInheritedKeys) {
            if (parentInheritableKeys[i] == childKey) {
                foundInChild = true;
                break;
            }
        }
        if (!foundInChild) {
            result.missingInheritedAces.push_back(*parentInheritableAces[i]);
        }
    }

    // Determine consistency
    result.isConsistent = result.orphanedInheritedAces.empty() && result.missingInheritedAces.empty();

    return result;
}

InheritanceFixResult fixInheritance(const std::wstring& path, bool recursive) {
    InheritanceFixResult result;

    // Build the icacls command
    std::wstring command = L"icacls \"" + path + L"\" /reset";
    if (recursive) {
        command += L" /t";
    }
    result.commandUsed = command;

    // Convert to narrow string for system()
    std::string narrowCmd;
    narrowCmd.reserve(command.length());
    for (wchar_t ch : command) {
        if (ch < 128) {
            narrowCmd += static_cast<char>(ch);
        } else {
            narrowCmd += '?';  // Replace non-ASCII with ?
        }
    }

    // Execute icacls
    // We use _wsystem for wide string support
    int exitCode = _wsystem(command.c_str());

    if (exitCode == 0) {
        result.success = true;
        result.errorCode = 0;
    } else {
        result.success = false;
        result.errorCode = static_cast<DWORD>(exitCode);
        result.errorMessage = L"icacls returned exit code " + std::to_wstring(exitCode);
    }

    return result;
}

AddSystemAceResult addSystemAce(const std::wstring& path) {
    AddSystemAceResult result;

    // First, analyze the current ACL
    AclAnalysisResult aclAnalysis = analyzeAcl(path);
    if (!aclAnalysis.success) {
        result.success = false;
        result.errorCode = aclAnalysis.errorCode;
        result.errorMessage = L"Failed to analyze ACL: " + aclAnalysis.errorMessage;
        return result;
    }

    // Check if inheritance is enabled
    if (!aclAnalysis.areAccessRulesProtected) {
        result.success = true;  // Not an error, just nothing to do
        result.inheritanceWasEnabled = true;
        result.errorMessage = L"Inheritance is enabled. SYSTEM should inherit from parent. No action taken.";
        return result;
    }

    // Check if SYSTEM already has access
    if (aclAnalysis.systemHasAccess) {
        result.success = true;
        result.systemAlreadyPresent = true;
        result.errorMessage = L"SYSTEM already has access. No action needed.";
        return result;
    }

    // Inheritance is blocked and SYSTEM doesn't have access - add it
    // Use icacls to grant SYSTEM:(OI)(CI)F (Full Control with Container and Object Inherit)
    std::wstring command = L"icacls \"" + path + L"\" /grant \"NT AUTHORITY\\SYSTEM:(OI)(CI)F\"";

    int exitCode = _wsystem(command.c_str());

    if (exitCode == 0) {
        result.success = true;
        result.errorCode = 0;
    } else {
        result.success = false;
        result.errorCode = static_cast<DWORD>(exitCode);
        result.errorMessage = L"icacls returned exit code " + std::to_wstring(exitCode);
    }

    return result;
}

// ============================================================================
// JSON Output Functions
// ============================================================================

namespace {

std::wstring escapeJson(const std::wstring& str) {
    std::wstring result;
    result.reserve(str.size() + 16);

    for (wchar_t ch : str) {
        switch (ch) {
            case L'"':  result += L"\\\""; break;
            case L'\\': result += L"\\\\"; break;
            case L'\b': result += L"\\b"; break;
            case L'\f': result += L"\\f"; break;
            case L'\n': result += L"\\n"; break;
            case L'\r': result += L"\\r"; break;
            case L'\t': result += L"\\t"; break;
            default:
                if (ch < 0x20) {
                    wchar_t buf[8];
                    swprintf_s(buf, L"\\u%04x", static_cast<unsigned int>(ch));
                    result += buf;
                } else {
                    result += ch;
                }
                break;
        }
    }

    return result;
}

} // anonymous namespace

std::wstring toJson(const PathValidationResult& result) {
    std::wstringstream json;

    json << L"{\n";
    json << L"  \"path\": \"" << escapeJson(result.path) << L"\",\n";
    json << L"  \"verdict\": \"" << (result.getVerdict() == ValidationVerdict::Pass ? L"PASS" :
                                     result.getVerdict() == ValidationVerdict::Warning ? L"WARNING" : L"FAIL") << L"\",\n";
    json << L"  \"exitCode\": " << static_cast<int>(result.getExitCode()) << L",\n";
    json << L"  \"pathInfo\": {\n";
    json << L"    \"exists\": " << (result.exists ? L"true" : L"false") << L",\n";

    if (result.exists) {
        json << L"    \"isDirectory\": " << (result.isDirectory ? L"true" : L"false") << L",\n";
        json << L"    \"fileSystem\": \"" << escapeJson(result.fsInfo.fileSystemName) << L"\",\n";
        json << L"    \"volumeName\": \"" << escapeJson(result.fsInfo.volumeName) << L"\",\n";
        if (result.reparseType != ReparsePointType::None) {
            json << L"    \"reparseType\": \"" << getReparsePointTypeString(result.reparseType) << L"\",\n";
        }
        json << L"    \"attributes\": {\n";
        json << L"      \"readonly\": " << (result.attributes.readonly ? L"true" : L"false") << L",\n";
        json << L"      \"hidden\": " << (result.attributes.hidden ? L"true" : L"false") << L",\n";
        json << L"      \"system\": " << (result.attributes.system ? L"true" : L"false") << L",\n";
        json << L"      \"compressed\": " << (result.attributes.compressed ? L"true" : L"false") << L",\n";
        json << L"      \"encrypted\": " << (result.attributes.encrypted ? L"true" : L"false") << L",\n";
        json << L"      \"reparsePoint\": " << (result.attributes.reparsePoint ? L"true" : L"false") << L"\n";
        json << L"    },\n";
    }

    json << L"    \"pathLength\": " << result.pathLength << L",\n";
    json << L"    \"exceedsMaxPath\": " << (result.exceedsMaxPath ? L"true" : L"false") << L"\n";
    json << L"  },\n";

    json << L"  \"accessTest\": {\n";
    json << L"    \"success\": " << (result.accessResult.success ? L"true" : L"false") << L",\n";
    json << L"    \"errorCode\": " << result.accessResult.errorCode << L",\n";
    json << L"    \"errorMessage\": " << (result.accessResult.errorMessage.empty() ? L"null" :
                                          L"\"" + escapeJson(result.accessResult.errorMessage) + L"\"") << L"\n";
    json << L"  },\n";

    json << L"  \"aclTest\": {\n";
    json << L"    \"success\": " << (result.aclResult.success ? L"true" : L"false") << L",\n";
    json << L"    \"errorCode\": " << result.aclResult.errorCode << L",\n";
    json << L"    \"daclPresent\": " << (result.aclResult.daclPresent ? L"true" : L"false") << L",\n";
    json << L"    \"aceCount\": " << result.aclResult.aceCount << L"\n";
    json << L"  },\n";

    json << L"  \"longPathTest\": {\n";
    json << L"    \"success\": " << (result.longPathWorks ? L"true" : L"false") << L",\n";
    json << L"    \"longPath\": \"" << escapeJson(result.longPath) << L"\"\n";
    json << L"  },\n";

    json << L"  \"recommendations\": [\n";
    auto recommendations = result.getRecommendations();
    for (size_t i = 0; i < recommendations.size(); ++i) {
        json << L"    \"" << escapeJson(recommendations[i]) << L"\"";
        if (i < recommendations.size() - 1) {
            json << L",";
        }
        json << L"\n";
    }
    json << L"  ]\n";

    json << L"}";

    return json.str();
}

std::wstring toJsonCompact(const PathValidationResult& result) {
    std::wstringstream json;

    json << L"{";
    json << L"\"path\":\"" << escapeJson(result.path) << L"\",";
    json << L"\"verdict\":\"" << (result.getVerdict() == ValidationVerdict::Pass ? L"PASS" :
                                   result.getVerdict() == ValidationVerdict::Warning ? L"WARNING" : L"FAIL") << L"\",";
    json << L"\"exists\":" << (result.exists ? L"true" : L"false") << L",";
    json << L"\"canAccess\":" << (result.accessResult.success ? L"true" : L"false") << L",";
    json << L"\"canGetAcl\":" << (result.aclResult.success ? L"true" : L"false") << L",";
    json << L"\"exitCode\":" << static_cast<int>(result.getExitCode());
    json << L"}";

    return json.str();
}

} // namespace PathUtils
