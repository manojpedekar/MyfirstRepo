USE [FileSizes]
GO
/****** Object:  View [stats].[vw_StaleFiles]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- vw_StaleFiles: Large files not modified in 2+ years
-- ============================================================================

CREATE   VIEW [stats].[vw_StaleFiles]
AS
SELECT
    f.BatchId,
    d.ScanVolumeId,
    v.VolumeName,
    d.FullPath + N'\' + f.FileName AS FullPath,
    f.FileName,
    f.FileSize,
    f.ModifiedTime,
    DATEDIFF(DAY, f.ModifiedTime, SYSUTCDATETIME()) AS DaysSinceModified
FROM stats.FileEntry f
JOIN stats.Directory d ON d.BatchId = f.BatchId AND d.DirectoryId = f.DirectoryId
JOIN stats.ScanVolume v ON v.BatchId = f.BatchId AND v.ScanVolumeId = d.ScanVolumeId
WHERE f.FileSize >= 104857600  -- 100 MB
  AND f.ModifiedTime < DATEADD(YEAR, -2, SYSUTCDATETIME());

GO
