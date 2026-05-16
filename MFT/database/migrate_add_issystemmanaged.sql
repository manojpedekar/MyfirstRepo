-- ============================================================================
-- Migration: Add IsSystemManaged classification
-- ============================================================================
--
-- Adds the IsSystemManaged column and supporting objects to distinguish
-- OS-managed directories ($Recycle.Bin, System Volume Information, etc.)
-- from user-controllable temp/cache directories.
--
-- Safe to run multiple times (idempotent).
--
-- After running this script:
--   1. Run backfill_issystemmanaged.sql to populate existing data
--   2. Update import scripts for new CSV column
--   3. Deploy updated Grafana dashboard
--
-- ============================================================================

USE [FileSizes];
GO

SET NOCOUNT ON;
PRINT '============================================================';
PRINT 'Migration: Add IsSystemManaged classification';
PRINT '============================================================';
PRINT '';

-- ============================================================================
-- Step 1: Add IsSystemManaged column to stats.Directory
-- ============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('stats.Directory')
      AND name = 'IsSystemManaged'
)
BEGIN
    ALTER TABLE stats.Directory
        ADD IsSystemManaged BIT NOT NULL
        CONSTRAINT DF_stats_Directory_IsSystemManaged DEFAULT 0;
    PRINT 'Added IsSystemManaged column to stats.Directory';
END
ELSE
    PRINT 'IsSystemManaged column already exists on stats.Directory (skipped)';
GO

-- ============================================================================
-- Step 2: Create filtered index on IsSystemManaged
-- ============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('stats.Directory')
      AND name = 'IX_stats_Directory_SystemManaged'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_stats_Directory_SystemManaged
    ON stats.Directory (BatchId, IsSystemManaged)
    INCLUDE (FullPath, FileCount, TotalFileSize, Depth)
    WHERE IsSystemManaged = 1
    WITH (DATA_COMPRESSION = PAGE);
    PRINT 'Created IX_stats_Directory_SystemManaged index';
END
ELSE
    PRINT 'IX_stats_Directory_SystemManaged index already exists (skipped)';
GO

-- ============================================================================
-- Step 3: Add SystemManaged columns to stats.BatchSummary
-- ============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('stats.BatchSummary')
      AND name = 'SystemManagedFilesCount'
)
BEGIN
    ALTER TABLE stats.BatchSummary
        ADD SystemManagedFilesCount BIGINT NULL,
            SystemManagedFilesBytes  BIGINT NULL;
    PRINT 'Added SystemManaged columns to stats.BatchSummary';
END
ELSE
    PRINT 'SystemManaged columns already exist on stats.BatchSummary (skipped)';
GO

-- ============================================================================
-- Step 4: Create stats.vw_SystemManagedFiles view
-- ============================================================================

PRINT 'Creating/updating stats.vw_SystemManagedFiles...';
GO

CREATE OR ALTER VIEW stats.vw_SystemManagedFiles
AS
SELECT
    f.BatchId,
    d.ScanVolumeId,
    d.FullPath + N'\' + f.FileName AS FullPath,
    f.FileName,
    f.Extension,
    f.FileSize,
    f.ModifiedTime
FROM stats.FileEntry f
JOIN stats.Directory d ON d.BatchId = f.BatchId AND d.DirectoryId = f.DirectoryId
WHERE d.IsSystemManaged = 1;
GO

PRINT 'Done.';

-- ============================================================================
-- Step 5: Update stats.ComputeBatchSummary stored procedure
-- ============================================================================

PRINT 'Updating stats.ComputeBatchSummary...';
GO

