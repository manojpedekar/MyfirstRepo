<#
.SYNOPSIS
    Imports MFT scan v2 data (JSON manifest + CSVs) into the stats schema.

.DESCRIPTION
    Reads the JSON manifest to find the associated CSV files, then executes
    BULK INSERT operations to load the data into stats.ScanBatch, stats.ScanVolume,
    stats.Directory, and stats.FileEntry tables.

    Optimizations:
    - Uses TABLOCK for minimal logging
    - Staging tables to avoid index maintenance during load
    - Automatic path resolution from JSON manifest

.PARAMETER JsonPath
    Path to the JSON manifest file (e.g., mftdirect_20260210_121127.json)

.PARAMETER SqlInstance
    SQL Server instance name. Default: localhost

.PARAMETER Database
    Database name. Default: FileSizes

.PARAMETER CsvPath
    Path to the CSV files. If not specified, uses the same directory as JsonPath.

.EXAMPLE
    .\Import-MftScanV2.ps1 -JsonPath "C:\scans\mftdirect_20260210_121127.json"

.EXAMPLE
    .\Import-MftScanV2.ps1 -JsonPath "\\server\share\mftdirect_20260210_121127.json" -SqlInstance "SQLPROD01"

.NOTES
    Requires:
    - SqlServer PowerShell module (Install-Module SqlServer)
    - BULK ADMIN permissions on the database
    - Files accessible by SQL Server service account
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$JsonPath,

    [Parameter()]
    [string]$SqlInstance = "localhost",

    [Parameter()]
    [string]$Database = "FileSizes",

    [Parameter()]
    [string]$CsvPath
)

$ErrorActionPreference = "Stop"

# Validate JSON file exists
if (-not (Test-Path $JsonPath)) {
    throw "JSON manifest not found: $JsonPath"
}

$JsonPath = (Resolve-Path $JsonPath).Path
Write-Host "JSON Manifest: $JsonPath" -ForegroundColor Cyan

# Read and parse JSON
$manifest = Get-Content $JsonPath -Raw | ConvertFrom-Json

if ($manifest.schemaVersion -ne 2) {
    throw "Expected schemaVersion 2, got $($manifest.schemaVersion)"
}

# Determine CSV directory
if (-not $CsvPath) {
    $CsvPath = Split-Path $JsonPath -Parent
}

# Build full paths for CSV files
$dirCsvPath = Join-Path $CsvPath $manifest.outputFiles.directories
$fileCsvPath = Join-Path $CsvPath $manifest.outputFiles.files

# Validate CSV files exist
if (-not (Test-Path $dirCsvPath)) {
    throw "Directories CSV not found: $dirCsvPath"
}
if (-not (Test-Path $fileCsvPath)) {
    throw "Files CSV not found: $fileCsvPath"
}

Write-Host "Directories CSV: $dirCsvPath" -ForegroundColor Cyan
Write-Host "Files CSV: $fileCsvPath" -ForegroundColor Cyan
Write-Host ""

# Display manifest info
Write-Host "Manifest Summary:" -ForegroundColor Yellow
Write-Host "  Server:      $($manifest.serverName)"
Write-Host "  Tool:        $($manifest.toolName) v$($manifest.toolVersion)"
Write-Host "  Collected:   $($manifest.collectedAtUtc)"
Write-Host "  By:          $($manifest.collectedBy)"
Write-Host "  Duration:    $($manifest.durationSec) sec"
Write-Host "  Entries:     $($manifest.totals.entries.ToString('N0'))"
Write-Host "  Directories: $($manifest.totals.directories.ToString('N0'))"
Write-Host "  Files:       $($manifest.totals.files.ToString('N0'))"
Write-Host "  Volumes:     $($manifest.volumes.Count)"
Write-Host "  LastAccess:  $($manifest.lastAccessTime.status)"
Write-Host ""

# Version validation - require 2.1.0+ for reliable imports
# v2.2.0+ adds IsSystemManaged column to directories CSV (10 columns vs 9)
$minVersion = [Version]"2.1.0"
$toolVersion = $manifest.toolVersion
try {
    $currentVersion = [Version]$toolVersion
    if ($currentVersion -lt $minVersion) {
        Write-Host "WARNING: Data collected with v$toolVersion (minimum recommended: v$minVersion)" -ForegroundColor Red
        Write-Host "         Older versions may have CSV formatting issues." -ForegroundColor Red
        Write-Host "         Consider re-scanning with mftdirect.exe v$minVersion or later." -ForegroundColor Red
        Write-Host ""
        $continue = Read-Host "Continue anyway? (y/N)"
        if ($continue -ne 'y' -and $continue -ne 'Y') {
            Write-Host "Import cancelled." -ForegroundColor Yellow
            return
        }
    }
} catch {
    Write-Host "WARNING: Could not parse tool version '$toolVersion'" -ForegroundColor Yellow
}

