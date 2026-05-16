USE [FileSizes]
GO
/****** Object:  StoredProcedure [dbo].[DeleteScanBatch]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


-- ============================================================================
-- Helper: Delete an entire scan batch (cascades to volumes and files)
-- ============================================================================

CREATE   PROCEDURE [dbo].[DeleteScanBatch]
    @BatchId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    -- CASCADE handles FileEntry and ScanVolume automatically
    DELETE FROM dbo.ScanBatch WHERE BatchId = @BatchId;

    PRINT 'Batch ' + CAST(@BatchId AS NVARCHAR(36)) + ' deleted.';
END;

GO
