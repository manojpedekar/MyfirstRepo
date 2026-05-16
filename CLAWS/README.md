# CollectNTFSPerms

A Windows utility for collecting and analyzing NTFS file system permissions, disk information, and SMB share configurations.

## Overview

CollectNTFSPerms is a comprehensive tool designed to inventory Windows file systems, capturing detailed information about:
- Folder structures and file permissions (ACLs/ACEs)
- Disk, volume, and partition configurations
- SMB share information and permissions
- System metadata and security principals

All collected data is stored in a SQLite database for easy querying and analysis.

## Features

- **NTFS Permission Collection**: Captures Access Control Lists (ACLs) and Access Control Entries (ACEs) for folders
- **Multi-threaded Scanning**: Configurable thread pool for efficient folder traversal
- **Disk & Volume Information**: Collects physical disk, volume, partition, and extent data (admin privileges required)
- **SMB Share Enumeration**: Discovers and collects SMB share permissions
- **Remote Computer Support**: Scan remote computers using UNC paths
- **Smart Skip Logic**: Automatically skips privileged operations when running without admin rights
- **Progress Tracking**: Real-time progress display with memory monitoring
- **Timing Breakdown**: Displays performance metrics for scan phases
- **Path Normalization**: Handles Windows path edge cases (trailing spaces, long paths)
- **SQLite Database**: Structured data storage with optimized indexes

## Requirements

- **Operating System**: Windows Server 2008 R2 or later, Windows 7 or later
- **Build Tools**: Visual Studio 2017 or later (Platform Toolset v141+)
- **Runtime**: Visual C++ Redistributable for Visual Studio 2017
- **Privileges**:
  - Standard user: Can scan folders and collect SMB shares (local scans only)
  - Administrator: Required for disk/volume/partition collection

## Building

### Prerequisites
- Visual Studio 2017 or later with C++ desktop development workload
- Windows SDK

### Build Steps
1. Open `CollectNTFSPerms.sln` in Visual Studio
2. Select configuration (Debug/Release) and platform (x64)
3. Build Solution (Ctrl+Shift+B)

The executable will be created in `x64\[Configuration]\CollectNTFSPerms.exe`

## Usage

### Basic Syntax
```cmd
CollectNTFSPerms.exe <FolderToScan> <DatabaseFile> [OPTIONS]
```

### Command-Line Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `<FolderToScan>` | Path to the folder to scan (local or UNC) | Yes |
| `<DatabaseFile>` | Path where SQLite database will be created | Yes |
| `--ExplicitOnly` | Only store explicitly set DACLs (skip inherited permissions) | No |
| `--RemoteComputer <name>` | Specify the computer name being scanned | No |

**Note:** Thread count is automatically determined based on CPU core count.

### Examples

**Local scan with admin privileges** (collects everything):
```cmd
CollectNTFSPerms.exe C:\MyFolder C:\data\perms.db
```

**Local scan without admin privileges** (skips disk/volume/partition):
```cmd
CollectNTFSPerms.exe C:\MyFolder C:\data\perms.db
```

**Remote computer scan**:
```cmd
CollectNTFSPerms.exe \\SERVER\Share C:\data\perms.db --RemoteComputer SERVER
```

**Collect only explicit permissions** (skip inherited):
```cmd
CollectNTFSPerms.exe C:\MyFolder C:\data\perms.db --ExplicitOnly
```

**Combined options**:
```cmd
CollectNTFSPerms.exe \\SERVER\Share C:\data\perms.db --ExplicitOnly --RemoteComputer SERVER
```

## Output Database Schema

The tool creates a SQLite database with the following main tables:

### Core Tables
- `app__Inventory` - Scan metadata and statistics
- `app__Folders` - Folder hierarchy and paths
- `app__ACL` - Access Control Lists for folders
- `app__ACE` - Access Control Entries (permissions)
- `app__Identities` - Security principals (users/groups)

### System Information Tables
- `app__Disks` - Physical disk information
- `app__Volumes` - Volume information
- `app__Partitions` - Partition information
- `app__VolumeExtents` - Volume extent mappings
- `app__SMBShares` - SMB share configurations
- `app__SMBShareAccess` - SMB share permissions

### Logging Tables
- `app__EventLog` - Application events and errors

## Collection Behavior

### Administrator vs Non-Administrator

**With Admin Privileges (Local Scan):**
- ✅ Folder and ACL collection
- ✅ Disk information
- ✅ Volume information
- ✅ Partition information
- ✅ Volume extents
- ✅ SMB share discovery and collection

**Without Admin Privileges (Local Scan):**
- ✅ Folder and ACL collection
- ✅ SMB share discovery and collection
- ⚠️ Disk information (skipped - logged to EventLog)
- ⚠️ Volume information (skipped - logged to EventLog)
- ⚠️ Partition information (skipped - logged to EventLog)

**Remote Computer Scan (Any Privilege Level):**
- ✅ Folder and ACL collection on remote path
- ⚠️ All local system information skipped (not applicable)
- ⚠️ SMB share information skipped (not applicable)

All skipped collections are logged to `app__EventLog` with severity WARNING.

## Performance

The tool provides a timing breakdown at the end of each scan:
```
Timing Breakdown:
--------------------------------------------------
  Folder Scan Time    : 2m 15s
  ACL Processing Time : 45s
  Database Write Time : 30s
  Total Runtime       : 3m 30s
--------------------------------------------------
```

## Compatibility

- **Windows Server**: 2008 R2, 2012, 2012 R2, 2016, 2019, 2022
- **Windows Client**: 7, 8, 8.1, 10, 11
- **Platform**: x64 only
- **Compiler**: Visual Studio 2017 (v141 toolset) or later

## Known Limitations

- Only x64 platform is supported
- Requires NTFS file system for ACL collection
- Long-running scans may consume significant memory for large folder structures
- Remote scans require appropriate network permissions
- Symbolic links and junction points are followed (may cause loops)

## Troubleshooting

**"Disk information not collected. User is not running as admin!"**
- This is expected behavior for non-admin users
- Run as administrator to collect disk/volume/partition information

**"Remote computer scan detected. Local system info not applicable."**
- This is expected when using `--REMOTECOMPUTER`
- Local disk/volume/SMB share collection is skipped for remote scans

**Database errors**
- Ensure the DBPATH directory exists
- Verify write permissions to the database location
- Check available disk space

**Access denied errors during scan**
- Normal for folders/files without read permissions
- Errors are logged to `app__EventLog` table
- Scan continues with accessible items

## Contributing

This project uses:
- C++17 standard
- SQLite 3 for database storage
- Windows API for system information collection
- Multi-threaded design for performance

## License

See LICENSE file for details.

## Version History

### Sprint 10 (Current)
- Added smart skip logic for non-admin and remote computer scans
- Fixed SMB share collection to not require admin privileges
- Fixed compilation warnings in volumes.cpp
- Added comprehensive event logging for skipped collections
- Removed GitHub Actions workflow

### Sprint 9
- Added timing breakdown display
- Implemented path normalization for trailing spaces/dots
- Fixed database schema initialization (index creation order)
- Fixed progress bar wrapping in narrow consoles
- Enhanced Windows Server 2008 R2 compatibility
