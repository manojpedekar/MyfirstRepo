USE [FileSizes]
GO
/****** Object:  View [stats].[vw_TopLevelFolders]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- vw_TopLevelFolders: Aggregated stats by top-level folder (depth=1)
-- ============================================================================

CREATE   VIEW [stats].[vw_TopLevelFolders]
AS
SELECT
    d.BatchId,
    d.ScanVolumeId,
    d.DirectoryId,
    d.DirectoryName AS TopFolder,
    d.FullPath,
    -- Direct stats from this folder
    d.FileCount AS DirectFileCount,
    d.TotalFileSize AS DirectFileSize,
    -- Recursive stats (if computed)
    d.RecursiveFileCount,
    d.RecursiveTotalSize
FROM stats.Directory d
WHERE d.Depth = 1;  -- First level below volume root

GO
