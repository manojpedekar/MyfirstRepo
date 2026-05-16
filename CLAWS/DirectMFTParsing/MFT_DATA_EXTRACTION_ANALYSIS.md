# MFT Data Extraction Analysis for Space Utilization Reporting

## Executive Summary

This document details the data to be extracted by the C++ MFT scanner to support space utilization reporting, data lifecycle management, and storage optimization for Windows servers with large NTFS volumes.

**Goal:** Enable business owners to identify opportunities to delete or archive data to:
- Free up SSD/NVMe storage
- Reduce backup times
- Improve storage cost efficiency

**Approach:** Extract raw file metadata from NTFS volumes, output to CSV. No derived or calculated values in the scanner -- all analysis, aggregation, and reporting will be performed downstream (database/reporting layer to be determined separately).

---

## 1. MVP Scope

### 1.1 Attributes to Extract

The scanner will extract the following attributes per file and directory entry:

| # | Attribute | Source | Type | Notes |
|---|-----------|--------|------|-------|
| 1 | **Volume** | Drive letter from scan root | string | Volume identifier (e.g., `C:`) |
| 2 | **Full Path** | FindFirstFileW | string | Complete path including drive letter |
| 3 | **File Name** | WIN32_FIND_DATA.cFileName | string | Name only (no path) |
| 4 | **File Size** | WIN32_FIND_DATA.nFileSizeLow/High | uint64 | Logical file size in bytes; empty for directories |
| 5 | **Creation Time** | WIN32_FIND_DATA.ftCreationTime | FILETIME | **NEW** - When file was created |
| 6 | **Modified Time** | WIN32_FIND_DATA.ftLastWriteTime | FILETIME | Last content modification |
| 7 | **Accessed Time** | WIN32_FIND_DATA.ftLastAccessTime | FILETIME | Last access (see caveat in 2.1) |
| 8 | **Is Directory** | FILE_ATTRIBUTE_DIRECTORY | bool | Directory vs file flag |
| 9 | **File Attributes** | WIN32_FIND_DATA.dwFileAttributes | uint32 | Raw attribute bitmask |

### 1.2 Output Format

- **CSV file** with one row per file/directory entry
- Full file paths and file names included
- Timestamps in ISO 8601 format (YYYY-MM-DDTHH:MM:SS)
- New scan overwrites previous output; no historical retention in the scanner (historical tracking deferred to database layer)
- Single combined CSV for all scanned volumes, with a `Volume` column to identify source volume
- Default behavior captures all files and directories (no size filter); `--minSize` available as an optional filter for ad-hoc use

### 1.3 Volume Selection

- Named volumes specified via command line (e.g., `mftscan.exe C: D: E:`)
- `--allVolumes` flag to automatically enumerate and scan all local NTFS volumes
- All volumes are combined into a single output CSV

### 1.4 Error Handling

- Inaccessible files/directories (ACL denied, locked files, etc.) are **not** included in the CSV output
- Errors are written to a **separate error log file** alongside the CSV (e.g., `mftscan_20260204_errors.log`)
- Error log contains: timestamp, full path, Windows error code, and error description
- Console summary reports total error count at scan completion

---

## 2. Known Constraints and Caveats

### 2.1 Last Access Time is Unreliable

**NtfsDisableLastAccessUpdate is enabled on target servers.** This means:

- The Accessed Time field will be populated but **may not reflect actual last access**
- Windows stops updating last access timestamps when this setting is enabled (default on Windows Server for performance)
- The access time will typically reflect the time the file was created or last written, not when it was last read
- This field is still collected as it may have value in some cases and costs nothing to extract
- **Downstream consumers of this data must be aware that Accessed Time is not reliable for stale file detection on these servers**

To verify on any server: `fsutil behavior query disablelastaccess`

### 2.2 Long Paths (>260 Characters)

**Long paths exceeding MAX_PATH (260 characters) exist on target servers.** The scanner must:

