# Data Structure Optimization Plan

## Executive Summary

The current implementation stores 161M+ file entries with full paths, resulting in massive data redundancy (44 GB CSV) and extremely slow import times (24+ hours). This document proposes a normalized structure that:

- Reduces data volume by **73%** (44 GB → 12 GB)
- Improves query performance with integer joins instead of string operations
- Shifts processing work from SQL Server to the scanning EXE (mftdirect.exe)
- Reduces import time from **24+ hours to 1-2 hours**
- Adds data quality indicators (Last Access Time reliability)

**Note:** All EXE changes target `mftdirect.cpp` only. The `mftscan.cpp` tool is deprecated.

---

## Current State

### Data Flow

```
[Windows Server] → [mftdirect.exe] → [JSON + CSV] → [BULK INSERT] → [SQL Server]
     5-15 min           scan              write         5+ hours        query
```

### Current Output Files

| File | Size | Contents |
|------|------|----------|
| `*.json` | ~2 KB | Manifest (server, volumes, stats) |
| `*.csv` | ~4 GB | All file entries with full paths |

### Current CSV Structure

```csv
Volume,FullPath,FileName,FileSize,CreatedTime,ModifiedTime,AccessedTime,IsDirectory,Attributes
C:,C:\Users\john\Documents\Projects\2024\Reports\Q1\sales.xlsx,sales.xlsx,45678,2024-01-15,2024-03-20,2024-03-20,0,32
C:,C:\Users\john\Documents\Projects\2024\Reports\Q1\budget.xlsx,budget.xlsx,34567,2024-01-15,2024-02-10,2024-02-10,0,32
C:,C:\Users\john\Documents\Projects\2024\Reports\Q2\sales.xlsx,sales.xlsx,48901,2024-04-01,2024-06-15,2024-06-15,0,32
```

**Problem:** The path `C:\Users\john\Documents\Projects\2024\Reports\` appears thousands of times.

### Current Database Schema

```
┌─────────────────────────────────────────────────────────────────────┐
│ FileEntry (45M+ rows, ~15 GB with compression)                      │
├─────────────────────────────────────────────────────────────────────┤
│ FileEntryId      BIGINT          PK                                 │
│ BatchId          UNIQUEIDENTIFIER FK → ScanBatch                    │
│ Volume           NVARCHAR(512)   "C:" repeated millions of times    │
│ FullPath         NVARCHAR(4000)  Full path repeated per file        │
│ FileName         NVARCHAR(512)   Just the filename                  │
│ FileSize         BIGINT                                             │
│ CreatedTime      DATETIME2(0)                                       │
│ ModifiedTime     DATETIME2(0)                                       │
│ AccessedTime     DATETIME2(0)                                       │
│ IsDirectory      BIT                                                │
│ Attributes       BIGINT                                             │
│ IsTempCache      BIT             Pre-computed flag                  │
└─────────────────────────────────────────────────────────────────────┘
```

### Current Pain Points

| Issue | Impact |
|-------|--------|
| Path redundancy | ~70% of CSV size is repeated path prefixes |
| String-heavy table | Large storage, slow comparisons |
| BULK INSERT bottleneck | 5+ hours to import 45M rows |
| Extension parsing at query time | CPU overhead on every query |
| Folder aggregation requires string parsing | Slow GROUP BY operations |

---

## Proposed Future State

### Data Flow

```
[Windows Server] → [mftdirect.exe] → [JSON + CSVs] → [BULK INSERT] → [SQL Server]
     5-15 min         scan+process      3 files        15-30 min       fast query
