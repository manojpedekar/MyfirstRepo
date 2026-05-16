# Grafana Dashboard Analysis & Enhancement Options

## Current Dashboard Overview

The `demoboard.json` dashboard ("FileStatReport") provides space utilization reporting with 6 panels:

| Panel | Type | Purpose |
|-------|------|---------|
| Batch Info | Table | Shows scan metadata (server, tool, collected time, volume count, total entries) |
| Volume Capacity Summary | Table | Volume-level breakdown with TotalGB, FreeGB, PctUsed, file/dir counts |
| File Type Distribution | Table | Space usage grouped by file extension |
| Duplicate File Candidates | Table | Files with same name+size appearing multiple times |
| Top 50 Largest Files | Table | Biggest files sorted by size |
| Stale Files | Table | Files >100MB not modified in 2+ years |

### Current Variables
- `${winventory}` — MSSQL datasource (hidden)
- `${batchid}` — Multi-select BatchId from ScanBatch table

---

## Enhancement Options

### 1. Visual Improvements

#### 1.1 Add Gauge/Stat Panels for KPIs
Replace or supplement the Batch Info table with visual stat panels:

| Metric | Visualization | Thresholds |
|--------|---------------|------------|
| Total Storage Scanned | Stat panel (TB) | — |
| Total Free Space | Stat panel (TB) | Green >20%, Yellow 10-20%, Red <10% |
| Percent Used (aggregate) | Gauge | Same as above |
| Total File Count | Stat panel | — |
| Stale Data (>2 years) | Stat panel (TB) | Red if >10% of total |
| Potential Duplicates | Stat panel (TB wasted) | Red if >5% of total |

**Query for aggregate stats:**
```sql
SELECT
    SUM(v.TotalSizeBytes) / 1099511627776.0 AS TotalTB,
    SUM(v.FreeSizeBytes) / 1099511627776.0 AS FreeTB,
    100.0 * SUM(v.TotalSizeBytes - v.FreeSizeBytes) / NULLIF(SUM(v.TotalSizeBytes), 0) AS PctUsed,
    SUM(v.FileCount) AS TotalFiles
FROM FileSizes.dbo.ScanVolume v
WHERE v.BatchId IN (${batchid:singlequote})
```

#### 1.2 Pie/Donut Charts
- **Space by Volume** — Pie chart showing each volume's contribution to total used space
- **Space by Extension** — Top 10 extensions as pie chart (currently table only)
- **Space by Top Folder** — New panel showing top-level directory breakdown

**Query for extension pie chart:**
```sql
SELECT TOP 10
    CASE
        WHEN CHARINDEX('.', REVERSE(f.FileName)) > 0
        THEN UPPER(RIGHT(f.FileName, CHARINDEX('.', REVERSE(f.FileName)) - 1))
        ELSE '(no ext)'
    END AS Extension,
    SUM(f.FileSize) / 1073741824.0 AS TotalGB
FROM FileSizes.dbo.FileEntry f
WHERE f.BatchId IN (${batchid:singlequote})
  AND f.IsDirectory = 0
  AND f.FileSize IS NOT NULL
GROUP BY
    CASE
        WHEN CHARINDEX('.', REVERSE(f.FileName)) > 0
        THEN UPPER(RIGHT(f.FileName, CHARINDEX('.', REVERSE(f.FileName)) - 1))
        ELSE '(no ext)'
    END
ORDER BY TotalGB DESC
```

#### 1.3 Bar Charts
- **Volume Capacity Bar Chart** — Stacked bar per volume: Used (blue) + Free (green)
- **Top Folders by Size** — Horizontal bar chart

---

### 2. New Analysis Panels

#### 2.1 Space by Top-Level Directory
Shows which root folders consume the most space per volume.

