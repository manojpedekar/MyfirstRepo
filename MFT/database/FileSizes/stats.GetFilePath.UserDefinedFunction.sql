USE [FileSizes]
GO
/****** Object:  UserDefinedFunction [stats].[GetFilePath]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- Helper: Reconstruct full path for a file
-- ============================================================================

CREATE   FUNCTION [stats].[GetFilePath] (
    @BatchId UNIQUEIDENTIFIER,
    @DirectoryId INT,
    @FileName NVARCHAR(256)
)
RETURNS NVARCHAR(4000)
AS
BEGIN
    DECLARE @DirPath NVARCHAR(4000);

    SELECT @DirPath = FullPath
    FROM stats.Directory
    WHERE BatchId = @BatchId AND DirectoryId = @DirectoryId;

    RETURN @DirPath + N'\' + @FileName;
END;

GO
