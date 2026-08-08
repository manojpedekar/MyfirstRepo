<#
.SYNOPSIS
    Consolidated tool for collecting and analyzing SMB share usage over time.

.DESCRIPTION
    Manage-ShareUsage_v2.ps1 replaces the following individual scripts:
        Collect-ShareOpenFiles.ps1   -> -Action Collect
        Summarize-ShareUsage.ps1     -> -Action Summarize
        Analyze-ShareAccess.ps1      -> -Action Analyze

    The workflow, used to identify the real owners/active users of a share ahead of a
    file migration, is:

        1. Collect   (scheduled hourly via Task Scheduler) appends one snapshot of the
                     files currently open over SMB, and who has them open, to a monthly CSV.
        2. Summarize rolls the collected snapshots up into a per-folder / per-user summary
                     (who touched what, how often, first/last seen).
        3. Analyze   prints an overview of the collected data (top users, activity by
                     date/hour, file types, top folders).

    CANONICAL SCHEMA
        All snapshot CSVs written by -Action Collect share one schema, which Summarize and
        Analyze both consume:
            Timestamp, User, ClientHost, Path, ShareRelativePath, FileId
        This resolves the schema mismatch in the original scripts (Analyze-ShareAccess.ps1
        expected AccessedBy/OpenFile/OpenMode columns that Collect-ShareOpenFiles.ps1 never
        produced). Get-SmbOpenFile does not expose an open read/write mode, so write-mode
        analysis is only available from the legacy Server 2008 openfiles.exe collector; when
        an OpenMode column is present in the data it is reported, otherwise it is skipped.

    COMPATIBILITY
        Requires Windows Server 2012+ (Get-SmbOpenFile) and PowerShell 5.1+ for -Action Collect.
        For Windows Server 2008 R2 / PowerShell 2.0, keep using Collect-ShareOpenFiles-2k8.ps1
        for collection; its output can still be analyzed here.

.PARAMETER Action
    The operation to perform: Collect, Summarize, or Analyze.

.PARAMETER LogDir
    Directory holding the monthly snapshot CSVs (ShareOpenFiles_YYYY-MM.csv).
    Written to by Collect; read by Summarize and Analyze. Default C:\temp\ShareUsageLogs.

.PARAMETER PathFilter
    Collect only: keep only open files whose path starts with this root. Omit to log all shares.

.PARAMETER GroupLevel
    Summarize only: folder depth (relative to the share root) to group by. Default 1
    (e.g. \\srv\share\TeamA\Sub\file.xlsx grouped by "TeamA").

.PARAMETER OutputDir
    Directory for Summarize/Analyze reports and the run log. Default C:\temp. Created if missing.

.EXAMPLE
    # Scheduled hourly collection (Task Scheduler action):
    powershell.exe -NoProfile -File .\Manage-ShareUsage_v2.ps1 -Action Collect

.EXAMPLE
    .\Manage-ShareUsage_v2.ps1 -Action Collect -PathFilter "G:\Group_Windt132k\Shared"

.EXAMPLE
    .\Manage-ShareUsage_v2.ps1 -Action Summarize -GroupLevel 1

.EXAMPLE
    .\Manage-ShareUsage_v2.ps1 -Action Analyze
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Collect', 'Summarize', 'Analyze')]
    [string]$Action,

    [string]$LogDir = 'C:\temp\ShareUsageLogs',

    # Collect
    [string]$PathFilter = '',

    # Summarize
    [ValidateRange(1, 20)]
    [int]$GroupLevel = 1,

    # Common
    [string]$OutputDir = 'C:\temp'
)

$ErrorActionPreference = 'Stop'

#region --------------------------------------------------------------- Logging / setup

$script:RunStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogFile = $null

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    switch ($Level) {
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line }
    }
    if ($script:LogFile) {
        try { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 }
        catch { Write-Warning "Could not write to log file '$script:LogFile': $_" }
    }
}

function Initialize-OutputDir {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }
    $script:LogFile = Join-Path $Dir ("Manage-ShareUsage_{0}.log" -f $script:RunStamp)
}

