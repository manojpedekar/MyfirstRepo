# AD_Object Table Schema Analysis

## Overview

This document provides a comprehensive analysis of the `AD_Object` table schema in the ADInventory module, documenting all columns defined, attributes collected for each object type (Users, Computers, Groups, Contacts), and recommendations for additional useful attributes not currently being collected.

**Analysis Date:** 2025-01-05
**Schema Version:** 3.0.0
**Module:** SSNC.ADInventory

---

## AD_Object Table Schema Definition

The `AD_Object` table stores all AD security principals in a single unified table. Source: `ADInventory/Resources/Schema/ADInventory.sql`

### Columns Defined

| Column Name | Data Type | Nullable | Description |
|------------|-----------|----------|-------------|
| **SID_String** | TEXT | NOT NULL | Real SID for security principals; synthetic "CN:{GUID}" for contacts |
| **ObjectType** | INTEGER | NOT NULL | 1=User, 2=Group, 3=Computer, 4=Contact |
| **SamAccountName** | TEXT | NULL | Pre-Windows 2000 logon name |
| **DisplayName** | TEXT | NULL | Display name |
| **UserPrincipalName** | TEXT | NULL | UPN (user@domain.com format) |
| **DomainName** | TEXT | NOT NULL | Object's domain (DNS format) |
| **DistinguishedName** | TEXT | NOT NULL | Full LDAP DN path |
| **ObjectGUID** | TEXT | NULL | Unique AD object identifier |
| **CanonicalName** | TEXT | NULL | Human-readable path (domain.com/OU/Name) |
| **Description** | TEXT | NULL | Object description |
| **WhenCreated** | TEXT | NULL | Creation timestamp (ISO 8601) |
| **WhenChanged** | TEXT | NULL | Last modification timestamp (ISO 8601) |
| **Enabled** | INTEGER | NULL | 1=enabled, 0=disabled |
| **LastLogonTimestamp** | TEXT | NULL | Last logon (replicated, ISO 8601) |
| **PasswordLastSet** | TEXT | NULL | Password last set (ISO 8601) |
| **AccountExpires** | TEXT | NULL | Account expiration (ISO 8601, NULL=never) |
| **PasswordNeverExpires** | INTEGER | NULL | 1=true, 0=false |
| **GivenName** | TEXT | NULL | First name |
| **Surname** | TEXT | NULL | Last name |
| **Mail** | TEXT | NULL | Email address |
| **Department** | TEXT | NULL | Department |
| **Title** | TEXT | NULL | Job title |
| **Manager** | TEXT | NULL | Manager DN |
| **EmployeeID** | TEXT | NULL | Employee ID |
| **GroupType** | INTEGER | NULL | Group type bitmask |
| **GroupScope** | INTEGER | NULL | 1=DomainLocal, 2=Global, 3=Universal |
| **ManagedBy** | TEXT | NULL | Group/object manager DN |
| **SIDHistory** | TEXT | NULL | JSON array of historical SIDs |
| **IsForeignSecurityPrincipal** | INTEGER | DEFAULT 0 | Flag for FSPs |
| **CollectionID** | INTEGER | NOT NULL | FK to AD_CollectionInfo |

**Primary Key:** (SID_String, CollectionID)

---

## LDAP Attributes Being Collected

The module queries the following LDAP attributes (from `Get-ADObjects.ps1` lines 96-126):

```
objectSid, distinguishedName, name, objectClass, objectGUID, canonicalName,
description, whenCreated, whenChanged, samAccountName, displayName,
userPrincipalName, mail, givenName, sn (surname), department, title,
manager, employeeID, memberOf, member, primaryGroupID, userAccountControl,
groupType, managedBy, sIDHistory, lastLogonTimestamp, pwdLastSet, accountExpires
```

---

## Attributes by Object Type

### Users (ObjectType = 1)

**LDAP Filter:** `(&(objectClass=user)(objectCategory=person))`

| Attribute | LDAP Property | Stored | Notes |
|-----------|---------------|--------|-------|
| SID | objectSid | Yes | Converted to string |
| Distinguished Name | distinguishedName | Yes | Full path |
| SAM Account Name | samAccountName | Yes | Pre-2000 name |
| Display Name | displayName | Yes | |
| User Principal Name | userPrincipalName | Yes | UPN format |
| Object GUID | objectGUID | Yes | Converted to string |
| Canonical Name | canonicalName | Yes | Readable path |
| Description | description | Yes | |
| When Created | whenCreated | Yes | ISO 8601 |
| When Changed | whenChanged | Yes | ISO 8601 |
| Enabled | userAccountControl | Yes | Derived from UAC bit 0x0002 |
| Last Logon | lastLogonTimestamp | Yes | ISO 8601 |
| Password Last Set | pwdLastSet | Yes | ISO 8601 |
| Account Expires | accountExpires | Yes | ISO 8601 |
| Password Never Expires | userAccountControl | Yes | Derived from UAC bit 0x10000 |
| First Name | givenName | Yes | |
| Last Name | sn | Yes | |
| Email | mail | Yes | |
| Department | department | Yes | |
| Title | title | Yes | |
| Manager | manager | Yes | DN format |
| Employee ID | employeeID | Yes | |
| SID History | sIDHistory | Yes | JSON array |