# Detect whether CSV includes IsSystemManaged column (v2.2.0+)
$hasSystemManaged = $false
try {
    $toolVer = [Version]$manifest.toolVersion
    $hasSystemManaged = $toolVer -ge [Version]"2.2.0"
} catch { }

if ($hasSystemManaged) {
    Write-Host "  Format:      v2.2+ (includes IsSystemManaged)" -ForegroundColor Green
} else {
    Write-Host "  Format:      v2.1 (IsSystemManaged will default to 0)" -ForegroundColor Yellow
}
Write-Host ""

# Import SQL module (SqlServer or SQLPS)
# Check if Invoke-Sqlcmd is already available (from SQLPS or SqlServer)
if (-not (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
    if (Get-Module SqlServer -ListAvailable) {
        Import-Module SqlServer
    } elseif (Get-Module SQLPS -ListAvailable) {
        Push-Location
        Import-Module SQLPS -DisableNameChecking
        Pop-Location
    } else {
        Write-Host "Installing SqlServer module..." -ForegroundColor Yellow
        Install-Module SqlServer -Scope CurrentUser -Force -AllowClobber
        Import-Module SqlServer
    }
}

$startTime = Get-Date

# Generate the import SQL with actual paths
$importSql = @"
SET NOCOUNT ON;

DECLARE @JsonText NVARCHAR(MAX);
SELECT @JsonText = CAST(BulkColumn AS NVARCHAR(MAX))
FROM OPENROWSET(BULK '$($JsonPath.Replace("'", "''"))', SINGLE_CLOB) AS j;

IF @JsonText IS NULL
BEGIN
    RAISERROR('Error: Could not read JSON manifest file.', 16, 1);
    RETURN;
END

-- Parse manifest
DECLARE @SchemaVersion INT = JSON_VALUE(@JsonText, '$.schemaVersion');
DECLARE @ServerName NVARCHAR(256) = JSON_VALUE(@JsonText, '$.serverName');
DECLARE @ToolName NVARCHAR(64) = JSON_VALUE(@JsonText, '$.toolName');
DECLARE @ToolVersion NVARCHAR(32) = JSON_VALUE(@JsonText, '$.toolVersion');
DECLARE @CollectedAtUtc NVARCHAR(32) = JSON_VALUE(@JsonText, '$.collectedAtUtc');
DECLARE @CollectedBy NVARCHAR(128) = JSON_VALUE(@JsonText, '$.collectedBy');
DECLARE @DurationSec DECIMAL(10,1) = CAST(JSON_VALUE(@JsonText, '$.durationSec') AS DECIMAL(10,1));
DECLARE @LastAccessReg BIGINT = JSON_VALUE(@JsonText, '$.lastAccessTime.registryValue');
DECLARE @LastAccessStatus NVARCHAR(64) = JSON_VALUE(@JsonText, '$.lastAccessTime.status');
DECLARE @LastAccessEnabled BIT = CASE JSON_VALUE(@JsonText, '$.lastAccessTime.enabled') WHEN 'true' THEN 1 ELSE 0 END;
DECLARE @AccessTimeCollected BIT = CASE JSON_VALUE(@JsonText, '$.lastAccessTime.collected') WHEN 'true' THEN 1 ELSE 0 END;
DECLARE @TotalEntries BIGINT = JSON_VALUE(@JsonText, '$.totals.entries');
DECLARE @TotalDirs BIGINT = JSON_VALUE(@JsonText, '$.totals.directories');
DECLARE @TotalFiles BIGINT = JSON_VALUE(@JsonText, '$.totals.files');

IF @SchemaVersion <> 2
BEGIN
    RAISERROR('Error: Expected schemaVersion 2', 16, 1);
    RETURN;
END

-- Create batch
DECLARE @BatchId UNIQUEIDENTIFIER = NEWID();

INSERT INTO stats.ScanBatch (
    BatchId, ServerName, CollectedAtUtc, CollectedBy,
    ToolName, ToolVersion, SchemaVersion, DurationSec,
    LastAccessEnabled, LastAccessRegistryValue, LastAccessStatus, AccessTimeCollected,
    TotalEntries, TotalDirectories, TotalFiles
)
VALUES (
    @BatchId, @ServerName, CAST(@CollectedAtUtc AS DATETIME2(0)), @CollectedBy,
    @ToolName, @ToolVersion, @SchemaVersion, @DurationSec,
    @LastAccessEnabled, @LastAccessReg, @LastAccessStatus, @AccessTimeCollected,
    @TotalEntries, @TotalDirs, @TotalFiles
);

PRINT 'BatchId: ' + CAST(@BatchId AS NVARCHAR(36));

-- Insert volumes
INSERT INTO stats.ScanVolume (
    ScanVolumeId, BatchId, VolumeName, VolumeLabel, FileSystemType,
    TotalSizeBytes, FreeSizeBytes, EntryCount, DirectoryCount, FileCount, ErrorCount, ScanDurationSec
)
SELECT
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    @BatchId,
    JSON_VALUE(v.[value], '$.name'),
    JSON_VALUE(v.[value], '$.label'),
    JSON_VALUE(v.[value], '$.fileSystem'),
    CAST(JSON_VALUE(v.[value], '$.totalSizeBytes') AS BIGINT),
    CAST(JSON_VALUE(v.[value], '$.freeSizeBytes') AS BIGINT),
    CAST(JSON_VALUE(v.[value], '$.entryCount') AS BIGINT),
    CAST(JSON_VALUE(v.[value], '$.directoryCount') AS BIGINT),
    CAST(JSON_VALUE(v.[value], '$.fileCount') AS BIGINT),
    CAST(JSON_VALUE(v.[value], '$.errorCount') AS BIGINT),
    CAST(JSON_VALUE(v.[value], '$.scanDurationSec') AS DECIMAL(10,1))
FROM OPENJSON(@JsonText, '$.volumes') v;

PRINT 'Volumes: ' + CAST(@@ROWCOUNT AS NVARCHAR(10));

-- Stage and insert directories
DROP TABLE IF EXISTS #DirStaging;
$(if ($hasSystemManaged) {
@"
-- v2.2+ format: 10 columns including IsSystemManaged
CREATE TABLE #DirStaging (
    DirectoryId INT NOT NULL, ScanVolumeId INT NOT NULL, ParentId INT NOT NULL,
    Depth TINYINT NOT NULL, DirectoryName NVARCHAR(256) NOT NULL,
    FullPath NVARCHAR(4000) NOT NULL, IsTempCache TINYINT NOT NULL,
    IsSystemManaged TINYINT NOT NULL,
    FileCount INT NULL, TotalFileSize BIGINT NULL
);
"@
} else {
@"
-- v2.1 format: 9 columns (IsSystemManaged will default to 0)
CREATE TABLE #DirStaging (
    DirectoryId INT NOT NULL, ScanVolumeId INT NOT NULL, ParentId INT NOT NULL,
    Depth TINYINT NOT NULL, DirectoryName NVARCHAR(256) NOT NULL,
    FullPath NVARCHAR(4000) NOT NULL, IsTempCache TINYINT NOT NULL,
    FileCount INT NULL, TotalFileSize BIGINT NULL
);
"@
})

