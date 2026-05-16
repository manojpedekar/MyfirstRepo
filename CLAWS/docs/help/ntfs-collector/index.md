# NTFS Permissions Collector

CollectNTFSPerms.exe is a native Windows executable that inventories NTFS folder permissions across your Windows file servers and stores them in a SQLite database.

## Version

Current version: **1.8.0**

## What It Collects

| Data Type | Description |
|-----------|-------------|
| **Folder ACLs** | Full access control list for each folder |
| **Inherited vs Explicit** | Distinguishes inherited permissions from explicit (with `--ExplicitOnly`) |
| **Share Permissions** | SMB share-level permissions |
| **Folder Attributes** | Hidden, system, read-only flags |
| **Disk Information** | Physical disk details (requires admin) |
| **Volume Information** | Volume size, free space, mount points (requires admin) |
| **Partition Information** | Partition layout (requires admin) |
| **SID Resolution** | Translates SIDs to account names |

## Runtime Dependencies

**CRITICAL:** The `sqlite3.dll` file must be present in the same directory as `CollectNTFSPerms.exe`. The application will fail to start with an error message if this DLL is missing.

## Key Features

- **Native C++ performance** - Optimized for large file systems with millions of folders
- **SQLite output** - Self-contained database file for reliable transport
- **Automatic compression** - Output is automatically zipped (unless `--NoZip` specified)
- **Multi-threaded** - Thread count auto-optimized based on storage type (SSD/HDD/Network)
- **Mount point traversal** - Handles volumes mounted as folders
- **UNC path support** - Scan network shares directly

## Execution Modes

| Mode | Command | Description |
|------|---------|-------------|
| **Folder Scan** | `CollectNTFSPerms.exe <Path> <Database>` | Scan a specific folder |
| **All Fixed Disks** | `CollectNTFSPerms.exe --allfixeddisks <Database>` | Scan all local fixed volumes |
| **Access Test** | `CollectNTFSPerms.exe --testaccess <Path>` | Test access without database |
| **Exclusion Test** | `CollectNTFSPerms.exe --testexclude <Path>` | Test if path would be excluded |

## In This Section

| Article | Description |
|---------|-------------|
| [Installation](installation.md) | Download and install the collector |
| [Usage Guide](usage.md) | Basic usage and workflow |
| [Parameters Reference](parameters.md) | Complete parameter documentation |
| [Examples](examples.md) | Common collection scenarios |

## Quick Example

```cmd
REM Scan a folder and create database
CollectNTFSPerms.exe D:\FileShares D:\Output\permissions.db

REM Output: D:\Output\permissions.zip (database is auto-compressed)
```

## Output Contents

The collector produces a ZIP file containing a SQLite database:

```
permissions.zip
└── permissions.db        # SQLite database with all collected data
```

The database includes tables for:
- Collection metadata and statistics
- Folders with hierarchy
- ACLs (Access Control Lists)
- ACEs (Access Control Entries)
- SIDs with resolved names
- Disk, Volume, and Partition information
- SMB Shares and Share Access permissions
- Event log of the collection process

## Next Steps

1. [Install the collector](installation.md)
2. [Review the parameters](parameters.md)
3. [Run your first collection](usage.md)
4. [Upload to the web application](../uploading/index)

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