```

### Proposed Output Files

| File | Est. Size | Contents |
|------|-----------|----------|
| `*_manifest.json` | ~2 KB | Server, volumes, stats (unchanged) |
| `*_directories.csv` | ~50 MB | Unique directory paths with IDs |
| `*_files.csv` | ~1.5 GB | Files referencing directory IDs |

### Proposed CSV Structures

**directories.csv** (~150K rows for 45M files)
```csv
DirectoryId,ParentId,Depth,FullPath,DirectoryName,VolumeId,IsTempCache
1,0,0,C:\,C:,1,0
2,1,1,C:\Users,Users,1,0
3,2,2,C:\Users\john,john,1,0
4,3,3,C:\Users\john\Documents,Documents,1,0
5,4,4,C:\Users\john\Documents\Projects,Projects,1,0
100,5,5,C:\Users\john\Documents\Projects\2024\Reports\Q1,Q1,1,0
```

**files.csv** (~45M rows, but much narrower)
```csv
DirectoryId,FileName,Extension,FileSize,CreatedTime,ModifiedTime,AccessedTime,Attributes
100,sales.xlsx,xlsx,45678,2024-01-15,2024-03-20,2024-03-20,32
100,budget.xlsx,xlsx,34567,2024-01-15,2024-02-10,2024-02-10,32
101,sales.xlsx,xlsx,48901,2024-04-01,2024-06-15,2024-06-15,32
```

### Proposed Database Schema

```
┌────────────────────────────────────┐
│ ScanBatch (unchanged)              │
├────────────────────────────────────┤
│ BatchId        UNIQUEIDENTIFIER PK │
│ ServerName     NVARCHAR(256)       │
│ CollectedAtUtc DATETIME2(0)        │
│ ...                                │
└────────────────────────────────────┘
          │
          │ 1:N
          ▼
┌────────────────────────────────────┐
│ ScanVolume (unchanged)             │
├────────────────────────────────────┤
│ ScanVolumeId   INT PK              │
│ BatchId        UNIQUEIDENTIFIER FK │
│ VolumeName     NVARCHAR(512)       │
│ ...                                │
└────────────────────────────────────┘
          │
          │ 1:N
          ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Directory (~150K rows per batch)                                    │
├─────────────────────────────────────────────────────────────────────┤
│ DirectoryId    INT               PK (assigned by EXE, not IDENTITY) │
│ BatchId        UNIQUEIDENTIFIER  FK → ScanBatch                     │
│ ScanVolumeId   INT               FK → ScanVolume                    │
│ ParentId       INT               FK → Directory (0 = root)          │
│ Depth          TINYINT           Folder depth (0 = volume root)     │
│ DirectoryName  NVARCHAR(256)     Just folder name, not full path    │
│ FullPath       NVARCHAR(4000)    Full path (for display/export)     │
│ IsTempCache    BIT               Pre-computed flag                  │
│ FileCount      INT               Pre-computed by EXE                │
│ TotalFileSize  BIGINT            Pre-computed by EXE                │
└─────────────────────────────────────────────────────────────────────┘
          │
          │ 1:N
          ▼
┌─────────────────────────────────────────────────────────────────────┐
│ FileEntry (~45M rows per batch, but MUCH smaller)                   │
├─────────────────────────────────────────────────────────────────────┤
│ FileEntryId    BIGINT            PK (IDENTITY)                      │
│ BatchId        UNIQUEIDENTIFIER  FK → ScanBatch                     │
│ DirectoryId    INT               FK → Directory                     │
│ FileName       NVARCHAR(256)     Just filename, no path             │
│ Extension      NVARCHAR(32)      Pre-extracted by EXE (lowercase)   │
│ FileSize       BIGINT                                               │
│ CreatedTime    DATETIME2(0)                                         │
│ ModifiedTime   DATETIME2(0)                                         │
│ AccessedTime   DATETIME2(0)                                         │
│ Attributes     INT               Reduced from BIGINT (32 bits max)  │
└─────────────────────────────────────────────────────────────────────┘
```

### Size Comparison

| Component | Current | Proposed | Reduction |
|-----------|---------|----------|-----------|
| Volume column | 512 bytes × 45M | INT FK (4 bytes) | ~99% |
| FullPath column | Avg 150 bytes × 45M | Moved to Directory | ~100% |
| FileName column | Avg 30 bytes × 45M | Same | 0% |
| Extension | Computed at query | Pre-stored (10 bytes) | Adds space, saves CPU |
| IsTempCache | 1 byte × 45M | 1 byte × 150K | ~99% |
| **Total FileEntry** | ~15 GB | ~4 GB | **~70%** |
| **Total Directory** | N/A | ~100 MB | New table |

---

## Pre-Processing in EXE

### Current EXE Output
- Writes raw data as scanned
- SQL Server does all transformation

### Proposed EXE Processing

| Task | Current (SQL) | Proposed (EXE) | Benefit |
|------|---------------|----------------|---------|
| Build directory tree | N/A | Hash map during scan | Enables normalization |
| Assign DirectoryId | N/A | Sequential counter | Integer FKs |
| Extract extension | Query-time CHARINDEX | During file write | Faster queries |
| Compute IsTempCache | Query-time LIKE | Path pattern match | Smaller flag table |
| Compute directory stats | GROUP BY at import | Running totals | Pre-aggregated |
| Strip `\\?\` prefix | CASE in INSERT | During write | Cleaner data |

### EXE Implementation Approach

```cpp
// During scan, maintain a directory dictionary
std::unordered_map<std::wstring, int> directoryMap;
int nextDirectoryId = 1;

