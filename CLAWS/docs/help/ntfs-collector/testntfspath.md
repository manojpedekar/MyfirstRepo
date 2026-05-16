# TestNTFSPath - Path Troubleshooting Tool

TestNTFSPath.exe is a diagnostic utility for troubleshooting path access issues and ACL problems identified in CollectNTFSPerms event logs.

## Overview

When CollectNTFSPerms encounters "Access Denied" errors or ACL issues, use TestNTFSPath to:
- Diagnose why a path cannot be accessed
- Analyze the complete ACL structure
- Detect inheritance inconsistencies
- Check for non-canonical ACL order
- Verify SYSTEM account access
- Fix inheritance problems

## Syntax

```
TestNTFSPath <path_to_test> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--json` | Output results in JSON format |
| `--check-system` | Check if SYSTEM account has access to the path |
| `--fix` | Fix inheritance by recalculating from parent |
| `--fix-recursive` | Fix inheritance recursively for all children |
| `--addsystem` | Add SYSTEM account with Full Control (only if inheritance blocked) |
| `--help`, `-h`, `/?` | Show usage information |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (no issues detected) |
| 1 | Path does not exist |
| 2 | Access denied (cannot read directory) |
| 3 | ACL access denied (cannot read security descriptor) |
| 4 | SYSTEM account missing from ACL (with `--check-system`) |
| 5 | ACL is not in canonical order |
| 6 | Inheritance inconsistency detected |
| 7 | Fix operation failed |
| 10 | Invalid command-line arguments |
| 99 | Unknown error |

## Basic Usage

### Analyze a Path

```cmd
TestNTFSPath.exe "D:\Shares\Finance"
```

Output includes:
- Path existence and accessibility
- File system information
- Directory attributes
- ACL retrieval status
- Detailed ACL analysis
- Owner and group information
- All ACEs with inheritance flags
- Inheritance consistency check
- Long path handling test
- Recommendations

### JSON Output

```cmd
TestNTFSPath.exe "D:\Shares\Finance" --json
```

Returns structured JSON for programmatic processing.

### Check SYSTEM Account Access

```cmd
TestNTFSPath.exe "D:\Shares\Finance" --check-system
```

Verifies the SYSTEM account (S-1-5-18) has explicit access. Returns exit code 4 if SYSTEM is missing.

## ACL Analysis Output

### Sample Output

```
==================================================
NTFS Path Troubleshooting Tool
==================================================

VERDICT: PASS
Path: D:\Shares\Finance

Path Information
----------------
Path exists: Yes
Is directory: Yes
File system: NTFS (Volume: Data)
  Supports ACLs: Yes
Attributes: Archive
Path length: 17 characters

FolderScanner Test (Directory Listing)
------------------------------------
Can list directory contents: Yes

AclProcessor Test (Security Descriptor Retrieval)
----------------------------------------------
Can retrieve security descriptor: Yes
DACL present: Yes
DACL defaulted: No
ACE count: 8

Detailed ACL Analysis
--------------------
Owner: BUILTIN\Administrators (S-1-5-32-544)
Group: DOMAIN\Domain Users (S-1-5-21-xxx-513)

AreAccessRulesProtected : False
AreAuditRulesProtected  : False
AreAccessRulesCanonical : True
AreAuditRulesCanonical  : True

ACE Summary:
  Total ACEs    : 8
  Inherited     : 6
  Explicit      : 2

Access Control Entries:
  #  Type   Inherit   Principal                                  Permissions        Flags
  -----------------------------------------------------------------------------------------
   0 Allow  Explicit  DOMAIN\Finance Team                        Modify             CI,OI
   1 Allow  Explicit  DOMAIN\Finance Admins                      FullControl        CI,OI
   2 Allow  Inherited NT AUTHORITY\SYSTEM                        FullControl        CI,OI
   3 Allow  Inherited BUILTIN\Administrators                     FullControl        CI,OI
   ...

  Flags: CI=Container Inherit, OI=Object Inherit, IO=Inherit Only, NP=No Propagate

Inheritance Consistency Check
-----------------------------
Parent path: D:\Shares
Inheritance enabled: Yes
Status: CONSISTENT - Inherited ACEs match parent's inheritable ACEs

Long Path Handling Test
---------------------
Long path format: \\?\D:\Shares\Finance
Long path access: Successful

Recommendations for CollectNTFSPerms
----------------------------------
- Path is accessible and permissions can be collected normally.
```

## Diagnosing Issues

### Issue: ACL Not in Canonical Order

```
AreAccessRulesCanonical : False (WARNING: non-canonical order!)
```

Non-canonical ACL order means ACEs are not in the standard order (explicit deny, explicit allow, inherited deny, inherited allow). This can cause unexpected permission behavior.

**Resolution:** Use Windows Security dialog to reorder, or use `icacls` to reset.

### Issue: Inheritance Inconsistency

