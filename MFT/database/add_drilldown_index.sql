-- ============================================================================
-- Add Index for Folder Drill-Down Queries
-- ============================================================================
--
-- Supports the Grafana drill-down feature where clicking a folder shows
-- all files within that folder path. The LIKE 'folder%' pattern benefits
-- from a leading-edge index on FullPath.
--
-- Note: This index can be large for tables with millions of rows.
-- Page compression helps reduce storage.
--
-- ============================================================================

-- Check if index already exists
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_FileEntry_Path'
    AND object_id = OBJECT_ID('dbo.FileEntry')
)
BEGIN
    PRINT 'Creating IX_FileEntry_Path index...';

    CREATE NONCLUSTERED INDEX IX_FileEntry_Path
    ON dbo.FileEntry (BatchId, FullPath)
    INCLUDE (FileName, FileSize, ModifiedTime)
    WHERE IsDirectory = 0
    WITH (DATA_COMPRESSION = PAGE, ONLINE = ON);

    PRINT 'Index created successfully.';
END
ELSE
BEGIN
    PRINT 'IX_FileEntry_Path already exists.';
END
GO
