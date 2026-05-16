# Dashboard Panel Descriptions

This document contains proposed descriptions for each panel in the File Storage Analysis dashboard. These descriptions appear as tooltips when users hover over the info icon (i) next to panel titles.

Review and refine these descriptions, then they will be applied to the dashboard.

---

## Overview Row

### Total Storage
**Current:** "Total storage capacity across all volumes"

**Proposed:**
> Combined capacity of all scanned volumes. Calculated as the sum of each volume's total size reported by the operating system at scan time. This represents the raw storage capacity before any usage.

---

### Used Space
**Current:** "Used space across all volumes"

**Proposed:**
> Total storage currently in use across all scanned volumes. Calculated as total capacity minus free space for each volume, then summed. This includes all files, directories, and system-reserved space.

---

### Used %
**Current:** "Percentage of storage used"

**Proposed:**
> Overall storage utilization as a percentage. Calculated as (Used Space / Total Storage) × 100.
>
> **Thresholds:**
> - Green: Below 70% — Healthy capacity
> - Yellow: 70-80% — Monitor growth
> - Orange: 80-90% — Plan capacity expansion
> - Red: Above 90% — Critical, action required

---

### Files
**Current:** "Total number of files scanned"

**Proposed:**
> Count of all files discovered during the scan. Excludes directories. This count comes from the scan tool's enumeration of the file system and may differ slightly from Windows Explorer due to permission restrictions or system files.

---

### Stale Data
**Current:** "Files >100MB not modified in 2+ years"

**Proposed:**
> Total size of large files that haven't been modified recently. These are candidates for archival or deletion.
>
> **Criteria:**
> - File size ≥ 100 MB
> - Last modified date > 2 years ago
>
> **Thresholds:**
> - Green: Below 50 GB
> - Yellow: 50-100 GB
> - Red: Above 100 GB

---

### Dup Waste
**Current:** "Wasted space from potential duplicate files (same name+size, >10MB)"

**Proposed:**
> Estimated wasted space from potential duplicate files. Files are flagged as duplicates if they share the same filename AND exact file size. The "wasted" calculation assumes one copy is needed and all others are redundant.
>
> **Criteria:**
> - File size ≥ 10 MB
> - Multiple files with identical name and size
>
> **Calculation:** (Copy Count - 1) × File Size, summed for all duplicate groups
>
> **Note:** Same name and size doesn't guarantee identical content. Verify with checksums before deleting.
>
> **Thresholds:**
> - Green: Below 20 GB
> - Yellow: 20-50 GB
> - Red: Above 50 GB

---

### Temp/Cache
**Current:** "Temp, cache, and log files"

