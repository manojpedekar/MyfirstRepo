-- ============================================================================
-- Import MFT Scan Data (JSON Manifest + CSV)
-- ============================================================================
--
-- Reads the JSON manifest to populate ScanBatch and ScanVolume tables
-- (including volume capacity, labels, and scan stats), then BULK INSERTs
-- the CSV data file into FileEntry.
--
-- Prerequisites:
--   - Both the .json manifest and .csv data file must be on the SQL Server
--     machine (local path or UNC share accessible by the SQL Server service)
--   - OPENROWSET(BULK...) requires sysadmin role or ADMINISTER BULK OPERATIONS
--
-- Usage:
--   1. Update the 3 file paths below (search for "CHANGE THIS")
--   2. Run this script against the MftData database
--
-- ============================================================================

-- ============================================================================
-- CHANGE THESE 3 PATHS to match your actual files:
-- ============================================================================
--
--   Path 1 (line 36):  OPENROWSET  JSON path
--   Path 2 (line 108): BULK INSERT CSV path
--
-- All 3 must point to the same scan run. Example:
--   'C:\temp\mftdirect_20260205_141509.json'
--   'C:\temp\mftdirect_20260205_141509.csv'
--
-- BULK INSERT and OPENROWSET require literal strings — variables don't work.
-- ============================================================================

-- ============================================================================
-- Step 1: Read and parse JSON manifest
-- ============================================================================

DECLARE @JsonText NVARCHAR(MAX);

SELECT @JsonText = CAST(BulkColumn AS NVARCHAR(MAX))
FROM OPENROWSET(BULK 'C:\temp\mftdirect_20260205_141509.json',    -- << CHANGE THIS (Path 1)
                SINGLE_CLOB) AS j;

IF @JsonText IS NULL
BEGIN
    PRINT 'Error: Could not read JSON manifest file.';
    RETURN;
END

-- Parse top-level fields
DECLARE @ServerName     NVARCHAR(256)  = JSON_VALUE(@JsonText, '$.serverName');
DECLARE @ToolName       NVARCHAR(64)   = JSON_VALUE(@JsonText, '$.toolName');
DECLARE @ToolVersion    NVARCHAR(32)   = JSON_VALUE(@JsonText, '$.toolVersion');
DECLARE @CollectedAtUtc NVARCHAR(32)   = JSON_VALUE(@JsonText, '$.collectedAtUtc');
DECLARE @CollectedBy    NVARCHAR(128)  = JSON_VALUE(@JsonText, '$.collectedBy');
DECLARE @DurationSec    NVARCHAR(32)   = JSON_VALUE(@JsonText, '$.durationSec');
DECLARE @TotalEntries   NVARCHAR(32)   = JSON_VALUE(@JsonText, '$.totalEntries');

PRINT 'Manifest loaded:';
PRINT '  Server:    ' + @ServerName;
PRINT '  Tool:      ' + @ToolName + ' v' + ISNULL(@ToolVersion, '?');
PRINT '  Collected: ' + @CollectedAtUtc;
PRINT '  By:        ' + ISNULL(@CollectedBy, '(unknown)');
PRINT '  Entries:   ' + @TotalEntries;

-- ============================================================================
-- Step 2: Create the batch record
-- ============================================================================

DECLARE @BatchId UNIQUEIDENTIFIER = NEWID();

INSERT INTO dbo.ScanBatch (BatchId, ServerName, CollectedAtUtc, CollectedBy,
                           ToolName, ToolVersion, DurationSec)
VALUES (@BatchId,
        @ServerName,
        CAST(@CollectedAtUtc AS DATETIME2(0)),
        @CollectedBy,
        @ToolName,
        @ToolVersion,
        CAST(@DurationSec AS DECIMAL(10,1)));

PRINT 'Created batch: ' + CAST(@BatchId AS NVARCHAR(36));

-- ============================================================================
-- Step 3: Populate ScanVolume from JSON manifest
-- ============================================================================

INSERT INTO dbo.ScanVolume (BatchId, VolumeName, VolumeLabel, FileSystemType,
                            TotalSizeBytes, FreeSizeBytes,
                            EntryCount, DirectoryCount, FileCount,
                            ErrorCount, ScanDurationSec)
SELECT
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

PRINT 'Populated ' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + ' volume(s) from manifest.';

-- ============================================================================
-- Step 4: Bulk load CSV into staging table
-- ============================================================================

DROP TABLE IF EXISTS #CsvStaging;

CREATE TABLE #CsvStaging (
    Volume          NVARCHAR(512),
    FullPath        NVARCHAR(4000),
    FileName        NVARCHAR(512),
    FileSize        NVARCHAR(32),       -- loaded as string; empty for dirs
    CreatedTime     NVARCHAR(32),
    ModifiedTime    NVARCHAR(32),
    AccessedTime    NVARCHAR(32),
    IsDirectory     NVARCHAR(4),
    Attributes      NVARCHAR(16)
);

BULK INSERT #CsvStaging
FROM 'C:\temp\mftdirect_20260205_141509.csv'                     -- << CHANGE THIS (Path 2)
WITH (
    FORMAT         = 'CSV',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR  = '\n',
    FIRSTROW       = 2,            -- skip header
    CODEPAGE       = '65001',      -- UTF-8 (handles BOM)
    TABLOCK,
    BATCHSIZE      = 500000
);

PRINT 'Staged ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' rows from CSV.';

-- ============================================================================
-- Step 5: Insert from staging into FileEntry
-- ============================================================================

INSERT INTO dbo.FileEntry (BatchId, Volume, FullPath, FileName, FileSize,
                           CreatedTime, ModifiedTime, AccessedTime,
                           IsDirectory, Attributes, IsTempCache)