// For each file encountered:
std::wstring dirPath = GetDirectoryPart(fullPath);
int dirId;
auto it = directoryMap.find(dirPath);
if (it == directoryMap.end()) {
    dirId = nextDirectoryId++;
    directoryMap[dirPath] = dirId;
    WriteDirectoryRecord(dirId, dirPath, ...);
} else {
    dirId = it->second;
}
WriteFileRecord(dirId, fileName, extension, ...);
```

---

## Last Access Time Handling

### The Problem

Windows disables NTFS last access time updates by default since Vista/Server 2008. Collecting access times when they're unreliable wastes space and misleads users.

### Registry Setting

The behavior is controlled by:
```
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\FileSystem\NtfsDisableLastAccessUpdate
```

| Value | Meaning | Access Times Reliable? |
|-------|---------|------------------------|
| 0 | User Managed, Enabled | Yes |
| 1 | User Managed, Disabled | No |
| 2 | System Managed, Enabled | Yes |
| 3 | System Managed, Disabled | **No (default)** |

### Implementation

**Step 1: Check registry at startup**
```cpp
struct LastAccessConfig {
    DWORD registryValue;
    bool isEnabled;
    const wchar_t* description;
};

static LastAccessConfig GetLastAccessTimeStatus() {
    LastAccessConfig config = { 3, false, L"Unknown" };

    HKEY hKey;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE,
                      L"SYSTEM\\CurrentControlSet\\Control\\FileSystem",
                      0, KEY_READ, &hKey) == ERROR_SUCCESS) {
        DWORD value = 0;
        DWORD size = sizeof(value);
        if (RegQueryValueExW(hKey, L"NtfsDisableLastAccessUpdate",
                            NULL, NULL, (LPBYTE)&value, &size) == ERROR_SUCCESS) {
            config.registryValue = value;
        }
        RegCloseKey(hKey);
    }

    // Interpret: bit 0 set = disabled
    switch (config.registryValue & 0x3) {
        case 0: config.isEnabled = true;  config.description = L"User Managed, Enabled"; break;
        case 1: config.isEnabled = false; config.description = L"User Managed, Disabled"; break;
        case 2: config.isEnabled = true;  config.description = L"System Managed, Enabled"; break;
        case 3: config.isEnabled = false; config.description = L"System Managed, Disabled"; break;
    }

    return config;
}
```

**Step 2: Record in JSON manifest**
```json
{
  "schemaVersion": 2,
  "toolName": "mftdirect",
  "toolVersion": "2.0",
  "serverName": "YKT1OFSPRD1",
  "collectedAtUtc": "2026-02-10T10:22:58Z",
  "lastAccessTime": {
    "registryValue": 3,
    "status": "System Managed, Disabled",
    "enabled": false,
    "collected": false
  },
  "volumes": [ ... ]
}
```

**Step 3: Conditionally collect access times**
- If `lastAccessTime.enabled == true`: Include AccessedTime in CSV
- If `lastAccessTime.enabled == false`: Omit AccessedTime column entirely

### Benefits

| Aspect | Impact |
|--------|--------|
| CSV size | ~10% smaller when access times omitted |
| Data quality | Clear signal that access times are unreliable |
| Dashboard | Can hide access-time panels when data unavailable |
| Import | Fewer columns = faster import |

---

## Import Optimization

### Current Import Method: BULK INSERT via T-SQL

```sql
BULK INSERT #CsvStaging
FROM 'C:\temp\file.csv'
WITH (FORMAT = 'CSV', ...);