function Import-SnapshotRows {
    <#
        Loads and concatenates all monthly snapshot CSVs from LogDir.
        Returns $null (with a logged warning) if none are found.
    #>
    param([string]$Dir)
    $files = Get-ChildItem -Path $Dir -Filter 'ShareOpenFiles_*.csv' -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-Log "No snapshot CSVs (ShareOpenFiles_*.csv) found in $Dir. Has -Action Collect been running?" -Level WARN
        return $null
    }
    $rows = $files | ForEach-Object { Import-Csv -Path $_.FullName }
    Write-Log ("Loaded {0} snapshot row(s) from {1} file(s) in {2}." -f @($rows).Count, @($files).Count, $Dir)
    $rows
}

#endregion

#region --------------------------------------------------------------- Actions

function Invoke-Collect {
    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    $now     = Get-Date
    $logFile = Join-Path $LogDir ("ShareOpenFiles_{0:yyyy-MM}.csv" -f $now)

    $open = Get-SmbOpenFile -ErrorAction SilentlyContinue
    if ($PathFilter) {
        $open = $open | Where-Object { $_.Path -like "$PathFilter*" }
    }

    $snapshot = foreach ($f in $open) {
        [PSCustomObject]@{
            Timestamp         = $now.ToString('yyyy-MM-dd HH:mm:ss')
            User              = $f.ClientUserName
            ClientHost        = $f.ClientComputerName
            Path              = $f.Path
            ShareRelativePath = $f.ShareRelativePath
            FileId            = $f.FileId
        }
    }

    if ($snapshot) {
        # Export-Csv -Append writes the header itself when the file is new (PS 5.1+).
        $snapshot | Export-Csv -Path $logFile -NoTypeInformation -Encoding UTF8 -Append
        Write-Log ("Logged {0} open handle(s) to {1}" -f @($snapshot).Count, $logFile)
    }
    else {
        Write-Log "No open files matched at this snapshot."
    }
}