- Use the `\\?\` prefix for all path operations to support paths up to 32,767 characters
- Use the wide-character (W-suffix) Win32 APIs exclusively: `FindFirstFileW`, `FindNextFileW`
- Ensure the CSV output can store full-length paths without truncation

### 2.3 Junction Points and Symlinks

**Decision: Enumerate from partition roots, skip reparse points.**

- The scanner will enumerate all local NTFS partitions/volumes
- Scanning begins at the root of each partition (e.g., `C:\`, `D:\`)
- **Reparse points (junctions, symlinks, mount points) are skipped** during enumeration (current behavior via `FILE_ATTRIBUTE_REPARSE_POINT` detection)
- This avoids:
  - Double-counting data that is linked from multiple locations
  - Infinite loops from circular junction points
  - Counting data on other volumes that are mounted as folders
- Reparse points are still logged as entries in the CSV (with their attributes) but their targets are not recursed into

### 2.4 File Attribute Bitmask Values

The raw `dwFileAttributes` value is stored as a 32-bit unsigned integer. Downstream consumers can decode it using standard Windows file attribute constants:

| Flag | Value | Meaning |
|------|-------|---------|
| FILE_ATTRIBUTE_READONLY | 0x00000001 | Read-only file |
| FILE_ATTRIBUTE_HIDDEN | 0x00000002 | Hidden file |
| FILE_ATTRIBUTE_SYSTEM | 0x00000004 | System file |
| FILE_ATTRIBUTE_DIRECTORY | 0x00000010 | Directory |
| FILE_ATTRIBUTE_ARCHIVE | 0x00000020 | Archive flag set |
| FILE_ATTRIBUTE_DEVICE | 0x00000040 | Device |
| FILE_ATTRIBUTE_NORMAL | 0x00000080 | No other attributes set |
| FILE_ATTRIBUTE_TEMPORARY | 0x00000100 | Temporary file |
| FILE_ATTRIBUTE_SPARSE_FILE | 0x00000200 | Sparse file |
| FILE_ATTRIBUTE_REPARSE_POINT | 0x00000400 | Reparse point (junction/symlink/dedup) |
| FILE_ATTRIBUTE_COMPRESSED | 0x00000800 | NTFS compressed |
| FILE_ATTRIBUTE_OFFLINE | 0x00001000 | Data moved to offline storage |
| FILE_ATTRIBUTE_NOT_CONTENT_INDEXED | 0x00002000 | Not indexed by content indexing service |
| FILE_ATTRIBUTE_ENCRYPTED | 0x00004000 | EFS encrypted |

Storing the raw bitmask rather than individual boolean columns keeps the CSV compact and allows downstream systems to filter on any combination of attributes without requiring scanner changes.

---

## 3. CSV Output Specification

### 3.1 Column Layout

```
Volume,FullPath,FileName,FileSize,CreatedTime,ModifiedTime,AccessedTime,IsDirectory,Attributes
```

| Column | Type | Example | Notes |
|--------|------|---------|-------|
| Volume | string | `C:` | Drive letter of source volume |
| FullPath | string | `\\?\C:\Users\jsmith\Documents\report.xlsx` | Quoted if contains commas |
| FileName | string | `report.xlsx` | Name portion only |
| FileSize | uint64 | `1048576` | Bytes; **empty for directories** |
| CreatedTime | string | `2024-01-15T10:30:45` | ISO 8601, UTC |
| ModifiedTime | string | `2024-06-20T14:15:00` | ISO 8601, UTC |
| AccessedTime | string | `2024-06-20T14:15:00` | ISO 8601, UTC (see caveat 2.1) |
| IsDirectory | int | `0` | 1=directory, 0=file |
| Attributes | uint32 | `32` | Raw dwFileAttributes bitmask |

### 3.2 CSV Conventions

- UTF-8 encoding with BOM for Excel compatibility
- Header row included
- Fields containing commas, quotes, or newlines are enclosed in double quotes
- Double quotes within fields are escaped as `""`
- Timestamps in UTC to avoid timezone ambiguity across servers
- Single combined file for all volumes; `Volume` column identifies the source

### 3.3 Example Output

```csv
Volume,FullPath,FileName,FileSize,CreatedTime,ModifiedTime,AccessedTime,IsDirectory,Attributes
C:,"\\?\C:\","",,2019-03-15T08:00:00,2026-01-30T12:00:00,2026-01-30T12:00:00,1,22
C:,"\\?\C:\Users","Users",,2019-03-15T08:00:00,2026-01-28T09:30:00,2026-01-28T09:30:00,1,8213
C:,"\\?\C:\Users\jsmith\Documents\report.xlsx","report.xlsx",1048576,2024-01-15T10:30:45,2024-06-20T14:15:00,2024-06-20T14:15:00,0,32
C:,"\\?\C:\Users\jsmith\Documents\archive.zip","archive.zip",524288000,2023-05-10T09:00:00,2023-05-10T09:00:00,2023-05-10T09:00:00,0,32
D:,"\\?\D:\Backups","Backups",,2022-11-01T10:00:00,2025-12-15T08:00:00,2025-12-15T08:00:00,1,16
D:,"\\?\D:\Backups\db_full.bak","db_full.bak",53687091200,2025-12-15T02:00:00,2025-12-15T02:00:00,2025-12-15T02:00:00,0,32
```

---

## 4. Command Line Interface

### 4.1 Proposed Usage

```
mftscan.exe [options] [volume...]