INSERT INTO dbo.FileEntry
SELECT ... FROM #CsvStaging;
```

**Problems:**
- BULK INSERT reads entire file into tempdb
- INSERT...SELECT generates full transaction log
- Single-threaded operation
- No parallelism

### Alternative Import Methods

| Method | Speed | Complexity | Parallelism | Notes |
|--------|-------|------------|-------------|-------|
| BULK INSERT (current) | Slow | Low | No | Limited by transaction log |
| bcp.exe utility | Fast | Low | No | Native tool, minimal logging |
| SSIS package | Fast | High | Yes | Enterprise feature |
| SqlBulkCopy (.NET) | Fast | Medium | Yes* | Can parallelize in code |
| OPENROWSET(BULK) | Medium | Low | No | Similar to BULK INSERT |
| Parallel bcp (multiple files) | Very Fast | Medium | Yes | Split CSV, parallel loads |

### Recommended Approach: Parallel bcp with Pre-Split Files

**Step 1: EXE outputs multiple file chunks**
```
files_part001.csv (1M rows)
files_part002.csv (1M rows)
...
files_part045.csv (remaining rows)
```

**Step 2: PowerShell parallel import**
```powershell
$files = Get-ChildItem "*_files_part*.csv"
$files | ForEach-Object -Parallel {
    bcp FileSizes.dbo.FileEntry_Staging in $_.FullName -S server -d FileSizes -T -c -t"," -r"\n"
} -ThrottleLimit 4
```

**Step 3: Merge staging to production (single statement)**
```sql
INSERT INTO dbo.FileEntry WITH (TABLOCK)
SELECT * FROM dbo.FileEntry_Staging;
TRUNCATE TABLE dbo.FileEntry_Staging;
```

### Database Configuration for Fast Import

```sql
-- Before import: Set bulk-logged recovery
ALTER DATABASE FileSizes SET RECOVERY BULK_LOGGED;

-- Use TABLOCK hint for minimal logging
BULK INSERT dbo.Directory
FROM 'C:\temp\directories.csv'
WITH (FORMAT = 'CSV', TABLOCK, BATCHSIZE = 100000);

-- After import: Return to full recovery
ALTER DATABASE FileSizes SET RECOVERY FULL;

-- Rebuild indexes that were disabled
ALTER INDEX ALL ON dbo.FileEntry REBUILD;
```

### Import Time Estimates

| Scenario | Current | Proposed |
|----------|---------|----------|
| CSV size | 4 GB | 1.5 GB |
| BULK INSERT | 5+ hours | 45 min |
| Parallel bcp (4 threads) | N/A | 15-20 min |
| Index rebuild | Included | 10-15 min |
| **Total** | **5+ hours** | **30-40 min** |

---

## Query Impact

### Current: Extension Grouping
```sql
-- Slow: String parsing on 45M rows
SELECT
    CASE WHEN CHARINDEX('.', REVERSE(FileName)) > 0
         THEN LOWER(RIGHT(FileName, CHARINDEX('.', REVERSE(FileName)) - 1))
         ELSE '(no ext)'
    END AS Extension,
    SUM(FileSize) AS TotalBytes
FROM FileEntry
WHERE BatchId = @BatchId
GROUP BY
    CASE WHEN CHARINDEX('.', REVERSE(FileName)) > 0
         THEN LOWER(RIGHT(FileName, CHARINDEX('.', REVERSE(FileName)) - 1))
         ELSE '(no ext)'
    END
```

### Proposed: Extension Grouping
```sql
-- Fast: Pre-computed column, simple GROUP BY
SELECT Extension, SUM(FileSize) AS TotalBytes
FROM FileEntry
WHERE BatchId = @BatchId
GROUP BY Extension
```

### Current: Folder Size Aggregation
```sql
-- Slow: String parsing to extract folder
SELECT
    SUBSTRING(FullPath, 1, LEN(FullPath) - LEN(FileName) - 1) AS Folder,
    SUM(FileSize)
FROM FileEntry
WHERE BatchId = @BatchId
GROUP BY SUBSTRING(FullPath, 1, LEN(FullPath) - LEN(FileName) - 1)
```

### Proposed: Folder Size Aggregation
```sql
-- Fast: Pre-aggregated in Directory table
SELECT d.FullPath, d.TotalFileSize
FROM Directory d
WHERE d.BatchId = @BatchId
ORDER BY d.TotalFileSize DESC

