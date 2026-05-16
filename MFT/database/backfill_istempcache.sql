-- ============================================================================
-- Backfill IsTempCache Flag for Existing Data
-- ============================================================================
--
-- Updates existing FileEntry rows to set the IsTempCache flag based on
-- path and filename patterns. Processes in batches to avoid transaction
-- log bloat and allow progress monitoring.
--
-- For 45M rows, expect this to run for 10-20 minutes depending on hardware.
--
-- Prerequisites:
--   - Run migrate_add_istempcache.sql first to add the column
--
-- ============================================================================

SET NOCOUNT ON;

DECLARE @BatchSize INT = 500000;
DECLARE @RowsUpdated INT = 1;
DECLARE @TotalUpdated BIGINT = 0;
DECLARE @StartTime DATETIME2 = SYSUTCDATETIME();

-- Count rows needing update (IsTempCache = 0 but matches pattern)
DECLARE @TotalToUpdate BIGINT;
SELECT @TotalToUpdate = COUNT(*)
FROM dbo.FileEntry
WHERE IsTempCache = 0
  AND IsDirectory = 0
  AND (FullPath LIKE '%\Temp\%'
       OR FullPath LIKE '%\tmp\%'
       OR FullPath LIKE '%\Cache\%'
       OR FullPath LIKE '%\.cache\%'
       OR FileName LIKE '%.tmp'
       OR FileName LIKE '%.temp'
       OR FileName LIKE '%.log');

IF @TotalToUpdate = 0
BEGIN
    PRINT 'No rows need updating. IsTempCache is already populated.';
    RETURN;
END

PRINT 'Found ' + FORMAT(@TotalToUpdate, 'N0') + ' rows to update.';
PRINT 'Processing in batches of ' + FORMAT(@BatchSize, 'N0') + '...';
PRINT '';

-- Process in batches
WHILE @RowsUpdated > 0
BEGIN
    UPDATE TOP (@BatchSize) dbo.FileEntry
    SET IsTempCache = 1
    WHERE IsTempCache = 0
      AND IsDirectory = 0
      AND (FullPath LIKE '%\Temp\%'
           OR FullPath LIKE '%\tmp\%'
           OR FullPath LIKE '%\Cache\%'
           OR FullPath LIKE '%\.cache\%'
           OR FileName LIKE '%.tmp'
           OR FileName LIKE '%.temp'
           OR FileName LIKE '%.log');

    SET @RowsUpdated = @@ROWCOUNT;
    SET @TotalUpdated = @TotalUpdated + @RowsUpdated;

    IF @RowsUpdated > 0
    BEGIN
        PRINT 'Updated ' + FORMAT(@TotalUpdated, 'N0') + ' / '
              + FORMAT(@TotalToUpdate, 'N0') + ' rows ('
              + CAST(CAST(100.0 * @TotalUpdated / @TotalToUpdate AS DECIMAL(5,1)) AS VARCHAR)
              + '%)';

        -- Brief pause to let other queries through
        WAITFOR DELAY '00:00:00.100';
    END
END

DECLARE @Duration INT = DATEDIFF(SECOND, @StartTime, SYSUTCDATETIME());

PRINT '';
PRINT '============================================================';
PRINT 'BACKFILL COMPLETE';
PRINT '============================================================';
PRINT 'Total rows updated: ' + FORMAT(@TotalUpdated, 'N0');
PRINT 'Duration: ' + CAST(@Duration AS VARCHAR) + ' seconds';

-- Verify the update
SELECT
    IsTempCache,
    COUNT(*) AS RowCount,
    SUM(FileSize) / 1073741824.0 AS TotalGB
FROM dbo.FileEntry
WHERE IsDirectory = 0
GROUP BY IsTempCache;
GO