```sql
DECLARE @Volume NVARCHAR(512) = '${volume}';

SELECT TOP 20
    CASE
        WHEN CHARINDEX('\', f.FullPath, LEN(f.Volume) + 2) > 0
        THEN SUBSTRING(f.FullPath, LEN(f.Volume) + 2,
                       CHARINDEX('\', f.FullPath, LEN(f.Volume) + 2) - LEN(f.Volume) - 2)
        ELSE '(root files)'
    END AS TopFolder,
    COUNT(*) AS FileCount,
    SUM(f.FileSize) / 1073741824.0 AS TotalGB
FROM FileSizes.dbo.FileEntry f
WHERE f.BatchId IN (${batchid:singlequote})
  AND f.Volume = @Volume
  AND f.IsDirectory = 0
GROUP BY
    CASE
        WHEN CHARINDEX('\', f.FullPath, LEN(f.Volume) + 2) > 0
        THEN SUBSTRING(f.FullPath, LEN(f.Volume) + 2,
                       CHARINDEX('\', f.FullPath, LEN(f.Volume) + 2) - LEN(f.Volume) - 2)
        ELSE '(root files)'
    END
ORDER BY TotalGB DESC
```

**Requires:** New variable `${volume}` populated from ScanVolume.

#### 2.2 File Age Distribution
Shows how data ages — useful for retention policy planning.

```sql
SELECT
    CASE
        WHEN f.ModifiedTime >= DATEADD(MONTH, -1, GETUTCDATE()) THEN '< 1 month'
        WHEN f.ModifiedTime >= DATEADD(MONTH, -6, GETUTCDATE()) THEN '1-6 months'
        WHEN f.ModifiedTime >= DATEADD(YEAR, -1, GETUTCDATE()) THEN '6-12 months'
        WHEN f.ModifiedTime >= DATEADD(YEAR, -2, GETUTCDATE()) THEN '1-2 years'
        WHEN f.ModifiedTime >= DATEADD(YEAR, -5, GETUTCDATE()) THEN '2-5 years'
        ELSE '> 5 years'
    END AS AgeCategory,
    COUNT(*) AS FileCount,
    SUM(f.FileSize) / 1073741824.0 AS TotalGB
FROM FileSizes.dbo.FileEntry f
WHERE f.BatchId IN (${batchid:singlequote})
  AND f.IsDirectory = 0
  AND f.ModifiedTime IS NOT NULL
GROUP BY
    CASE
        WHEN f.ModifiedTime >= DATEADD(MONTH, -1, GETUTCDATE()) THEN '< 1 month'
        WHEN f.ModifiedTime >= DATEADD(MONTH, -6, GETUTCDATE()) THEN '1-6 months'
        WHEN f.ModifiedTime >= DATEADD(YEAR, -1, GETUTCDATE()) THEN '6-12 months'
        WHEN f.ModifiedTime >= DATEADD(YEAR, -2, GETUTCDATE()) THEN '1-2 years'
        WHEN f.ModifiedTime >= DATEADD(YEAR, -5, GETUTCDATE()) THEN '2-5 years'
        ELSE '> 5 years'
    END
ORDER BY
    CASE
        WHEN f.ModifiedTime >= DATEADD(MONTH, -1, GETUTCDATE()) THEN 1
        WHEN f.ModifiedTime >= DATEADD(MONTH, -6, GETUTCDATE()) THEN 2
        WHEN f.ModifiedTime >= DATEADD(YEAR, -1, GETUTCDATE()) THEN 3
        WHEN f.ModifiedTime >= DATEADD(YEAR, -2, GETUTCDATE()) THEN 4
        WHEN f.ModifiedTime >= DATEADD(YEAR, -5, GETUTCDATE()) THEN 5
        ELSE 6
    END
```

#### 2.3 File Size Distribution (Histogram)
Shows count of files in size buckets — helps understand file size patterns.