-- Or join for real-time calculation
SELECT d.FullPath, SUM(f.FileSize)
FROM Directory d
JOIN FileEntry f ON f.DirectoryId = d.DirectoryId AND f.BatchId = d.BatchId
WHERE d.BatchId = @BatchId
GROUP BY d.DirectoryId, d.FullPath
```

### Current: Temp/Cache Files
```sql
-- Slow: Multiple LIKE patterns on 45M rows
SELECT * FROM FileEntry
WHERE BatchId = @BatchId
  AND (FullPath LIKE '%\Temp\%' OR FullPath LIKE '%\Cache\%' ...)
```

### Proposed: Temp/Cache Files
```sql
-- Fast: Flag is on Directory, join is on INT
SELECT f.*, d.FullPath
FROM FileEntry f
JOIN Directory d ON d.DirectoryId = f.DirectoryId AND d.BatchId = f.BatchId
WHERE f.BatchId = @BatchId
  AND d.IsTempCache = 1
```

---

## EXE Implementation Plan (mftdirect.cpp)

### Overview

All changes target `mftdirect.cpp`. The goal is to shift processing from SQL Server to the EXE, producing optimized output files that import quickly.

### New Data Structures

```cpp
// Configuration for last access time behavior
struct LastAccessConfig {
    DWORD registryValue;
    bool isEnabled;
    const wchar_t* description;
};

// Directory entry with pre-computed stats
struct DirectoryEntry {
    int directoryId;
    int parentId;
    int volumeIndex;
    int depth;
    std::wstring fullPath;
    std::wstring directoryName;
    bool isTempCache;
    LONGLONG fileCount;        // Incremented as files are found
    LONGLONG totalFileSize;    // Accumulated as files are found
};