### Computers (ObjectType = 3)

**LDAP Filter:** `(objectClass=computer)`

| Attribute | LDAP Property | Stored | Notes |
|-----------|---------------|--------|-------|
| SID | objectSid | Yes | Converted to string |
| Distinguished Name | distinguishedName | Yes | Full path |
| SAM Account Name | samAccountName | Yes | Includes trailing $ |
| Display Name | displayName | Yes | |
| Object GUID | objectGUID | Yes | Converted to string |
| Canonical Name | canonicalName | Yes | Readable path |
| Description | description | Yes | |
| When Created | whenCreated | Yes | ISO 8601 |
| When Changed | whenChanged | Yes | ISO 8601 |
| Enabled | userAccountControl | Yes | Derived from UAC bit |
| Last Logon | lastLogonTimestamp | Yes | ISO 8601 |
| Password Last Set | pwdLastSet | Yes | ISO 8601 |
| Account Expires | accountExpires | Yes | ISO 8601 |
| Password Never Expires | userAccountControl | Yes | Derived from UAC |
| SID History | sIDHistory | Yes | JSON array |

### Groups (ObjectType = 2)

**LDAP Filter:** `(objectClass=group)`

| Attribute | LDAP Property | Stored | Notes |
|-----------|---------------|--------|-------|
| SID | objectSid | Yes | Converted to string |
| Distinguished Name | distinguishedName | Yes | Full path |
| SAM Account Name | samAccountName | Yes | |
| Display Name | displayName | Yes | |
| Object GUID | objectGUID | Yes | Converted to string |
| Canonical Name | canonicalName | Yes | Readable path |
| Description | description | Yes | |
| When Created | whenCreated | Yes | ISO 8601 |
| When Changed | whenChanged | Yes | ISO 8601 |
| Group Type | groupType | Yes | Bitmask |
| Group Scope | groupType | Yes | Derived: 1=DL, 2=Global, 3=Universal |
| Managed By | managedBy | Yes | DN format |
| SID History | sIDHistory | Yes | JSON array |
| Members | member | No | Stored in AD_GroupMembership table |

### Contacts (ObjectType = 4)

**LDAP Filter:** `(objectClass=contact)`

| Attribute | LDAP Property | Stored | Notes |
|-----------|---------------|--------|-------|
| Synthetic SID | objectGUID | Yes | "CN:{GUID}" format since contacts have no real SID |
| Distinguished Name | distinguishedName | Yes | Full path |
| SAM Account Name | samAccountName | Yes | Usually empty for contacts |
| Display Name | displayName | Yes | |
| Object GUID | objectGUID | Yes | Converted to string |
| Canonical Name | canonicalName | Yes | Readable path |
| Description | description | Yes | |
| When Created | whenCreated | Yes | ISO 8601 |
| When Changed | whenChanged | Yes | ISO 8601 |
| First Name | givenName | Yes | |
| Last Name | sn | Yes | |
| Email | mail | Yes | Primary contact info |
| Department | department | Yes | |
| Title | title | Yes | |
| Manager | manager | Yes | DN format |

---

## Useful Attributes NOT Currently Being Collected

The following attributes are commonly useful in AD inventory scenarios but are not currently collected:

### High Priority - Security & Compliance

| Attribute | LDAP Name | Object Types | Use Case |
|-----------|-----------|--------------|----------|
| **Account Lockout Time** | lockoutTime | User, Computer | Security monitoring, detect brute force |
| **Bad Password Count** | badPwdCount | User, Computer | Security monitoring (not replicated) |
| **Bad Password Time** | badPasswordTime | User, Computer | Security monitoring (not replicated) |
| **Logon Count** | logonCount | User, Computer | Activity tracking (not replicated) |
| **Last Logon (local)** | lastLogon | User, Computer | More accurate than lastLogonTimestamp but not replicated |
| **Password Expired** | msDS-UserPasswordExpired | User | Computed attribute for compliance |
| **Service Principal Names** | servicePrincipalName | User, Computer | Kerberos service accounts, security auditing |
| **Admin Count** | adminCount | User, Group | Identifies privileged accounts (SDProp protected) |
| **User Account Control (raw)** | userAccountControl | User, Computer | Full bitmask for all account flags |
| **ms-DS-CreatorSID** | msDS-CreatorSID | All | Who created the object |

