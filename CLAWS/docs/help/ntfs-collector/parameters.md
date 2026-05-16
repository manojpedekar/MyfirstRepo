# NTFS Collector Parameters Reference

Complete reference for all CollectNTFSPerms.exe command-line options.

## Syntax Overview

```
CollectNTFSPerms.exe <FolderPath> <DatabaseFile> [options]
CollectNTFSPerms.exe --allfixeddisks <DatabaseFile> [options]
CollectNTFSPerms.exe --testaccess <FolderPath> [--Debug]
CollectNTFSPerms.exe --testexclude <Path>
```

## Execution Modes

### Folder Scan Mode (Default)

Scan a specific folder and store permissions in a database.

```
CollectNTFSPerms.exe <FolderPath> <DatabaseFile> [options]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `<FolderPath>` | Yes | Root folder path to scan (local or UNC) |
| `<DatabaseFile>` | Yes | Output SQLite database file path |

**Examples:**
```cmd
CollectNTFSPerms.exe D:\Shares D:\Output\permissions.db
CollectNTFSPerms.exe "E:\File Server\Data" E:\Output\data.db
CollectNTFSPerms.exe "\\FileServer01\Shares" C:\Output\server01.db
```

### All Fixed Disks Mode

Scan all fixed disk volumes on the local machine.

```
CollectNTFSPerms.exe --allfixeddisks <DatabaseFile> [options]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `<DatabaseFile>` | Yes | Output SQLite database file path |

**Features:**
- Discovers volumes via Windows Volume Management APIs
- Includes volumes mounted as folders (mount points)
- Includes volumes without drive letters
- Automatically handles nested volumes via mount point traversal

**Restrictions:**
- Cannot be combined with `--RemoteComputer`
- Only scans local fixed disks (DRIVE_FIXED)

**Example:**
```cmd
CollectNTFSPerms.exe --allfixeddisks C:\Output\full_inventory.db
```

### Test Access Mode

Test folder access permissions without writing to a database.

```
CollectNTFSPerms.exe --testaccess <FolderPath> [--Debug]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `<FolderPath>` | Yes | Folder path to test access |

**Output:**
- Reports total folders scanned
- Reports accessible folders count
- Lists all folders returning ACCESS_DENIED
- Lists other error counts

**Restrictions:**
- Cannot be combined with `--ExplicitOnly`
- Cannot be combined with `--RemoteComputer`
- No database operations performed

**Example:**
```cmd
CollectNTFSPerms.exe --testaccess D:\SecureFolder
CollectNTFSPerms.exe --testaccess "\\Server\Share" --Debug
```

### Exclusion Test Mode

Test whether a path matches the built-in exclusion filters.

```
CollectNTFSPerms.exe --testexclude <Path>
```

**Output:**
- `EXCLUDED` - Path would be skipped during scanning
- `INCLUDED` - Path would be scanned

**Example:**
```cmd
CollectNTFSPerms.exe --testexclude "C:\System Volume Information"
CollectNTFSPerms.exe --testexclude "D:\Data\Recovery"
```

## Optional Parameters

### --ExplicitOnly

Collect only explicitly-set DACLs; skip inherited ACLs.

| Property | Value |
|----------|-------|
| Type | Switch |
| Default | Off (inherited ACLs included) |
| Available in | Folder Scan, All Fixed Disks |

**Use cases:**
- Reduces database size significantly
- Faster collection times
- When inheritance analysis is not required

**Example:**
```cmd
CollectNTFSPerms.exe D:\Shares D:\Output\perms.db --ExplicitOnly
```

### --RemoteComputer

Specify the source computer name for UNC path scans.

| Property | Value |
|----------|-------|
| Type | String |
| Default | Local computer name |
| Available in | Folder Scan mode only |

**Purpose:**
- Recorded in the database for inventory identification
- Allows associating UNC scans with specific servers

**Restrictions:**
- Cannot be used with `--allfixeddisks`
- Cannot be used with `--testaccess`

**Example:**
```cmd
CollectNTFSPerms.exe "\\FileServer01\Data" C:\Output\server01.db --RemoteComputer FileServer01
```

### --Debug

Enable verbose diagnostic output.

| Property | Value |
|----------|-------|
| Type | Switch |
| Default | Off |
| Available in | All modes |

**Output:**
- Creates `CollectNTFSPerms.debug` file in current directory
- Contains detailed trace information
- Useful for troubleshooting performance issues or errors

**Example:**
```cmd
CollectNTFSPerms.exe D:\Shares D:\Output\perms.db --Debug
```

### --NoZip

Skip automatic compression and cleanup of the database file.

| Property | Value |
|----------|-------|
| Type | Switch |
| Default | Off (database is compressed) |
| Available in | Folder Scan, All Fixed Disks |

**Default behavior (without --NoZip):**
1. Collection completes
2. Database is compressed to .zip file
3. Original .db file is deleted
4. Final output: `permissions.zip`

**With --NoZip:**
1. Collection completes
2. Database file preserved as-is
3. Final output: `permissions.db`

**Use cases:**
- When you need to query the database immediately
- When compression time is a concern
- When you'll compress separately

**Example:**
```cmd
CollectNTFSPerms.exe D:\Shares D:\Output\perms.db --NoZip
```

## Built-in Path Exclusions

The following paths are automatically excluded during scanning (cannot be changed):

### NAS Snapshot Folders

| Pattern | Vendors/Systems |
|---------|-----------------|
| `~snapshot`, `.snapshot`, `#snapshot` | NetApp, Pure Storage |
| `@Snapshot`, `@Recently-Snapshot` | Various NAS vendors |
| `@GMT-*` timestamp folders | Windows Previous Versions |
| `snapmirror`, `snapvault` | NetApp replication |
| `.sync`, `.ifs`, `.ifsvar`, `.ifsquota` | Isilon/PowerScale |
| `@Recycle`, `#recycle` | NAS recycle bins |
| `.vvclone`, `.copy` | HPE Nimble |

