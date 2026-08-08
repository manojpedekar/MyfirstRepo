<#
.SYNOPSIS
    Enable, report on, and disable Windows file-access auditing to determine which users
    accessed which files (and when) on a file share.

.DESCRIPTION
    Manage-ShareAudit_v2.ps1 replaces the two loose files that previously held this approach:
        enable_audit_policy       -> -Action Enable  (auditpol + Security-log sizing + SACL)
        Read_Shared_Audit_Event   -> -Action Report  (parse Security-log events into a report)

    This is the AUTHORITATIVE method for share-usage analysis. Unlike the open-file
    snapshot approach in Manage-ShareUsage_v2.ps1 (which only catches handles open at the
    sampling instant), Windows object-access auditing records EVERY access, with no gaps.

    GOAL SUPPORTED: "which users accessed which files, and at what time."
    That requires FILE-LEVEL auditing (Security event 4663), which needs BOTH:
        1. The "File System" audit subcategory enabled (auditpol), and
        2. A SACL (audit rule) on the folder tree you want tracked.
    Event 4663 records the user, the exact object (file) path, the access performed
    (Read / Write / Delete / ...), and the timestamp. This action also enables the
    "File Share" subcategory (event 5140) for share-connection context (client, IP).

    ACTIONS
        Enable    Turn on File System + File Share auditing, size the Security log, and
                  apply an audit SACL to -Path so 4663 events are generated for it.
        Report    Read 4663 (file access) and 5140 (share connect) events from the Security
                  log over -LookbackDays and produce per-access and rolled-up reports.
        Disable   Reverse Enable: remove the SACL from -Path and turn the subcategories off.
                  Run this after the assessment window - file-level auditing is high volume.

    IMPORTANT OPERATIONAL NOTES
        * VOLUME: 4663 is chatty. A busy tree can generate large event volumes and roll the
          Security log quickly. Scope the SACL to the specific -Path you care about, size the
          log adequately (-LogSizeMB), keep the assessment window short, and Disable when done.
        * SACL REQUIRED: without a SACL on the target, no 4663 events are produced even with
          the subcategory enabled. Enable sets it; Disable removes it.
        * REMOTING: with -ComputerName, the action runs on the target(s). -Path and log
          settings are interpreted on the target. Requires PS Remoting/WinRM and admin rights.
        * NO SOURCE IP IN 4663: file-access events identify the user and file but not the
          client IP. 5140 (share connect) carries the client/IP; the Report correlates by user.

    COMPATIBILITY
        Requires Windows Server 2008 R2+ (Get-WinEvent, auditpol) and PowerShell 5.1+.
        Advanced Audit Policy subcategories are supported on 2008 R2 and later.

.PARAMETER Action
    Enable, Report, or Disable.

.PARAMETER Path
    The folder tree to audit (Enable/Disable set/remove its SACL) and to filter the Report by.
    Interpreted on the target server when remoting. Required for Enable/Disable.

.PARAMETER Principal
    Identity whose access is audited in the SACL. Default 'Everyone' (audit all users).

.PARAMETER LookbackDays
    Report only: how far back to read Security-log events. Default 7.

.PARAMETER MaxEvents
    Report only: cap on events read per event ID (safety valve on busy servers). Default 100000.

.PARAMETER LogSizeMB
    Enable only: Security log maximum size in MB. Default 1024 (1 GB).

.PARAMETER ComputerName
    One or more remote servers. Omit to run locally.

.PARAMETER Credential
    Credential for remoting. Omit to use current Windows identity.

.PARAMETER ThrottleLimit
    Max servers processed concurrently when remoting. Default 32.

.PARAMETER OutputDir
    Directory for report CSVs and the run log. Default C:\temp. Created if missing.

.PARAMETER Force
    Skip the confirmation prompt for Enable/Disable (both change server audit configuration).

.EXAMPLE
    # Turn on auditing for a specific share tree (one-time, before the assessment window)
    .\Manage-ShareAudit_v2.ps1 -Action Enable -Path "G:\Group_Windt132k\Shared" -ComputerName FS01

.EXAMPLE
    # After a few days, report who accessed which files
    .\Manage-ShareAudit_v2.ps1 -Action Report -Path "G:\Group_Windt132k\Shared" -LookbackDays 7 -ComputerName FS01

