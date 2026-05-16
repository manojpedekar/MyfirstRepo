-- ============================================================================
-- Recalculate Import Statistics for Existing Uploads
-- ============================================================================
-- This script recalculates per-inventory record counts for all existing
-- uploads in the ImportStatistics table. It replaces the evenly-divided
-- counts with actual per-inventory counts from the fssimport tables.
--
-- Run this ONCE after deploying the per-inventory counting feature to fix
-- historical data.
-- ============================================================================

SET NOCOUNT ON;

BEGIN TRANSACTION;

BEGIN TRY
    PRINT 'Starting recalculation of ImportStatistics...';
    PRINT '';

    -- Create a temp table to hold the recalculated statistics
    CREATE TABLE #RecalculatedStats (
        UploadId UNIQUEIDENTIFIER NOT NULL,
        InventoryId UNIQUEIDENTIFIER NOT NULL,
        TableName NVARCHAR(128) NOT NULL,
        RecordsImported BIGINT NOT NULL,
        PRIMARY KEY (UploadId, InventoryId, TableName)
    );

    -- Get distinct uploads that have ImportStatistics
    DECLARE @UploadCount INT;
    SELECT @UploadCount = COUNT(DISTINCT UploadId) FROM [app].[ImportStatistics];
    PRINT 'Found ' + CAST(@UploadCount AS NVARCHAR(20)) + ' uploads with statistics to recalculate.';
    PRINT '';

    -- ========================================================================
    -- Count records per InventoryID for each table
    -- ========================================================================

    PRINT 'Counting records in fssimport.SIDs...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'SIDs', COUNT(*)
    FROM [fssimport].[SIDs] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT 'Counting records in fssimport.CollectionInfo...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'CollectionInfo', COUNT(*)
    FROM [fssimport].[CollectionInfo] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT 'Counting records in fssimport.Disks...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'Disks', COUNT(*)
    FROM [fssimport].[Disks] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT 'Counting records in fssimport.Volumes...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'Volumes', COUNT(*)
    FROM [fssimport].[Volumes] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT 'Counting records in fssimport.VolumeMounts...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'VolumeMounts', COUNT(*)
    FROM [fssimport].[VolumeMounts] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT 'Counting records in fssimport.VolumeExtents...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'VolumeExtents', COUNT(*)
    FROM [fssimport].[VolumeExtents] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT 'Counting records in fssimport.Partitions...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'Partitions', COUNT(*)
    FROM [fssimport].[Partitions] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT 'Counting records in fssimport.Folders...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'Folders', COUNT(*)
    FROM [fssimport].[Folders] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT 'Counting records in fssimport.ACL...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'ACL', COUNT(*)
    FROM [fssimport].[ACL] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT 'Counting records in fssimport.ACE...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'ACE', COUNT(*)
    FROM [fssimport].[ACE] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT 'Counting records in fssimport.SMBShares...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'SMBShares', COUNT(*)
    FROM [fssimport].[SMBShares] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT 'Counting records in fssimport.SMBShareAccess...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'SMBShareAccess', COUNT(*)
    FROM [fssimport].[SMBShareAccess] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT 'Counting records in fssimport.EventLog...';
    INSERT INTO #RecalculatedStats (UploadId, InventoryId, TableName, RecordsImported)
    SELECT s.UploadId, t.InventoryID, 'EventLog', COUNT(*)
    FROM [fssimport].[EventLog] t
    INNER JOIN (SELECT DISTINCT UploadId, InventoryId FROM [app].[ImportStatistics]) s
        ON t.InventoryID = s.InventoryId
    GROUP BY s.UploadId, t.InventoryID;

    PRINT '';
    PRINT 'Record counting complete.';

    -- ========================================================================
    -- Show before/after comparison for verification
    -- ========================================================================

    PRINT '';
    PRINT 'Comparison of old vs new values (showing records that will change):';
    PRINT '';

    SELECT
        existing.UploadId,
        existing.InventoryId,
        existing.TableName,
        existing.RecordsImported AS OldCount,
        recalc.RecordsImported AS NewCount,
        recalc.RecordsImported - existing.RecordsImported AS Difference
    FROM [app].[ImportStatistics] existing
    INNER JOIN #RecalculatedStats recalc
        ON existing.UploadId = recalc.UploadId
        AND existing.InventoryId = recalc.InventoryId
        AND existing.TableName = recalc.TableName
    WHERE existing.RecordsImported <> recalc.RecordsImported
    ORDER BY existing.UploadId, existing.InventoryId, existing.TableName;

    -- ========================================================================
    -- Update the ImportStatistics table
    -- ========================================================================

    DECLARE @UpdatedRows INT;

    UPDATE existing
    SET RecordsImported = recalc.RecordsImported
    FROM [app].[ImportStatistics] existing
    INNER JOIN #RecalculatedStats recalc
        ON existing.UploadId = recalc.UploadId
        AND existing.InventoryId = recalc.InventoryId
        AND existing.TableName = recalc.TableName
    WHERE existing.RecordsImported <> recalc.RecordsImported;

    SET @UpdatedRows = @@ROWCOUNT;

    PRINT '';
    PRINT 'Updated ' + CAST(@UpdatedRows AS NVARCHAR(20)) + ' records in ImportStatistics.';

    -- ========================================================================
    -- Summary by upload
    -- ========================================================================

    PRINT '';
    PRINT 'Summary by Upload:';

    SELECT
        u.UploadId,
        u.OriginalFileName,
        COUNT(DISTINCT s.InventoryId) AS InventoryCount,
        SUM(s.RecordsImported) AS TotalRecords
    FROM [app].[Uploads] u
    INNER JOIN [app].[ImportStatistics] s ON u.UploadId = s.UploadId
    GROUP BY u.UploadId, u.OriginalFileName
    ORDER BY u.UploadId;

    -- Cleanup
    DROP TABLE #RecalculatedStats;

    COMMIT TRANSACTION;

    PRINT '';
    PRINT 'Recalculation completed successfully.';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT 'ERROR: ' + ERROR_MESSAGE();
    PRINT 'Transaction rolled back.';

    -- Cleanup on error
    IF OBJECT_ID('tempdb..#RecalculatedStats') IS NOT NULL
        DROP TABLE #RecalculatedStats;

    THROW;
END CATCH;
GO
