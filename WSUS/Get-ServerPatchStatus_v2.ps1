<#
.SYNOPSIS
    Collects Windows patching and reboot status from one or more servers to
    investigate why scheduled patching (e.g. Salt patching module) did not
    install updates or reboot as expected.

.DESCRIPTION
    Runs a self-contained, PowerShell v2-safe collection script block on each
    target via PowerShell Remoting (WinRM). Because collection runs remotely,
    a single script supports modern targets AND Windows Server 2008 R2 (PSv2).

    For each server it returns a rich object designed to distinguish between the
    common root causes of "patching ran but nothing happened":

        1. Already patched by a prior run     -> recent quality update / current UBR
        2. WSUS target-group / approval issue  -> WSUS group set, but no approvals
        3. Broken scan reporting success       -> stale/failed last successful scan
        4. Patched but never rebooted          -> pending reboot, boot predates update

    Collected signals:
        * OS caption/version, build + UBR (true patch level), OS install date
        * Last boot time and uptime (days)
        * Windows Update Agent history: last OS quality/security update (the
          monthly OS cumulative update or legacy monthly rollup) and last update
          of any kind, with install dates
        * Get-HotFix cross-check (most recent KB + InstalledOn)
        * Pending reboot flags (CBS / Windows Update / PendingFileRename)
        * Windows Update last successful Detect (scan) and Install times
        * WSUS configuration (WUServer, UseWUServer, TargetGroup)
        * wuauserv and salt-minion service state (+ Salt version, best effort)

    Unreachable or failed hosts are returned as explicit rows (CollectionStatus
    = 'Offline' / 'Failed') so gaps are never silent.

.PARAMETER ComputerName
    One or more target server names. Combined with any names from -Path.

.PARAMETER Path
    Path to a .txt (one name per line) or .csv file containing server names.
    For CSV, the 'ComputerName' column is used if present, otherwise the first
    column. Blank lines and lines starting with '#' are ignored.

.PARAMETER Credential
    Optional PSCredential for remote access. Defaults to the current user
    (Windows integrated authentication).

.PARAMETER ThrottleLimit
    Maximum concurrent remote connections for the parallel fan-out. Default 32.

.PARAMETER UpdateHistoryCount
    Number of most-recent installed updates to include per server. Default 10.

.PARAMETER OutputFolder
    Folder for the CSV report and log. Default C:\temp (created if missing).

.PARAMETER SkipConnectivityTest
    Skip the pre-flight ICMP ping check and attempt WinRM against every host.
    Use when ICMP is blocked but WinRM is open.

.EXAMPLE
    .\Get-ServerPatchStatus_v2.ps1 -ComputerName SRV01,SRV02 -Verbose

.EXAMPLE
    .\Get-ServerPatchStatus_v2.ps1 -Path C:\temp\servers.txt -Credential (Get-Credential)

.EXAMPLE
    $r = .\Get-ServerPatchStatus_v2.ps1 -Path .\hosts.csv -ThrottleLimit 50
    $r | Where-Object PendingReboot -eq $true | Format-Table ComputerName,LastBootUpTime,LastQualityUpdateDate

.NOTES
    Author  : Manoj Pedekar
    Version : 2.0
    Requires: Orchestrator PowerShell 5.1+; targets need WinRM enabled.
              Remote collection block is PSv2-safe (Windows Server 2008 R2 OK).

    CHANGES FROM v1
      * Fixed LastQualityUpdate* mislabeling. v1 defined the "quality update" as
        the newest WUA install that was not a Defender definition, which wrongly
        matched application/driver installs (PowerShell, Edge, Broadcom, MSRT).
        v2 classifies by title and selects the actual OS quality/security update
        (monthly OS cumulative update, or legacy Security Monthly Quality Rollup
        on WS2008 R2 / 2012), explicitly excluding .NET (which ships its own
        "Cumulative Update for .NET" title). If no OS quality update is found in
        history, the LastQualityUpdate* fields are left blank rather than falling
        back to an unrelated update.

    LIMITATIONS
      * WUA history / WSUS scan times reflect the Windows Update Agent, not Salt
        internals. If Salt uses its own mechanism, cross-reference Salt logs.
      * WU 'LastSuccessTime' registry values are typically stored in UTC.
      * Requires WinRM (5985/5986). For hosts without WinRM, a WMI/DCOM fallback
        would be needed (not implemented in this version).
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('CN', 'Server', 'Name')]
    [string[]]$ComputerName,

    [Parameter()]
    [ValidateScript({
        if (Test-Path -LiteralPath $_ -PathType Leaf) { $true }
        else { throw "Input file not found: $_" }
    })]
    [string]$Path,

    [Parameter()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty,

    [Parameter()]
    [ValidateRange(1, 256)]
    [int]$ThrottleLimit = 32,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$UpdateHistoryCount = 10,

    [Parameter()]
    [string]$OutputFolder = 'C:\temp',

    [Parameter()]
    [switch]$SkipConnectivityTest
)