```
*** ACL INHERITANCE INCONSISTENCY DETECTED ***

This indicates the security descriptor is corrupted, typically from:
  - Backup/restore that preserved ACLs from a different inheritance state
  - Folder moved (not copied) from a different location
  - Manual SDDL manipulation or third-party tool

ACEs marked as 'inherited' but NOT from parent (will be DROPPED on fix):
  -------------------------------------------------------------------------
  [DROP] Allow - DOMAIN\OldGroup : Modify [CI,OI]

ACEs in parent that SHOULD inherit but are missing (will be ADDED on fix):
  -------------------------------------------------------------------------
  [ADD]  Allow - NT AUTHORITY\SYSTEM : FullControl [CI,OI]

To fix this issue, run: TestNTFSPath "<path>" --fix
To fix recursively:    TestNTFSPath "<path>" --fix-recursive
```

### Issue: SYSTEM Account Missing

```
SYSTEM Access Check:
  SYSTEM has access: NO - WARNING!
  The SYSTEM account (S-1-5-18) is not granted explicit access.
  This may prevent system services from accessing this folder.
```

## Fixing Issues

### Fix Inheritance (Single Folder)

```cmd
TestNTFSPath.exe "D:\Shares\Finance" --fix
```

Output:
```
==================================================
Fixing Inheritance for: D:\Shares\Finance
==================================================

The following ACEs will be REMOVED:
  - Allow - DOMAIN\OldGroup : Modify

The following ACEs will be ADDED:
  + Allow - NT AUTHORITY\SYSTEM : FullControl

Executing fix...
Command: icacls "D:\Shares\Finance" /reset

SUCCESS: Inheritance has been recalculated.

Verifying new ACL state...

New ACE count: 6
  Inherited: 6
  Explicit:  0
```

### Fix Inheritance Recursively

```cmd
TestNTFSPath.exe "D:\Shares\Finance" --fix-recursive
```

**Warning:** This recursively resets inheritance on all child folders. Use with caution on large directory trees.

### Add SYSTEM Account

```cmd
TestNTFSPath.exe "D:\Shares\Finance" --addsystem
```

This only adds SYSTEM when:
- Inheritance is blocked on the folder
- SYSTEM doesn't already have access

If inheritance is enabled, the tool reports that inheritance should provide SYSTEM access and suggests using `--fix` instead.

## Use Cases

### Troubleshoot Access Denied from Collection

1. Find the path from CollectNTFSPerms event log
2. Run diagnostic:
   ```cmd
   TestNTFSPath.exe "D:\Problem\Path"
   ```
3. Review the VERDICT and recommendations
4. Fix if needed using `--fix`

### Audit SYSTEM Access on Critical Folders

```cmd
TestNTFSPath.exe "D:\CriticalData" --check-system
if %ERRORLEVEL% EQU 4 (
    echo WARNING: SYSTEM account missing from D:\CriticalData
)
```

### Batch Check Multiple Paths

```batch
@echo off
for %%P in ("D:\Shares" "E:\Data" "F:\Archive") do (
    echo Checking %%P...
    TestNTFSPath.exe %%P --check-system
    if %ERRORLEVEL% NEQ 0 (
        echo   Issue detected: Exit code %ERRORLEVEL%
    ) else (
        echo   OK
    )
)
```

### PowerShell Integration

```powershell
# Check path and capture JSON output
$result = & "C:\Tools\CollectNTFSPerms\TestNTFSPath.exe" "D:\Shares" --json | ConvertFrom-Json

if ($result.verdict -ne "PASS") {
    Write-Warning "Issue detected: $($result.verdict)"
    # Handle specific issues...
}
```

## Exit Code Usage in Scripts

```batch
@echo off
TestNTFSPath.exe "D:\Shares\Secure" --check-system

if %ERRORLEVEL% EQU 0 echo Path OK
if %ERRORLEVEL% EQU 1 echo Path does not exist
if %ERRORLEVEL% EQU 2 echo Access denied
if %ERRORLEVEL% EQU 3 echo Cannot read ACL
if %ERRORLEVEL% EQU 4 echo SYSTEM missing
if %ERRORLEVEL% EQU 5 echo Non-canonical ACL
if %ERRORLEVEL% EQU 6 echo Inheritance issue
```

## Common Scenarios

### Scenario: Backup/Restore ACL Corruption

After restoring from backup, folders may have "inherited" ACEs that don't match the current parent.

**Symptoms:**
- Inheritance shows as enabled
- ACEs marked inherited but from wrong parent
- Access doesn't match what parent would provide

**Solution:**
```cmd
TestNTFSPath.exe "D:\Restored\Folder" --fix-recursive
```

### Scenario: Folder Moved Instead of Copied

Moving folders within NTFS preserves ACLs, which may cause mismatches when the new parent has different inheritable permissions.

**Solution:**
```cmd
TestNTFSPath.exe "D:\NewLocation\MovedFolder" --fix
```

### Scenario: Service Account Access

A Windows service can't access a folder that has inheritance blocked.

**Diagnose:**
```cmd
TestNTFSPath.exe "D:\ServiceData" --check-system
```

**Fix (if SYSTEM missing and inheritance blocked):**
```cmd
TestNTFSPath.exe "D:\ServiceData" --addsystem
```

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