### Medium Priority - Identity & Organization

| Attribute | LDAP Name | Object Types | Use Case |
|-----------|-----------|--------------|----------|
| **Company** | company | User, Contact | Organization reporting |
| **Office** | physicalDeliveryOfficeName | User, Contact | Location tracking |
| **Street Address** | streetAddress | User, Contact | Location/compliance |
| **City** | l | User, Contact | Location reporting |
| **State** | st | User, Contact | Location reporting |
| **Country** | co / c | User, Contact | Regional compliance |
| **Postal Code** | postalCode | User, Contact | Location reporting |
| **Telephone** | telephoneNumber | User, Contact | Directory services |
| **Mobile** | mobile | User, Contact | MFA/directory services |
| **Employee Number** | employeeNumber | User | HR integration (different from employeeID) |
| **Employee Type** | employeeType | User | Contractor vs Employee |
| **Division** | division | User | Organization structure |
| **Home Directory** | homeDirectory | User | User profile management |
| **Home Drive** | homeDrive | User | User profile management |
| **Profile Path** | profilePath | User | Roaming profiles |
| **Script Path** | scriptPath | User | Logon scripts |

### Medium Priority - Computer Specific

| Attribute | LDAP Name | Object Types | Use Case |
|-----------|-----------|--------------|----------|
| **Operating System** | operatingSystem | Computer | Inventory, patching |
| **OS Version** | operatingSystemVersion | Computer | Version compliance |
| **OS Service Pack** | operatingSystemServicePack | Computer | Patch level |
| **DNS Host Name** | dNSHostName | Computer | Network identification |
| **IPv4 Address** | msDS-IPv4Address | Computer | Network inventory |
| **Site** | msDS-SiteName | Computer | AD site membership |
| **Is Critical System** | isCriticalSystemObject | Computer | Identify DCs, critical infra |
| **Last Logon Date (DC)** | lastLogonTimestamp | Computer | Machine activity |
| **Managed By** | managedBy | Computer | Ownership tracking |

### Lower Priority - Extended Attributes

| Attribute | LDAP Name | Object Types | Use Case |
|-----------|-----------|--------------|----------|
| **Proxy Addresses** | proxyAddresses | User, Contact, Group | All email aliases (multi-valued) |
| **Target Address** | targetAddress | Contact | External routing |
| **Member Of** | memberOf | User, Computer | Direct group memberships (already tracked separately) |
| **Primary Group ID** | primaryGroupID | User, Computer | Default primary group |
| **Photo** | thumbnailPhoto | User | Directory photos |
| **Info/Notes** | info | All | General notes field |
| **WWW Home Page** | wWWHomePage | User | User web page |
| **ms-DS-Allowed-To-Delegate-To** | msDS-AllowedToDelegateTo | User, Computer | Kerberos delegation config |
| **ms-DS-Allowed-To-Act-On-Behalf-Of** | msDS-AllowedToActOnBehalfOfOtherIdentity | Computer | Resource-based delegation |
| **User Certificate** | userCertificate | User | PKI/certificate tracking |
| **Extension Attributes 1-15** | extensionAttribute1-15 | User | Custom enterprise attributes |

### Group Specific Attributes

| Attribute | LDAP Name | Object Types | Use Case |
|-----------|-----------|--------------|----------|
| **Group Category** | groupType | Group | Security vs Distribution (already partially captured) |
| **Mail Enabled** | mail | Group | Distribution list tracking |
| **Is Critical System Object** | isCriticalSystemObject | Group | Built-in groups |
| **Admin SD Holder Protected** | adminCount | Group | Privileged groups |

---

## Recommendations

### Immediate Additions (Security Focus)

1. **servicePrincipalName** - Critical for identifying service accounts and Kerberoastable accounts
2. **adminCount** - Identifies privileged/SDProp-protected objects
3. **lockoutTime** - Security monitoring
4. **operatingSystem** + **operatingSystemVersion** (Computers) - Essential for inventory

### Secondary Additions (Operational)

1. **company** - Common organizational attribute
2. **telephoneNumber** + **mobile** - Directory completeness
3. **dNSHostName** (Computers) - Network identification
4. **proxyAddresses** - Email alias tracking (consider JSON storage)