.EXAMPLE
    # Clean up when finished
    .\Manage-ShareAudit_v2.ps1 -Action Disable -Path "G:\Group_Windt132k\Shared" -ComputerName FS01 -Force
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Enable', 'Report', 'Disable')]
    [string]$Action,

    [string]$Path,
    [string]$Principal = 'Everyone',

    # Report
    [ValidateRange(1, 3650)]
    [int]$LookbackDays = 7,
    [ValidateRange(1, 5000000)]
    [int]$MaxEvents = 100000,

    # Enable
    [ValidateRange(64, 4194304)]
    [int]$LogSizeMB = 1024,

    # Remoting
    [string[]]$ComputerName,
    [System.Management.Automation.PSCredential]$Credential,
    [ValidateRange(1, 256)]
    [int]$ThrottleLimit = 32,

    [string]$OutputDir = 'C:\temp',

    [switch]$Force
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
    $script:LogFile = Join-Path $Dir ("Manage-ShareAudit_{0}.log" -f $script:RunStamp)
}

function Save-Report {
    param(
        [object[]]$Report,
        [Parameter(Mandatory)][string]$BaseName,
        [switch]$NoDisplay
    )
    if (-not $Report -or $Report.Count -eq 0) {
        Write-Log "No rows produced for '$BaseName'; nothing to save." -Level WARN
        return
    }
    $csv = Join-Path $OutputDir ("{0}_{1}.csv" -f $BaseName, $script:RunStamp)
    if (-not $NoDisplay) { $Report | Format-Table -AutoSize | Out-Host }
    $Report | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    Write-Log ("Saved {0} row(s) to {1}" -f $Report.Count, $csv)
    $Report
}

#endregion

#region --------------------------------------------------------------- Remote script blocks

$SbEnable = {
    param([string]$Path, [string]$Principal, [int]$LogSizeMB)

    if (-not $Path)                          { throw "Enable requires -Path." }
    if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found: $Path" }

    $steps = New-Object System.Collections.Generic.List[object]

    # 1. Enable the audit subcategories (Success).
    #    "File System" -> 4663 (per-object access); "File Share" -> 5140 (share connect).
    foreach ($sub in 'File System', 'File Share') {
        $out = & auditpol /set /subcategory:"$sub" /success:enable 2>&1
        $ok  = ($LASTEXITCODE -eq 0)
        $steps.Add([PSCustomObject]@{ Step = "auditpol enable '$sub'"; Status = if ($ok) { 'OK' } else { 'Failed' }; Detail = "$out" })
    }

    # 2. Size the Security log so a multi-day capture does not roll over.
    $bytes = [long]$LogSizeMB * 1MB
    $out = & wevtutil sl Security /ms:$bytes 2>&1
    $ok  = ($LASTEXITCODE -eq 0)
    $steps.Add([PSCustomObject]@{ Step = "size Security log to ${LogSizeMB}MB"; Status = if ($ok) { 'OK' } else { 'Failed' }; Detail = "$out" })

    # 3. Apply an audit SACL on the target tree (required for 4663 to fire).
    #    Audit Success for the access rights that indicate real usage.
    try {
        $rights = [System.Security.AccessControl.FileSystemRights]'ReadData,WriteData,AppendData,Delete,DeleteSubdirectoriesAndFiles'
        $rule = New-Object System.Security.AccessControl.FileSystemAuditRule(
            $Principal,
            $rights,
            ([System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'),
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AuditFlags]::Success
        )
        $acl = Get-Acl -LiteralPath $Path -Audit
        $acl.AddAuditRule($rule)
        Set-Acl -LiteralPath $Path -AclObject $acl
        $steps.Add([PSCustomObject]@{ Step = "set SACL on '$Path' for '$Principal'"; Status = 'OK'; Detail = "Rights=$rights (Success), inherited to children" })
    }
    catch {
        $steps.Add([PSCustomObject]@{ Step = "set SACL on '$Path' for '$Principal'"; Status = 'Failed'; Detail = "$_" })
    }

    $steps
}

$SbDisable = {
    param([string]$Path, [string]$Principal)

    $steps = New-Object System.Collections.Generic.List[object]

    # 1. Remove the audit SACL from the target tree (if the path still exists).
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        try {
            $acl = Get-Acl -LiteralPath $Path -Audit
            $existing = @($acl.Audit | Where-Object { $_.IdentityReference -like "*$Principal" -or $_.IdentityReference -eq $Principal })
            if ($existing.Count -gt 0) {
                foreach ($r in $existing) { [void]$acl.RemoveAuditRule($r) }
                Set-Acl -LiteralPath $Path -AclObject $acl
                $steps.Add([PSCustomObject]@{ Step = "remove SACL on '$Path'"; Status = 'OK'; Detail = "Removed $($existing.Count) audit rule(s) for '$Principal'" })
            }
            else {
                $steps.Add([PSCustomObject]@{ Step = "remove SACL on '$Path'"; Status = 'OK'; Detail = "No matching audit rule for '$Principal' found" })
            }
        }
        catch {
            $steps.Add([PSCustomObject]@{ Step = "remove SACL on '$Path'"; Status = 'Failed'; Detail = "$_" })
        }
    }
    else {
        $steps.Add([PSCustomObject]@{ Step = "remove SACL on '$Path'"; Status = 'Skipped'; Detail = 'Path not supplied or not found' })
    }

    # 2. Turn the subcategories back off (Success disable).
    foreach ($sub in 'File System', 'File Share') {
        $out = & auditpol /set /subcategory:"$sub" /success:disable 2>&1
        $ok  = ($LASTEXITCODE -eq 0)
        $steps.Add([PSCustomObject]@{ Step = "auditpol disable '$sub'"; Status = if ($ok) { 'OK' } else { 'Failed' }; Detail = "$out" })
    }

    $steps
}

