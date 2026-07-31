<#
.SYNOPSIS
    Exports all GPOs in a domain to individual, collision-safe XML reports.

.DESCRIPTION
    Exports every GPO in the specified domain to an XML report. Each report file name
    combines the GPO display name with its GUID so that GPOs with duplicate or
    illegal-character display names never overwrite one another. Reports are written to a
    per-domain subfolder under -ReportPath, so multiple domains can safely share the same
    root path.

    Run this once per domain, then use Search-GPOReports_v2.ps1 to search the exported
    reports for any string (UNC path, server name, registry key, account, etc.).

.PARAMETER Domain
    The Active Directory domain to export GPOs from. Required.

.PARAMETER ReportPath
    Root folder where reports are written. A per-domain subfolder is created beneath it.
    Created if it does not exist. Defaults to "C:\Temp\GPOReports".

.PARAMETER LogPath
    Optional path to a log file. If omitted, a timestamped log is written into the
    per-domain report folder.

.PARAMETER CleanDomainFolder
    Remove any existing *.xml reports in the per-domain folder before exporting. Prevents
    stale reports (for GPOs that were since deleted) from producing false search hits.

.EXAMPLE
    .\Export_GPO_Find_GPO_v2.ps1 -Domain "ssnc.global"
    Exports all GPOs from ssnc.global to C:\Temp\GPOReports\ssnc.global.

.EXAMPLE
    .\Export_GPO_Find_GPO_v2.ps1 -Domain "contoso.com" -ReportPath "E:\GPOReports" -CleanDomainFolder
    Clears old reports, then exports all GPOs from contoso.com to E:\GPOReports\contoso.com.

.NOTES
    Requires the GroupPolicy module (RSAT: Group Policy Management Tools).
    Returns a summary object describing the run.

    To search the exported reports afterwards:
        .\Search-GPOReports_v2.ps1 -SearchString "\\windt132k.ssnc.global\Group" -ReportPath "C:\Temp\GPOReports"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Domain,

    [ValidateNotNullOrEmpty()]
    [string]$ReportPath = "C:\Temp\GPOReports",

    [string]$LogPath,

    [switch]$CleanDomainFolder
)

#region Helper functions
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO',

        [string]$Path
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line      = "$timestamp [$Level] $Message"

    switch ($Level) {
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'ERROR'   { Write-Host $line -ForegroundColor Red }
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line -ForegroundColor Cyan }
    }

    if ($Path) {
        try   { Add-Content -Path $Path -Value $line -Encoding UTF8 -ErrorAction Stop }
        catch { Write-Host "$timestamp [WARN] Could not write to log '$Path': $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}
#endregion

#region Prerequisites
# Ensure the GroupPolicy module is available before doing anything.
if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
    throw "The GroupPolicy module is not installed. Install RSAT: Group Policy Management Tools."
}
Import-Module GroupPolicy -ErrorAction Stop

# Per-domain subfolder keeps reports from different domains from colliding.
$domainFolder = Join-Path -Path $ReportPath -ChildPath $Domain
try {
    New-Item -Path $domainFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
catch {
    throw "Failed to create output folder '$domainFolder': $($_.Exception.Message)"
}

# Resolve the log path (defaults into the per-domain folder with a timestamp).
if (-not $LogPath) {
    $logStamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $LogPath  = Join-Path -Path $domainFolder -ChildPath "Export_GPO_$logStamp.log"
}
#endregion

#region Main processing
Write-Log -Message "Starting GPO export from domain '$Domain' to '$domainFolder'." -Path $LogPath

if ($CleanDomainFolder) {
    $existing = Get-ChildItem -Path $domainFolder -Filter *.xml -File -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Log -Message "Removed $($existing.Count) existing report(s) from '$domainFolder'." -Path $LogPath
    }
}

# Enumerate GPOs. A failure here (unreachable domain, insufficient rights) is fatal.
try {
    $gpos = @(Get-GPO -All -Domain $Domain -ErrorAction Stop)
}
catch {
    Write-Log -Message "Failed to enumerate GPOs in '$Domain': $($_.Exception.Message)" -Level ERROR -Path $LogPath
    throw
}

Write-Log -Message "Found $($gpos.Count) GPO(s) in '$Domain'." -Path $LogPath

$success = 0
$failed  = 0
$failures = [System.Collections.Generic.List[object]]::new()

foreach ($gpo in $gpos) {
    # Replace characters that are illegal in file names, then append the GUID so that
    # duplicate/illegal-character display names cannot overwrite each other.
    $safeName = ($gpo.DisplayName -replace '[\\/:*?"<>|]', '_')
    $outFile  = Join-Path -Path $domainFolder -ChildPath "$safeName-$($gpo.Id).xml"

    try {
        Get-GPOReport -Guid $gpo.Id -Domain $Domain -ReportType XML -Path $outFile -ErrorAction Stop
        $success++
    }
    catch {
        $failed++
        $failures.Add([PSCustomObject]@{
            DisplayName = $gpo.DisplayName
            Guid        = $gpo.Id
            Error       = $_.Exception.Message
        })
        Write-Log -Message "Failed to export '$($gpo.DisplayName)' ($($gpo.Id)): $($_.Exception.Message)" -Level WARN -Path $LogPath
    }
}
#endregion

#region Summary
$level = if ($failed -gt 0) { 'WARN' } else { 'SUCCESS' }
Write-Log -Message "Export complete. Exported: $success | Failed: $failed | Total: $($gpos.Count)." -Level $level -Path $LogPath
Write-Log -Message "Reports: '$domainFolder'  |  Log: '$LogPath'." -Path $LogPath
Write-Log -Message "To search: .\Search-GPOReports_v2.ps1 -SearchString '<string>' -ReportPath '$ReportPath'" -Path $LogPath

# Return a structured object for callers/automation (formatting stays at the presentation layer).
[PSCustomObject]@{
    Domain        = $Domain
    ReportFolder  = $domainFolder
    LogPath       = $LogPath
    TotalGpos     = $gpos.Count
    Exported      = $success
    Failed        = $failed
    Failures      = $failures
    TimestampUtc  = (Get-Date).ToUniversalTime()
}
#endregion
