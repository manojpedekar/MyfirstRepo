-- ============================================================================
-- Import MFT Scan Data v2 (JSON Manifest + Normalized CSVs)
-- ============================================================================
--
-- Imports the v2 normalized format:
--   - JSON manifest with metadata and volume info
--   - _directories.csv with directory hierarchy
--   - _files.csv with file entries referencing directories by ID
--
-- Optimizations for fast import:
--   - TABLOCK hint for minimal logging (requires SIMPLE/BULK_LOGGED recovery)
--   - Staging tables to avoid index maintenance during load
--   - Batch inserts with optimal batch size
--   - Deferred index creation on staging tables
--
-- Prerequisites:
--   - Files must be accessible by SQL Server service account
--   - BULK ADMIN or sysadmin role required
--   - Database should use SIMPLE or BULK_LOGGED recovery model for best perf
--
-- Usage:
--   1. Update the 3 file paths below (search for "CHANGE THIS")
--   2. Run against the FileSizes database
--
-- ============================================================================

USE FileSizes;
GO

SET NOCOUNT ON;

-- ============================================================================
-- CHANGE THESE PATHS to match your actual files:
-- ============================================================================
-- All paths must be accessible by the SQL Server service account.
-- Use local paths or UNC shares (not mapped drives).
--
--   Path 1: JSON manifest file
--   Path 2: Directories CSV file
--   Path 3: Files CSV file
-- ============================================================================

-- ============================================================================
-- Step 1: Read and parse JSON manifest
-- ============================================================================

PRINT '============================================================';
PRINT 'IMPORT V2 - Starting...';
PRINT '============================================================';
PRINT '';

DECLARE @JsonText NVARCHAR(MAX);

SELECT @JsonText = CAST(BulkColumn AS NVARCHAR(MAX))
FROM OPENROWSET(BULK 'C:\temp\mftdirect_20260210_121127.json',    -- << CHANGE THIS (Path 1)
                SINGLE_CLOB) AS j;

IF @JsonText IS NULL
BEGIN
    RAISERROR('Error: Could not read JSON manifest file.', 16, 1);
    RETURN;
END

-- Parse top-level fields
DECLARE @SchemaVersion   INT            = JSON_VALUE(@JsonText, '$.schemaVersion');
DECLARE @ServerName      NVARCHAR(256)  = JSON_VALUE(@JsonText, '$.serverName');
DECLARE @ToolName        NVARCHAR(64)   = JSON_VALUE(@JsonText, '$.toolName');
DECLARE @ToolVersion     NVARCHAR(32)   = JSON_VALUE(@JsonText, '$.toolVersion');
DECLARE @CollectedAtUtc  NVARCHAR(32)   = JSON_VALUE(@JsonText, '$.collectedAtUtc');
DECLARE @CollectedBy     NVARCHAR(128)  = JSON_VALUE(@JsonText, '$.collectedBy');
DECLARE @DurationSec     DECIMAL(10,1)  = CAST(JSON_VALUE(@JsonText, '$.durationSec') AS DECIMAL(10,1));

-- Parse lastAccessTime section
DECLARE @LastAccessReg   BIGINT         = JSON_VALUE(@JsonText, '$.lastAccessTime.registryValue');
DECLARE @LastAccessStatus NVARCHAR(64)  = JSON_VALUE(@JsonText, '$.lastAccessTime.status');
DECLARE @LastAccessEnabled BIT          = CASE JSON_VALUE(@JsonText, '$.lastAccessTime.enabled')
                                               WHEN 'true' THEN 1 ELSE 0 END;
DECLARE @AccessTimeCollected BIT        = CASE JSON_VALUE(@JsonText, '$.lastAccessTime.collected')
                                               WHEN 'true' THEN 1 ELSE 0 END;

-- Parse totals
DECLARE @TotalEntries    BIGINT         = JSON_VALUE(@JsonText, '$.totals.entries');
DECLARE @TotalDirs       BIGINT         = JSON_VALUE(@JsonText, '$.totals.directories');
DECLARE @TotalFiles      BIGINT         = JSON_VALUE(@JsonText, '$.totals.files');

-- Validate schema version
IF @SchemaVersion <> 2
BEGIN
    RAISERROR('Error: Expected schemaVersion 2, got %d', 16, 1, @SchemaVersion);
    RETURN;
END