$SbReport = {
    param([string]$Path, [int]$LookbackDays, [int]$MaxEvents)

    $start = (Get-Date).AddDays(-$LookbackDays)

    # Decode a 4663 AccessMask (hex string) into human-readable access names.
    function ConvertFrom-AccessMask {
        param([string]$MaskHex)
        $map = [ordered]@{
            0x1     = 'ReadData/List'
            0x2     = 'WriteData/AddFile'
            0x4     = 'AppendData/AddSubdir'
            0x8     = 'ReadEA'
            0x10    = 'WriteEA'
            0x20    = 'Execute/Traverse'
            0x40    = 'DeleteChild'
            0x80    = 'ReadAttributes'
            0x100   = 'WriteAttributes'
            0x10000 = 'Delete'
            0x20000 = 'ReadControl'
            0x40000 = 'WriteDAC'
            0x80000 = 'WriteOwner'
        }
        $mask = 0
        try { $mask = [Convert]::ToInt64($MaskHex, 16) } catch { return $MaskHex }
        $names = foreach ($bit in $map.Keys) { if ($mask -band $bit) { $map[$bit] } }
        if ($names) { $names -join ',' } else { $MaskHex }
    }

    function Get-EventField {
        param($EventXml, [string]$Name)
        ($EventXml.Event.EventData.Data | Where-Object { $_.Name -eq $Name }).'#text'
    }

    # --- 4663: file/object access (the core "who touched which file") ---
    $access = @()
    $ev4663 = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4663; StartTime = $start } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
    foreach ($e in $ev4663) {
        $x    = [xml]$e.ToXml()
        $obj  = Get-EventField $x 'ObjectName'
        if ($Path -and $obj -and ($obj -notlike "$Path*")) { continue }
        $access += [PSCustomObject]@{
            Time    = $e.TimeCreated
            User    = "{0}\{1}" -f (Get-EventField $x 'SubjectDomainName'), (Get-EventField $x 'SubjectUserName')
            File    = $obj
            Access  = ConvertFrom-AccessMask (Get-EventField $x 'AccessMask')
            Process = Get-EventField $x 'ProcessName'
        }
    }

    # --- 5140: share connections (client/IP context) ---
    $connects = @()
    $ev5140 = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 5140; StartTime = $start } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
    foreach ($e in $ev5140) {
        $x = [xml]$e.ToXml()
        $connects += [PSCustomObject]@{
            Time     = $e.TimeCreated
            User     = "{0}\{1}" -f (Get-EventField $x 'SubjectDomainName'), (Get-EventField $x 'SubjectUserName')
            Share    = Get-EventField $x 'ShareName'
            SourceIP = Get-EventField $x 'IpAddress'
        }
    }

    [PSCustomObject]@{
        Access   = $access
        Connects = $connects
    }
}

#endregion

#region --------------------------------------------------------------- Remoting dispatch

function Invoke-OnTargets {
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
        ErrorAction   = 'Continue'
    }
    if ($Credential) { $icmParams['Credential'] = $Credential }

    Write-Log ("Dispatching to {0} server(s) [throttle {1}]: {2}" -f $ComputerName.Count, $ThrottleLimit, ($ComputerName -join ', '))
    Invoke-Command @icmParams | ForEach-Object {
        if ($null -ne $_ -and -not ($_.PSObject.Properties.Name -contains 'ComputerName')) {
            $_ | Add-Member -NotePropertyName ComputerName -NotePropertyValue $_.PSComputerName -PassThru
        }
        else { $_ }
    }
}

function Confirm-ConfigChange {
    param([string]$Verb)
    $targetDesc = if ($ComputerName) { $ComputerName -join ', ' } else { $env:COMPUTERNAME }
    if ($Force) { return $true }
    Write-Log ("About to {0} file-access auditing on: {1}" -f $Verb, $targetDesc) -Level WARN
    $confirm = Read-Host "Type YES to proceed (or use -Force for unattended runs)"
    if ($confirm -ne 'YES') {
        Write-Log "Aborted by operator. No changes made." -Level WARN
        return $false
    }
    $true
}

#endregion

#region --------------------------------------------------------------- Actions

