USE [FileSizes]
GO
/****** Object:  View [stats].[vw_ExtensionStats]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- vw_ExtensionStats: Pre-aggregated extension statistics per batch
-- ============================================================================

CREATE   VIEW [stats].[vw_ExtensionStats]
AS
SELECT
    f.BatchId,
    ISNULL(f.Extension, '(no ext)') AS Extension,
    COUNT(*) AS FileCount,
    SUM(f.FileSize) AS TotalBytes,
    AVG(f.FileSize) AS AvgBytes,
    MAX(f.FileSize) AS MaxBytes
FROM stats.FileEntry f
WHERE f.FileSize IS NOT NULL
GROUP BY f.BatchId, f.Extension;

GO