// Scan configuration (extended)
struct ScanConfig {
    // ... existing fields ...
    LastAccessConfig lastAccessConfig;
    bool outputNormalizedFormat;   // New: enable multi-file output
    int fileChunkSize;             // New: rows per files_partNNN.csv (default 5M)
};
```

### New Helper Functions

| Function | Purpose |
|----------|---------|
| `GetLastAccessTimeStatus()` | Read registry, determine if access times reliable |
| `GetOrCreateDirectoryId()` | Hash map lookup/insert for directory paths |
| `ExtractExtension()` | Parse extension from filename (lowercase) |
| `IsTempCachePath()` | Check if path matches temp/cache patterns |
| `ComputeParentId()` | Find parent directory ID from path |
| `WriteDirectoryRecord()` | Output row to directories.csv |
| `WriteFileRecord()` | Output row to files.csv (or chunked file) |
| `FinalizeDirectoryStats()` | Write directory aggregates after scan |

### Output File Changes

**Current (v1):**
```
mftdirect_YYYYMMDD_HHMMSS.json        # Manifest
mftdirect_YYYYMMDD_HHMMSS.csv         # All data (44 GB)
mftdirect_YYYYMMDD_HHMMSS_errors.log  # Errors
```

**Proposed (v2):**
```
mftdirect_YYYYMMDD_HHMMSS.json              # Manifest (updated schema)
mftdirect_YYYYMMDD_HHMMSS_directories.csv   # Directory tree (~3 GB)
mftdirect_YYYYMMDD_HHMMSS_files_001.csv     # Files chunk 1 (~1.5 GB)
mftdirect_YYYYMMDD_HHMMSS_files_002.csv     # Files chunk 2 (~1.5 GB)
...
mftdirect_YYYYMMDD_HHMMSS_files_NNN.csv     # Files chunk N
mftdirect_YYYYMMDD_HHMMSS_errors.log        # Errors
```

### JSON Manifest Schema v2

```json
{
  "schemaVersion": 2,
  "toolName": "mftdirect",
  "toolVersion": "2.0",
  "serverName": "YKT1OFSPRD1",
  "collectedAtUtc": "2026-02-10T10:22:58Z",
  "collectedBy": "ADMGMT\\dt234083-adm",
  "durationSec": 1840.2,

  "lastAccessTime": {
    "registryValue": 3,
    "status": "System Managed, Disabled",
    "enabled": false,
    "collected": false
  },

  "outputFiles": {
    "directories": "mftdirect_20260210_102258_directories.csv",
    "fileChunks": [
      "mftdirect_20260210_102258_files_001.csv",
      "mftdirect_20260210_102258_files_002.csv"
    ],
    "errors": "mftdirect_20260210_102258_errors.log"
  },

  "totals": {
    "entries": 161824006,
    "directories": 19707899,
    "files": 142116107,
    "totalBytes": 48000000000000
  },

  "volumes": [
    {
      "volumeId": 1,
      "name": "C:",
      "label": "",
      "fileSystem": "NTFS",
      "totalSizeBytes": 224848285696,
      "freeSizeBytes": 91404730368,
      "entryCount": 392919,
      "directoryCount": 66238,
      "fileCount": 326681,
      "errorCount": 0,
      "scanDurationSec": 8.9
    }
  ]
}
```

### CSV Column Definitions

**directories.csv:**
```csv
DirectoryId,ParentId,VolumeId,Depth,FullPath,DirectoryName,IsTempCache,FileCount,TotalFileSize
1,0,1,0,C:\,(root),0,15,234567
2,1,1,1,C:\Users,Users,0,0,0
3,2,1,2,C:\Users\john,john,0,0,0
4,3,1,3,C:\Users\john\AppData\Local\Temp,Temp,1,5420,1234567890
```

**files_NNN.csv (when access times enabled):**
```csv
DirectoryId,FileName,Extension,FileSize,CreatedTime,ModifiedTime,AccessedTime,Attributes
4,cache001.tmp,tmp,12345,2026-01-15 10:00:00,2026-02-01 14:30:00,2026-02-10 09:00:00,32
```

**files_NNN.csv (when access times disabled):**
```csv
DirectoryId,FileName,Extension,FileSize,CreatedTime,ModifiedTime,Attributes
4,cache001.tmp,tmp,12345,2026-01-15 10:00:00,2026-02-01 14:30:00,32
```

### Implementation Phases

#### Phase 1: Foundation ✅ COMPLETE
1. ✅ Add `LastAccessConfig` struct and `GetLastAccessTimeStatus()`
2. ✅ Add `lastAccessTime` section to JSON manifest
3. ✅ Add directory hash map data structure (extended DirEntry)
4. ✅ Add `ExtractExtension()` helper
5. ✅ Add `IsTempCachePath()` helper
6. Test: Verify manifest includes access time status

#### Phase 2: Normalized Output ✅ COMPLETE
1. ✅ Extended `DirEntry` struct with stats tracking (directoryId, parentDirId, depth, isTempCache, fileCount, totalFileSize)
2. ✅ Implement `AssignDirectoryIds()` with parent tracking
3. ✅ Create `WriteDirectoriesCsv()` - writes _directories.csv
4. ✅ Create files CSV writer - writes _files.csv
5. ✅ Update main scan loop to use new output format
6. ✅ V2 is now the default format (v1 removed for simplicity)
7. Test: Compare output with database schema

#### Phase 3: Conditional Access Time ✅ COMPLETE
1. ⏳ File chunking (5M rows per chunk) - DEFERRED to future release
2. ✅ Track filenames in manifest (outputFiles section)
3. ✅ Conditionally omit AccessedTime column based on registry check
4. ✅ Pre-compute directory FileCount/TotalFileSize during Pass 2
5. ✅ Finalize directory stats after scan completes
6. Test: Verify parallel import works with chunks

#### Phase 4: Cleanup
1. ✅ V2 format is the default
2. V1 format removed (breaking change)
3. Update documentation

---

## Database Migration Path

### Phase 1: New Schema (alongside existing)
1. Create `Directory` table
2. Create `FileEntry_v2` table (optimized schema)
3. Create new import script for v2 format
4. Test import performance with production data

### Phase 2: Dashboard Updates
1. Create v2 versions of dashboard queries
2. Add Directory-based panels
3. Leverage pre-aggregated directory stats
4. Handle missing AccessedTime gracefully

### Phase 3: Cutover
1. Import new scans to v2 schema only
2. Keep old data in v1 schema (read-only)
3. Update dashboards to use v2 schema

### Phase 4: Deprecation
1. Drop v1 FileEntry table after retention period
2. Remove v1 import scripts
3. Rename FileEntry_v2 to FileEntry

---

## Open Questions

1. **Chunk size** — How many rows per files CSV chunk? Options:
   - 1M rows (~65 MB per chunk) — More parallelism, more files
   - 5M rows (~325 MB per chunk) — Balance of parallelism and file count
   - 10M rows (~650 MB per chunk) — Fewer files, less overhead

2. **Memory usage** — The directory hash map will hold 19.7M entries. At ~300 bytes each, that's ~6 GB RAM. Acceptable for a file server scan tool?

3. **Command-line interface** — Proposed flags:
   ```
   --format=v1         Output legacy single-CSV format
   --format=v2         Output normalized multi-file format (default)
   --chunk-size=5000000  Rows per file chunk
   --no-access-time    Force omit access times even if enabled
   ```
   Are these sufficient?

4. **Import tooling** — Options for the import process:
   - PowerShell script calling bcp in parallel
   - Standalone .NET import tool with progress reporting
   - SSIS package (if enterprise SQL Server)

   Which approach fits your environment?

5. **Backward compatibility period** — How long should we support v1 format alongside v2? Suggested: 2-3 releases.

6. **Directory stats timing** — Two options:
   - **Option A:** Two-pass scan — first pass counts files, second pass writes with stats
   - **Option B:** Write directories at end — hold all directory entries in memory, write after scan completes with final stats

   Option B uses more memory but is faster. With 19.7M directories at ~300 bytes, that's ~6 GB. Acceptable?

7. **Error handling** — If scan fails mid-way:
   - Should partial directories.csv be usable?
   - Should we write a "scan incomplete" flag in manifest?
   - Should chunks be importable independently?

---

## Appendix: Data Volume Estimates

### Real Production Data (YKT1OFSPRD1 - File Server)

```
Server: YKT1OFSPRD1
Scan Duration: 30.7 minutes
Total Entries: 161,824,006
CSV Size: 44.4 GB