```sql
SELECT
    CASE
        WHEN f.FileSize < 1024 THEN '< 1 KB'
        WHEN f.FileSize < 1048576 THEN '1 KB - 1 MB'
        WHEN f.FileSize < 10485760 THEN '1 MB - 10 MB'
        WHEN f.FileSize < 104857600 THEN '10 MB - 100 MB'
        WHEN f.FileSize < 1073741824 THEN '100 MB - 1 GB'
        WHEN f.FileSize < 10737418240 THEN '1 GB - 10 GB'
        ELSE '> 10 GB'
    END AS SizeCategory,
    COUNT(*) AS FileCount,
    SUM(f.FileSize) / 1073741824.0 AS TotalGB
FROM FileSizes.dbo.FileEntry f
WHERE f.BatchId IN (${batchid:singlequote})
  AND f.IsDirectory = 0
GROUP BY
    CASE
        WHEN f.FileSize < 1024 THEN '< 1 KB'
        WHEN f.FileSize < 1048576 THEN '1 KB - 1 MB'
        WHEN f.FileSize < 10485760 THEN '1 MB - 10 MB'
        WHEN f.FileSize < 104857600 THEN '10 MB - 100 MB'
        WHEN f.FileSize < 1073741824 THEN '100 MB - 1 GB'
        WHEN f.FileSize < 10737418240 THEN '1 GB - 10 GB'
        ELSE '> 10 GB'
    END
ORDER BY MIN(f.FileSize)
```

#### 2.4 Growth Trend Over Time
Compare current scan to previous scans of the same server.

```sql
SELECT
    b.CollectedAtUtc,
    SUM(v.TotalSizeBytes - v.FreeSizeBytes) / 1099511627776.0 AS UsedTB,
    SUM(v.FreeSizeBytes) / 1099511627776.0 AS FreeTB,
    SUM(v.FileCount) AS TotalFiles
FROM FileSizes.dbo.ScanBatch b
JOIN FileSizes.dbo.ScanVolume v ON v.BatchId = b.BatchId
WHERE b.ServerName = '${server}'
GROUP BY b.BatchId, b.CollectedAtUtc
ORDER BY b.CollectedAtUtc
```

**Visualization:** Time series graph showing used space growth over time.
**Requires:** New variable `${server}` and multiple historical scans.

#### 2.5 Cleanup Recommendations Summary
Aggregates actionable items for business owners.

```sql
SELECT
    'Stale Files (>2 years, >100MB)' AS Category,
    COUNT(*) AS FileCount,
    SUM(f.FileSize) / 1073741824.0 AS TotalGB
FROM FileSizes.dbo.FileEntry f
WHERE f.BatchId IN (${batchid:singlequote})
  AND f.IsDirectory = 0
  AND f.FileSize >= 104857600
  AND f.ModifiedTime < DATEADD(YEAR, -2, GETUTCDATE())

UNION ALL

SELECT
    'Potential Duplicates (>10MB)',
    SUM(cnt),
    SUM(waste)
FROM (
    SELECT COUNT(*) AS cnt, (COUNT(*) - 1) * f.FileSize / 1073741824.0 AS waste
    FROM FileSizes.dbo.FileEntry f
    WHERE f.BatchId IN (${batchid:singlequote})
      AND f.IsDirectory = 0
      AND f.FileSize >= 10485760
    GROUP BY f.FileName, f.FileSize
    HAVING COUNT(*) > 1
) d

UNION ALL

SELECT
    'Temp/Cache Files',
    COUNT(*),
    SUM(f.FileSize) / 1073741824.0
FROM FileSizes.dbo.FileEntry f
WHERE f.BatchId IN (${batchid:singlequote})
  AND f.IsDirectory = 0
  AND (f.FullPath LIKE '%\Temp\%'
       OR f.FullPath LIKE '%\tmp\%'
       OR f.FullPath LIKE '%\Cache\%'
       OR f.FileName LIKE '%.tmp'
       OR f.FileName LIKE '*.log')
```

---

### 3. Improved Variable Selectors

#### 3.1 Server Selector (instead of raw BatchId)
Users likely think in terms of servers, not GUIDs.

```sql
-- Variable: ${server}
SELECT DISTINCT ServerName
FROM FileSizes.dbo.ScanBatch
ORDER BY ServerName

-- Variable: ${batchid} (dependent on ${server})
SELECT BatchId,
       CONCAT(CONVERT(VARCHAR, CollectedAtUtc, 120), ' (', ToolName, ')') AS __text
FROM FileSizes.dbo.ScanBatch
WHERE ServerName = '${server}'
ORDER BY CollectedAtUtc DESC
```

#### 3.2 Volume Selector
For panels that drill into specific volumes.

```sql
-- Variable: ${volume}
SELECT DISTINCT v.VolumeName
FROM FileSizes.dbo.ScanVolume v
WHERE v.BatchId IN (${batchid:singlequote})
ORDER BY v.VolumeName
```