### Windows System Folders (at drive root only)

| Folder | Description |
|--------|-------------|
| `$Recycle.Bin` | Windows Recycle Bin (Vista+) |
| `RECYCLER` | Windows Recycle Bin (XP) |
| `Recycled` | Older Windows Recycle Bin |
| `System Volume Information` | VSS and indexing |
| `Recovery` | Windows Recovery Environment |
| `PerfLogs` | Performance logs |
| `MSOCache` | Office installation cache |
| `$WinREAgent` | Windows Recovery Agent |
| `Windows.old` | Previous Windows installation |
| `$Windows.~BT`, `$Windows.~WS` | Windows upgrade folders |

### Program Data Folders

| Path | Description |
|------|-------------|
| `ProgramData\Microsoft\Windows\WER` | Windows Error Reporting |
| `ProgramData\Package Cache` | Installer cache |
| `Windows\Config.Msi` | MSI configuration |

### VSS Paths

| Pattern | Description |
|---------|-------------|
| `GLOBALROOT\Device\HarddiskVolumeShadowCopy*` | Volume shadow copies |

## Output

### Database Contents

The SQLite database contains these primary tables:

| Table | Description |
|-------|-------------|
| `CollectionInfo` | Metadata about the collection |
| `Folders` | Folder hierarchy with attributes |
| `ACL` | Access Control Lists per folder |
| `ACE` | Individual Access Control Entries |
| `SIDs` | Security identifiers with resolved names |
| `Disks` | Physical disk information |
| `Volumes` | Volume information |
| `Partitions` | Partition layout |
| `SMBShares` | SMB share definitions |
| `SMBShareAccess` | Share-level permissions |
| `EventLog` | Collection event log |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (invalid arguments, access denied, database failure) |

## Thread Count Optimization

Thread count is automatically calculated based on storage type:

| Storage Type | Thread Count | Rationale |
|--------------|--------------|-----------|
| Local HDD | 4-8 | Limited by seek latency |
| Local SSD (SATA) | Up to 8 | Moderate parallelism |
| NVMe SSD | Up to CPU cores | High IOPS capability |
| Network (UNC) | 2-4 | Network bandwidth limited |
| RAM Disk | CPU cores | Extremely fast |

The calculated thread count is displayed during startup.

## Administrator Privileges

Running as Administrator enables additional data collection:

| Data Type | Without Admin | With Admin |
|-----------|---------------|------------|
| Folder permissions | Yes | Yes |
| SMB shares | Yes | Yes |
| Disk information | No | Yes |
| Volume information | No | Yes |
| Partition information | No | Yes |
| All folder access | Limited | Full |

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
