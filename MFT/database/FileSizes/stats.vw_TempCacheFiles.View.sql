USE [FileSizes]
GO
/****** Object:  View [stats].[vw_TempCacheFiles]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- vw_TempCacheFiles: Files in temp/cache directories
-- ============================================================================

CREATE   VIEW [stats].[vw_TempCacheFiles]
AS
SELECT
    f.BatchId,
    d.ScanVolumeId,
    d.FullPath + N'\' + f.FileName AS FullPath,
    f.FileName,
    f.Extension,
    f.FileSize,
    f.ModifiedTime
FROM stats.FileEntry f
JOIN stats.Directory d ON d.BatchId = f.BatchId AND d.DirectoryId = f.DirectoryId
WHERE d.IsTempCache = 1;

GO