SELECT
    @BatchId,
    Volume,
    -- Strip \\?\ prefix if present for cleaner paths
    CASE WHEN FullPath LIKE '\\?\%' THEN SUBSTRING(FullPath, 5, LEN(FullPath) - 4)
         ELSE FullPath
    END,
    FileName,
    CASE WHEN FileSize = '' OR FileSize IS NULL THEN NULL
         ELSE CAST(FileSize AS BIGINT)
    END,
    CASE WHEN CreatedTime  = '' THEN NULL ELSE CAST(CreatedTime  AS DATETIME2(0)) END,
    CASE WHEN ModifiedTime = '' THEN NULL ELSE CAST(ModifiedTime AS DATETIME2(0)) END,
    CASE WHEN AccessedTime = '' THEN NULL ELSE CAST(AccessedTime AS DATETIME2(0)) END,
    CAST(IsDirectory AS BIT),
    CAST(Attributes AS BIGINT),
    -- Pre-compute IsTempCache flag for fast queries
    CASE WHEN FullPath LIKE '%\Temp\%'
           OR FullPath LIKE '%\tmp\%'
           OR FullPath LIKE '%\Cache\%'
           OR FullPath LIKE '%\.cache\%'
           OR FileName LIKE '%.tmp'
           OR FileName LIKE '%.temp'
           OR FileName LIKE '%.log'
         THEN 1 ELSE 0
    END
FROM #CsvStaging;

PRINT 'Inserted ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' rows into FileEntry.';

DROP TABLE #CsvStaging;

-- ============================================================================
-- Step 6: Populate BatchSummary with pre-aggregated metrics
-- ============================================================================

PRINT 'Computing batch summary metrics...';

INSERT INTO dbo.BatchSummary (
    BatchId,
    TotalUsedBytes,
    TotalFreeBytes,
    TotalFiles,
    TotalDirectories,
    StaleFilesCount,
    StaleFilesBytes,
    DuplicateCandidatesCount,
    DuplicateCandidatesWastedBytes,
    TempCacheFilesCount,
    TempCacheFilesBytes,
    ComputedAtUtc
)
SELECT
    @BatchId,
    -- Total used/free from ScanVolume
    (SELECT SUM(TotalSizeBytes - FreeSizeBytes) FROM dbo.ScanVolume WHERE BatchId = @BatchId),
    (SELECT SUM(FreeSizeBytes) FROM dbo.ScanVolume WHERE BatchId = @BatchId),
    -- Total files/directories from ScanVolume
    (SELECT SUM(FileCount) FROM dbo.ScanVolume WHERE BatchId = @BatchId),
    (SELECT SUM(DirectoryCount) FROM dbo.ScanVolume WHERE BatchId = @BatchId),
    -- Stale files: >2 years old, >100MB
    (SELECT COUNT(*)
     FROM dbo.FileEntry
     WHERE BatchId = @BatchId
       AND IsDirectory = 0
       AND FileSize >= 104857600
       AND ModifiedTime < DATEADD(YEAR, -2, SYSUTCDATETIME())),
    (SELECT ISNULL(SUM(FileSize), 0)
     FROM dbo.FileEntry
     WHERE BatchId = @BatchId
       AND IsDirectory = 0
       AND FileSize >= 104857600
       AND ModifiedTime < DATEADD(YEAR, -2, SYSUTCDATETIME())),
    -- Duplicate candidates: same name+size, >10MB
    (SELECT ISNULL(SUM(cnt), 0)
     FROM (
         SELECT COUNT(*) AS cnt
         FROM dbo.FileEntry
         WHERE BatchId = @BatchId
           AND IsDirectory = 0
           AND FileSize >= 10485760
         GROUP BY FileName, FileSize
         HAVING COUNT(*) > 1
     ) d),
    (SELECT ISNULL(SUM(wasted), 0)
     FROM (
         SELECT (COUNT(*) - 1) * FileSize AS wasted
         FROM dbo.FileEntry
         WHERE BatchId = @BatchId
           AND IsDirectory = 0
           AND FileSize >= 10485760
         GROUP BY FileName, FileSize
         HAVING COUNT(*) > 1
     ) d),
    -- Temp/cache files (uses pre-computed IsTempCache flag)
    (SELECT COUNT(*)
     FROM dbo.FileEntry
     WHERE BatchId = @BatchId
       AND IsDirectory = 0
       AND IsTempCache = 1),
    (SELECT ISNULL(SUM(FileSize), 0)
     FROM dbo.FileEntry
     WHERE BatchId = @BatchId
       AND IsDirectory = 0
       AND IsTempCache = 1),
    SYSUTCDATETIME();

PRINT 'Batch summary computed.';

-- ============================================================================
-- Verify
-- ============================================================================

PRINT '';
PRINT '============================================================';
PRINT 'IMPORT COMPLETE';
PRINT '============================================================';

SELECT
    b.BatchId,
    b.ServerName,
    b.CollectedAtUtc,
    b.ToolName,
    b.ToolVersion,
    b.DurationSec,
    b.CollectedBy
FROM dbo.ScanBatch b
WHERE b.BatchId = @BatchId;

SELECT
    v.VolumeName,
    v.VolumeLabel,
    v.FileSystemType,
    v.TotalSizeBytes / 1073741824.0 AS TotalGB,
    v.FreeSizeBytes  / 1073741824.0 AS FreeGB,
    v.EntryCount,
    v.DirectoryCount,
    v.FileCount,
    v.ErrorCount,
    v.ScanDurationSec
FROM dbo.ScanVolume v
WHERE v.BatchId = @BatchId
ORDER BY v.VolumeName;

SELECT
    COUNT(*) AS TotalFileEntryRows
FROM dbo.FileEntry
WHERE BatchId = @BatchId;
GO
