# NTFS Collector Usage Guide

This guide explains how to run NTFS permissions collections using CollectNTFSPerms.exe.

## Before You Begin

1. Ensure `sqlite3.dll` is in the same directory as `CollectNTFSPerms.exe`
2. Open a Command Prompt (preferably as Administrator)
3. Navigate to or specify the full path to the executable

## Basic Collection

### Scan a Single Folder

```cmd
CollectNTFSPerms.exe D:\Shares D:\Output\permissions.db
```

Output:
```
CollectNTFSPerms v1.8.0
NTFS Permissions Collection Utility
Build: Jan 12 2026 14:30:00

Checking if folder exists and is accessible...
Optimized thread count: 8 (Drive type detection based on: D:\Shares)
--------------------------------------------------
Execution Mode : Normal
Start Time     : 2026-01-12T14:30:45 UTC
Scan Folder    : D:\Shares (Local)
Database File  : D:\Output\permissions.db
Computer Name  : FILESERVER01
Hardware Cores : 16
Thread Count   : 8
--------------------------------------------------

Collecting disk information...
...
```

### Understanding the Output

When collection completes, you'll see:

```
Timing Breakdown:
--------------------------------------------------
  Folder Scan Time    : 2m 15s
  ACL Processing Time : 5m 32s
  Database Write Time : 1m 8s
  Total Runtime       : 8m 55s
--------------------------------------------------

Compressing database file...
Source: D:\Output\permissions.db
Target: D:\Output\permissions.zip
...
Compression ratio: 78.5% reduction
Database compressed successfully
Original database file deleted
Final output: D:\Output\permissions.zip

Processing completed successfully!
```

## Collection Modes

### Single Path Collection

Scan a specific folder:

```cmd
CollectNTFSPerms.exe "D:\File Shares" D:\Output\shares.db
```

### UNC Path Collection

Scan a remote share:

```cmd
CollectNTFSPerms.exe "\\FileServer01\Data" C:\Output\server01.db --RemoteComputer FileServer01
```

### All Fixed Disks

Scan all local fixed volumes:

```cmd
CollectNTFSPerms.exe --allfixeddisks C:\Output\full_inventory.db
```

Output shows discovered volumes:
```
=== ALL FIXED DISKS MODE ===
Enumerating all fixed disk volumes with nesting detection...

Found 5 fixed disk volume(s):
  - 3 root volume(s) (will be scanned as starting points)
  - 2 nested volume(s) (will be reached via mount point traversal)

Root volumes to scan:
  - C:\ (System) [System]
  - D:\ (Data)
  - E:\ (Archive)
```

## Pre-Flight Testing

### Test Access Before Scanning

Before running a full collection, test for access issues:

```cmd
CollectNTFSPerms.exe --testaccess D:\Shares
```

Output:
```
=== ACCESS TEST MODE ===
Testing folder access permissions (no database operations)

Root folder: D:\Shares
Thread count: 8

--------------------------------------------------
Scanning folders (ACCESS DENIED paths shown in summary)...

--------------------------------------------------
ACCESS TEST SUMMARY
--------------------------------------------------
Total folders scanned   : 125,432
Accessible folders      : 125,419
Access denied folders   : 13
Other errors            : 0
--------------------------------------------------

Paths with ACCESS DENIED:
  D:\Shares\HR\Confidential\Payroll
  D:\Shares\IT\Certificates
  ...
```

### Test Path Exclusions

Check if a path would be excluded:

```cmd
CollectNTFSPerms.exe --testexclude "C:\System Volume Information"
```

Output:
```
Path: C:\System Volume Information
Result: True
EXCLUDED - This path would be skipped during scanning
```

```cmd
CollectNTFSPerms.exe --testexclude "D:\Data\Recovery"
```

Output:
```
Path: D:\Data\Recovery
Result: False
INCLUDED - This path would be scanned
```

Note: `Recovery` at drive root is excluded, but `Recovery` in a subfolder is not.

## Controlling Output

### Keep Original Database (Skip Compression)

```cmd
CollectNTFSPerms.exe D:\Shares D:\Output\permissions.db --NoZip
```

Output file: `permissions.db` (no compression, original file kept)

### Collect Explicit Permissions Only

Skip inherited ACLs for smaller output:

```cmd
CollectNTFSPerms.exe D:\Shares D:\Output\permissions.db --ExplicitOnly
```

## Troubleshooting with Debug Mode

Enable verbose logging:

```cmd
CollectNTFSPerms.exe D:\Shares D:\Output\permissions.db --Debug
```

This creates `CollectNTFSPerms.debug` in the current directory with detailed trace information.

## Progress Monitoring

The collector displays real-time progress:

```
Starting folder inventory scan...
--------------------------------------------------
Scanning: 45,230 folders | Queued: 1,247 | Current: D:\Shares\Finance\Reports\2026

Starting ACE/ACL processing scan...
--------------------------------------------------
Processing: 45,230/125,432 (36%) | ACLs: 45,230 | ACEs: 892,156 | Errors: 0
```

## Handling Errors

### Access Denied Errors

The collector continues past access denied errors and reports them at the end:

```
ACL/ACL processing summary
--------------------------------------------------
Total folders processed : 125,432
Failed folders          : 13
...
```

Access denied folders are logged in the database's `EventLog` table.

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "sqlite3.dll is not found" | Missing DLL | Ensure sqlite3.dll is in same directory |
| "Invalid or inaccessible folder path" | Path doesn't exist or no access | Verify path and permissions |
| "cannot enumerate remote fixed disks" | --allfixeddisks with --RemoteComputer | Use one or the other, not both |

## Scheduled Collections

### Create a Batch File

```batch
@echo off
REM File: C:\Scripts\CollectNTFS.cmd

cd /d C:\Tools\CollectNTFSPerms
CollectNTFSPerms.exe --allfixeddisks C:\Output\%COMPUTERNAME%_%DATE:~-4%%DATE:~4,2%%DATE:~7,2%.db

REM Copy to network share
copy /y C:\Output\*.zip \\CentralServer\Collections\
```

### Schedule with Task Scheduler

1. Open Task Scheduler
2. Create Basic Task
3. Set trigger (e.g., Weekly, Sunday 2:00 AM)
4. Action: Start a program
   - Program: `C:\Scripts\CollectNTFS.cmd`
   - Start in: `C:\Scripts`
5. Run with highest privileges
6. Run whether user is logged on or not

## Best Practices

| Practice | Reason |
|----------|--------|
| Run as Administrator | Full access to all folders and system metadata |
| Use local output path | Faster than writing to network share during collection |
| Test access first | Identify permission issues before full collection |
| Use --ExplicitOnly for large systems | Reduces database size and collection time |
| Schedule during off-hours | Reduces impact on file server performance |

## After Collection

1. **Upload** the resulting .zip file to the web application
2. **Review** the database EventLog for any warnings or errors
3. **Verify** folder counts match expectations

## Next Steps

- [Parameters Reference](parameters.md) - All available parameters
- [Examples](examples.md) - Common scenarios
- [Troubleshooting](../troubleshooting/collector-issues.md) - Solve common problems
- [Uploading](../uploading/index) - Upload your collection

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
