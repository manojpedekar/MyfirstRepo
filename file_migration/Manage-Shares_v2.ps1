<#
.SYNOPSIS
    Consolidated tool for enumerating and managing SMB shares on Windows file servers.

.DESCRIPTION
    Manage-Shares_v2.ps1 replaces the following individual scripts:
        Windows_Share_Permissions.ps1   -> -Action Permissions
        Windows_ShareFolder_Sizes.ps1   -> -Action FolderSizes
        Windows_Shares_Disable.ps1       -> -Action Disable
        Windows_Shares_Enable.ps1        -> -Action Enable
        Get-ShareFolderActivity.ps1      -> -Action FolderActivity

    Improvements over the originals:
        * Optional multi-server execution via PowerShell Remoting (-ComputerName),
          with a configurable throttle limit.
        * Timestamped output written to C:\temp\ by default (per repo standard).
        * Consistent, timestamped logging to a per-run log file.
        * Structured error handling (try/catch/finally) that never silently
          suppresses failures.
        * PowerShell objects returned to the pipeline (formatting is a
          presentation concern handled only for on-screen display).

    ACTIONS
        Permissions     Export share-level ACLs for every (matched) share.
        FolderSizes     One-level sub-folder sizes under -Path.
        FolderActivity  Per top-level sub-folder: newest file write time and NTFS owner.
        Disable         Back up all (matched) shares to JSON on the target, then remove them (DR).
        Enable          Restore shares from a backup JSON on the target.

    REMOTING NOTES
        * When -ComputerName is supplied, each action runs on the target server(s)
          via Invoke-Command. File paths (-Path) and backup paths (-BackupDir /
          -BackupFile) are interpreted ON THE TARGET, not on the machine you run from.
        * Backups for -Action Disable are written to the target's own -BackupDir so
          that -Action Enable can restore locally on that same server.
        * Destructive actions (Disable) prompt once for confirmation on the machine
          you run from. Use -Force to skip the prompt (required for unattended runs).

    COMPATIBILITY
        Requires Windows Server 2012+ (SMB cmdlets) and PowerShell 5.1+ on both the
        machine you run from and every target. For Windows Server 2008 R2 / PowerShell 2.0,
        keep using the legacy standalone scripts (SMB cmdlets are unavailable there).

.PARAMETER Action
    The operation to perform: Permissions, FolderSizes, FolderActivity, Disable, Enable.

.PARAMETER Path
    Root directory for FolderSizes / FolderActivity. Interpreted on the target server.

.PARAMETER Days
    Look-back window (in days) for FolderActivity. Default 30.

.PARAMETER ShareName
    Optional list of share-name patterns (wildcards allowed) for Permissions / Disable / Enable.
    Omit to work on all shares.

.PARAMETER IncludeAdminShares
    Include administrative/special shares (C$, ADMIN$, IPC$, ...). Excluded by default.

.PARAMETER BackupDir
    Directory on the target where Disable writes (and Enable reads) backup JSON. Default C:\ShareBackup.

.PARAMETER BackupFile
    Explicit backup JSON path on the target for Enable. If omitted, the newest backup in BackupDir is used.

.PARAMETER ComputerName
    One or more remote servers to run against. Omit to run on the local machine.

.PARAMETER Credential
    Credential used for remoting. Omit to use the current user's Windows integrated authentication.

.PARAMETER ThrottleLimit
    Maximum number of servers processed concurrently when remoting. Default 32.

.PARAMETER OutputDir
    Directory for CSV reports and the run log. Default C:\temp. Created if missing.

.PARAMETER Force
    Skip the interactive confirmation for the destructive Disable action.

.EXAMPLE
    .\Manage-Shares_v2.ps1 -Action Permissions

.EXAMPLE
    .\Manage-Shares_v2.ps1 -Action Permissions -ComputerName FS01,FS02,FS03 -ShareName Finance,HR

