-- Add progress tracking columns to app.Uploads table
-- Run this script against your SQL Server database

USE [fsapp]  -- Change to your database name if different
GO

-- Add RowsProcessed column
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('app.Uploads') AND name = 'RowsProcessed')
BEGIN
    ALTER TABLE [app].[Uploads] ADD [RowsProcessed] BIGINT NULL;
    PRINT 'Added column: RowsProcessed';
END
ELSE
BEGIN
    PRINT 'Column RowsProcessed already exists';
END
GO

-- Add TotalRows column
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('app.Uploads') AND name = 'TotalRows')
BEGIN
    ALTER TABLE [app].[Uploads] ADD [TotalRows] BIGINT NULL;
    PRINT 'Added column: TotalRows';
END
ELSE
BEGIN
    PRINT 'Column TotalRows already exists';
END
GO

-- Add PhaseStartedAt column
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('app.Uploads') AND name = 'PhaseStartedAt')
BEGIN
    ALTER TABLE [app].[Uploads] ADD [PhaseStartedAt] DATETIME2 NULL;
    PRINT 'Added column: PhaseStartedAt';
END
ELSE
BEGIN
    PRINT 'Column PhaseStartedAt already exists';
END
GO

PRINT 'Migration complete. All progress tracking columns have been added.';
GO
