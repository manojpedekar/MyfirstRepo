USE [FileSizes]
GO
/****** Object:  View [stats].[vw_FileWithPath]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- vw_FileWithPath: Files with full path reconstructed
-- ============================================================================
-- Already exists in create_schema_v2.sql as stats.vw_FileWithPath
-- Reproduced here for reference

CREATE   VIEW [stats].[vw_FileWithPath]
AS
SELECT
    f.FileEntryId,
    f.BatchId,
    d.ScanVolumeId,
    d.FullPath + N'\' + f.FileName AS FullPath,
    f.FileName,
    f.Extension,
    f.FileSize,
    f.CreatedTime,
    f.ModifiedTime,
    f.AccessedTime,
    f.Attributes,
    d.IsTempCache,
    d.Depth,
    d.DirectoryId
FROM stats.FileEntry f
JOIN stats.Directory d ON d.BatchId = f.BatchId AND d.DirectoryId = f.DirectoryId;

GO