.EXAMPLE
    .\Manage-Shares_v2.ps1 -Action FolderSizes -Path "G:\Group_Windt132k\Shared"

.EXAMPLE
    .\Manage-Shares_v2.ps1 -Action FolderActivity -Path "G:\Group_Windt132k\Shared" -Days 60

.EXAMPLE
    .\Manage-Shares_v2.ps1 -Action Disable -ComputerName FS01 -Force

.EXAMPLE
    .\Manage-Shares_v2.ps1 -Action Enable -ComputerName FS01
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Permissions', 'FolderSizes', 'FolderActivity', 'Disable', 'Enable')]
    [string]$Action,

    # FolderSizes / FolderActivity
    [string]$Path,
    [ValidateRange(1, 3650)]
    [int]$Days = 30,

    # Target-specific shares (Permissions / Disable / Enable). Wildcards + list ok.
    [string[]]$ShareName,
    [switch]$IncludeAdminShares,

    # Disable / Enable
    [string]$BackupDir = 'C:\ShareBackup',
    [string]$BackupFile,

    # Remoting
    [string[]]$ComputerName,
    [System.Management.Automation.PSCredential]$Credential,
    [ValidateRange(1, 256)]
    [int]$ThrottleLimit = 32,

    # Common
    [string]$OutputDir = 'C:\temp',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

#region --------------------------------------------------------------- Logging / setup

$script:RunStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogFile = $null

function Write-Log {
    <#
        Writes a timestamped line to the console and, once initialized, to the run log file.
        Level controls the console stream (INFO/WARN/ERROR) but every level is persisted.
    #>
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
    $script:LogFile = Join-Path $Dir ("Manage-Shares_{0}.log" -f $script:RunStamp)
}

function Save-Report {
    <#
        Displays the report on screen and writes it to a timestamped CSV in OutputDir.
        Returns the objects to the pipeline so callers/automation can consume them.
    #>
    param(
        [object[]]$Report,
        [Parameter(Mandatory)][string]$BaseName
    )
    if (-not $Report -or $Report.Count -eq 0) {
        Write-Log "No rows produced for '$BaseName'; nothing to save." -Level WARN
        return
    }
    $csv = Join-Path $OutputDir ("{0}_{1}.csv" -f $BaseName, $script:RunStamp)
    $Report | Format-Table -AutoSize | Out-Host
    $Report | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    Write-Log ("Saved {0} row(s) to {1}" -f $Report.Count, $csv)
    $Report
}

#endregion

#region --------------------------------------------------------------- Remote script blocks
# Each block is fully self-contained (no reference to outer functions/variables) so it can
# run unchanged inside Invoke-Command. Blocks return PSCustomObjects; the orchestrator tags
# them with the originating computer and handles all file output/logging locally.

$SbPermissions = {
    param([string[]]$ShareName, [bool]$IncludeAdmin)

    function Test-NameMatch {
        param([string]$Name, [string[]]$Patterns)
        if (-not $Patterns) { return $true }
        foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }
        return $false
    }

    $shares = Get-SmbShare
    if (-not $IncludeAdmin) { $shares = $shares | Where-Object { -not $_.Special } }
    if ($ShareName)         { $shares = $shares | Where-Object { Test-NameMatch -Name $_.Name -Patterns $ShareName } }

    foreach ($share in $shares) {
        Get-SmbShareAccess -Name $share.Name -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                ShareName   = $share.Name
                SharePath   = $share.Path
                Description = $share.Description
                Account     = $_.AccountName
                AccessType  = "$($_.AccessControlType)"
                AccessRight = "$($_.AccessRight)"
            }
        }
    }
}

$SbFolderSizes = {
    param([string]$Path)
    if (-not $Path)                          { throw "FolderSizes requires -Path." }
    if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found: $Path" }

    Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $totalSize = (Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                      Measure-Object -Property Length -Sum).Sum
        [PSCustomObject]@{
            FolderName = $_.Name
            FolderPath = $_.FullName
            SizeGB     = [math]::Round(($totalSize / 1GB), 2)
        }
    }
}

