USE [FileSizes]
GO
/****** Object:  StoredProcedure [stats].[ComputeBatchSummary]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- Helper: Compute batch summary after import
-- ============================================================================

CREATE   PROCEDURE [stats].[ComputeBatchSummary]
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
