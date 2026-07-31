<#
.SYNOPSIS
    Initializes a newly-attached ~500 GB VMware disk as the E: drive on multiple
    Windows Servers in parallel, using the full capacity of the disk.

.DESCRIPTION
    For each target server this script (via PowerShell Remoting):

      1. Rescans storage so a freshly-attached VMware disk is detected.
      2. Selects the target disk using SAFE criteria:
           - PartitionStyle is RAW (uninitialized), AND
           - Size is within tolerance of the expected size (default 500 GB).
      3. Applies strict safety gates before making ANY change:
           - If ZERO matching disks are found  -> SKIP (nothing to do).
           - If MORE THAN ONE match is found    -> SKIP (ambiguous; manual review).
           - If drive letter E: is already in use -> SKIP (already provisioned).
      4. Only when exactly one candidate is found: brings the disk online,
         clears read-only, initializes it as GPT, creates a single partition
         using the maximum available size, assigns E:, and formats NTFS.

    The script NEVER touches an already-initialized disk, so existing data disks
    are never at risk. All actions are timestamped and logged to C:\temp\.

    Requires the Storage module (Windows Server 2012 or newer). For Windows
    Server 2008 R2, use the diskpart-based companion script.

.PARAMETER ComputerName
    One or more target server names. Mutually exclusive with -ServerListPath.

.PARAMETER ServerListPath
    Path to a text file containing one server name per line.

.PARAMETER Credential
    Optional PSCredential used for remoting (useful across multiple domains).

.PARAMETER ExpectedSizeGB
    Expected size of the newly-added disk. Default 500.

.PARAMETER SizeToleranceGB
    Allowed +/- deviation from ExpectedSizeGB when matching the disk. VMware and
    Windows report slightly different sizes, so a tolerance avoids false misses.
    Default 20.

.PARAMETER DriveLetter
    Drive letter to assign. Default 'E'.

.PARAMETER FileSystemLabel
    Volume label for the new NTFS volume. Default 'Data'.

.PARAMETER AllocationUnitSize
    NTFS allocation unit (cluster) size in bytes. Default 4096 (4 KB).

.PARAMETER ThrottleLimit
    Maximum concurrent remote sessions. Default 32.

.PARAMETER OutputFolder
    Folder for the report and log. Default C:\temp.

.PARAMETER WhatIf
    Runs the full detection and safety logic and reports the action that WOULD
    be taken, without modifying any disk. Strongly recommended for a first pass.

.EXAMPLE
    .\Initialize-NewDataDisk_E_v1.ps1 -ServerListPath C:\temp\servers.txt -WhatIf

    Dry run: reports what each server would do without changing anything.

.EXAMPLE
    .\Initialize-NewDataDisk_E_v1.ps1 -ServerListPath C:\temp\servers.txt -Credential (Get-Credential)

    Provisions E: on every server in the list using explicit credentials.

.NOTES
    Author  : Manoj Pedekar
    Version : 1.0
    Requires: PowerShell 5.1+ and Storage module on targets (Windows Server 2012+).
              WinRM / PowerShell Remoting enabled on targets.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'List')]
    [string[]]$ComputerName,

    [Parameter(Mandatory = $true, ParameterSetName = 'File')]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$ServerListPath,

    [System.Management.Automation.PSCredential]$Credential,

    [ValidateRange(1, 65536)]
    [int]$ExpectedSizeGB = 500,

    [ValidateRange(0, 1024)]
    [int]$SizeToleranceGB = 20,

    [ValidatePattern('^[D-Zd-z]$')]
    [string]$DriveLetter = 'E',

    [string]$FileSystemLabel = 'Data',

    [ValidateSet(4096, 8192, 16384, 32768, 65536)]
    [int]$AllocationUnitSize = 4096,

    [ValidateRange(1, 256)]
    [int]$ThrottleLimit = 32,

    [string]$OutputFolder = 'C:\temp'
)

#region Setup and logging
$ErrorActionPreference = 'Stop'

# WhatIf flows through to remote sessions so no disk is touched during a dry run.
$IsWhatIf = $PSBoundParameters['WhatIf'].IsPresent -or $WhatIfPreference

