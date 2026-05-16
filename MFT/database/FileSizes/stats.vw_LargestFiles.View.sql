USE [FileSizes]
GO
/****** Object:  View [stats].[vw_LargestFiles]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- vw_LargestFiles: Top files by size with full path
-- ============================================================================

CREATE   VIEW [stats].[vw_LargestFiles]
AS
SELECT
    f.BatchId,
    d.ScanVolumeId,
    v.VolumeName,
    d.FullPath + N'\' + f.FileName AS FullPath,
    f.FileName,
    f.Extension,
    f.FileSize,
    f.ModifiedTime,
    f.AccessedTime
FROM stats.FileEntry f
JOIN stats.Directory d ON d.BatchId = f.BatchId AND d.DirectoryId = f.DirectoryId
JOIN stats.ScanVolume v ON v.BatchId = f.BatchId AND v.ScanVolumeId = d.ScanVolumeId
WHERE f.FileSize IS NOT NULL;

GO
