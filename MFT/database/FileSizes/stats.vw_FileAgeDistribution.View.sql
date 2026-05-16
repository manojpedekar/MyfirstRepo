USE [FileSizes]
GO
/****** Object:  View [stats].[vw_FileAgeDistribution]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- vw_FileAgeDistribution: Files categorized by age (based on ModifiedTime)
-- ============================================================================

CREATE   VIEW [stats].[vw_FileAgeDistribution]
AS
SELECT
    f.BatchId,
    CASE
        WHEN f.ModifiedTime >= DATEADD(MONTH, -1, SYSUTCDATETIME()) THEN '< 1 month'
        WHEN f.ModifiedTime >= DATEADD(MONTH, -6, SYSUTCDATETIME()) THEN '1-6 months'
        WHEN f.ModifiedTime >= DATEADD(YEAR, -1, SYSUTCDATETIME()) THEN '6-12 months'
        WHEN f.ModifiedTime >= DATEADD(YEAR, -2, SYSUTCDATETIME()) THEN '1-2 years'
        WHEN f.ModifiedTime >= DATEADD(YEAR, -5, SYSUTCDATETIME()) THEN '2-5 years'
        ELSE '> 5 years'
    END AS AgeCategory,
    CASE
        WHEN f.ModifiedTime >= DATEADD(MONTH, -1, SYSUTCDATETIME()) THEN 1
        WHEN f.ModifiedTime >= DATEADD(MONTH, -6, SYSUTCDATETIME()) THEN 2
        WHEN f.ModifiedTime >= DATEADD(YEAR, -1, SYSUTCDATETIME()) THEN 3
        WHEN f.ModifiedTime >= DATEADD(YEAR, -2, SYSUTCDATETIME()) THEN 4
        WHEN f.ModifiedTime >= DATEADD(YEAR, -5, SYSUTCDATETIME()) THEN 5
        ELSE 6
    END AS SortOrder,
    COUNT(*) AS FileCount,
    SUM(f.FileSize) AS TotalBytes
FROM stats.FileEntry f
WHERE f.ModifiedTime IS NOT NULL
GROUP BY
    f.BatchId,
    CASE
        WHEN f.ModifiedTime >= DATEADD(MONTH, -1, SYSUTCDATETIME()) THEN '< 1 month'
        WHEN f.ModifiedTime >= DATEADD(MONTH, -6, SYSUTCDATETIME()) THEN '1-6 months'
        WHEN f.ModifiedTime >= DATEADD(YEAR, -1, SYSUTCDATETIME()) THEN '6-12 months'
        WHEN f.ModifiedTime >= DATEADD(YEAR, -2, SYSUTCDATETIME()) THEN '1-2 years'
        WHEN f.ModifiedTime >= DATEADD(YEAR, -5, SYSUTCDATETIME()) THEN '2-5 years'
        ELSE '> 5 years'
    END,
    CASE
        WHEN f.ModifiedTime >= DATEADD(MONTH, -1, SYSUTCDATETIME()) THEN 1
        WHEN f.ModifiedTime >= DATEADD(MONTH, -6, SYSUTCDATETIME()) THEN 2
        WHEN f.ModifiedTime >= DATEADD(YEAR, -1, SYSUTCDATETIME()) THEN 3
        WHEN f.ModifiedTime >= DATEADD(YEAR, -2, SYSUTCDATETIME()) THEN 4
        WHEN f.ModifiedTime >= DATEADD(YEAR, -5, SYSUTCDATETIME()) THEN 5
        ELSE 6
    END;

GO