if (-not (Test-Path -Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

$RunStamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile    = Join-Path $OutputFolder "Initialize-NewDataDisk_E_$RunStamp.log"
$ReportFile = Join-Path $OutputFolder "Initialize-NewDataDisk_E_$RunStamp.csv"

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')][string]$Level = 'INFO'
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$ts [$Level] $Message"
    switch ($Level) {
        'ERROR'   { Write-Host $line -ForegroundColor Red }
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line -ForegroundColor Cyan }
    }
    Add-Content -Path $LogFile -Value $line
}
#endregion

#region Resolve target list
if ($PSCmdlet.ParameterSetName -eq 'File') {
    $Servers = Get-Content -Path $ServerListPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        Select-Object -Unique
}
else {
    $Servers = $ComputerName | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique
}

if (-not $Servers -or $Servers.Count -eq 0) {
    Write-Log -Message 'No target servers resolved. Exiting.' -Level 'ERROR'
    return
}

Write-Log -Message "Run started. Targets: $($Servers.Count). WhatIf: $IsWhatIf. Expected disk: ${ExpectedSizeGB}GB (+/- ${SizeToleranceGB}GB). Target drive: ${DriveLetter}:." -Level 'INFO'
#endregion

#region Remote worker
# This script block runs on each target server and returns a single status object.
$RemoteScript = {
    param(
        [int]$ExpectedSizeGB,
        [int]$SizeToleranceGB,
        [string]$DriveLetter,
        [string]$FileSystemLabel,
        [int]$AllocationUnitSize,
        [bool]$IsWhatIf
    )

    $ErrorActionPreference = 'Stop'

    $result = [PSCustomObject]@{
        ComputerName   = $env:COMPUTERNAME
        Status         = $null      # Success | Skipped | Failed
        Action         = $null      # what was done or would be done
        DiskNumber     = $null
        DiskSizeGB     = $null
        DriveLetter    = $DriveLetter
        Message        = $null
        TimeStamp      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }

    try {
        # Storage module is required (Windows Server 2012+).
        if (-not (Get-Command -Name Get-Disk -ErrorAction SilentlyContinue)) {
            $result.Status  = 'Failed'
            $result.Action  = 'None'
            $result.Message = 'Storage module / Get-Disk not available (needs Windows Server 2012+). Use the 2008 R2 script.'
            return $result
        }

        # Rescan so a freshly-attached VMware disk is visible.
        Update-HostStorageCache | Out-Null
        Start-Sleep -Seconds 3

        # Guard: if the target drive letter is already in use, do not touch anything.
        $existing = Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue
        if ($existing) {
            $result.Status  = 'Skipped'
            $result.Action  = 'None'
            $result.Message = "Drive ${DriveLetter}: already exists (likely already provisioned)."
            return $result
        }

        # Select candidate disks: RAW (uninitialized) AND size within tolerance.
        $minBytes = ($ExpectedSizeGB - $SizeToleranceGB) * 1GB
        $maxBytes = ($ExpectedSizeGB + $SizeToleranceGB) * 1GB

        $candidates = Get-Disk | Where-Object {
            $_.PartitionStyle -eq 'RAW' -and
            $_.Size -ge $minBytes -and
            $_.Size -le $maxBytes
        }

        $count = @($candidates).Count

        if ($count -eq 0) {
            $result.Status  = 'Skipped'
            $result.Action  = 'None'
            $result.Message = "No RAW disk matching ${ExpectedSizeGB}GB (+/- ${SizeToleranceGB}GB) found. Nothing to provision."
            return $result
        }

        if ($count -gt 1) {
            $nums = ($candidates.Number -join ', ')
            $result.Status  = 'Skipped'
            $result.Action  = 'None'
            $result.Message = "AMBIGUOUS: $count matching RAW disks found (disk numbers: $nums). Skipped for manual review to prevent data loss."
            return $result
        }

        # Exactly one candidate.
        $disk = $candidates | Select-Object -First 1
        $result.DiskNumber = $disk.Number
        $result.DiskSizeGB = [math]::Round($disk.Size / 1GB, 2)

        if ($IsWhatIf) {
            $result.Status  = 'Skipped'
            $result.Action  = 'WhatIf'
            $result.Message = "WHATIF: Would initialize disk $($disk.Number) ($($result.DiskSizeGB)GB) as ${DriveLetter}: (NTFS, ${AllocationUnitSize}-byte clusters, label '$FileSystemLabel')."
            return $result
        }

        # Bring online and clear read-only if needed (newly-attached VMware disks are often offline/RO).
        if ($disk.IsOffline) {
            Set-Disk -Number $disk.Number -IsOffline $false
        }
        if ($disk.IsReadOnly) {
            Set-Disk -Number $disk.Number -IsReadOnly $false
        }

        # Initialize as GPT, create partition using max size, assign letter, format NTFS.
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT -ErrorAction Stop | Out-Null

        $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter $DriveLetter -ErrorAction Stop

        Format-Volume -DriveLetter $DriveLetter `
                      -FileSystem NTFS `
                      -NewFileSystemLabel $FileSystemLabel `
                      -AllocationUnitSize $AllocationUnitSize `
                      -Confirm:$false -Force -ErrorAction Stop | Out-Null

        $vol = Get-Volume -DriveLetter $DriveLetter
        $result.Status  = 'Success'
        $result.Action  = 'Initialized'
        $result.Message = "Provisioned ${DriveLetter}: from disk $($disk.Number). Volume size $([math]::Round($vol.Size/1GB,2))GB."
        return $result
    }
    catch {
        $result.Status  = 'Failed'
        $result.Action  = if ($result.Action) { $result.Action } else { 'Error' }
        $result.Message = "ERROR: $($_.Exception.Message)"
        return $result
    }
}
#endregion

