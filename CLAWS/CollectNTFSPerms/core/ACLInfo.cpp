// getAcl.cpp
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <ntsecapi.h>
#include <wil/resource.h>
#include <iostream>
#include <iomanip>
#include <vector>
#include <string>
#include <stdexcept>
#include <algorithm>
#include <locale>
#include <sstream>
#include "AclInfo.h"  // assumes your AclInfo.h is in the same folder

#pragma comment(lib, "secur32.lib")

// Define LSA constants if not available in older Windows SDKs
#ifndef LSA_LOOKUP_RETURN_LOCAL_NAMES
#define LSA_LOOKUP_RETURN_LOCAL_NAMES 0x80000000
#endif

#ifndef STATUS_SOME_NOT_MAPPED
#define STATUS_SOME_NOT_MAPPED ((NTSTATUS)0x00000107L)
#endif

// Forward declaration for ResolveServiceSid
static std::wstring ResolveServiceSid(const std::wstring& sidString);

//-------------------------------------------------------------------------------------------------
// Enable SeSecurityPrivilege and SeBackupPrivilege before any ACL calls
static bool EnableAclPrivs()
{
    wil::unique_handle hToken;
    if (!OpenProcessToken(GetCurrentProcess(),
        TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY,
        hToken.addressof()))
    {
        return false;
    }

    auto Enable = [&](LPCWSTR name) -> bool {
        TOKEN_PRIVILEGES tp = {};
        LUID luid;
        if (!LookupPrivilegeValueW(nullptr, name, &luid)) {
            return false;
        }
        tp.PrivilegeCount = 1;
        tp.Privileges[0].Luid = luid;
        tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
        if (!AdjustTokenPrivileges(hToken.get(), FALSE, &tp, sizeof(tp), nullptr, nullptr)) {
            return false;
        }
        if (GetLastError() == ERROR_NOT_ALL_ASSIGNED) {
            return false;
        }
        return true;
    };

    bool ok = Enable(SE_BACKUP_NAME);
    ok &= Enable(SE_SECURITY_NAME);
    return ok;
}

// Convert PSID to S-1-... string
static std::wstring SidToString(PSID sid) {
    if (!sid) return L"";
    LPWSTR str = nullptr;
    if (ConvertSidToStringSidW(sid, &str)) {
        std::wstring ret = str;
        LocalFree(str);
        return ret;
    }
    return L"";
}

// Improve SidToAccountName function to better handle all types of SIDs
static std::wstring SidToAccountName(PSID sid) {
    if (!sid) return L"";
    
    DWORD nameLen = 0, domainLen = 0;
    SID_NAME_USE use;
    
    // First call to get buffer sizes
    LookupAccountSidW(nullptr, sid, nullptr, &nameLen, nullptr, &domainLen, &use);
    
    if (nameLen > 0 && domainLen > 0) {
        // Allocate buffers
        std::vector<wchar_t> name(nameLen);
        std::vector<wchar_t> domain(domainLen);
        
        // Second call to get actual data
        if (LookupAccountSidW(nullptr, sid, name.data(), &nameLen, domain.data(), &domainLen, &use)) {
            std::wstring accountName;
            
            // Format the account name based on domain
            if (domain[0] != L'\0') {
                accountName = std::wstring(domain.data()) + L"\\" + std::wstring(name.data());
            } else {
                accountName = std::wstring(name.data());
            }
            
            return accountName;
        }
    }
    
    // If standard lookup failed, try to handle special SIDs
    
    // Convert SID to string for further processing
    LPWSTR sidString = nullptr;
    if (!ConvertSidToStringSidW(sid, &sidString)) {
        return L"";
    }
    
    std::wstring sidStr(sidString);
    LocalFree(sidString);
    
    // Try to resolve service SIDs (S-1-5-80-...)
    if (sidStr.find(L"S-1-5-80-") == 0) {
        return ResolveServiceSid(sidStr);
    }
    
    // If all else fails, return the SID string
    return sidStr;
}

// Is this path a directory?
static bool IsDirectory(const std::wstring& path) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY);
}