$SbFolderActivity = {
    param([string]$Path, [int]$Days)
    if (-not $Path)                          { throw "FolderActivity requires -Path." }
    if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found: $Path" }

    $cutoff = (Get-Date).AddDays(-$Days)
    Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $folder = $_
        $lastWrite = Get-ChildItem -LiteralPath $folder.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                     Measure-Object -Property LastWriteTime -Maximum |
                     Select-Object -ExpandProperty Maximum
        $owner = try { (Get-Acl -LiteralPath $folder.FullName -ErrorAction Stop).Owner } catch { '<unreadable>' }
        [PSCustomObject]@{
            FolderName   = $folder.Name
            FolderPath   = $folder.FullName
            Owner        = $owner
            LastActivity = $lastWrite
            ActiveInDays = ($null -ne $lastWrite -and $lastWrite -ge $cutoff)
        }
    }
}

$SbDisable = {
    param([string[]]$ShareName, [bool]$IncludeAdmin, [string]$BackupDir)

    function Test-NameMatch {
        param([string]$Name, [string[]]$Patterns)
        if (-not $Patterns) { return $true }
        foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }
        return $false
    }

    if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupPath = Join-Path $BackupDir "Shares_Backup_$stamp.json"

    $shares = Get-SmbShare
    if (-not $IncludeAdmin) { $shares = $shares | Where-Object { -not $_.Special } }
    if ($ShareName)         { $shares = $shares | Where-Object { Test-NameMatch -Name $_.Name -Patterns $ShareName } }

    if (-not $shares) {
        return [PSCustomObject]@{ BackupPath = $null; ShareCount = 0; Removed = 0; Results = @() }
    }

    $backup = foreach ($share in $shares) {
        $acls = Get-SmbShareAccess -Name $share.Name | ForEach-Object {
            [PSCustomObject]@{
                AccountName       = $_.AccountName
                AccessControlType = "$($_.AccessControlType)"
                AccessRight       = "$($_.AccessRight)"
            }
        }
        [PSCustomObject]@{
            Name           = $share.Name
            Path           = $share.Path
            Description    = $share.Description
            FolderEnumMode = "$($share.FolderEnumerationMode)"
            CachingMode    = "$($share.CachingMode)"
            Access         = $acls
        }
    }
    $backup | ConvertTo-Json -Depth 5 | Out-File -FilePath $backupPath -Encoding UTF8

    $results = foreach ($share in $shares) {
        try {
            Remove-SmbShare -Name $share.Name -Force -ErrorAction Stop
            [PSCustomObject]@{ ShareName = $share.Name; Path = $share.Path; Status = 'Removed'; Detail = '' }
        }
        catch {
            [PSCustomObject]@{ ShareName = $share.Name; Path = $share.Path; Status = 'Failed'; Detail = "$_" }
        }
    }

    [PSCustomObject]@{
        BackupPath = $backupPath
        ShareCount = @($shares).Count
        Removed    = @($results | Where-Object { $_.Status -eq 'Removed' }).Count
        Results    = $results
    }
}