### Schema Changes Required

To add new attributes, modifications would be needed in:

1. **ADInventory.sql** - Add new columns to AD_Object table
2. **Get-ADObjects.ps1** - Add attributes to `$propertiesToLoad` array (line 96-126)
3. **Get-ADObjects.ps1** - Extract and transform new attributes in `$processObject` script block (line 129-290)
4. **Add-SQLiteBatch.ps1** - Column mapping may need updates

### Storage Considerations

- Multi-valued attributes (proxyAddresses, servicePrincipalName) should be stored as JSON arrays
- Large binary attributes (thumbnailPhoto, userCertificate) may significantly increase database size
- Consider separate tables for multi-valued attributes if needed for querying

---

## Proposed Schema Additions

The following attributes are recommended for addition to the AD_Object table, with appropriate data types for both SQLite and MSSQL:

### New Columns Definition

| LDAP Name | Column Name | Object Types | SQLite Type | MSSQL Type | Description |
|-----------|-------------|--------------|-------------|------------|-------------|
| dNSHostName | DNSHostName | Computer | TEXT | NVARCHAR(255) | DNS hostname (e.g., "server01.contoso.com") |
| employeeNumber | EmployeeNumber | User | TEXT | NVARCHAR(50) | HR employee number (different from EmployeeID) |
| employeeType | EmployeeType | User | TEXT | NVARCHAR(100) | "Employee", "Contractor", "Intern", etc. |
| isCriticalSystemObject | IsCriticalSystemObject | Computer, Group | INTEGER | BIT | 1=critical (DCs, built-in), 0=normal |
| operatingSystem | OperatingSystem | Computer | TEXT | NVARCHAR(128) | "Windows Server 2022 Standard" |
| operatingSystemServicePack | OperatingSystemServicePack | Computer | TEXT | NVARCHAR(64) | "Service Pack 1" (legacy) |
| operatingSystemVersion | OperatingSystemVersion | Computer | TEXT | NVARCHAR(32) | "10.0 (20348)" build format |
| operatingSystemHotfix | OperatingSystemHotfix | Computer | TEXT | NVARCHAR(64) | Deprecated - rarely populated |
| msDS-UserPasswordExpired | PasswordExpired | User | INTEGER | BIT | Computed: 1=expired, 0=valid |
| servicePrincipalName | ServicePrincipalName | User, Computer | TEXT | NVARCHAR(MAX) | **Multi-valued** - JSON array |
| userAccountControl | UserAccountControl | User, Computer | INTEGER | INT | Full bitmask (raw value) |

### SQLite Column Definitions

```sql
-- Add to AD_Object table (ADInventory.sql)
DNSHostName                TEXT,
EmployeeNumber             TEXT,
EmployeeType               TEXT,
IsCriticalSystemObject     INTEGER,
OperatingSystem            TEXT,
OperatingSystemVersion     TEXT,
OperatingSystemServicePack TEXT,
OperatingSystemHotfix      TEXT,
PasswordExpired            INTEGER,
ServicePrincipalName       TEXT,      -- JSON array: ["HTTP/server", "MSSQLSvc/sql:1433"]
UserAccountControl         INTEGER    -- Full bitmask (raw value)
```

### MSSQL Column Definitions

```sql
-- Add to AD_Object table
DNSHostName                NVARCHAR(255)  NULL,
EmployeeNumber             NVARCHAR(50)   NULL,
EmployeeType               NVARCHAR(100)  NULL,
IsCriticalSystemObject     BIT            NULL,
OperatingSystem            NVARCHAR(128)  NULL,
OperatingSystemVersion     NVARCHAR(32)   NULL,
OperatingSystemServicePack NVARCHAR(64)   NULL,
OperatingSystemHotfix      NVARCHAR(64)   NULL,
PasswordExpired            BIT            NULL,
ServicePrincipalName       NVARCHAR(MAX)  NULL,  -- JSON array
UserAccountControl         INT            NULL   -- Full bitmask
```

### userAccountControl Bitmask Reference

The raw `userAccountControl` value contains these important flags:

| Flag Name | Hex Value | Decimal | Description |
|-----------|-----------|---------|-------------|
| SCRIPT | 0x0001 | 1 | Logon script executed |
| ACCOUNTDISABLE | 0x0002 | 2 | Account is disabled |
| HOMEDIR_REQUIRED | 0x0008 | 8 | Home directory required |
| LOCKOUT | 0x0010 | 16 | Account is locked out |
| PASSWD_NOTREQD | 0x0020 | 32 | No password required |
| PASSWD_CANT_CHANGE | 0x0040 | 64 | User cannot change password |
| ENCRYPTED_TEXT_PWD_ALLOWED | 0x0080 | 128 | Reversible encryption |
| NORMAL_ACCOUNT | 0x0200 | 512 | Default account type |
| INTERDOMAIN_TRUST_ACCOUNT | 0x0800 | 2048 | Trust account |
| WORKSTATION_TRUST_ACCOUNT | 0x1000 | 4096 | Computer account |
| SERVER_TRUST_ACCOUNT | 0x2000 | 8192 | Domain controller |
| DONT_EXPIRE_PASSWD | 0x10000 | 65536 | Password never expires |
| MNS_LOGON_ACCOUNT | 0x20000 | 131072 | MNS logon account |
| SMARTCARD_REQUIRED | 0x40000 | 262144 | Smart card required |
| TRUSTED_FOR_DELEGATION | 0x80000 | 524288 | Kerberos delegation trusted |
| NOT_DELEGATED | 0x100000 | 1048576 | Cannot be delegated |
| USE_DES_KEY_ONLY | 0x200000 | 2097152 | DES encryption only |
| DONT_REQ_PREAUTH | 0x400000 | 4194304 | No Kerberos pre-auth |
| PASSWORD_EXPIRED | 0x800000 | 8388608 | Password has expired |
| TRUSTED_TO_AUTH_FOR_DELEGATION | 0x1000000 | 16777216 | Protocol transition |

### LDAP Properties to Add

Add these to `$propertiesToLoad` in `Get-ADObjects.ps1`:

```powershell
# Computer-specific
'dNSHostName',
'operatingSystem',
'operatingSystemVersion',
'operatingSystemServicePack',
'operatingSystemHotfix',
'isCriticalSystemObject',

# User-specific
'employeeNumber',
'employeeType',
'msDS-UserPasswordExpired',

# Security (User & Computer)
'servicePrincipalName'
# Note: userAccountControl is already collected but only used for derived fields
```

### Object Type Attribute Mapping

| Attribute | User | Computer | Group | Contact |
|-----------|:----:|:--------:|:-----:|:-------:|
| DNSHostName | - | ✓ | - | - |
| EmployeeNumber | ✓ | - | - | - |
| EmployeeType | ✓ | - | - | - |
| IsCriticalSystemObject | - | ✓ | ✓ | - |
| OperatingSystem | - | ✓ | - | - |
| OperatingSystemVersion | - | ✓ | - | - |
| OperatingSystemServicePack | - | ✓ | - | - |
| OperatingSystemHotfix | - | ✓ | - | - |
| PasswordExpired | ✓ | - | - | - |
| ServicePrincipalName | ✓ | ✓ | - | - |
| UserAccountControl | ✓ | ✓ | - | - |

---

## Current Schema Gaps Summary

| Category | Currently Collected | Missing (Recommended) |
|----------|--------------------|-----------------------|
| **Security** | Enabled, PasswordNeverExpires, PasswordLastSet, SIDHistory | SPN, adminCount, lockoutTime, UAC (raw) |
| **User Identity** | Name, Mail, Department, Title, Manager, EmployeeID | Company, Phone, Mobile, Location fields, EmployeeNumber, EmployeeType |
| **Computer** | Basic identity, Last Logon | OS info, DNS name, IsCriticalSystemObject |
| **Group** | Type, Scope, ManagedBy | IsCriticalSystemObject |

---

## Appendix A: LDAP Filter Reference

```ldap
# Users
(&(objectClass=user)(objectCategory=person))

# Groups
(objectClass=group)

# Computers
(objectClass=computer)

# Contacts
(objectClass=contact)

# All Security Principals (combined)
(|(objectClass=user)(objectClass=group)(objectClass=computer))
```

---

## Appendix B: Implementation Checklist

To implement the proposed schema additions:

- [ ] **ADInventory.sql** - Add 11 new columns to AD_Object table
- [ ] **Get-ADObjects.ps1** - Add 10 new LDAP attributes to `$propertiesToLoad` (line 96-126)
- [ ] **Get-ADObjects.ps1** - Extract new attributes in `$processObject` script block (line 129-290)
- [ ] **SQLiteInventoryWriter.ps1** - Verify column mapping handles new fields
- [ ] **Add-SQLiteBatch.ps1** - Verify batch insert handles new columns
- [ ] **v_AD_Object view** - Update compatibility view if needed
- [ ] **Unit tests** - Add tests for new attribute extraction
- [ ] **MSSQL import scripts** - Update target table DDL

---

*Document generated as part of ADInventory schema analysis task.*
*Last updated: 2025-01-05*