#region Execute in parallel and collect results
$invokeParams = @{
    ComputerName  = $Servers
    ScriptBlock   = $RemoteScript
    ArgumentList  = @($ExpectedSizeGB, $SizeToleranceGB, $DriveLetter, $FileSystemLabel, $AllocationUnitSize, $IsWhatIf)
    ThrottleLimit = $ThrottleLimit
    ErrorAction   = 'SilentlyContinue'
    ErrorVariable = 'remoteErrors'
}
if ($Credential) { $invokeParams['Credential'] = $Credential }

Write-Log -Message "Dispatching to $($Servers.Count) server(s) with throttle limit $ThrottleLimit..." -Level 'INFO'

$results = Invoke-Command @invokeParams

# Capture unreachable / remoting failures as explicit rows so nothing is silently lost.
$reachedNames = @($results.ComputerName)
$unreachable = @()
foreach ($err in $remoteErrors) {
    $target = $err.TargetObject
    if ($target -and ($reachedNames -notcontains $target)) {
        $unreachable += [PSCustomObject]@{
            ComputerName = $target
            Status       = 'Failed'
            Action       = 'None'
            DiskNumber   = $null
            DiskSizeGB   = $null
            DriveLetter  = $DriveLetter
            Message      = "UNREACHABLE / remoting error: $($err.Exception.Message)"
            TimeStamp    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    }
}

$allResults = @($results | Select-Object ComputerName, Status, Action, DiskNumber, DiskSizeGB, DriveLetter, Message, TimeStamp) + $unreachable
#endregion

#region Report and summary
$allResults | Sort-Object Status, ComputerName | Export-Csv -Path $ReportFile -NoTypeInformation -Encoding UTF8

foreach ($r in ($allResults | Sort-Object ComputerName)) {
    $level = switch ($r.Status) {
        'Success' { 'SUCCESS' }
        'Failed'  { 'ERROR' }
        default   { 'WARN' }
    }
    Write-Log -Message "$($r.ComputerName): [$($r.Status)] $($r.Message)" -Level $level
}

$summary = $allResults | Group-Object Status | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Log -Message "Run complete. Summary: $($summary -join ', '). Report: $ReportFile" -Level 'INFO'

# Return objects to the pipeline for further processing if desired.
$allResults
#endregion
