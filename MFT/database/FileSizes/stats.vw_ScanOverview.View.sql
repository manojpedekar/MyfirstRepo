USE [FileSizes]
GO
/****** Object:  View [stats].[vw_ScanOverview]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- vw_ScanOverview: Batch summary with computed totals
-- ============================================================================

CREATE   VIEW [stats].[vw_ScanOverview]
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