#### 3.3 Configurable Thresholds
Add variables for stale file age and minimum size:
- `${stale_years}` — default 2
- `${min_size_mb}` — default 100
- `${dup_min_size_mb}` — default 10

---

### 4. Dashboard Organization

#### Option A: Single Dashboard with Rows
Organize into collapsible rows:
1. **Overview** — Stats, gauges, volume summary
2. **Space Analysis** — Top folders, extensions, size distribution
3. **Cleanup Candidates** — Stale files, duplicates, temp files
4. **Largest Files** — Top 50 table
5. **Trends** — Growth over time (if historical data exists)

#### Option B: Multiple Dashboards
- **Executive Summary** — High-level stats and gauges only
- **Detailed Analysis** — Full tables and breakdowns
- **Cleanup Report** — Actionable items for business owners
- **Trend Analysis** — Historical comparison (separate to avoid query load)

---

## Database Schema Enhancements

### Additional Indexes for Dashboard Performance

```sql
-- Speed up extension grouping queries
CREATE NONCLUSTERED INDEX IX_FileEntry_Extension
ON dbo.FileEntry (BatchId, IsDirectory)
INCLUDE (FileName, FileSize)
WHERE IsDirectory = 0
WITH (DATA_COMPRESSION = PAGE);

-- Speed up stale file queries
CREATE NONCLUSTERED INDEX IX_FileEntry_StaleFiles
ON dbo.FileEntry (BatchId, ModifiedTime, FileSize)
WHERE IsDirectory = 0 AND FileSize >= 104857600
WITH (DATA_COMPRESSION = PAGE);

-- Speed up folder breakdown (first path component)
-- Note: Computed column approach may be better for large tables
```

### Pre-Aggregated Summary Table
For very large datasets, consider a nightly job that pre-computes:

```sql
CREATE TABLE dbo.BatchSummary (
    BatchId UNIQUEIDENTIFIER PRIMARY KEY,
    TotalUsedBytes BIGINT,
    TotalFreeBytes BIGINT,
    TotalFiles BIGINT,
    TotalDirectories BIGINT,
    StaleFilesCount BIGINT,       -- >2 years, >100MB
    StaleFilesBytes BIGINT,
    DuplicateCandidatesCount BIGINT,
    DuplicateCandidatesWastedBytes BIGINT,
    TempCacheFilesCount BIGINT,
    TempCacheFilesBytes BIGINT,
    ComputedAtUtc DATETIME2(0)
);
```

This would make the KPI stat panels instant instead of scanning 46M+ rows.

---

## Decisions

| Question | Decision | Impact |
|----------|----------|--------|
| Historical Data Retention | Keep all scans; report on newest by default | Batch selector defaults to most recent; no auto-purge |
| Multi-Server View | Single-server focused | No server comparison panels; simpler variable structure |
| Alerting | None required | No alert rules or thresholds to configure |
| User Audience | Both IT ops and business owners | Use collapsible rows: overview for business, detail for IT |
| Folder Drill-Down | Yes — clicking folder shows contents | Requires `${folder}` variable + data links |
| Extension Drill-Down | Yes — clicking extension shows files | Requires `${extension}` variable + data links |
| Pre-Aggregation | Approved | BatchSummary table already created; KPI panels use it |

---

## Implementation Plan

Based on the decisions above, here's the prioritized implementation approach:

### Phase 1: Variables & Data Links (enables drill-down)

**New Variables:**
```sql
-- ${batchid} - default to newest batch
SELECT TOP 1 BatchId
FROM dbo.ScanBatch
ORDER BY CollectedAtUtc DESC

-- ${volume} - for volume-specific panels
SELECT DISTINCT VolumeName AS __value, VolumeName AS __text
FROM dbo.ScanVolume
WHERE BatchId = '${batchid}'
ORDER BY VolumeName

-- ${folder} - for folder drill-down (hidden, set via data link)
-- Type: Text box, default: empty

-- ${extension} - for extension drill-down (hidden, set via data link)
-- Type: Text box, default: empty
```