BULK INSERT #DirStaging
FROM '$($dirCsvPath.Replace("'", "''"))'
WITH (FORMAT = 'CSV', FIELDTERMINATOR = ',', ROWTERMINATOR = '\n',
      FIRSTROW = 2, CODEPAGE = '65001', TABLOCK, BATCHSIZE = 100000);

PRINT 'Directories staged: ' + CAST(@@ROWCOUNT AS NVARCHAR(20));

INSERT INTO stats.Directory WITH (TABLOCK) (
    DirectoryId, BatchId, ScanVolumeId, ParentId, Depth,
    DirectoryName, FullPath, IsTempCache, IsSystemManaged, FileCount, TotalFileSize
)
SELECT DirectoryId, @BatchId, ScanVolumeId, ParentId, Depth,
       DirectoryName, FullPath, CAST(IsTempCache AS BIT),
       $(if ($hasSystemManaged) { "CAST(IsSystemManaged AS BIT)" } else { "CAST(0 AS BIT)" }),
       FileCount, TotalFileSize
FROM #DirStaging;

PRINT 'Directories inserted: ' + CAST(@@ROWCOUNT AS NVARCHAR(20));
DROP TABLE #DirStaging;

-- Stage and insert files (column count depends on whether AccessedTime was collected)
DROP TABLE IF EXISTS #FileStaging;
DROP TABLE IF EXISTS #FileStagingNoAccess;