begin {
    #region Setup and logging ------------------------------------------------
    $ErrorActionPreference = 'Stop'
    $runTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    if (-not (Test-Path -LiteralPath $OutputFolder)) {
        New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
    }

    $script:LogFile = Join-Path $OutputFolder "Get-ServerPatchStatus_v2_$runTimestamp.log"
    $script:CsvFile = Join-Path $OutputFolder "Get-ServerPatchStatus_v2_$runTimestamp.csv"

    function Write-Log {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)][string]$Message,
            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')][string]$Level = 'INFO'
        )
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line = "[$stamp] [$Level] $Message"
        switch ($Level) {
            'WARN'    { Write-Warning $Message }
            'ERROR'   { Write-Host $line -ForegroundColor Red }
            'SUCCESS' { Write-Host $line -ForegroundColor Green }
            default   { Write-Verbose $line }
        }
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    }

    Write-Log "Script started. Log: $script:LogFile" -Level INFO

    # Accumulator so pipeline-supplied names are gathered before processing.
    $script:TargetList = New-Object System.Collections.Generic.List[string]
    #endregion

    #region Remote collection script block (PSv2-safe) -----------------------
    $collectionScript = {
        param([int]$HistoryCount)

        # --- helpers (PSv2-safe) ---
        function Convert-WmiDate {
            param($Value)
            if ($Value) {
                try { return [System.Management.ManagementDateTimeConverter]::ToDateTime($Value) }
                catch { return $null }
            }
            return $null
        }
        function Get-RegValue {
            param([string]$RegPath, [string]$RegName)
            try {
                $item = Get-ItemProperty -Path $RegPath -Name $RegName -ErrorAction Stop
                return $item.$RegName
            } catch { return $null }
        }

        $result = New-Object PSObject -Property @{
            ComputerName             = $env:COMPUTERNAME
            CollectionStatus         = 'OK'
            CollectionError          = $null
            OSCaption                = $null
            OSVersion                = $null
            OSBuild                  = $null
            OSDisplayVersion         = $null
            OSInstallDate            = $null
            LastBootUpTime           = $null
            UptimeDays               = $null
            LastQualityUpdateKB      = $null
            LastQualityUpdateTitle   = $null
            LastQualityUpdateDate    = $null
            DaysSinceQualityUpdate   = $null
            LastAnyUpdateTitle       = $null
            LastAnyUpdateDate        = $null
            LastHotFixKB             = $null
            LastHotFixInstalledOn    = $null
            RecentUpdates            = $null
            PendingReboot            = $false
            PendingRebootReasons     = $null
            WU_LastScanSuccess       = $null
            WU_LastInstallSuccess    = $null
            WSUS_Server              = $null
            WSUS_UseWUServer         = $null
            WSUS_TargetGroup         = $null
            WUAuServiceStatus        = $null
            WUAuServiceStartMode     = $null
            SaltMinionStatus         = $null
            SaltMinionVersion        = $null
        }

        try {
            # --- OS / boot ---
            $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
            $result.OSCaption     = $os.Caption
            $result.OSVersion     = $os.Version
            $result.OSInstallDate = Convert-WmiDate $os.InstallDate
            $boot = Convert-WmiDate $os.LastBootUpTime
            $result.LastBootUpTime = $boot
            if ($boot) {
                $result.UptimeDays = [math]::Round(((Get-Date) - $boot).TotalDays, 2)
            }

            # --- true patch level (build + UBR) ---
            $cvPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            $build  = Get-RegValue $cvPath 'CurrentBuild'
            if (-not $build) { $build = Get-RegValue $cvPath 'CurrentBuildNumber' }
            $ubr = Get-RegValue $cvPath 'UBR'
            if ($build -and $ubr) { $result.OSBuild = "$build.$ubr" }
            elseif ($build)       { $result.OSBuild = "$build" }
            $result.OSDisplayVersion = Get-RegValue $cvPath 'DisplayVersion'
            if (-not $result.OSDisplayVersion) { $result.OSDisplayVersion = Get-RegValue $cvPath 'ReleaseId' }

            # --- Windows Update Agent history (accurate install dates) ---
            try {
                # Classification regexes for update history titles:
                #   $defRegex       - Defender definitions / MSRT: high-frequency noise.
                #   $osQualityRegex - the OS monthly quality/security update. Modern OS
                #                     uses "Cumulative Update for Microsoft server
                #                     operating system"/"...for Windows"; legacy OS
                #                     (WS2008 R2 / 2012) uses monthly rollups.
                #   $dotNetRegex    - .NET ships its own "Cumulative Update for .NET"
                #                     title and must NOT be counted as the OS update.
                $defRegex       = 'Defender|Antivirus|Definition|Security Intelligence|Antimalware|Malicious Software Removal Tool'
                $osQualityRegex = 'Cumulative Update for (Microsoft server operating system|Windows)|Security Monthly Quality Rollup|Security[- ]Only.*Quality Update'
                $dotNetRegex    = '\.NET'

                $session  = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                $total    = $searcher.GetTotalHistoryCount()
                if ($total -gt 0) {
                    $history = $searcher.QueryHistory(0, $total)
                    # Operation 1 = Installation; ResultCode 2 = Succeeded. Newest first.
                    $installed = @()
                    foreach ($h in $history) {
                        if ($h.Operation -eq 1 -and $h.ResultCode -eq 2 -and $h.Title) {
                            $installed += $h
                        }
                    }

                    if ($installed.Count -gt 0) {
                        # Newest install of ANY kind (patch, driver, app) - activity marker.
                        $newestAny = $installed[0]
                        $result.LastAnyUpdateTitle = $newestAny.Title
                        $result.LastAnyUpdateDate  = $newestAny.Date

                        # Newest OS quality/security update (the meaningful monthly patch),
                        # excluding .NET and definition/MSRT noise.
                        $quality = $installed | Where-Object {
                            $_.Title -match $osQualityRegex -and
                            $_.Title -notmatch $dotNetRegex -and
                            $_.Title -notmatch $defRegex
                        } | Select-Object -First 1

                        if ($quality) {
                            $result.LastQualityUpdateTitle = $quality.Title
                            $result.LastQualityUpdateDate  = $quality.Date
                            if ($quality.Date) {
                                $result.DaysSinceQualityUpdate = [math]::Round(((Get-Date) - $quality.Date).TotalDays, 1)
                            }
                            $m = [regex]::Match($quality.Title, 'KB\d{6,7}')
                            if ($m.Success) { $result.LastQualityUpdateKB = $m.Value }
                        }

                        $topN = $installed | Select-Object -First $HistoryCount | ForEach-Object {
                            $d = if ($_.Date) { $_.Date.ToString('yyyy-MM-dd HH:mm') } else { 'n/a' }
                            "$d | $($_.Title)"
                        }
                        $result.RecentUpdates = ($topN -join ' || ')
                    }
                }
            } catch {
                $result.RecentUpdates = "WUA history error: $($_.Exception.Message)"
            }

            # --- Get-HotFix cross-check ---
            try {
                $hf = Get-HotFix -ErrorAction Stop |
                      Where-Object { $_.InstalledOn } |
                      Sort-Object InstalledOn -Descending |
                      Select-Object -First 1
                if ($hf) {
                    $result.LastHotFixKB          = $hf.HotFixID
                    $result.LastHotFixInstalledOn = $hf.InstalledOn
                }
            } catch { }

            # --- Pending reboot detection ---
            $reasons = @()
            if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
                $reasons += 'CBS'
            }
            if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
                $reasons += 'WindowsUpdate'
            }
            $pfr = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations'
            if ($pfr) { $reasons += 'PendingFileRename' }
            if ($reasons.Count -gt 0) {
                $result.PendingReboot        = $true
                $result.PendingRebootReasons = ($reasons -join ', ')
            }

            # --- WU last successful scan / install ---
            $auResults = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results'
            $result.WU_LastScanSuccess    = Get-RegValue "$auResults\Detect"  'LastSuccessTime'
            $result.WU_LastInstallSuccess = Get-RegValue "$auResults\Install" 'LastSuccessTime'

            # --- WSUS configuration ---
            $wuPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
            $result.WSUS_Server      = Get-RegValue $wuPolicy 'WUServer'
            $result.WSUS_TargetGroup = Get-RegValue $wuPolicy 'TargetGroup'
            $result.WSUS_UseWUServer = Get-RegValue "$wuPolicy\AU" 'UseWUServer'

            # --- Services ---
            $wu = Get-WmiObject -Class Win32_Service -Filter "Name='wuauserv'" -ErrorAction SilentlyContinue
            if ($wu) {
                $result.WUAuServiceStatus    = $wu.State
                $result.WUAuServiceStartMode = $wu.StartMode
            }
            $salt = Get-WmiObject -Class Win32_Service -Filter "Name='salt-minion'" -ErrorAction SilentlyContinue
            if ($salt) {
                $result.SaltMinionStatus = $salt.State
                # Best-effort Salt version from install path binary, non-fatal.
                try {
                    $pathExe = ($salt.PathName -replace '"', '') -replace '\s+/.*$', ''
                    if ($pathExe -and (Test-Path $pathExe)) {
                        $result.SaltMinionVersion = (Get-Item $pathExe).VersionInfo.ProductVersion
                    }
                } catch { }
            } else {
                $result.SaltMinionStatus = 'NotInstalled'
            }
        }
        catch {
            $result.CollectionStatus = 'Failed'
            $result.CollectionError  = $_.Exception.Message
        }

        return $result
    }
    #endregion
}