function Invoke-Enable {
    if (-not $Path) { throw "Enable requires -Path <directory>." }
    if (-not (Confirm-ConfigChange -Verb 'ENABLE')) { return }

    $steps = Invoke-OnTargets -ScriptBlock $SbEnable -ArgumentList @($Path, $Principal, $LogSizeMB)
    foreach ($s in $steps) {
        if (-not $s) { continue }
        $level = if ($s.Status -eq 'Failed') { 'ERROR' } else { 'INFO' }
        Write-Log ("[{0}] {1}: {2} {3}" -f $s.ComputerName, $s.Step, $s.Status, $s.Detail) -Level $level
    }
    Save-Report -Report $steps -BaseName 'ShareAudit_Enable' -NoDisplay | Out-Null
    Write-Log "Auditing enabled. Let it collect for your assessment window, then run -Action Report."
}

function Invoke-Disable {
    if (-not (Confirm-ConfigChange -Verb 'DISABLE')) { return }

    $steps = Invoke-OnTargets -ScriptBlock $SbDisable -ArgumentList @($Path, $Principal)
    foreach ($s in $steps) {
        if (-not $s) { continue }
        $level = if ($s.Status -eq 'Failed') { 'ERROR' } else { 'INFO' }
        Write-Log ("[{0}] {1}: {2} {3}" -f $s.ComputerName, $s.Step, $s.Status, $s.Detail) -Level $level
    }
    Save-Report -Report $steps -BaseName 'ShareAudit_Disable' -NoDisplay | Out-Null
}

function Invoke-Report {
    $raw = Invoke-OnTargets -ScriptBlock $SbReport -ArgumentList @($Path, $LookbackDays, $MaxEvents)

    $access   = foreach ($r in $raw) { if ($r) { $r.Access   | ForEach-Object { if ($_) { $_ | Add-Member -NotePropertyName ComputerName -NotePropertyValue $r.ComputerName -Force -PassThru } } } }
    $connects = foreach ($r in $raw) { if ($r) { $r.Connects | ForEach-Object { if ($_) { $_ | Add-Member -NotePropertyName ComputerName -NotePropertyValue $r.ComputerName -Force -PassThru } } } }

    if (-not $access -and -not $connects) {
        Write-Log "No audit events found. Confirm auditing was enabled (Action Enable) and the SACL/window are correct." -Level WARN
        return
    }

    Write-Log ("File-access events (4663): {0}   Share-connect events (5140): {1}" -f @($access).Count, @($connects).Count)

    # Detailed per-access rows: who touched which file, what access, when.
    $accessSorted = $access | Sort-Object Time -Descending
    Save-Report -Report $accessSorted -BaseName 'ShareAudit_FileAccess' -NoDisplay | Out-Null

    # Rollup: per user + file, how many accesses and first/last seen.
    $rollup = $access | Group-Object User, File | ForEach-Object {
        $g = $_.Group
        [PSCustomObject]@{
            User       = $g[0].User
            File       = $g[0].File
            AccessSeen = $_.Count
            Accesses   = (($g.Access -split ',') | Sort-Object -Unique) -join ','
            FirstSeen  = ($g.Time | Measure-Object -Minimum).Minimum
            LastSeen   = ($g.Time | Measure-Object -Maximum).Maximum
        }
    } | Sort-Object AccessSeen -Descending
    Save-Report -Report $rollup -BaseName 'ShareAudit_UserFile_Rollup'

    # Connection context (client/IP per user), if any 5140 events were captured.
    if ($connects) {
        $connRollup = $connects | Group-Object User, SourceIP, Share | ForEach-Object {
            $g = $_.Group
            [PSCustomObject]@{
                User         = $g[0].User
                SourceIP     = $g[0].SourceIP
                Share        = $g[0].Share
                ConnectCount = $_.Count
                FirstSeen    = ($g.Time | Measure-Object -Minimum).Minimum
                LastSeen     = ($g.Time | Measure-Object -Maximum).Maximum
            }
        } | Sort-Object ConnectCount -Descending
        Save-Report -Report $connRollup -BaseName 'ShareAudit_Connections' -NoDisplay | Out-Null
    }
}

#endregion

#region --------------------------------------------------------------- Main

try {
    Initialize-OutputDir -Dir $OutputDir
    Write-Log ("Manage-ShareAudit_v2 started. Action='{0}', Targets='{1}'." -f $Action, $(if ($ComputerName) { $ComputerName -join ', ' } else { 'local' }))

    switch ($Action) {
        'Enable'  { Invoke-Enable }
        'Report'  { Invoke-Report }
        'Disable' { Invoke-Disable }
    }
}
catch {
    Write-Log ("Fatal error: {0}" -f $_.Exception.Message) -Level ERROR
    Write-Log ($_.ScriptStackTrace) -Level ERROR
    throw
}
finally {
    Write-Log "Manage-ShareAudit_v2 finished."
}

#endregion