PRINT 'Manifest loaded:';
PRINT '  Server:       ' + @ServerName;
PRINT '  Tool:         ' + @ToolName + ' v' + ISNULL(@ToolVersion, '?');
PRINT '  Collected:    ' + @CollectedAtUtc;
PRINT '  By:           ' + ISNULL(@CollectedBy, '(unknown)');
PRINT '  Duration:     ' + CAST(@DurationSec AS NVARCHAR(20)) + ' sec';
PRINT '  Entries:      ' + FORMAT(@TotalEntries, 'N0');
PRINT '  Directories:  ' + FORMAT(@TotalDirs, 'N0');
PRINT '  Files:        ' + FORMAT(@TotalFiles, 'N0');
PRINT '  LastAccess:   ' + @LastAccessStatus;
PRINT '';

-- ============================================================================
-- Step 2: Create the batch record in stats.ScanBatch
-- ============================================================================

DECLARE @BatchId UNIQUEIDENTIFIER = NEWID();
DECLARE @StartTime DATETIME2 = SYSUTCDATETIME();

INSERT INTO stats.ScanBatch (
    BatchId, ServerName, CollectedAtUtc, CollectedBy,
    ToolName, ToolVersion, SchemaVersion, DurationSec,
    LastAccessEnabled, LastAccessRegistryValue, LastAccessStatus, AccessTimeCollected,
    TotalEntries, TotalDirectories, TotalFiles
)
VALUES (
    @BatchId,
    @ServerName,
    CAST(@CollectedAtUtc AS DATETIME2(0)),
    @CollectedBy,
    @ToolName,
    @ToolVersion,
    @SchemaVersion,
    @DurationSec,
    @LastAccessEnabled,
    @LastAccessReg,
    @LastAccessStatus,
    @AccessTimeCollected,
    @TotalEntries,
    @TotalDirs,
    @TotalFiles
);

PRINT 'Created batch: ' + CAST(@BatchId AS NVARCHAR(36));

-- ============================================================================
-- Step 3: Populate stats.ScanVolume from JSON manifest
-- ============================================================================

-- Use ROW_NUMBER to generate ScanVolumeId (1-based, matches EXE output order)
INSERT INTO stats.ScanVolume (
    ScanVolumeId, BatchId, VolumeName, VolumeLabel, FileSystemType,
    TotalSizeBytes, FreeSizeBytes,
    EntryCount, DirectoryCount, FileCount, ErrorCount, ScanDurationSec
)
SELECT
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),  -- Preserves JSON array order
    @BatchId,
    JSON_VALUE(v.[value], '$.name'),
    JSON_VALUE(v.[value], '$.label'),
    JSON_VALUE(v.[value], '$.fileSystem'),
    CAST(JSON_VALUE(v.[value], '$.totalSizeBytes')  AS BIGINT),
    CAST(JSON_VALUE(v.[value], '$.freeSizeBytes')   AS BIGINT),
    CAST(JSON_VALUE(v.[value], '$.entryCount')      AS BIGINT),
    CAST(JSON_VALUE(v.[value], '$.directoryCount')  AS BIGINT),
    CAST(JSON_VALUE(v.[value], '$.fileCount')       AS BIGINT),
    CAST(JSON_VALUE(v.[value], '$.errorCount')      AS BIGINT),
    CAST(JSON_VALUE(v.[value], '$.scanDurationSec') AS DECIMAL(10,1))
FROM OPENJSON(@JsonText, '$.volumes') v;

DECLARE @VolumeCount INT = @@ROWCOUNT;
PRINT 'Inserted ' + CAST(@VolumeCount AS NVARCHAR(10)) + ' volume(s) from manifest.';
PRINT '';

-- ============================================================================
-- Step 4: Bulk load directories CSV into staging table
-- ============================================================================

PRINT 'Loading directories CSV...';

DROP TABLE IF EXISTS #DirStaging;

CREATE TABLE #DirStaging (
    DirectoryId     INT             NOT NULL,
    ScanVolumeId    INT             NOT NULL,
    ParentId        INT             NOT NULL,
    Depth           TINYINT         NOT NULL,
    DirectoryName   NVARCHAR(256)   NOT NULL,
    FullPath        NVARCHAR(4000)  NOT NULL,
    IsTempCache     TINYINT         NOT NULL,
    IsSystemManaged TINYINT         NOT NULL,
    FileCount       INT             NULL,
    TotalFileSize   BIGINT          NULL
);

BULK INSERT #DirStaging
FROM 'C:\temp\mftdirect_20260210_121127_directories.csv'    -- << CHANGE THIS (Path 2)
WITH (
    FORMAT          = 'CSV',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\n',
    FIRSTROW        = 2,
    CODEPAGE        = '65001',
    TABLOCK,
    BATCHSIZE       = 100000
);

DECLARE @DirCount BIGINT = @@ROWCOUNT;
PRINT 'Staged ' + FORMAT(@DirCount, 'N0') + ' directories.';

-- ============================================================================
-- Step 5: Insert directories into stats.Directory
-- ============================================================================

PRINT 'Inserting directories...';