Volumes:
  C: D: E:              Scan specific volumes
  --allVolumes          Scan all local NTFS volumes

Options:
  --output <path>       Output CSV file path (default: mftscan_<timestamp>.csv)
  --threads <n>         Number of worker threads (default: number of logical processors)
  --minSize <bytes>     Optional minimum file size filter (default: 0, no filter)
  --help                Show usage information

Output files:
  <output>.csv          Combined CSV with all volumes
  <output>_errors.log   Separate error log for inaccessible files
```

### 4.2 Examples

```
mftscan.exe C:
mftscan.exe C: D: --output results.csv
mftscan.exe --allVolumes --threads 8
mftscan.exe D: --minSize 1048576
mftscan.exe --allVolumes --output server01_scan.csv
```

### 4.3 Volume Enumeration for --allVolumes

When `--allVolumes` is specified, the scanner will:

1. Call `GetLogicalDriveStrings` to enumerate drive letters
2. For each drive, call `GetDriveType` to confirm it is `DRIVE_FIXED`
3. Call `GetVolumeInformation` to confirm the filesystem is NTFS
4. Add the volume root to the scan list
5. Skip removable, network, CD-ROM, and non-NTFS volumes

---

## 5. Assumptions

### 5.1 Environment

1. **Windows Server environment** - Windows Server 2016 or later
2. **NTFS filesystem** - Scanner targets NTFS volumes only; non-NTFS volumes are skipped with `--allVolumes`
3. **Local volumes** - Direct access to volumes (not network shares)
4. **64-bit system** - Required for handling files >4GB and large file counts
5. **No administrator privilege required** - Scanner uses FindFirstFileW/FindNextFileW which does not require elevated access (some files may be inaccessible due to ACLs)
6. **Sufficient disk space for CSV output** - Large volumes (millions of files) can produce CSV files in the hundreds of MB to low GB range

### 5.2 Data

1. **NtfsDisableLastAccessUpdate is ON** - Confirmed. Access time is collected but unreliable for determining actual last access
2. **Standard NTFS volumes** - Not using ReFS, Storage Spaces with parity, or other non-standard configurations
3. **Long paths exist** - Scanner must handle paths >260 characters using `\\?\` prefix
4. **Some files will be inaccessible** - Files locked by OS, protected by ACLs, or in use will generate errors; these are logged and scanning continues

### 5.3 Scope

1. **No derived values** - The scanner outputs raw extracted data only; all calculations, aggregation, categorization, and reporting are deferred to the downstream database/reporting layer
2. **No filtering/exclusions in scanner** - By default all files and directories are emitted to the CSV; `--minSize` is available as an optional filter but defaults to 0 (no filter). All exclusion logic is done at the database/query level
3. **No historical retention in scanner** - Each scan produces a fresh output file that overwrites any previous output; historical tracking is deferred to the database layer
4. **CSV output only** - No database writes from the scanner; data is loaded into a database separately
5. **Errors to separate file** - Inaccessible files are omitted from CSV and logged to a separate error log file

---

## 6. Deferred Items

The following items were considered but are deferred to future phases:

| # | Item | Reason |
|---|------|--------|
| 1 | Windows Server Deduplication detection | Deferred |
| 2 | Shadow copies / VSS reporting | Deferred |
| 3 | Alternate Data Streams enumeration | Deferred |
| 4 | Scan frequency / scheduling | Deferred |
| 5 | Database storage and schema | Deferred (separate discussion) |
| 6 | Report distribution mechanism | Deferred |
| 7 | Approval workflow for deletion/archival | Deferred |
| 8 | Retention policy integration | Deferred |
| 9 | Archive destination selection | Deferred |
| 10 | Success metrics definition | Deferred |
| 11 | Derived/calculated values (age, extension category, etc.) | Deferred to database layer |
| 12 | Owner/SID resolution | Deferred |
| 13 | Duplicate detection | Deferred |
| 14 | Allocated size (requires additional API or MFT parsing) | Deferred |
| 15 | Folder-level aggregation | Deferred to database layer |

---

## 7. Future Attributes for Consideration

When the scanner is extended beyond MVP, the following attributes are available from the MFT and Win32 APIs for future phases:

| Attribute | Source | Use Case |
|-----------|--------|----------|
| Allocated Size | GetFileInformationByHandleEx or MFT $DATA | True disk space consumption |
| Owner SID | GetSecurityInfo | Per-user storage attribution |
| Alternate Data Streams | FindFirstStreamW | Hidden storage consumers |
| Reparse Tag | DeviceIoControl FSCTL_GET_REPARSE_POINT | Dedup, HSM, symlink type |
| Hard Link Count | GetFileInformationByHandle | Shared file detection |
| MFT Change Time | Direct MFT parsing | Metadata-only change detection |
| File ID | GetFileInformationByHandle | Stable identifier across renames |
| Compression state detail | DeviceIoControl FSCTL_GET_COMPRESSION | Compression ratio |
| EFS encryption status | Attribute flags + detailed query | Encrypted file handling |

---

## 8. Reference: NTFS MFT Attribute Types

For context on what the MFT contains (useful for future scanner enhancements):

| Type Code | Attribute Name | Description |
|-----------|---------------|-------------|
| 0x10 | $STANDARD_INFORMATION | Timestamps, permissions, flags |
| 0x20 | $ATTRIBUTE_LIST | List of attributes if record spans multiple MFT entries |
| 0x30 | $FILE_NAME | File name (may have multiple: Win32, DOS, POSIX) |
| 0x40 | $OBJECT_ID | Unique object identifier (GUID) |
| 0x50 | $SECURITY_DESCRIPTOR | ACL and ownership (usually in $Secure) |
| 0x60 | $VOLUME_NAME | Volume label (root only) |
| 0x70 | $VOLUME_INFORMATION | NTFS version info (root only) |
| 0x80 | $DATA | File content or stream |
| 0x90 | $INDEX_ROOT | Directory index (small directories) |
| 0xA0 | $INDEX_ALLOCATION | Directory index (large directories) |
| 0xB0 | $BITMAP | Allocation bitmap |
| 0xC0 | $REPARSE_POINT | Symlink, junction, dedup, HSM, etc. |
| 0xD0 | $EA_INFORMATION | Extended attributes info |
| 0xE0 | $EA | Extended attributes data |
| 0x100 | $LOGGED_UTILITY_STREAM | EFS encrypted file info |

---

## 9. Resolved Decisions

All implementation questions from v2.0 have been resolved:

| # | Question | Decision | Rationale |
|---|----------|----------|-----------|
| 1 | Volume column in CSV | **Combined CSV with Volume column** | Easier to load into database; single file to manage |
| 2 | Error handling | **Separate error log file** | Keeps CSV clean for database import; errors available for troubleshooting |
| 3 | Directory size | **Empty (omitted)** | Directories have no meaningful file size; avoids confusion with folder totals |
| 4 | Reparse point entries | **Attributes only, no target resolution** | Simpler; attributes bitmask identifies reparse points; target resolution deferred |
| 5 | Default size filter | **No filter (capture everything)** | Comprehensive data capture for database; `--minSize` retained as optional filter |

### 9.1 Error Log Format

The error log file (`<output>_errors.log`) will contain one line per error:

```
2026-02-04T14:30:15Z | ERROR | 5 | Access is denied. | \\?\C:\System Volume Information\tracking.log
2026-02-04T14:30:15Z | ERROR | 3 | The system cannot find the path specified. | \\?\C:\Users\jsmith\AppData\Local\Temp\~DF1234.tmp
```

Format: `Timestamp | ERROR | WindowsErrorCode | ErrorDescription | FullPath`

---

## 10. Decision Log

| Date | Version | Decisions Made |
|------|---------|----------------|
| 2026-02-02 | 1.0 | Initial analysis document created with full MFT attribute inventory and open questions |
| 2026-02-04 | 2.0 | MVP scope defined: 8 attributes, CSV output, no derived values. Answered questions on access time, long paths, junctions, volumes, exclusions, historical data, output format, file names |
| 2026-02-04 | 3.0 | All implementation questions resolved: combined CSV with Volume column, separate error log, empty directory size, reparse attributes only, no default size filter. 9 attributes total (Volume added) |
| 2026-02-04 | 3.1 | Implementation complete: `cpp/mftscan/mftscan.cpp` created (1079 lines). Visual Studio project files created. Solution file updated to include both mfttest and mftscan projects. |

---

*Document Version: 3.1*
*Updated: 2026-02-04*
*Previous Versions: 3.0 (2026-02-04), 2.0 (2026-02-04), 1.0 (2026-02-02)*
*Purpose: MVP specification for MFT data extraction to CSV for space utilization reporting*