**Proposed:**
> Total size of temporary, cache, and log files that may be safe to clean up. These files are often recreated automatically and can accumulate over time.
>
> **Matched patterns:**
> - Paths containing: `\Temp\`, `\tmp\`, `\Cache\`, `\.cache\`
> - File extensions: `.tmp`, `.temp`, `.log`
>
> **Thresholds:**
> - Green: Below 10 GB
> - Yellow: 10-25 GB
> - Red: Above 25 GB
>
> **Caution:** Some log files may be needed for compliance or troubleshooting. Review before bulk deletion.

---

### Scan Info
**Current:** "Scan metadata"

**Proposed:**
> Metadata about the selected scan batch. Shows when and how the file system data was collected.
>
> **Fields:**
> - **Server:** The Windows server that was scanned
> - **Collected:** UTC timestamp when the scan completed
> - **Tool:** Scanner used (mftdirect or mftscan) and version
> - **Collected By:** Windows user account that ran the scan
> - **Duration:** Wall-clock time to complete the scan

---

### Volume Summary
**Current:** (none)

**Proposed:**
> Breakdown of storage by volume/drive. Each row represents one volume from the scanned server.
>
> **Columns:**
> - **VolumeName:** Drive letter or mount point path
> - **VolumeLabel:** Windows volume label (if set)
> - **TotalGB:** Total capacity in gigabytes
> - **FreeGB:** Available free space in gigabytes
> - **PctUsed:** Percentage of capacity in use (shown as inline gauge)
> - **FileCount:** Number of files on this volume
> - **DirectoryCount:** Number of directories on this volume

---

## Space Analysis Row

### Top 20 Folders by Size
**Current:** (none)

**Proposed:**
> The 20 largest top-level folders ranked by total file size. Helps identify which areas of the file system consume the most space.
>
> **Calculation:** For each file, extracts the first folder name after the volume root (e.g., "Users" from "C:\Users\john\file.txt"), then sums file sizes per folder.
>
> **Note:** "(root files)" represents files stored directly in the volume root, not in any folder.

---

### Space by Extension (Top 10)
**Current:** (none)

**Proposed:**
> Pie chart showing storage consumption by file type. The top 10 extensions by total size are displayed.
>
> **Calculation:** Extracts the file extension from each filename (text after the last dot), converts to uppercase, and sums file sizes per extension.
>
> **Note:** "(no ext)" represents files without an extension.

---

### File Age Distribution
**Current:** (none)

**Proposed:**
> Distribution of storage by file age, based on last modified date. Useful for understanding data freshness and identifying retention policy opportunities.
>
> **Age buckets:**
> - < 1 month — Recently active files
> - 1-6 months — Moderately recent
> - 6-12 months — Aging data
> - 1-2 years — Old data
> - 2-5 years — Very old data
> - \> 5 years — Legacy data, strong archival candidates

---

### File Type Distribution
**Current:** (none)

**Proposed:**
> Detailed table of storage usage by file extension. Click any extension to drill down and see individual files of that type.
>
> **Columns:**
> - **Extension:** File extension (lowercase)
> - **FileCount:** Number of files with this extension
> - **TotalGB:** Combined size of all files with this extension
> - **AvgSizeMB:** Average file size for this extension
> - **LargestGB:** Size of the largest single file with this extension

---

### Top Folders
**Current:** (none)

**Proposed:**
> Table listing the 50 largest top-level folders. Click any folder name to drill down and see files within that folder.
>
> **Columns:**
> - **TopFolder:** First-level folder name after the volume root
> - **FileCount:** Number of files in this folder tree
> - **TotalGB:** Combined size of all files in this folder tree

---

## Cleanup Candidates Row

### Stale Files
**Current:** (none)

**Proposed:**
> List of large files that haven't been modified in over 2 years. These are strong candidates for archival to cold storage or deletion.
>
> **Criteria:**
> - File size ≥ 100 MB
> - Last modified > 2 years ago
>
> **Columns:**
> - **Volume:** Drive letter or mount point
> - **FullPath:** Complete file path
> - **SizeMB:** File size in megabytes
> - **ModifiedTime:** Last modification timestamp
> - **DaysSinceModified:** Number of days since last modification
>
> **Sorted by:** File size (largest first)
>
> **Limit:** Top 100 files

---

### Duplicate Candidates
**Current:** (none)

**Proposed:**
> Files that may be duplicates based on matching filename and size. Review these for potential consolidation or cleanup.
>
> **Criteria:**
> - File size ≥ 10 MB
> - Two or more files share the same name AND exact size
>
> **Columns:**
> - **FileName:** The shared filename
> - **SizeMB:** File size in megabytes
> - **CopyCount:** Number of files with this name and size
> - **WastedGB:** Estimated wasted space = (CopyCount - 1) × Size
>
> **Sorted by:** Wasted space (highest first)
>
> **Important:** Same name and size is a heuristic, not proof of identical content. Use file hashes (MD5/SHA) to confirm before deleting.

---

### Temp/Cache Files (largest)
**Current:** (none)

**Proposed:**
> Largest temporary, cache, and log files found on the system. These files are often safe to delete but should be reviewed first.
>
> **Matched patterns:**
> - Paths containing: `\Temp\`, `\tmp\`, `\Cache\`, `\.cache\`
> - File extensions: `.tmp`, `.temp`, `.log`
>
> **Columns:**
> - **FullPath:** Complete file path
> - **FileName:** File name only
> - **SizeMB:** File size in megabytes
> - **ModifiedTime:** Last modification timestamp
>
> **Sorted by:** File size (largest first)
>
> **Limit:** Top 100 files
>
> **Caution:** Some temporary files may be in use. Application logs may be needed for troubleshooting. Review before bulk deletion.

---

## Largest Files Row

### Top 50 Largest Files
**Current:** (none)

**Proposed:**
> The 50 largest individual files on the server. Use this to identify space hogs and verify they are still needed.
>
> **Columns:**
> - **Volume:** Drive letter or mount point
> - **FullPath:** Complete file path
> - **SizeGB:** File size in gigabytes
> - **ModifiedTime:** Last modification timestamp
> - **AccessedTime:** Last access timestamp (may not be reliable if disabled)
>
> **Sorted by:** File size (largest first)
>
> **Tip:** Large files that haven't been modified recently may be candidates for archival.

---

## Drill-Down Results Row

### Files with .${extension} extension
**Current:** "Files with the selected extension. Clear the extension variable to hide this panel."

**Proposed:**
> Shows individual files matching the selected extension. This panel appears when you click an extension in the File Type Distribution table.
>
> **Columns:**
> - **FullPath:** Complete file path
> - **FileName:** File name only
> - **SizeMB:** File size in megabytes
> - **ModifiedTime:** Last modification timestamp
>
> **Sorted by:** File size (largest first)
>
> **Limit:** Top 200 files
>
> **To clear:** Delete the Extension variable value at the top of the dashboard.

---

### Files in ${folder}
**Current:** "Files within the selected folder. Clear the folder variable to hide this panel."

**Proposed:**
> Shows individual files within the selected folder tree. This panel appears when you click a folder name in the Top Folders table.
>
> **Columns:**
> - **FullPath:** Complete file path
> - **FileName:** File name only
> - **SizeMB:** File size in megabytes
> - **ModifiedTime:** Last modification timestamp
>
> **Sorted by:** File size (largest first)
>
> **Limit:** Top 200 files
>
> **To clear:** Delete the Folder variable value at the top of the dashboard.

---

## Variables

### Scan Batch
**Description:** "Select scan batch to analyze"

**Proposed:**
> Select which scan to analyze. The dropdown shows all available scans sorted by date (newest first). Each option displays the server name and collection timestamp.
>
> The dashboard defaults to the most recent scan.

---

### Extension
**Description:** "Filter by file extension (set via data link or manually)"

**Proposed:**
> Filter to show files with a specific extension. Usually set automatically when clicking an extension in the File Type Distribution table. You can also type an extension manually (without the dot).
>
> Clear this field to hide the extension drill-down panel.

---

### Folder
**Description:** "Filter by folder name (set via data link or manually)"

**Proposed:**
> Filter to show files within a specific top-level folder. Usually set automatically when clicking a folder in the Top Folders table. You can also type a folder name manually.
>
> Clear this field to hide the folder drill-down panel.

---

## Notes for Review

1. **Threshold values** — Are the current thresholds (50/100 GB for stale, 20/50 GB for duplicates, 10/25 GB for temp) appropriate for your environment?

2. **Stale file criteria** — Is 2 years and 100 MB the right threshold? Some environments may want 1 year or 500 MB.

3. **Duplicate detection** — Should we note that hash-based deduplication would be more accurate?

4. **Temp/cache patterns** — Are there additional patterns specific to your environment (e.g., application-specific temp folders)?

5. **Description length** — Some descriptions are detailed. Should we shorten them for cleaner tooltips?