process {
    if ($ComputerName) {
        foreach ($c in $ComputerName) {
            if ($c -and $c.Trim()) { $script:TargetList.Add($c.Trim()) }
        }
    }
}

end {
    #region Build target list ------------------------------------------------
    if ($Path) {
        Write-Log "Reading server names from file: $Path" -Level INFO
        try {
            $ext = [System.IO.Path]::GetExtension($Path)
            if ($ext -ieq '.csv') {
                $csv = Import-Csv -Path $Path
                $prop = if ($csv -and ($csv[0].PSObject.Properties.Name -contains 'ComputerName')) {
                    'ComputerName'
                } else {
                    $csv[0].PSObject.Properties.Name | Select-Object -First 1
                }
                foreach ($row in $csv) {
                    $val = $row.$prop
                    if ($val -and $val.Trim()) { $script:TargetList.Add($val.Trim()) }
                }
            } else {
                Get-Content -Path $Path | ForEach-Object {
                    $line = $_.Trim()
                    if ($line -and -not $line.StartsWith('#')) { $script:TargetList.Add($line) }
                }
            }
        } catch {
            Write-Log "Failed to read input file '$Path': $($_.Exception.Message)" -Level ERROR
            throw
        }
    }

    $targets = $script:TargetList | Select-Object -Unique
    if (-not $targets -or $targets.Count -eq 0) {
        Write-Log "No target servers supplied. Use -ComputerName and/or -Path." -Level ERROR
        throw "No target servers supplied."
    }
    Write-Log "Total unique targets: $($targets.Count)" -Level INFO
    #endregion

    #region Connectivity pre-check ------------------------------------------
    $reachable = @()
    $offline   = @()
    if ($SkipConnectivityTest) {
        $reachable = $targets
        Write-Log "Connectivity pre-check skipped (-SkipConnectivityTest)." -Level INFO
    } else {
        Write-Log "Running ICMP connectivity pre-check..." -Level INFO
        foreach ($t in $targets) {
            if (Test-Connection -ComputerName $t -Count 1 -Quiet -ErrorAction SilentlyContinue) {
                $reachable += $t
            } else {
                $offline += $t
                Write-Log "Host did not respond to ping: $t" -Level WARN
            }
        }
    }
    Write-Log "Reachable: $($reachable.Count); Offline: $($offline.Count)" -Level INFO
    #endregion

    #region Remote collection (parallel fan-out) -----------------------------
    $results = New-Object System.Collections.Generic.List[object]

    if ($reachable.Count -gt 0) {
        Write-Log "Collecting from $($reachable.Count) host(s), throttle $ThrottleLimit..." -Level INFO
        $icParams = @{
            ComputerName  = $reachable
            ScriptBlock   = $collectionScript
            ArgumentList  = $UpdateHistoryCount
            ThrottleLimit = $ThrottleLimit
            ErrorAction   = 'SilentlyContinue'
            ErrorVariable = 'icErrors'
        }
        if ($Credential -and $Credential -ne [System.Management.Automation.PSCredential]::Empty) {
            $icParams['Credential'] = $Credential
        }

        $raw = Invoke-Command @icParams
        foreach ($r in $raw) { $results.Add($r) }

        # Reconcile: any reachable host with no returned object = WinRM/remoting failure.
        $returnedNames = @($raw | ForEach-Object { $_.ComputerName })
        foreach ($t in $reachable) {
            $matched = $returnedNames | Where-Object { $_ -and ($_ -ieq $t -or $t -ilike "$_*") }
            if (-not $matched) {
                $errText = ($icErrors | Where-Object { $_.TargetObject -eq $t -or "$_" -match [regex]::Escape($t) } |
                            Select-Object -First 1)
                $results.Add([PSCustomObject]@{
                    ComputerName     = $t
                    CollectionStatus = 'Failed'
                    CollectionError  = if ($errText) { "$errText" } else { 'WinRM/remoting failure (no data returned)' }
                })
                Write-Log "Remoting failed for $t : $errText" -Level WARN
            }
        }
    }

    foreach ($t in $offline) {
        $results.Add([PSCustomObject]@{
            ComputerName     = $t
            CollectionStatus = 'Offline'
            CollectionError  = 'No ICMP response during pre-check'
        })
    }
    #endregion

    #region Output -----------------------------------------------------------
    # Stable, human-friendly column order for the CSV report.
    $columns = @(
        'ComputerName', 'CollectionStatus', 'OSCaption', 'OSVersion', 'OSBuild',
        'OSDisplayVersion', 'OSInstallDate', 'LastBootUpTime', 'UptimeDays',
        'LastQualityUpdateKB', 'LastQualityUpdateTitle', 'LastQualityUpdateDate',
        'DaysSinceQualityUpdate', 'LastAnyUpdateTitle', 'LastAnyUpdateDate',
        'LastHotFixKB', 'LastHotFixInstalledOn', 'PendingReboot',
        'PendingRebootReasons', 'WU_LastScanSuccess', 'WU_LastInstallSuccess',
        'WSUS_Server', 'WSUS_UseWUServer', 'WSUS_TargetGroup',
        'WUAuServiceStatus', 'WUAuServiceStartMode', 'SaltMinionStatus',
        'SaltMinionVersion', 'RecentUpdates', 'CollectionError'
    )

    $output = $results | Select-Object $columns

    try {
        $output | Export-Csv -Path $script:CsvFile -NoTypeInformation -Encoding UTF8
        Write-Log "CSV report written: $script:CsvFile" -Level SUCCESS
    } catch {
        Write-Log "Failed to write CSV: $($_.Exception.Message)" -Level ERROR
    }

    $ok      = ($results | Where-Object { $_.CollectionStatus -eq 'OK' }).Count
    $pending = ($results | Where-Object { $_.PendingReboot -eq $true }).Count
    $bad     = ($results | Where-Object { $_.CollectionStatus -ne 'OK' }).Count
    Write-Log "Summary: OK=$ok  PendingReboot=$pending  Failed/Offline=$bad  Total=$($results.Count)" -Level INFO
    Write-Log "Script completed." -Level SUCCESS

    # Return objects to the pipeline for further filtering / analysis.
    $output
    #endregion
}