AclInfo GetAclInfo(const std::wstring& path) {
    if (path.empty()) throw std::invalid_argument("Path cannot be empty");

    if (!EnableAclPrivs())
        throw std::runtime_error("Failed to enable required privileges");

    AclInfo info;
    PSECURITY_DESCRIPTOR pSD = nullptr;
    PSID ownerSid = nullptr, groupSid = nullptr;
    PACL pDacl = nullptr;

    // FIX NEW-016: Create mutable copy instead of const_cast to avoid violating const-correctness
    // GetNamedSecurityInfoW takes non-const LPWSTR but doesn't actually modify it (Windows API quirk)
    std::wstring mutablePath = path;

    // 1) Get named security info
    DWORD res = GetNamedSecurityInfoW(
        mutablePath.data(),  // Use data() on mutable copy instead of const_cast
        SE_FILE_OBJECT,
        OWNER_SECURITY_INFORMATION |
        GROUP_SECURITY_INFORMATION |
        DACL_SECURITY_INFORMATION,
        &ownerSid, &groupSid, &pDacl, nullptr, &pSD
    );
    if (res != ERROR_SUCCESS) {
        throw std::runtime_error("GetNamedSecurityInfoW failed with error code: " + std::to_string(res));
    }
    // ensure security descriptor freed
    struct SDCleanup { PSECURITY_DESCRIPTOR* p; ~SDCleanup() { if (*p) LocalFree(*p); } }
    sd{ &pSD };

    // 2) Owner & group - use SID strings directly
    info.owner = ownerSid ? SidToString(ownerSid) : L"<unknown>";
    info.group = groupSid ? SidToString(groupSid) : L"<unknown>";

    // 3) Protection & canonical flags
    {
        SECURITY_DESCRIPTOR_CONTROL ctrl;
        DWORD rev;
        if (GetSecurityDescriptorControl(pSD, &ctrl, &rev)) {
            info.areAccessRulesProtected = BOOL(ctrl & SE_DACL_PROTECTED) != 0;
            info.areAuditRulesProtected = BOOL(ctrl & SE_SACL_PROTECTED) != 0;
            info.areAccessRulesCanonical = BOOL(ctrl & SE_DACL_AUTO_INHERITED) != 0;
            info.areAuditRulesCanonical = BOOL(ctrl & SE_SACL_AUTO_INHERITED) != 0;
        }
    }

    // 4) Get inheritance source information
    // FC-006 FIX: Validate owner before calling GetInheritanceSourceW
    // GetInheritanceSourceW internally needs to read the owner from the security descriptor
    // If the owner is NULL, the API can fail. This is rare but can happen with corrupted
    // or improperly created security descriptors.
    DWORD aceCount = pDacl ? pDacl->AceCount : 0;
    std::vector<INHERITED_FROMW> inheritArray;
    if (aceCount > 0 && ownerSid != nullptr) {  // FC-006: Check ownerSid is valid
        inheritArray.resize(aceCount);
        memset(inheritArray.data(), 0, aceCount * sizeof(INHERITED_FROMW));
        GENERIC_MAPPING mapping = {
            FILE_GENERIC_READ,
            FILE_GENERIC_WRITE,
            FILE_GENERIC_EXECUTE,
            FILE_ALL_ACCESS
        };
        BOOL isContainer = IsDirectory(path);
        res = GetInheritanceSourceW(
            const_cast<LPWSTR>(path.c_str()),
            SE_FILE_OBJECT,
            DACL_SECURITY_INFORMATION,
            isContainer,
            nullptr,
            0,  // This is fine as 0, no need for casting
            pDacl,
            nullptr,
            &mapping,
            inheritArray.data()
        );
        if (res != ERROR_SUCCESS) {
            std::wcerr << L"GetInheritanceSourceW failed: " << res << L"\n";
            inheritArray.clear();
        }
    } else if (aceCount > 0 && ownerSid == nullptr) {
        // FC-006: Log when inheritance source cannot be determined due to NULL owner
        std::wcerr << L"Warning: Cannot determine ACE inheritance sources - security descriptor has NULL owner: "
                   << path << L"\n";
    }

    // 5) Enumerate ACEs
    if (pDacl) {
        for (DWORD i = 0; i < pDacl->AceCount; ++i) {
            LPVOID pAce = nullptr;
            if (!GetAce(pDacl, i, &pAce)) continue;
            auto hdr = static_cast<ACE_HEADER*>(pAce);

            AceInfo ace;
            ace.inheritanceMask = hdr->AceFlags & (OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE);
            ace.propagationMask = hdr->AceFlags & (NO_PROPAGATE_INHERIT_ACE | INHERIT_ONLY_ACE);
            ace.isInherited = BOOL(hdr->AceFlags & INHERITED_ACE);

            // Set inherited from information if available
            if (ace.isInherited && !inheritArray.empty() && inheritArray[i].AncestorName) {
                ace.inheritedFrom = inheritArray[i].AncestorName;
            }

            PSID sidPtr = nullptr;
            if (hdr->AceType == ACCESS_ALLOWED_ACE_TYPE) {
                auto* a = reinterpret_cast<ACCESS_ALLOWED_ACE*>(pAce);
                ace.accessMask = a->Mask;
                sidPtr = reinterpret_cast<PSID>(&a->SidStart);
                ace.accessType = AceType::Allow;
            }
            else if (hdr->AceType == ACCESS_DENIED_ACE_TYPE) {
                auto* d = reinterpret_cast<ACCESS_DENIED_ACE*>(pAce);
                ace.accessMask = d->Mask;
                sidPtr = reinterpret_cast<PSID>(&d->SidStart);
                ace.accessType = AceType::Deny;
            }
            else {
                continue;
            }

            ace.sidString = SidToString(sidPtr);
            ace.trustee = ace.sidString;  // Use SID string instead of resolved name
            info.aces.push_back(std::move(ace));
        }
    }

    // 6) Cleanup inheritance source information
    if (!inheritArray.empty()) {
        FreeInheritedFromArray(inheritArray.data(), static_cast<USHORT>(inheritArray.size()), nullptr);
    }

    return info;
}

