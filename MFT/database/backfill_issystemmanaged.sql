-- ============================================================================
-- Backfill: Classify IsSystemManaged directories and recompute summaries
-- ============================================================================
--
-- Marks existing directories as system-managed based on known Windows OS
-- folder patterns, fixes IsTempCache misclassification, and recomputes
-- all batch summaries.
--
-- Prerequisites:
--   1. Run migrate_add_issystemmanaged.sql first
--
-- Safe to run multiple times (idempotent).
--
-- System-managed folder patterns:
--   - $Recycle.Bin, RECYCLER, RECYCLED  (Recycle Bin variants)
--   - System Volume Information          (VSS/restore points)
--   - $WINDOWS.~BT, $WINDOWS.~WS       (Windows upgrade)
--   - $WinREAgent, $SysReset            (Recovery/Reset)
--   - $GetCurrent                       (Windows update downloads)
--   - Recovery (depth=1 only)           (WinRE partition files)
--
-- ============================================================================

USE [FileSizes];
GO

SET NOCOUNT ON;
PRINT '============================================================';
PRINT 'Backfill: IsSystemManaged classification';
PRINT '============================================================';
PRINT '';

-- ============================================================================
-- Step 1: Batch-update IsSystemManaged flag on stats.Directory
-- ============================================================================

PRINT 'Step 1: Marking system-managed directories...';

DECLARE @BatchSize INT = 100000;
DECLARE @RowsUpdated INT = 1;
DECLARE @TotalUpdated BIGINT = 0;

WHILE @RowsUpdated > 0
BEGIN
    UPDATE TOP (@BatchSize) stats.Directory
    SET IsSystemManaged = 1
    WHERE IsSystemManaged = 0
      AND (
          -- Recycle Bin (all naming conventions)
          FullPath LIKE N'%\$Recycle.Bin%'
          OR FullPath LIKE N'%\RECYCLER%'
          OR FullPath LIKE N'%\RECYCLED%'
          -- System Volume Information (protected, VSS snapshots)
          OR FullPath LIKE N'%\System Volume Information%'
          -- Windows upgrade temp files
          OR FullPath LIKE N'%\$WINDOWS.~BT%'
          OR FullPath LIKE N'%\$WINDOWS.~WS%'
          -- Recovery/Reset agents
          OR FullPath LIKE N'%\$WinREAgent%'
          OR FullPath LIKE N'%\$SysReset%'
          -- Windows update downloads
          OR FullPath LIKE N'%\$GetCurrent%'
          -- Recovery folder (only top-level to avoid false positives)
          OR (DirectoryName = N'Recovery' AND Depth = 1)
      );

    SET @RowsUpdated = @@ROWCOUNT;
    SET @TotalUpdated += @RowsUpdated;

    IF @RowsUpdated > 0
    BEGIN
        PRINT '  Updated ' + FORMAT(@TotalUpdated, 'N0') + ' directories so far...';
        -- Small delay to avoid blocking other operations
        WAITFOR DELAY '00:00:00.100';
    END
END

PRINT 'Step 1 complete: ' + FORMAT(@TotalUpdated, 'N0') + ' directories marked as system-managed.';
PRINT '';

-- ============================================================================
-- Step 2: Fix IsTempCache for system-managed directories
-- ============================================================================
-- $Recycle.Bin and System Volume Information were previously classified as
-- IsTempCache. Correct them to only be IsSystemManaged.

PRINT 'Step 2: Fixing IsTempCache on system-managed directories...';

DECLARE @FixedCount INT;

UPDATE stats.Directory
SET IsTempCache = 0
WHERE IsTempCache = 1
  AND IsSystemManaged = 1;

SET @FixedCount = @@ROWCOUNT;

PRINT 'Step 2 complete: ' + FORMAT(@FixedCount, 'N0') + ' directories reclassified (IsTempCache -> IsSystemManaged).';
PRINT '';

-- ============================================================================
-- Step 3: Recompute all batch summaries
-- ============================================================================
-- The updated ComputeBatchSummary proc now includes SystemManaged aggregates
-- and the TempCache values need recalculating after the IsTempCache fix.

PRINT 'Step 3: Recomputing batch summaries...';
PRINT '';

DECLARE @BatchId UNIQUEIDENTIFIER;
DECLARE @ServerName NVARCHAR(256);
DECLARE @CollectedAtUtc DATETIME2(0);
DECLARE @BatchCount INT = 0;
DECLARE @TotalBatches INT;

SELECT @TotalBatches = COUNT(*) FROM stats.ScanBatch;

IF @TotalBatches = 0
BEGIN
    PRINT 'No batches found. Nothing to recompute.';
END
ELSE
BEGIN
    PRINT 'Recomputing summaries for ' + CAST(@TotalBatches AS NVARCHAR(10)) + ' batch(es)...';
    PRINT '';

    DECLARE batch_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT b.BatchId, b.ServerName, b.CollectedAtUtc
        FROM stats.ScanBatch b
        ORDER BY b.CollectedAtUtc;

    OPEN batch_cursor;
    FETCH NEXT FROM batch_cursor INTO @BatchId, @ServerName, @CollectedAtUtc;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @BatchCount = @BatchCount + 1;

        PRINT 'Processing batch ' + CAST(@BatchCount AS NVARCHAR(10)) + '/'
              + CAST(@TotalBatches AS NVARCHAR(10)) + ': '
              + @ServerName + ' (' + CONVERT(NVARCHAR(20), @CollectedAtUtc, 120) + ')';

        EXEC stats.ComputeBatchSummary @BatchId;

        FETCH NEXT FROM batch_cursor INTO @BatchId, @ServerName, @CollectedAtUtc;
    END

    CLOSE batch_cursor;
    DEALLOCATE batch_cursor;
END

-- ============================================================================
-- Summary
-- ============================================================================

PRINT '';
PRINT '============================================================';
PRINT 'BACKFILL COMPLETE';
PRINT '============================================================';
PRINT 'Directories marked system-managed: ' + FORMAT(@TotalUpdated, 'N0');
PRINT 'Directories reclassified (temp->system): ' + FORMAT(@FixedCount, 'N0');
PRINT 'Batch summaries recomputed: ' + CAST(@BatchCount AS NVARCHAR(10));
PRINT '';

-- Show verification results
PRINT 'Verification:';

-- Mutual exclusivity check
DECLARE @BothFlags INT;
SELECT @BothFlags = COUNT(*) FROM stats.Directory WHERE IsTempCache = 1 AND IsSystemManaged = 1;
PRINT '  Directories with BOTH flags (should be 0): ' + CAST(@BothFlags AS NVARCHAR(10));

-- Summary of system-managed data per batch
SELECT
    b.ServerName,
    b.CollectedAtUtc,
    s.TempCacheFilesCount   AS TempCacheFiles,
    s.TempCacheFilesBytes   / 1073741824.0 AS TempCacheGB,
    s.SystemManagedFilesCount AS SysManagedFiles,
    s.SystemManagedFilesBytes / 1073741824.0 AS SysManagedGB
FROM stats.BatchSummary s
JOIN stats.ScanBatch b ON b.BatchId = s.BatchId
ORDER BY b.CollectedAtUtc DESC;
GO