Volumes:
  C: drive -    393K entries (66K dirs,    327K files) -  209 GB capacity
  D: drive -     39K entries ( 4K dirs,     35K files) -  209 GB capacity
  E: drive - 161.4M entries (19.6M dirs, 141.8M files) - 59.6 TB capacity (file share)
```

| Metric | Current | Proposed |
|--------|---------|----------|
| Total files | 142,116,107 | 142,116,107 |
| Unique directories | N/A | **19,707,899** |
| Files per directory (avg) | N/A | 7.2 |
| Avg path length | ~275 bytes | ~275 bytes (Directory only) |
| Avg filename length | ~35 bytes | ~35 bytes |
| **CSV file size** | **44.4 GB** | **~12 GB** |
| CSV reduction | — | **73%** |
| Estimated import time | 24-36 hours | 1-2 hours |

### Breakdown of Proposed Files

| File | Rows | Est. Row Size | Est. File Size |
|------|------|---------------|----------------|
| directories.csv | 19.7M | 150 bytes | ~3 GB |
| files.csv | 142M | 65 bytes | ~9 GB |
| manifest.json | 1 | 2 KB | 2 KB |
| **Total** | — | — | **~12 GB** |

### Why Current Import Is So Slow

With 44.4 GB CSV and 161M rows:
1. **BULK INSERT** reads entire file through tempdb
2. **Transaction log** grows to handle 161M inserts
3. **String columns** (FullPath NVARCHAR(4000)) cause page splits
4. **No parallelism** — single-threaded operation
5. **Index maintenance** on every batch

### Why Proposed Import Will Be Fast

1. **73% less data** to read from disk
2. **Integer DirectoryId** instead of repeated paths
3. **Pre-computed Extension** — no string parsing
4. **Parallel loading** — 4-8 bcp processes
5. **Minimal logging** with TABLOCK hint
6. **Narrower rows** = more rows per page = fewer I/O operations

---

## Summary: Key Improvements

| Area | Current | Proposed | Improvement |
|------|---------|----------|-------------|
| CSV output size | 44.4 GB | ~12 GB | 73% reduction |
| Import time | 24-36 hours | 1-2 hours | 95% faster |
| Extension queries | String parsing | Pre-computed column | 10-100x faster |
| Folder aggregation | String parsing | Integer join | 10-100x faster |
| Temp/cache queries | LIKE on 142M rows | Flag on 19.7M dirs | 100x faster |
| Access time quality | Unknown | Documented in manifest | Clear data quality |
| Directory stats | Computed at query | Pre-aggregated | Instant |

## Next Steps

1. **Review this document** — Confirm approach and answer open questions
2. **Phase 1 implementation** — Add Last Access Time detection to mftdirect.cpp
3. **Phase 2 implementation** — Add normalized output format
4. **Create import scripts** — Parallel bcp or .NET importer
5. **Update database schema** — Add Directory table, FileEntry_v2
6. **Update dashboards** — Leverage new schema for faster queries
