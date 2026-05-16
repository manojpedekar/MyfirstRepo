USE [FileSizes]
GO
/****** Object:  View [stats].[vw_DirectoryTree]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- vw_DirectoryTree: Directory hierarchy with computed stats
-- ============================================================================

CREATE   VIEW [stats].[vw_DirectoryTree]
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