**Data Link Configuration:**
- Top Folders panel: Link on TopFolder column → sets `${folder}` variable
- File Type Distribution panel: Link on Extension column → sets `${extension}` variable

### Phase 2: KPI Overview Row (for business owners)

Replace Batch Info table with stat panels using BatchSummary:

| Panel | Query | Visualization |
|-------|-------|---------------|
| Total Storage | `SELECT (TotalUsedBytes + TotalFreeBytes) / 1099511627776.0 FROM BatchSummary WHERE BatchId = '${batchid}'` | Stat (TB) |
| Used Space | `SELECT TotalUsedBytes / 1099511627776.0 ...` | Stat (TB) |
| Free Space | `SELECT TotalFreeBytes / 1099511627776.0 ...` | Gauge (%, thresholds) |
| Total Files | `SELECT TotalFiles ...` | Stat |
| Stale Data | `SELECT StaleFilesBytes / 1073741824.0 ...` | Stat (GB, red if high) |
| Duplicate Waste | `SELECT DuplicateCandidatesWastedBytes / 1073741824.0 ...` | Stat (GB) |
| Temp/Cache | `SELECT TempCacheFilesBytes / 1073741824.0 ...` | Stat (GB) |

### Phase 3: Drill-Down Panels

**Files in Folder (conditional panel):**
```sql
SELECT
    FullPath,
    FileName,
    FileSize / 1048576.0 AS SizeMB,
    ModifiedTime
FROM dbo.FileEntry
WHERE BatchId = '${batchid}'
  AND FullPath LIKE '${folder}%'
  AND IsDirectory = 0
ORDER BY FileSize DESC
```
- Only visible when `${folder}` is not empty
- Panel title: "Files in ${folder}"

**Files by Extension (conditional panel):**
```sql
SELECT
    FullPath,
    FileName,
    FileSize / 1048576.0 AS SizeMB,
    ModifiedTime
FROM dbo.FileEntry
WHERE BatchId = '${batchid}'
  AND UPPER(RIGHT(FileName, LEN('${extension}'))) = UPPER('${extension}')
  AND IsDirectory = 0
ORDER BY FileSize DESC
```
- Only visible when `${extension}` is not empty
- Panel title: "Files with .${extension} extension"

### Phase 4: Dashboard Layout (collapsible rows)

```
Row 1: Overview (open by default)
├── [Stat] Total Storage    [Stat] Used    [Gauge] Free %
├── [Stat] Total Files      [Stat] Stale   [Stat] Duplicates   [Stat] Temp
└── [Table] Volume Summary

Row 2: Space Analysis (collapsed)
├── [Bar] Top 20 Folders by Size
├── [Pie] Space by Extension (top 10)
└── [Bar] File Age Distribution

Row 3: Cleanup Candidates (collapsed)
├── [Table] Stale Files (>100MB, >2 years)
├── [Table] Duplicate Candidates
└── [Table] Temp/Cache Files

Row 4: Largest Files (collapsed)
└── [Table] Top 50 Largest Files

Row 5: Drill-Down Results (collapsed, auto-opens when variable set)
├── [Table] Files in Folder (if ${folder} set)
└── [Table] Files by Extension (if ${extension} set)
```

### Phase 5: Additional Indexes

For drill-down performance, add:
```sql
-- Speed up folder prefix queries
CREATE NONCLUSTERED INDEX IX_FileEntry_Path
ON dbo.FileEntry (BatchId, FullPath)
WHERE IsDirectory = 0
WITH (DATA_COMPRESSION = PAGE);
```

---

## Assumptions

1. **Single Batch Focus** — Dashboard is designed to analyze one scan batch at a time (though multi-select exists, queries may not handle it well for all panels)

2. **Space Reclamation Goal** — Primary use case is identifying data to delete/archive, not just capacity planning

3. **File-Level Detail Needed** — Users need to see actual file paths, not just summaries

4. **MSSQL Backend** — Queries use T-SQL syntax; no cross-database portability needed

5. **Grafana 11+** — Uses current panel types (stat, gauge, table, pie chart); older versions may differ

6. **Reasonable Refresh** — Dashboard is not real-time; queries can take several seconds on large datasets