$SbEnable = {
    param([string[]]$ShareName, [string]$BackupDir, [string]$BackupFile)

    function Test-NameMatch {
        param([string]$Name, [string[]]$Patterns)
        if (-not $Patterns) { return $true }
        foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }
        return $false
    }

    $file = $BackupFile
    if (-not $file) {
        $file = Get-ChildItem -Path $BackupDir -Filter 'Shares_Backup_*.json' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { throw "Backup file not found. Specify -BackupFile or ensure one exists in $BackupDir." }

    $backup = Get-Content -Path $file -Raw | ConvertFrom-Json
    if ($ShareName) { $backup = $backup | Where-Object { Test-NameMatch -Name $_.Name -Patterns $ShareName } }

    $results = foreach ($share in $backup) {
        if (Get-SmbShare -Name $share.Name -ErrorAction SilentlyContinue) {
            [PSCustomObject]@{ ShareName = $share.Name; Path = $share.Path; Status = 'Skipped'; Detail = 'Share already exists' }
            continue
        }
        if (-not (Test-Path -LiteralPath $share.Path)) {
            [PSCustomObject]@{ ShareName = $share.Name; Path = $share.Path; Status = 'Skipped'; Detail = 'Target path missing' }
            continue
        }
        try {
            New-SmbShare -Name $share.Name -Path $share.Path `
                -Description $share.Description `
                -FolderEnumerationMode $share.FolderEnumMode `
                -CachingMode $share.CachingMode `
                -FullAccess 'Administrators' -ErrorAction Stop | Out-Null
            Revoke-SmbShareAccess -Name $share.Name -AccountName 'Administrators' -Force -ErrorAction SilentlyContinue | Out-Null

            foreach ($ace in $share.Access) {
                if ($ace.AccessControlType -eq 'Allow') {
                    Grant-SmbShareAccess -Name $share.Name -AccountName $ace.AccountName -AccessRight $ace.AccessRight -Force | Out-Null
                }
                else {
                    Block-SmbShareAccess -Name $share.Name -AccountName $ace.AccountName -Force | Out-Null
                }
            }
            [PSCustomObject]@{ ShareName = $share.Name; Path = $share.Path; Status = 'Restored'; Detail = "From $file" }
        }
        catch {
            [PSCustomObject]@{ ShareName = $share.Name; Path = $share.Path; Status = 'Failed'; Detail = "$_" }
        }
    }
    $results
}

#endregion

#region --------------------------------------------------------------- Remoting dispatch

function Invoke-OnTargets {
    <#
        Runs a script block locally (no -ComputerName) or across the target servers via
        Invoke-Command with a throttle. Results are tagged with the originating computer.
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @()
    )

    if (-not $ComputerName) {
        $result = & $ScriptBlock @ArgumentList
        return $result | ForEach-Object {
            if ($null -ne $_ -and -not ($_.PSObject.Properties.Name -contains 'ComputerName')) {
                $_ | Add-Member -NotePropertyName ComputerName -NotePropertyValue $env:COMPUTERNAME -PassThru
            }
            else { $_ }
        }
    }

    $icmParams = @{
        ComputerName  = $ComputerName
        ScriptBlock   = $ScriptBlock
        ArgumentList  = $ArgumentList
        ThrottleLimit = $ThrottleLimit
        ErrorAction   = 'Continue'   # keep going if one server fails; failures are logged
    }
    if ($Credential) { $icmParams['Credential'] = $Credential }

    Write-Log ("Dispatching to {0} server(s) [throttle {1}]: {2}" -f $ComputerName.Count, $ThrottleLimit, ($ComputerName -join ', '))
    # Invoke-Command adds PSComputerName automatically; normalize to ComputerName for reporting.
    Invoke-Command @icmParams | ForEach-Object {
        if ($null -ne $_ -and -not ($_.PSObject.Properties.Name -contains 'ComputerName')) {
            $_ | Add-Member -NotePropertyName ComputerName -NotePropertyValue $_.PSComputerName -PassThru
        }
        else { $_ }
    }
}

#endregion

#region --------------------------------------------------------------- Actions

function Invoke-Permissions {
    $report = Invoke-OnTargets -ScriptBlock $SbPermissions -ArgumentList @($ShareName, [bool]$IncludeAdminShares)
    Save-Report -Report $report -BaseName 'Share_Permissions'
}

function Invoke-FolderSizes {
    if (-not $Path) { throw "FolderSizes requires -Path <directory>." }
    $report = Invoke-OnTargets -ScriptBlock $SbFolderSizes -ArgumentList @($Path)
    Save-Report -Report $report -BaseName 'ShareFolder_Sizes'
}

