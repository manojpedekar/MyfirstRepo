USE [FileSizes]
GO
/****** Object:  StoredProcedure [dbo].[PurgeOldScans]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


-- ============================================================================
-- Helper: Purge scans older than N days for a specific server
-- ============================================================================

CREATE   PROCEDURE [dbo].[PurgeOldScans]
    @ServerName NVARCHAR(256),
    @RetainDays INT = 90
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @cutoff DATETIME2(0) = DATEADD(DAY, -@RetainDays, SYSUTCDATETIME());

    DECLARE @count INT;
    SELECT @count = COUNT(*) FROM dbo.ScanBatch
    WHERE ServerName = @ServerName AND CollectedAtUtc < @cutoff;

    DELETE FROM dbo.ScanBatch
    WHERE ServerName = @ServerName AND CollectedAtUtc < @cutoff;

    PRINT CAST(@count AS NVARCHAR(10)) + ' batch(es) purged for ' + @ServerName
          + ' older than ' + CAST(@RetainDays AS NVARCHAR(10)) + ' days.';
END;

GO