INSERT INTO stats.Directory WITH (TABLOCK) (
    DirectoryId, BatchId, ScanVolumeId, ParentId, Depth,
    DirectoryName, FullPath, IsTempCache, IsSystemManaged, FileCount, TotalFileSize
)
SELECT
    DirectoryId,
    @BatchId,
    ScanVolumeId,
    ParentId,
    Depth,
    DirectoryName,
    FullPath,
    CAST(IsTempCache AS BIT),
    CAST(IsSystemManaged AS BIT),
    FileCount,
    TotalFileSize
FROM #DirStaging;

PRINT 'Inserted ' + FORMAT(@@ROWCOUNT, 'N0') + ' directories into stats.Directory.';
PRINT '';

DROP TABLE #DirStaging;

-- ============================================================================
-- Step 6: Bulk load files CSV into staging table
-- ============================================================================
-- Note: The files CSV has either 7 or 8 columns depending on whether
-- AccessedTime was collected (check @AccessTimeCollected from manifest).
-- We create the staging table dynamically to match.
-- ============================================================================

PRINT 'Loading files CSV (this may take a while for large scans)...';

DROP TABLE IF EXISTS #FileStaging;
DROP TABLE IF EXISTS #FileStagingNoAccess;

IF @AccessTimeCollected = 1
BEGIN
    -- 8-column format: DirectoryId,FileName,Extension,FileSize,CreatedTime,ModifiedTime,AccessedTime,Attributes
    CREATE TABLE #FileStaging (
        DirectoryId     INT             NOT NULL,
        FileName        NVARCHAR(256)   NOT NULL,
        Extension       NVARCHAR(32)    NULL,
        FileSize        BIGINT          NULL,
        CreatedTime     NVARCHAR(32)    NULL,
        ModifiedTime    NVARCHAR(32)    NULL,
        AccessedTime    NVARCHAR(32)    NULL,
        Attributes      INT             NOT NULL
    );

    BULK INSERT #FileStaging
    FROM 'C:\temp\mftdirect_20260210_121127_files.csv'          -- << CHANGE THIS (Path 3)
    WITH (
        FORMAT          = 'CSV',
        FIELDTERMINATOR = ',',
        ROWTERMINATOR   = '\n',
        FIRSTROW        = 2,
        CODEPAGE        = '65001',
        TABLOCK,
        BATCHSIZE       = 500000
    );

    PRINT 'Staged ' + FORMAT(@@ROWCOUNT, 'N0') + ' files (with AccessedTime).';
END
ELSE
BEGIN
    -- 7-column format: DirectoryId,FileName,Extension,FileSize,CreatedTime,ModifiedTime,Attributes
    CREATE TABLE #FileStagingNoAccess (
        DirectoryId     INT             NOT NULL,
        FileName        NVARCHAR(256)   NOT NULL,
        Extension       NVARCHAR(32)    NULL,
        FileSize        BIGINT          NULL,
        CreatedTime     NVARCHAR(32)    NULL,
        ModifiedTime    NVARCHAR(32)    NULL,
        Attributes      INT             NOT NULL
    );

    BULK INSERT #FileStagingNoAccess
    FROM 'C:\temp\mftdirect_20260210_121127_files.csv'          -- << CHANGE THIS (Path 3 - same as above)
    WITH (
        FORMAT          = 'CSV',
        FIELDTERMINATOR = ',',
        ROWTERMINATOR   = '\n',
        FIRSTROW        = 2,
        CODEPAGE        = '65001',
        TABLOCK,
        BATCHSIZE       = 500000
    );

    PRINT 'Staged ' + FORMAT(@@ROWCOUNT, 'N0') + ' files (no AccessedTime).';
END

-- ============================================================================
-- Step 7: Insert files into stats.FileEntry
-- ============================================================================

PRINT 'Inserting files into stats.FileEntry...';

IF @AccessTimeCollected = 1
BEGIN
    INSERT INTO stats.FileEntry WITH (TABLOCK) (
        BatchId, DirectoryId, FileName, Extension, FileSize,
        CreatedTime, ModifiedTime, AccessedTime, Attributes
    )
    SELECT
        @BatchId,
        DirectoryId,
        FileName,
        NULLIF(Extension, ''),
        FileSize,
        CASE WHEN CreatedTime = '' OR CreatedTime IS NULL THEN NULL
             ELSE CAST(CreatedTime AS DATETIME2(0)) END,
        CASE WHEN ModifiedTime = '' OR ModifiedTime IS NULL THEN NULL
             ELSE CAST(ModifiedTime AS DATETIME2(0)) END,
        CASE WHEN AccessedTime = '' OR AccessedTime IS NULL THEN NULL
             ELSE CAST(AccessedTime AS DATETIME2(0)) END,
        Attributes
    FROM #FileStaging;

    DROP TABLE #FileStaging;
