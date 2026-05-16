-- ============================================================================
-- Backfill BatchSummary for Existing Batches
-- ============================================================================
--
-- Populates dbo.BatchSummary with pre-aggregated metrics for all batches
-- that don't already have a summary row. Safe to run multiple times.
--
-- Prerequisites:
--   1. Run migrate_add_istempcache.sql to add the IsTempCache column
--   2. Run backfill_istempcache.sql to populate the flag for existing data
--   3. Then run this script to compute batch summaries
--
-- For large datasets (46M+ rows), this may take several minutes per batch.
-- Progress is printed after each batch completes.
--
-- ============================================================================

SET NOCOUNT ON;

DECLARE @BatchId UNIQUEIDENTIFIER;
DECLARE @ServerName NVARCHAR(256);
DECLARE @CollectedAtUtc DATETIME2(0);
DECLARE @BatchCount INT = 0;
DECLARE @TotalBatches INT;

-- Count batches needing backfill
SELECT @TotalBatches = COUNT(*)
FROM dbo.ScanBatch b
WHERE NOT EXISTS (SELECT 1 FROM dbo.BatchSummary s WHERE s.BatchId = b.BatchId);

IF @TotalBatches = 0
BEGIN
    PRINT 'All batches already have summary records. Nothing to backfill.';
    RETURN;
END

PRINT 'Found ' + CAST(@TotalBatches AS NVARCHAR(10)) + ' batch(es) to backfill.';
PRINT '';

-- Cursor through batches that don't have a summary yet
DECLARE batch_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT b.BatchId, b.ServerName, b.CollectedAtUtc
    FROM dbo.ScanBatch b
    WHERE NOT EXISTS (SELECT 1 FROM dbo.BatchSummary s WHERE s.BatchId = b.BatchId)
    ORDER BY b.CollectedAtUtc;

OPEN batch_cursor;
FETCH NEXT FROM batch_cursor INTO @BatchId, @ServerName, @CollectedAtUtc;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @BatchCount = @BatchCount + 1;

    PRINT 'Processing batch ' + CAST(@BatchCount AS NVARCHAR(10)) + '/'
          + CAST(@TotalBatches AS NVARCHAR(10)) + ': '
          + @ServerName + ' (' + CONVERT(NVARCHAR(20), @CollectedAtUtc, 120) + ')';

    -- Insert summary for this batch
    INSERT INTO dbo.BatchSummary (
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
        ComputedAtUtc
    )
    SELECT
        @BatchId,
        -- Total used/free from ScanVolume
        (SELECT SUM(TotalSizeBytes - FreeSizeBytes) FROM dbo.ScanVolume WHERE BatchId = @BatchId),
        (SELECT SUM(FreeSizeBytes) FROM dbo.ScanVolume WHERE BatchId = @BatchId),
        -- Total files/directories from ScanVolume
        (SELECT SUM(FileCount) FROM dbo.ScanVolume WHERE BatchId = @BatchId),
        (SELECT SUM(DirectoryCount) FROM dbo.ScanVolume WHERE BatchId = @BatchId),
        -- Stale files: >2 years old, >100MB
        (SELECT COUNT(*)
         FROM dbo.FileEntry
         WHERE BatchId = @BatchId
           AND IsDirectory = 0
           AND FileSize >= 104857600
           AND ModifiedTime < DATEADD(YEAR, -2, SYSUTCDATETIME())),
        (SELECT ISNULL(SUM(FileSize), 0)
         FROM dbo.FileEntry
         WHERE BatchId = @BatchId
           AND IsDirectory = 0
           AND FileSize >= 104857600
           AND ModifiedTime < DATEADD(YEAR, -2, SYSUTCDATETIME())),
        -- Duplicate candidates: same name+size, >10MB
        (SELECT ISNULL(SUM(cnt), 0)
         FROM (
             SELECT COUNT(*) AS cnt
             FROM dbo.FileEntry
             WHERE BatchId = @BatchId
               AND IsDirectory = 0
               AND FileSize >= 10485760
             GROUP BY FileName, FileSize
             HAVING COUNT(*) > 1
         ) d),
        (SELECT ISNULL(SUM(wasted), 0)
         FROM (
             SELECT (COUNT(*) - 1) * FileSize AS wasted
             FROM dbo.FileEntry
             WHERE BatchId = @BatchId
               AND IsDirectory = 0
               AND FileSize >= 10485760
             GROUP BY FileName, FileSize
             HAVING COUNT(*) > 1
         ) d),
        -- Temp/cache files (uses pre-computed IsTempCache flag)
        (SELECT COUNT(*)
         FROM dbo.FileEntry
         WHERE BatchId = @BatchId
           AND IsDirectory = 0
           AND IsTempCache = 1),
        (SELECT ISNULL(SUM(FileSize), 0)
         FROM dbo.FileEntry
         WHERE BatchId = @BatchId
           AND IsDirectory = 0
           AND IsTempCache = 1),
        SYSUTCDATETIME();

    PRINT '  -> Summary computed.';

    FETCH NEXT FROM batch_cursor INTO @BatchId, @ServerName, @CollectedAtUtc;
END

CLOSE batch_cursor;
DEALLOCATE batch_cursor;

PRINT '';
PRINT '============================================================';
PRINT 'BACKFILL COMPLETE';
PRINT '============================================================';
PRINT 'Processed ' + CAST(@BatchCount AS NVARCHAR(10)) + ' batch(es).';

-- Show summary of what was computed
SELECT
    b.ServerName,
    b.CollectedAtUtc,
    s.TotalUsedBytes / 1099511627776.0 AS UsedTB,
    s.TotalFreeBytes / 1099511627776.0 AS FreeTB,
    s.TotalFiles,
    s.TotalDirectories,
    s.StaleFilesCount,
    s.StaleFilesBytes / 1073741824.0 AS StaleGB,
    s.DuplicateCandidatesCount AS DupCount,
    s.DuplicateCandidatesWastedBytes / 1073741824.0 AS DupWastedGB,
    s.TempCacheFilesCount AS TempCount,
    s.TempCacheFilesBytes / 1073741824.0 AS TempGB
FROM dbo.BatchSummary s
JOIN dbo.ScanBatch b ON b.BatchId = s.BatchId
ORDER BY b.CollectedAtUtc DESC;
GO
