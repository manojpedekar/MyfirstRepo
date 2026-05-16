USE [FileSizes]
GO
/****** Object:  StoredProcedure [stats].[DeleteScanBatch]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- Helper: Delete an entire scan batch
-- ============================================================================

CREATE   PROCEDURE [stats].[DeleteScanBatch]
    @BatchId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    -- CASCADE handles all child tables
    DELETE FROM stats.ScanBatch WHERE BatchId = @BatchId;

    PRINT 'Batch ' + CAST(@BatchId AS NVARCHAR(36)) + ' deleted from stats schema.';
END;

GO