//---------------------------------------------------------------------------
// wmain: print everything in one loop
#ifdef ACLINFO_STANDALONE
int wmain(int argc, wchar_t* argv[]) {
    if (argc != 2) {
        std::wcerr << L"Usage: " << argv[0] << L" <path>\n";
        return 1;
    }

    try {
        std::wstring path = argv[1];
        AclInfo acl = GetAclInfo(path);

        // Print basic info
        std::wcout
            << L"Path:  " << path << L"\n"
            << L"Owner: " << acl.owner << L"\n"
            << L"Group: " << acl.group << L"\n\n"
            << L"AreAccessRulesProtected:  " << (acl.areAccessRulesProtected ? L"Yes" : L"No") << L"\n"
            << L"AreAuditRulesProtected:   " << (acl.areAuditRulesProtected ? L"Yes" : L"No") << L"\n"
            << L"AreAccessRulesCanonical:  " << (acl.areAccessRulesCanonical ? L"Yes" : L"No") << L"\n"
            << L"AreAuditRulesCanonical:   " << (acl.areAuditRulesCanonical ? L"Yes" : L"No") << L"\n\n";

        // Print detailed ACE information
        for (const auto& ace : acl.aces) {
            std::wcout
                << L"IdentityReference:  " << ace.trustee << L"\n"
                << L"AccessControlType:  " << (ace.accessType == AceType::Allow ? L"Allow" : L"Deny") << L"\n"
                << L"Mask:               0x" << std::hex << std::setw(10) << std::setfill(L'0')
                << ace.accessMask << std::dec << L"\n"
                << L"Inherited:          " << (ace.isInherited ? L"Yes" : L"No") << L"\n"
                << L"InheritanceMask:    0x" << std::hex << std::setw(2) << std::setfill(L'0')
                << static_cast<unsigned>(ace.inheritanceMask) << std::dec << L"\n"
                << L"PropagationMask:    0x" << std::hex << std::setw(2) << std::setfill(L'0')
                << static_cast<unsigned>(ace.propagationMask) << std::dec << L"\n";

            //if (ace.isInherited) {
            std::wcout << L"InheritedFrom:      " << (ace.inheritedFrom.empty() ? path : ace.inheritedFrom);
            //}
            std::wcout << L"\n\n";
        }

        return 0;
    }
    catch (const std::exception& e) {
        std::wcerr << L"Error: " << e.what() << L"\n";
        return 1;
    }
}
#endif