function Invoke-Summarize {
    $rows = Import-SnapshotRows -Dir $LogDir
    if (-not $rows) { return }

    # Derive a grouping folder key from each logged path. UNC parts[0..1] are server + share;
    # the folder we group by sits after that, offset by GroupLevel.
    $tagged = foreach ($r in $rows) {
        if ([string]::IsNullOrWhiteSpace($r.Path)) { continue }
        $parts  = $r.Path.TrimStart('\') -split '\\'
        $folder = ($parts | Select-Object -Skip (2 + $GroupLevel - 1) -First 1)
        if (-not $folder) { $folder = '<root>' }
        $r | Add-Member -NotePropertyName Folder -NotePropertyValue $folder -PassThru
    }

    $summary = $tagged | Group-Object Folder, User | ForEach-Object {
        $g = $_.Group
        [PSCustomObject]@{
            Folder    = $g[0].Folder
            User      = $g[0].User
            TimesSeen = $_.Count
            FirstSeen = ($g.Timestamp | Measure-Object -Minimum).Minimum
            LastSeen  = ($g.Timestamp | Measure-Object -Maximum).Maximum
        }
    } | Sort-Object Folder, { [int]$_.TimesSeen } -Descending

    if (-not $summary) {
        Write-Log "No usable rows to summarize (all paths were empty?)." -Level WARN
        return
    }

    $csv = Join-Path $OutputDir ("ShareUsage_Summary_{0}.csv" -f $script:RunStamp)
    $summary | Format-Table -AutoSize | Out-Host
    $summary | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    Write-Log ("Saved usage summary ({0} folder/user pairs) to {1}" -f @($summary).Count, $csv)
    $summary
}

function Invoke-Analyze {
    $rows = Import-SnapshotRows -Dir $LogDir
    if (-not $rows) { return }

    # Keep only rows with a real user and a drive/UNC-style path.
    $rows = $rows | Where-Object {
        $_.User -and $_.User -ne 'N/A' -and
        ($_.Path -match '^[A-Za-z]:\\' -or $_.Path -match '^\\\\')
    }
    if (-not $rows) {
        Write-Log "No valid share-open records after filtering." -Level WARN
        return
    }

    # OpenMode only exists in legacy openfiles.exe-sourced data; detect it before use.
    $hasOpenMode = ($rows[0].PSObject.Properties.Name -contains 'OpenMode')

    Write-Output '==================== OVERVIEW ===================='
    Write-Output ("Valid share-open records : {0}" -f @($rows).Count)
    $span = $rows | Measure-Object Timestamp -Minimum -Maximum
    Write-Output ("Snapshot window          : {0}  ->  {1}" -f $span.Minimum, $span.Maximum)
    Write-Output ("Distinct snapshots       : {0}" -f ($rows.Timestamp | Sort-Object -Unique).Count)
    Write-Output ("Distinct users           : {0}" -f ($rows.User | Sort-Object -Unique).Count)

    if ($hasOpenMode) {
        $writeModes = @('Write', 'Write + Read', 'Read + Write')
        $writeRows  = $rows | Where-Object { $writeModes -contains $_.OpenMode }
        Write-Output ("Write-mode opens         : {0} ({1:P1} of records)" -f @($writeRows).Count, (@($writeRows).Count / [double]@($rows).Count))
    }
    else {
        Write-Output "Write-mode opens         : n/a (Get-SmbOpenFile does not expose open mode)"
    }

    Write-Output ''
    Write-Output '==================== TOP USERS (by open events) ===================='
    $rows | Group-Object User | Sort-Object Count -Descending | Select-Object -First 20 |
        ForEach-Object { '{0,-24} {1,6}' -f $_.Name, $_.Count }

    if ($hasOpenMode) {
        Write-Output ''
        Write-Output '==================== USERS WHO WROTE (had Write mode at least once) ===================='
        $rows | Where-Object { @('Write', 'Write + Read', 'Read + Write') -contains $_.OpenMode } |
            Group-Object User | Sort-Object Count -Descending |
            ForEach-Object { '{0,-24} {1,6} write-opens' -f $_.Name, $_.Count }
    }

    Write-Output ''
    Write-Output '==================== TOP-LEVEL SHARE ROOTS ===================='
    $rows | ForEach-Object {
        $p = $_.Path -replace '^[A-Za-z]:\\', '' -replace '^\\\\', ''
        ($p -split '\\')[0]
    } | Group-Object | Sort-Object Count -Descending |
        ForEach-Object { '{0,8}  {1}' -f $_.Count, $_.Name }

    Write-Output ''
    Write-Output '==================== ACTIVITY BY DATE ===================='
    $rows | ForEach-Object { ($_.Timestamp -split ' ')[0] } |
        Group-Object | Sort-Object Name |
        ForEach-Object { '{0}  {1,6} opens' -f $_.Name, $_.Count }

    Write-Output ''
    Write-Output '==================== ACTIVITY BY HOUR OF DAY ===================='
    $rows | ForEach-Object {
        $t = ($_.Timestamp -split ' ')[1]
        if ($t) { ($t -split ':')[0] }
    } | Where-Object { $_ } | Group-Object | Sort-Object Name |
        ForEach-Object { '{0}:00  {1,6} opens' -f $_.Name, $_.Count }

    Write-Output ''
    Write-Output '==================== FILE TYPES (by extension) ===================='
    $fileRows = $rows | Where-Object { $_.Path -match '\.[A-Za-z0-9]{1,5}$' }
    Write-Output ("Distinct paths observed  : {0}" -f ($rows.Path | Sort-Object -Unique).Count)
    Write-Output ("  of which look like files: {0}" -f ($fileRows.Path | Sort-Object -Unique).Count)
    $fileRows | ForEach-Object {
        if ($_.Path -match '\.([A-Za-z0-9]{1,5})$') { $Matches[1].ToLower() } else { 'other' }
    } | Group-Object | Sort-Object Count -Descending | Select-Object -First 15 |
        ForEach-Object { '{0,6}  .{1}' -f $_.Count, $_.Name }

    Write-Log "Analyze complete."
}

#endregion

#region --------------------------------------------------------------- Main

try {
    Initialize-OutputDir -Dir $OutputDir
    Write-Log ("Manage-ShareUsage_v2 started. Action='{0}', LogDir='{1}'." -f $Action, $LogDir)

    switch ($Action) {
        'Collect'   { Invoke-Collect }
        'Summarize' { Invoke-Summarize }
        'Analyze'   { Invoke-Analyze }
    }
}
catch {
    Write-Log ("Fatal error: {0}" -f $_.Exception.Message) -Level ERROR
    Write-Log ($_.ScriptStackTrace) -Level ERROR
    throw
}
finally {
    Write-Log "Manage-ShareUsage_v2 finished."
}

#endregion