CREATE OR ALTER PROCEDURE stats.ComputeBatchSummary
    @BatchId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    -- Delete existing summary if present
    DELETE FROM stats.BatchSummary WHERE BatchId = @BatchId;

    INSERT INTO stats.BatchSummary (
        BatchId,
        TotalUsedBytes,
        TotalFreeBytes,
        TotalFiles,
        TotalDirectories,
        StaleFilesCount,
        StaleFilesBytes,
        DuplicateCandidatesCount,
        DuplicateCandidatesWastedBytes,
        TempCacheFilesCount,
        TempCacheFilesBytes,
        SystemManagedFilesCount,
        SystemManagedFilesBytes,
        TopExtensionsJson,
        ComputedAtUtc
    )
    SELECT
        @BatchId,

        -- Total used/free from ScanVolume
        (SELECT SUM(TotalSizeBytes - FreeSizeBytes) FROM stats.ScanVolume WHERE BatchId = @BatchId),
        (SELECT SUM(FreeSizeBytes) FROM stats.ScanVolume WHERE BatchId = @BatchId),

        -- Totals from ScanVolume (faster than counting FileEntry)
        (SELECT SUM(FileCount) FROM stats.ScanVolume WHERE BatchId = @BatchId),
        (SELECT SUM(DirectoryCount) FROM stats.ScanVolume WHERE BatchId = @BatchId),

        -- Stale files: >2 years old, >100MB
        (SELECT COUNT(*)
         FROM stats.FileEntry
         WHERE BatchId = @BatchId
           AND FileSize >= 104857600
           AND ModifiedTime < DATEADD(YEAR, -2, SYSUTCDATETIME())),
        (SELECT ISNULL(SUM(FileSize), 0)
         FROM stats.FileEntry
         WHERE BatchId = @BatchId
           AND FileSize >= 104857600
           AND ModifiedTime < DATEADD(YEAR, -2, SYSUTCDATETIME())),

        -- Duplicates: same name+size, >10MB
        (SELECT ISNULL(SUM(cnt), 0)
         FROM (
             SELECT COUNT(*) AS cnt
             FROM stats.FileEntry
             WHERE BatchId = @BatchId
               AND FileSize >= 10485760
             GROUP BY FileName, FileSize
             HAVING COUNT(*) > 1
         ) d),
        (SELECT ISNULL(SUM(wasted), 0)
         FROM (
             SELECT (COUNT(*) - 1) * FileSize AS wasted
             FROM stats.FileEntry
             WHERE BatchId = @BatchId
               AND FileSize >= 10485760
             GROUP BY FileName, FileSize
             HAVING COUNT(*) > 1
         ) d),

        -- Temp/cache: Use pre-computed Directory.IsTempCache flag
        (SELECT ISNULL(SUM(d.FileCount), 0)
         FROM stats.Directory d
         WHERE d.BatchId = @BatchId
           AND d.IsTempCache = 1),
        (SELECT ISNULL(SUM(d.TotalFileSize), 0)
         FROM stats.Directory d
         WHERE d.BatchId = @BatchId
           AND d.IsTempCache = 1),

        -- System-managed: Use pre-computed Directory.IsSystemManaged flag
        (SELECT ISNULL(SUM(d.FileCount), 0)
         FROM stats.Directory d
         WHERE d.BatchId = @BatchId
           AND d.IsSystemManaged = 1),
        (SELECT ISNULL(SUM(d.TotalFileSize), 0)
         FROM stats.Directory d
         WHERE d.BatchId = @BatchId
           AND d.IsSystemManaged = 1),

        -- Top 10 extensions as JSON
        (SELECT TOP 10
             Extension AS ext,
             COUNT(*) AS cnt,
             SUM(FileSize) AS bytes
         FROM stats.FileEntry
         WHERE BatchId = @BatchId
           AND Extension IS NOT NULL
         GROUP BY Extension
         ORDER BY SUM(FileSize) DESC
         FOR JSON PATH),

        SYSUTCDATETIME();

    PRINT 'Batch summary computed for ' + CAST(@BatchId AS NVARCHAR(36));
END;
GO

PRINT 'Done.';

-- ============================================================================
-- Step 6: Update stats.vw_ScanOverview view
-- ============================================================================

PRINT 'Updating stats.vw_ScanOverview...';
GO

CREATE OR ALTER VIEW stats.vw_ScanOverview
AS
SELECT
    b.BatchId,
    b.ServerName,
    b.CollectedAtUtc,
    b.CollectedBy,
    b.ToolName,
    b.ToolVersion,
    b.SchemaVersion,
    b.DurationSec,
    b.LastAccessEnabled,
    b.LastAccessStatus,
    b.AccessTimeCollected,
    s.TotalUsedBytes,
    s.TotalFreeBytes,
    s.TotalUsedBytes + s.TotalFreeBytes AS TotalCapacityBytes,
    CASE WHEN s.TotalUsedBytes + s.TotalFreeBytes > 0
         THEN 100.0 * s.TotalUsedBytes / (s.TotalUsedBytes + s.TotalFreeBytes)
         ELSE NULL
    END AS UsedPercent,
    s.TotalFiles,
    s.TotalDirectories,
    s.StaleFilesCount,
    s.StaleFilesBytes,
    s.DuplicateCandidatesCount,
    s.DuplicateCandidatesWastedBytes,
    s.TempCacheFilesCount,
    s.TempCacheFilesBytes,
    s.SystemManagedFilesCount,
    s.SystemManagedFilesBytes,
    s.TopExtensionsJson
FROM stats.ScanBatch b
LEFT JOIN stats.BatchSummary s ON s.BatchId = b.BatchId;
GO

PRINT 'Done.';

-- ============================================================================
-- Step 7: Update stats.vw_DirectoryTree view
-- ============================================================================

PRINT 'Updating stats.vw_DirectoryTree...';
GO

CREATE OR ALTER VIEW stats.vw_DirectoryTree
AS
SELECT
    d.BatchId,
    d.DirectoryId,
    d.ScanVolumeId,
    d.ParentId,
    d.Depth,
    d.DirectoryName,
    d.FullPath,
    d.IsTempCache,
    d.IsSystemManaged,
    d.FileCount,
    d.TotalFileSize,
    d.RecursiveFileCount,
    d.RecursiveTotalSize,
    v.VolumeName
FROM stats.Directory d
JOIN stats.ScanVolume v ON v.BatchId = d.BatchId AND v.ScanVolumeId = d.ScanVolumeId;
GO

PRINT 'Done.';

-- ============================================================================
-- Summary
-- ============================================================================

PRINT '';
PRINT '============================================================';
PRINT 'MIGRATION COMPLETE';
PRINT '============================================================';
PRINT '';
PRINT 'Objects modified:';
PRINT '  - stats.Directory: added IsSystemManaged column + filtered index';
PRINT '  - stats.BatchSummary: added SystemManagedFilesCount, SystemManagedFilesBytes';
PRINT '  - stats.ComputeBatchSummary: updated to compute SystemManaged aggregates';
PRINT '  - stats.vw_SystemManagedFiles: created (new view)';
PRINT '  - stats.vw_ScanOverview: updated to expose SystemManaged columns';
PRINT '  - stats.vw_DirectoryTree: updated to expose IsSystemManaged';
PRINT '';
PRINT 'Next steps:';
PRINT '  1. Run backfill_issystemmanaged.sql to classify existing data';
PRINT '  2. Update import_v2.sql / Import-MftScanV2.ps1 for new CSV column';
PRINT '  3. Deploy updated Grafana dashboard';
GO