// Function to resolve service SIDs using native Windows APIs (LsaLookupSids2)
// This replaces the previous PowerShell-based approach which had command injection vulnerabilities
static std::wstring ResolveServiceSid(const std::wstring& sidString) {
    // Convert string SID to binary SID
    PSID pSid = nullptr;
    if (!ConvertStringSidToSidW(sidString.c_str(), &pSid)) {
        return sidString; // Return original if conversion fails
    }

    // RAII cleanup for the SID
    struct SidCleanup {
        PSID* p;
        ~SidCleanup() { if (*p) LocalFree(*p); }
    } sidGuard{ &pSid };

    // Open a handle to the local LSA policy
    LSA_HANDLE hPolicy = nullptr;
    LSA_OBJECT_ATTRIBUTES oa = {};

    NTSTATUS status = LsaOpenPolicy(nullptr, &oa, POLICY_LOOKUP_NAMES, &hPolicy);
    if (status != STATUS_SUCCESS) {
        return sidString; // Return original if policy open fails
    }

    // RAII cleanup for the policy handle
    struct PolicyCleanup {
        LSA_HANDLE h;
        ~PolicyCleanup() { if (h) LsaClose(h); }
    } policyGuard{ hPolicy };

    // Lookup the SID using LsaLookupSids2 for better resolution
    PLSA_REFERENCED_DOMAIN_LIST domains = nullptr;
    PLSA_TRANSLATED_NAME names = nullptr;

    status = LsaLookupSids2(
        hPolicy,
        LSA_LOOKUP_RETURN_LOCAL_NAMES,  // Flag to try harder to resolve local accounts
        1,                               // Number of SIDs to lookup
        &pSid,                          // Array of SIDs
        &domains,                        // Output: referenced domains
        &names                           // Output: translated names
    );

    // RAII cleanup for LSA memory
    struct LsaMemoryCleanup {
        PLSA_REFERENCED_DOMAIN_LIST* d;
        PLSA_TRANSLATED_NAME* n;
        ~LsaMemoryCleanup() {
            if (*n) LsaFreeMemory(*n);
            if (*d) LsaFreeMemory(*d);
        }
    } lsaGuard{ &domains, &names };

    // Check if lookup succeeded and we got a valid name
    if (status != STATUS_SUCCESS && status != STATUS_SOME_NOT_MAPPED) {
        return sidString; // Return original if lookup fails completely
    }

    // Check if we got a valid translated name
    if (!names || names[0].Use == SidTypeUnknown || names[0].Use == SidTypeInvalid) {
        return sidString; // Return original if SID type is unknown
    }

    // Build the result string
    std::wstring result;

    // Get the account name
    if (names[0].Name.Length > 0 && names[0].Name.Buffer) {
        std::wstring accountName(names[0].Name.Buffer, names[0].Name.Length / sizeof(WCHAR));

        // Prepend domain if available and valid
        if (domains && names[0].DomainIndex >= 0 &&
            static_cast<ULONG>(names[0].DomainIndex) < domains->Entries) {

            LSA_TRUST_INFORMATION& domain = domains->Domains[names[0].DomainIndex];
            if (domain.Name.Length > 0 && domain.Name.Buffer) {
                std::wstring domainName(domain.Name.Buffer, domain.Name.Length / sizeof(WCHAR));
                result = domainName + L"\\" + accountName;
            } else {
                result = accountName;
            }
        } else {
            result = accountName;
        }
    }

    // Return resolved name or original SID if resolution produced empty result
    return result.empty() ? sidString : result;
}
