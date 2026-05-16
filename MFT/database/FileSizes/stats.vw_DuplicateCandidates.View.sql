USE [FileSizes]
GO
/****** Object:  View [stats].[vw_DuplicateCandidates]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- vw_DuplicateCandidates: Files with same name+size (potential duplicates)
-- ============================================================================

CREATE   VIEW [stats].[vw_DuplicateCandidates]
AS
SELECT
    f.BatchId,
    f.FileName,
    f.FileSize,
    COUNT(*) AS CopyCount,
    (COUNT(*) - 1) * f.FileSize AS WastedBytes
FROM stats.FileEntry f
WHERE f.FileSize >= 10485760  -- 10 MB minimum
GROUP BY f.BatchId, f.FileName, f.FileSize
HAVING COUNT(*) > 1;

GO
