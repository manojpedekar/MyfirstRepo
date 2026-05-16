// ACLInfo.h
#pragma once

#include <string>
#include <vector>
#include <windows.h>

/// Access control entry types
enum class AceType {
    Allow,
    Deny,
    Audit,          // For SYSTEM_AUDIT_ACE_TYPE
    Alarm,          // For SYSTEM_ALARM_ACE_TYPE
    AllowCallback,  // For ACCESS_ALLOWED_CALLBACK_ACE_TYPE
    DenyCallback,   // For ACCESS_DENIED_CALLBACK_ACE_TYPE
    Unknown         // For unsupported or unrecognized ACE types
};

/// Information about a single access control entry
struct AceInfo {
    DWORD accessMask = 0;
    AceType accessType = AceType::Allow;  // Initialize to prevent warning
    std::wstring sidString;
    std::wstring trustee;
    bool isInherited = false;
    BYTE inheritanceMask = 0;
    BYTE propagationMask = 0;
    std::wstring inheritedFrom;
};

/// Information about an access control list
struct AclInfo {
    std::wstring owner;
    std::wstring group;
    bool areAccessRulesProtected = false;
    bool areAuditRulesProtected = false;
    bool areAccessRulesCanonical = true;
    bool areAuditRulesCanonical = true;
    std::vector<AceInfo> aces;
};

// Function to get ACL information for a path
AclInfo GetAclInfo(const std::wstring& path);

// Function to enable required privileges for ACL operations
bool EnableAclPrivs();