END
ELSE
BEGIN
    INSERT INTO stats.FileEntry WITH (TABLOCK) (
        BatchId, DirectoryId, FileName, Extension, FileSize,
        CreatedTime, ModifiedTime, AccessedTime, Attributes
    )
    SELECT
        @BatchId,
        DirectoryId,
        FileName,
        NULLIF(Extension, ''),
        FileSize,
        CASE WHEN CreatedTime = '' OR CreatedTime IS NULL THEN NULL
             ELSE CAST(CreatedTime AS DATETIME2(0)) END,
        CASE WHEN ModifiedTime = '' OR ModifiedTime IS NULL THEN NULL
             ELSE CAST(ModifiedTime AS DATETIME2(0)) END,
        NULL,  -- AccessedTime not collected
        Attributes
    FROM #FileStagingNoAccess;

    DROP TABLE #FileStagingNoAccess;
END

PRINT 'Inserted ' + FORMAT(@@ROWCOUNT, 'N0') + ' files into stats.FileEntry.';
PRINT '';

-- ============================================================================
-- Step 8: Compute batch summary
-- ============================================================================

PRINT 'Computing batch summary metrics...';

EXEC stats.ComputeBatchSummary @BatchId;

-- ============================================================================
-- Report results
-- ============================================================================

DECLARE @EndTime DATETIME2 = SYSUTCDATETIME();
DECLARE @ImportDuration DECIMAL(10,1) = DATEDIFF(SECOND, @StartTime, @EndTime);

PRINT '';
PRINT '============================================================';
PRINT 'IMPORT COMPLETE';
PRINT '============================================================';
PRINT 'BatchId:        ' + CAST(@BatchId AS NVARCHAR(36));
PRINT 'Import time:    ' + CAST(@ImportDuration AS NVARCHAR(20)) + ' seconds';
PRINT '';

-- Show batch summary
SELECT
    b.BatchId,
    b.ServerName,
    b.CollectedAtUtc,
    b.ToolName + ' v' + b.ToolVersion AS Tool,
    b.DurationSec AS ScanDurationSec,
    b.LastAccessStatus,
    FORMAT(b.TotalEntries, 'N0') AS TotalEntries,
    FORMAT(b.TotalDirectories, 'N0') AS TotalDirectories,
    FORMAT(b.TotalFiles, 'N0') AS TotalFiles
FROM stats.ScanBatch b
WHERE b.BatchId = @BatchId;

-- Show volumes
SELECT
    v.ScanVolumeId,
    v.VolumeName,
    v.VolumeLabel,
    v.FileSystemType,
    FORMAT(v.TotalSizeBytes / 1073741824.0, 'N1') AS TotalGB,
    FORMAT(v.FreeSizeBytes / 1073741824.0, 'N1') AS FreeGB,
    FORMAT(100.0 * (v.TotalSizeBytes - v.FreeSizeBytes) / v.TotalSizeBytes, 'N1') AS UsedPct,
    FORMAT(v.EntryCount, 'N0') AS Entries,
    FORMAT(v.FileCount, 'N0') AS Files,
    v.ScanDurationSec
FROM stats.ScanVolume v
WHERE v.BatchId = @BatchId
ORDER BY v.ScanVolumeId;

-- Show summary stats
SELECT
    FORMAT(s.TotalUsedBytes / 1099511627776.0, 'N2') AS TotalUsedTB,
    FORMAT(s.TotalFreeBytes / 1099511627776.0, 'N2') AS TotalFreeTB,
    FORMAT(s.TotalFiles, 'N0') AS TotalFiles,
    FORMAT(s.TotalDirectories, 'N0') AS TotalDirectories,
    FORMAT(s.StaleFilesCount, 'N0') AS StaleFiles,
    FORMAT(s.StaleFilesBytes / 1073741824.0, 'N1') AS StaleGB,
    FORMAT(s.DuplicateCandidatesCount, 'N0') AS DuplicateCandidates,
    FORMAT(s.DuplicateCandidatesWastedBytes / 1073741824.0, 'N1') AS DuplicateWastedGB,
    FORMAT(s.TempCacheFilesCount, 'N0') AS TempCacheFiles,
    FORMAT(s.TempCacheFilesBytes / 1073741824.0, 'N1') AS TempCacheGB,
    FORMAT(s.SystemManagedFilesCount, 'N0') AS SystemManagedFiles,
    FORMAT(s.SystemManagedFilesBytes / 1073741824.0, 'N1') AS SystemManagedGB
FROM stats.BatchSummary s
WHERE s.BatchId = @BatchId;

GO
