<#
.SYNOPSIS
    Batch imports multiple MFT scan v2 manifests into the stats schema.

.DESCRIPTION
    Finds all JSON manifests in a directory and imports them sequentially.
    Useful for importing multiple scans collected over time.

.PARAMETER Path
    Directory containing JSON manifest files. Default: current directory.

.PARAMETER SqlInstance
    SQL Server instance name. Default: localhost

.PARAMETER Database
    Database name. Default: FileSizes

.PARAMETER Pattern
    Glob pattern for JSON files. Default: mftdirect_*.json

.EXAMPLE
    .\Import-MftScanBatch.ps1 -Path "C:\scans"

.EXAMPLE
    .\Import-MftScanBatch.ps1 -Path "\\fileserver\scans" -SqlInstance "SQLPROD01"
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path = ".",

    [Parameter()]
    [string]$SqlInstance = "localhost",

    [Parameter()]
    [string]$Database = "FileSizes",

    [Parameter()]
    [string]$Pattern = "mftdirect_*.json"
)

$ErrorActionPreference = "Stop"

# Find all JSON manifests
$jsonFiles = Get-ChildItem -Path $Path -Filter $Pattern | Sort-Object Name

if ($jsonFiles.Count -eq 0) {
    Write-Host "No JSON manifests found matching '$Pattern' in $Path" -ForegroundColor Yellow
    return
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "BATCH IMPORT - Found $($jsonFiles.Count) manifest(s)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$results = @()
$totalStart = Get-Date

foreach ($jsonFile in $jsonFiles) {
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "Processing: $($jsonFile.Name)" -ForegroundColor Yellow

    $manifest = Get-Content $jsonFile.FullName -Raw | ConvertFrom-Json

    # Check if already imported (by server + timestamp)
    $checkQuery = @"
SELECT BatchId FROM stats.ScanBatch
WHERE ServerName = '$($manifest.serverName)'
  AND CollectedAtUtc = '$($manifest.collectedAtUtc)';
"@

    try {
        # Ensure SQL cmdlets are available
        if (-not (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
            if (Get-Module SQLPS -ListAvailable) {
                Push-Location; Import-Module SQLPS -DisableNameChecking; Pop-Location
            } elseif (Get-Module SqlServer -ListAvailable) {
                Import-Module SqlServer
            }
        }
        $existing = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database $Database -Query $checkQuery -ErrorAction Stop

        if ($existing) {
            Write-Host "  SKIPPED: Already imported (BatchId: $($existing.BatchId))" -ForegroundColor DarkYellow
            $results += [PSCustomObject]@{
                File = $jsonFile.Name
                Server = $manifest.serverName
                Status = "Skipped"
                Entries = $manifest.totals.entries
                Duration = 0
                BatchId = $existing.BatchId
            }
            continue
        }
    } catch {
        # Table might not exist yet, continue with import
    }

    # Import using the single-file script
    $scriptPath = Join-Path $PSScriptRoot "Import-MftScanV2.ps1"
    $importStart = Get-Date

    try {
        & $scriptPath -JsonPath $jsonFile.FullName -SqlInstance $SqlInstance -Database $Database

        $duration = ((Get-Date) - $importStart).TotalSeconds
        $results += [PSCustomObject]@{
            File = $jsonFile.Name
            Server = $manifest.serverName
            Status = "Success"
            Entries = $manifest.totals.entries
            Duration = [math]::Round($duration, 1)
            BatchId = "See output"
        }
    } catch {
        $results += [PSCustomObject]@{
            File = $jsonFile.Name
            Server = $manifest.serverName
            Status = "FAILED: $($_.Exception.Message)"
            Entries = $manifest.totals.entries
            Duration = 0
            BatchId = $null
        }
    }
}

$totalDuration = ((Get-Date) - $totalStart).TotalSeconds

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "BATCH IMPORT COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Total time: $([math]::Round($totalDuration, 1)) seconds" -ForegroundColor Cyan
Write-Host ""

$results | Format-Table -AutoSize