IF @AccessTimeCollected = 1
BEGIN
    -- 8-column format with AccessedTime
    CREATE TABLE #FileStaging (
        DirectoryId INT NOT NULL, FileName NVARCHAR(256) NOT NULL,
        Extension NVARCHAR(32) NULL, FileSize BIGINT NULL,
        CreatedTime NVARCHAR(32) NULL, ModifiedTime NVARCHAR(32) NULL,
        AccessedTime NVARCHAR(32) NULL, Attributes INT NOT NULL
    );

    BULK INSERT #FileStaging
    FROM '$($fileCsvPath.Replace("'", "''"))'
    WITH (FORMAT = 'CSV', FIELDTERMINATOR = ',', ROWTERMINATOR = '\n',
          FIRSTROW = 2, CODEPAGE = '65001', TABLOCK, BATCHSIZE = 500000);

    PRINT 'Files staged: ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' (with AccessedTime)';

    INSERT INTO stats.FileEntry WITH (TABLOCK) (
        BatchId, DirectoryId, FileName, Extension, FileSize,
        CreatedTime, ModifiedTime, AccessedTime, Attributes
    )
    SELECT @BatchId, DirectoryId, FileName, NULLIF(Extension, ''), FileSize,
           CASE WHEN CreatedTime = '' OR CreatedTime IS NULL THEN NULL ELSE CAST(CreatedTime AS DATETIME2(0)) END,
           CASE WHEN ModifiedTime = '' OR ModifiedTime IS NULL THEN NULL ELSE CAST(ModifiedTime AS DATETIME2(0)) END,
           CASE WHEN AccessedTime = '' OR AccessedTime IS NULL THEN NULL ELSE CAST(AccessedTime AS DATETIME2(0)) END,
           Attributes
    FROM #FileStaging;

    PRINT 'Files inserted: ' + CAST(@@ROWCOUNT AS NVARCHAR(20));
    DROP TABLE #FileStaging;
END
ELSE
BEGIN
    -- 7-column format without AccessedTime
    CREATE TABLE #FileStagingNoAccess (
        DirectoryId INT NOT NULL, FileName NVARCHAR(256) NOT NULL,
        Extension NVARCHAR(32) NULL, FileSize BIGINT NULL,
        CreatedTime NVARCHAR(32) NULL, ModifiedTime NVARCHAR(32) NULL,
        Attributes INT NOT NULL
    );

    BULK INSERT #FileStagingNoAccess
    FROM '$($fileCsvPath.Replace("'", "''"))'
    WITH (FORMAT = 'CSV', FIELDTERMINATOR = ',', ROWTERMINATOR = '\n',
          FIRSTROW = 2, CODEPAGE = '65001', TABLOCK, BATCHSIZE = 500000);

    PRINT 'Files staged: ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' (no AccessedTime)';

    INSERT INTO stats.FileEntry WITH (TABLOCK) (
        BatchId, DirectoryId, FileName, Extension, FileSize,
        CreatedTime, ModifiedTime, AccessedTime, Attributes
    )
    SELECT @BatchId, DirectoryId, FileName, NULLIF(Extension, ''), FileSize,
           CASE WHEN CreatedTime = '' OR CreatedTime IS NULL THEN NULL ELSE CAST(CreatedTime AS DATETIME2(0)) END,
           CASE WHEN ModifiedTime = '' OR ModifiedTime IS NULL THEN NULL ELSE CAST(ModifiedTime AS DATETIME2(0)) END,
           NULL,
           Attributes
    FROM #FileStagingNoAccess;

    PRINT 'Files inserted: ' + CAST(@@ROWCOUNT AS NVARCHAR(20));
    DROP TABLE #FileStagingNoAccess;
END

-- Compute summary
EXEC stats.ComputeBatchSummary @BatchId;
PRINT 'Summary computed';

-- Return batch ID for verification
SELECT @BatchId AS BatchId;
"@

Write-Host "Starting import to $SqlInstance.$Database..." -ForegroundColor Yellow
Write-Host ""

try {
    $result = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database $Database -Query $importSql -QueryTimeout 0 -Verbose

    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "IMPORT COMPLETE" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "BatchId:     $($result.BatchId)" -ForegroundColor Cyan
    Write-Host "Duration:    $([math]::Round($duration, 1)) seconds" -ForegroundColor Cyan
    Write-Host ""

    # Show summary
    $summaryQuery = @"
SELECT
    b.ServerName,
    b.CollectedAtUtc,
    FORMAT(b.TotalEntries, 'N0') AS Entries,
    FORMAT(b.TotalDirectories, 'N0') AS Directories,
    FORMAT(b.TotalFiles, 'N0') AS Files,
    FORMAT(s.TotalUsedBytes / 1099511627776.0, 'N2') AS UsedTB,
    FORMAT(s.StaleFilesBytes / 1073741824.0, 'N1') AS StaleGB,
    FORMAT(s.DuplicateCandidatesWastedBytes / 1073741824.0, 'N1') AS DuplicateWastedGB,
    FORMAT(s.SystemManagedFilesBytes / 1073741824.0, 'N1') AS SystemManagedGB
FROM stats.ScanBatch b
LEFT JOIN stats.BatchSummary s ON s.BatchId = b.BatchId
WHERE b.BatchId = '$($result.BatchId)';
"@

    $summary = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database $Database -Query $summaryQuery
    $summary | Format-Table -AutoSize

} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