function Invoke-FolderActivity {
    if (-not $Path) { throw "FolderActivity requires -Path <directory>." }
    $report = Invoke-OnTargets -ScriptBlock $SbFolderActivity -ArgumentList @($Path, $Days)
    $report = $report | Sort-Object ComputerName, { $_.LastActivity } -Descending
    $active = @($report | Where-Object { $_.ActiveInDays }).Count
    Write-Log ("FolderActivity: {0} folder(s) scanned, {1} active within {2} day(s)." -f @($report).Count, $active, $Days)
    Save-Report -Report $report -BaseName 'ShareFolder_Activity'
}

function Invoke-Disable {
    # Confirmation gate on the machine you run from (Read-Host inside a remote block would not prompt you).
    $targetDesc = if ($ComputerName) { $ComputerName -join ', ' } else { $env:COMPUTERNAME }
    if (-not $Force) {
        Write-Log ("About to BACK UP and REMOVE shares on: {0}" -f $targetDesc) -Level WARN
        $confirm = Read-Host "Type YES to proceed (or use -Force for unattended runs)"
        if ($confirm -ne 'YES') {
            Write-Log "Aborted by operator. No shares removed." -Level WARN
            return
        }
    }

    $outcome = Invoke-OnTargets -ScriptBlock $SbDisable -ArgumentList @($ShareName, [bool]$IncludeAdminShares, $BackupDir)

    foreach ($o in $outcome) {
        if (-not $o) { continue }
        if ($o.ShareCount -eq 0) {
            Write-Log ("[{0}] No shares matched; nothing removed." -f $o.ComputerName) -Level WARN
            continue
        }
        Write-Log ("[{0}] Backup: {1}" -f $o.ComputerName, $o.BackupPath)
        Write-Log ("[{0}] Removed {1} of {2} share(s). Restore with: -Action Enable -ComputerName {0}" -f $o.ComputerName, $o.Removed, $o.ShareCount)
    }

    $flat = foreach ($o in $outcome) {
        if (-not $o) { continue }
        foreach ($r in $o.Results) {
            [PSCustomObject]@{
                ComputerName = $o.ComputerName
                ShareName    = $r.ShareName
                Path         = $r.Path
                Status       = $r.Status
                Detail       = $r.Detail
                BackupPath   = $o.BackupPath
            }
        }
    }
    Save-Report -Report $flat -BaseName 'Share_Disable_Results'
}

function Invoke-Enable {
    $report = Invoke-OnTargets -ScriptBlock $SbEnable -ArgumentList @($ShareName, $BackupDir, $BackupFile)
    $restored = @($report | Where-Object { $_.Status -eq 'Restored' }).Count
    $skipped  = @($report | Where-Object { $_.Status -eq 'Skipped' }).Count
    $failed   = @($report | Where-Object { $_.Status -eq 'Failed' }).Count
    Write-Log ("Enable complete: {0} restored, {1} skipped, {2} failed." -f $restored, $skipped, $failed)
    Save-Report -Report $report -BaseName 'Share_Enable_Results'
}

#endregion

#region --------------------------------------------------------------- Main

try {
    Initialize-OutputDir -Dir $OutputDir
    Write-Log ("Manage-Shares_v2 started. Action='{0}', Targets='{1}'." -f $Action, $(if ($ComputerName) { $ComputerName -join ', ' } else { 'local' }))

    switch ($Action) {
        'Permissions'    { Invoke-Permissions }
        'FolderSizes'    { Invoke-FolderSizes }
        'FolderActivity' { Invoke-FolderActivity }
        'Disable'        { Invoke-Disable }
        'Enable'         { Invoke-Enable }
    }
}
catch {
    Write-Log ("Fatal error: {0}" -f $_.Exception.Message) -Level ERROR
    Write-Log ($_.ScriptStackTrace) -Level ERROR
    throw
}
finally {
    Write-Log "Manage-Shares_v2 finished."
}

#endregion
