function Get-DiagPatching {
    <#
    .SYNOPSIS
        Collect patching state: HotFix list, update history, pending reboot, WSUS/WUfB policy, CBS logs, WindowsUpdate ETL traces.

    .DESCRIPTION
        Inventories installed hotfixes via Get-HotFix and queries the last 200 entries of update history through the Microsoft.Update.Session COM object. Probes pending-reboot state from the Component Based Servicing, Windows Update, and Session Manager registry keys, and queries SCCM via the root\ccm\ClientSDK CCM_ClientUtilities.DetermineIfRebootPending CIM method. Reads WSUS/WUfB policy from HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate. Copies the tail of CBS.log and the last two CbsPersist archives, plus up to five recent WindowsUpdate ETL traces.

    .PARAMETER WorkingDirectory
        Root of the staging tree. Artifacts land under summary\ and raw\ inside this path.

    .PARAMETER WindowHours
        Time window in hours for context. Defaults to 24.

    .PARAMETER CbsTailBytes
        Maximum bytes to copy from the end of CBS.log and each CbsPersist archive. Defaults to 50MB. Files smaller than this are copied whole.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with path/category/type/description and per-type metadata), Errors (array of hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagPatching -WorkingDirectory 'C:\ProgramData\DiagBundle\work\bundle-001'

    .NOTES
        Artifacts written:
          summary/patching.json
          raw/cbs/CBS.log                  (50MB tail when oversize)
          raw/cbs/CbsPersist_*.log         (last two archives, 50MB tail each when oversize)
          raw/windowsupdate/*.etl          (up to five most recent traces)

        SCCM detection prefers the CCM WMI path because the HKLM\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData registry key is a known false positive; the registry breadcrumb is consulted only when the WMI call fails.

        The collector never throws. On fatal abort it returns Success=$false with populated Errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter()]
        [int] $WindowHours = 24,

        [Parameter()]
        [long] $CbsTailBytes = 50MB,

        [Parameter()]
        [bool] $SkipNetworkTests = $false,

        [Parameter()]
        [int] $WsusProbeTimeoutSec = 15
    )

    $started = Get-Date
    $result = [pscustomobject]@{
        Success         = $false
        Artifacts       = @()
        Errors          = @()
        DurationSeconds = 0
    }
    $fmt = 'yyyy-MM-ddTHH:mm:ss.fffZ'

    try {
        $hotfixes = @(Invoke-DiagTimed -Collector 'Get-DiagPatching' -Step 'Get-HotFix' -Action {
            Get-HotFix -ErrorAction SilentlyContinue
        } | ForEach-Object {
            [ordered]@{
                hotfix_id    = $_.HotFixID
                description  = $_.Description
                installed_on = if ($_.InstalledOn) { $_.InstalledOn.ToUniversalTime().ToString($fmt) } else { $null }
                installed_by = $_.InstalledBy
            }
        })

        $updateHistory = @()
        try {
            $hist = Invoke-DiagTimed -Collector 'Get-DiagPatching' -Step 'Microsoft.Update.Session.QueryHistory(200)' -Action {
                $session = New-Object -ComObject 'Microsoft.Update.Session'
                $searcher = $session.CreateUpdateSearcher()
                $count = $searcher.GetTotalHistoryCount()
                if ($count -gt 0) {
                    , $searcher.QueryHistory(0, [Math]::Min($count, 200))
                } else {
                    , @()
                }
            }
            if ($hist -and $hist.Count -gt 0) {
                foreach ($h in $hist) {
                    $updateHistory += [ordered]@{
                        title             = $h.Title
                        date_utc          = if ($h.Date) { $h.Date.ToUniversalTime().ToString($fmt) } else { $null }
                        operation         = switch ([int]$h.Operation) { 1 {'Install'} 2 {'Uninstall'} 3 {'Other'} default {'Unknown'} }
                        result_code       = [int]$h.ResultCode
                        hresult           = '0x{0:X8}' -f [int]$h.HResult
                        client_app        = $h.ClientApplicationID
                        server_selection  = [int]$h.ServerSelection
                    }
                }
            }
        }
        catch {
            $result.Errors += @{ collector = 'Get-DiagPatching'; reason = "Update history query failed: $($_.Exception.Message)"; severity = 'warning' }
        }

        $pendingKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        )
        $pendingReboot = [ordered]@{
            cbs_reboot_pending             = [bool](Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
            wu_reboot_required             = [bool](Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
            pending_file_rename            = $false
            pending_file_rename_count      = 0
            pending_file_rename_truncated  = $false
            pending_file_rename_list       = @()
            sccm_pending_reboot            = $false
            keys_present                   = @($pendingKeys | Where-Object { Test-Path $_ })
        }
        # PendingFileRenameOperations is REG_MULTI_SZ. Pairs of "source\0dest\0".
        # Empty dest = delete-on-next-boot. Servicing can queue thousands of these
        # during a CU stage; cap the captured list at 200 entries to bound the
        # summary size, but always record the true count.
        $pfrCap = 200
        try {
            $pfr = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
            if ($pfr -and $pfr.PendingFileRenameOperations) {
                $items = @($pfr.PendingFileRenameOperations)
                $pairs = @()
                for ($i = 0; $i -lt $items.Count; $i += 2) {
                    $src = [string]$items[$i]
                    $dst = if ($i + 1 -lt $items.Count) { [string]$items[$i + 1] } else { '' }
                    $pairs += ,([ordered]@{
                        source      = $src
                        destination = if ([string]::IsNullOrEmpty($dst)) { '' } else { $dst }
                        operation   = if ([string]::IsNullOrEmpty($dst)) { 'delete' } else { 'rename' }
                    })
                }
                $pendingReboot.pending_file_rename       = ($pairs.Count -gt 0)
                $pendingReboot.pending_file_rename_count = $pairs.Count
                if ($pairs.Count -gt $pfrCap) {
                    $pendingReboot.pending_file_rename_truncated = $true
                    $pendingReboot.pending_file_rename_list      = @($pairs[0..($pfrCap - 1)])
                } else {
                    $pendingReboot.pending_file_rename_list      = @($pairs)
                }
            }
        } catch { }

        try {
            $r = Invoke-CimMethod -Namespace 'root\ccm\ClientSDK' -ClassName 'CCM_ClientUtilities' -MethodName 'DetermineIfRebootPending' -ErrorAction Stop
            $pendingReboot.sccm_pending_reboot = ([bool]$r.RebootPending -or [bool]$r.IsHardRebootPending)
        } catch {
            # CCM client absent or method unavailable; fall back to the registry breadcrumb.
            $pendingReboot.sccm_pending_reboot = [bool](Test-Path 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData')
        }

        $wuPolicy = [ordered]@{}
        try {
            $au = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
            $wuPolicy.wsus_server         = if ($au) { $au.WUServer } else { $null }
            $wuPolicy.wsus_status_server  = if ($au) { $au.WUStatusServer } else { $null }
            $wuPolicy.target_group_enabled = if ($au) { $au.TargetGroupEnabled } else { $null }
            $wuPolicy.target_group         = if ($au) { $au.TargetGroup } else { $null }
        } catch { }

        # WUA client state: when did the box last successfully scan, install,
        # report? What is in SoftwareDistribution that suggests stuck downloads?
        $wuClientState = [ordered]@{}
        $lastSearchUtc = $null
        $lastInstallUtc = $null
        try {
            $auCom = New-Object -ComObject 'Microsoft.Update.AutoUpdate'
            if ($auCom.Results.LastSearchSuccessDate) {
                $lastSearchUtc = $auCom.Results.LastSearchSuccessDate.ToUniversalTime().ToString($fmt)
            }
            if ($auCom.Results.LastInstallationSuccessDate) {
                $lastInstallUtc = $auCom.Results.LastInstallationSuccessDate.ToUniversalTime().ToString($fmt)
            }
        } catch {
            # COM blocked / WUA service down. Try registry mirror as fallback.
            try {
                $detect = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect' -ErrorAction Stop
                if ($detect.LastSuccessTime) { $lastSearchUtc = ([DateTime]$detect.LastSuccessTime).ToUniversalTime().ToString($fmt) }
            } catch { }
            try {
                $install = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install' -ErrorAction Stop
                if ($install.LastSuccessTime) { $lastInstallUtc = ([DateTime]$install.LastSuccessTime).ToUniversalTime().ToString($fmt) }
            } catch { }
        }

        $now = Get-Date
        $lastSearchAgeH = if ($lastSearchUtc)  { [int]((($now.ToUniversalTime()) - [DateTime]::Parse($lastSearchUtc).ToUniversalTime()).TotalHours) } else { $null }
        $lastInstallAgeD = if ($lastInstallUtc) { [int]((($now.ToUniversalTime()) - [DateTime]::Parse($lastInstallUtc).ToUniversalTime()).TotalDays) } else { $null }

        $reportingLog = Join-Path $env:windir 'SoftwareDistribution\ReportingEvents.log'
        $reportingAgeH = $null
        $reportingBytes = $null
        if (Test-Path -LiteralPath $reportingLog) {
            try {
                $info = Get-Item -LiteralPath $reportingLog -ErrorAction Stop
                $reportingAgeH = [int](($now - $info.LastWriteTime).TotalHours)
                $reportingBytes = $info.Length
            } catch { }
        }

        $downloadDir = Join-Path $env:windir 'SoftwareDistribution\Download'
        $dlSize = 0L
        $dlCount = 0
        $dlOldestAgeD = $null
        $dlNewestAgeD = $null
        if (Test-Path -LiteralPath $downloadDir) {
            try {
                $dlFiles = @(Get-ChildItem -Path $downloadDir -Recurse -File -ErrorAction SilentlyContinue)
                $dlCount = $dlFiles.Count
                if ($dlCount -gt 0) {
                    $dlSize = ($dlFiles | Measure-Object -Property Length -Sum).Sum
                    $oldestMtime = ($dlFiles | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime
                    $newestMtime = ($dlFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
                    $dlOldestAgeD = [int](($now - $oldestMtime).TotalDays)
                    $dlNewestAgeD = [int](($now - $newestMtime).TotalDays)
                }
            } catch { }
        }

        $datastoreEdb = Join-Path $env:windir 'SoftwareDistribution\DataStore\DataStore.edb'
        $datastoreSize = $null
        $datastoreAgeH = $null
        if (Test-Path -LiteralPath $datastoreEdb) {
            try {
                $info = Get-Item -LiteralPath $datastoreEdb -ErrorAction Stop
                $datastoreSize = $info.Length
                $datastoreAgeH = [int](($now - $info.LastWriteTime).TotalHours)
            } catch { }
        }

        # Cross-reference install_stale against update_history. WUA's
        # LastInstallationSuccessDate only ticks on direct WUA installs --
        # on WSUS- or SCCM-managed boxes it permanently shows the OS install
        # date, which would falsely trip install_stale even though the box
        # is patching fine via another path.
        $cutoff60 = (Get-Date).ToUniversalTime().AddDays(-60)
        $recentSuccessfulInstalls = 0
        foreach ($h in $updateHistory) {
            if ($h.operation -eq 'Install' -and [int]$h.result_code -eq 2 -and $h.date_utc) {
                try {
                    $when = [DateTime]::Parse($h.date_utc).ToUniversalTime()
                    if ($when -ge $cutoff60) { $recentSuccessfulInstalls++ }
                } catch { }
            }
        }
        $installPath = if ($recentSuccessfulInstalls -gt 0) {
            if ($null -ne $lastInstallAgeD -and $lastInstallAgeD -gt 60) { 'wsus_or_sccm' } else { 'wua_direct' }
        } else { 'unknown' }

        # download_stuck_likely: focus on the "stuck" window (7-30 days old).
        # Older files are residue/cruft, not active stuck downloads. Newer
        # files might be in-progress and should not trigger.
        $dlStuckBytes = 0L
        $dlStuckCount = 0
        if (Test-Path -LiteralPath $downloadDir) {
            try {
                $dlStuck = @(Get-ChildItem -Path $downloadDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                    $age = ($now - $_.LastWriteTime).TotalDays
                    $age -ge 7 -and $age -le 30
                })
                $dlStuckCount = $dlStuck.Count
                if ($dlStuckCount -gt 0) {
                    $dlStuckBytes = ($dlStuck | Measure-Object -Property Length -Sum).Sum
                }
            } catch { }
        }

        $flags = [ordered]@{
            scan_stale            = ($null -ne $lastSearchAgeH  -and $lastSearchAgeH  -gt 48)
            install_stale         = ($null -ne $lastInstallAgeD -and $lastInstallAgeD -gt 60 -and $recentSuccessfulInstalls -eq 0)
            download_stuck_likely = ($dlStuckBytes -gt 50MB)
            wsus_reporting_stale  = ([bool]$wuPolicy.wsus_server -and $null -ne $reportingAgeH -and $reportingAgeH -gt 48)
        }

        $wuClientState = [ordered]@{
            last_search_success_utc          = $lastSearchUtc
            last_search_age_hours            = $lastSearchAgeH
            last_install_success_utc         = $lastInstallUtc
            last_install_age_days            = $lastInstallAgeD
            recent_successful_installs_60d   = $recentSuccessfulInstalls
            install_path                     = $installPath
            reporting_events_log_age_hours   = $reportingAgeH
            reporting_events_log_bytes       = $reportingBytes
            download_dir_size_bytes          = $dlSize
            download_dir_file_count          = $dlCount
            download_dir_oldest_age_days     = $dlOldestAgeD
            download_dir_newest_age_days     = $dlNewestAgeD
            download_dir_stuck_window_bytes  = $dlStuckBytes
            download_dir_stuck_window_count  = $dlStuckCount
            datastore_edb_size_bytes         = $datastoreSize
            datastore_edb_age_hours          = $datastoreAgeH
            flags                            = $flags
        }

        # Copy ReportingEvents.log (tail to 1MB if oversize). FileShare.ReadWrite
        # because WUA may have it open.
        if (Test-Path -LiteralPath $reportingLog) {
            try {
                Invoke-DiagTimed -Collector 'Get-DiagPatching' -Step 'copy ReportingEvents.log' -Action {
                    $dest = Join-Path $WorkingDirectory 'raw\windowsupdate\ReportingEvents.log'
                    $info = Get-Item -LiteralPath $reportingLog
                    $tailCap = 1MB
                    $src = [System.IO.File]::Open($reportingLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        if ($info.Length -gt $tailCap) {
                            [void]$src.Seek($info.Length - $tailCap, [System.IO.SeekOrigin]::Begin)
                            $script:_diagReportingDesc = "Tail of WUA reporting events log (last $tailCap bytes of $($info.Length))"
                        } else {
                            $script:_diagReportingDesc = "WUA reporting events log"
                        }
                        $dst = [System.IO.File]::Open($dest, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                        try { $src.CopyTo($dst) } finally { $dst.Dispose() }
                    } finally { $src.Dispose() }
                }
                $result.Artifacts += @{
                    path        = 'raw/windowsupdate/ReportingEvents.log'
                    category    = 'wua_reporting_events'
                    type        = 'raw'
                    description = $script:_diagReportingDesc
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagPatching'; artifact = 'raw/windowsupdate/ReportingEvents.log'; reason = $_.Exception.Message; severity = 'warning' }
            }
        }

        # WSUS interrogation (TCP + WSDL + iuident + SelfUpdate) -- only if a
        # WSUS server is configured AND network tests are not skipped.
        $wsusCheck = [ordered]@{}
        if ($SkipNetworkTests) {
            $wsusCheck = [ordered]@{ url = $wuPolicy.wsus_server; verdict = 'skipped_by_parameter' }
        } elseif (-not $wuPolicy.wsus_server) {
            $wsusCheck = [ordered]@{ url = $null; verdict = 'no_wsus_configured' }
        } else {
            $wsusCheck = Invoke-DiagTimed -Collector 'Get-DiagPatching' -Step "WSUS probe ($($wuPolicy.wsus_server))" -Action {
                _ProbeDiagWsus -BaseUrl $wuPolicy.wsus_server -TimeoutSec $WsusProbeTimeoutSec
            }
        }

        $data = [ordered]@{
            schema_version = '1.1'
            host = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data = [ordered]@{
                hotfixes_count       = $hotfixes.Count
                hotfixes             = $hotfixes
                update_history_count = $updateHistory.Count
                update_history       = $updateHistory
                pending_reboot       = $pendingReboot
                wu_policy            = $wuPolicy
                wu_client_state      = $wuClientState
                wsus_check           = $wsusCheck
            }
        }

        $path = Join-Path $WorkingDirectory 'summary\patching.json'
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))

        $result.Artifacts += @{
            path           = 'summary/patching.json'
            category       = 'patching'
            schema_version = '1.1'
            type           = 'derived'
            description    = 'HotFix, update history, pending reboot, WSUS policy + client state, WSUS server probe'
            row_count      = $hotfixes.Count + $updateHistory.Count
        }

        $cbs = Join-Path $env:windir 'Logs\CBS\CBS.log'
        if (Test-Path -LiteralPath $cbs) {
            try {
                $info = Get-Item -LiteralPath $cbs
                $dest = Join-Path $WorkingDirectory 'raw\cbs\CBS.log'
                Invoke-DiagTimed -Collector 'Get-DiagPatching' -Step "copy CBS.log ($([math]::Round($info.Length/1MB,1))MB)" -Action {
                    if ($info.Length -le $CbsTailBytes) {
                        Copy-Item -LiteralPath $cbs -Destination $dest -Force
                    } else {
                        $fs = [System.IO.File]::Open($cbs, 'Open', 'Read', 'ReadWrite')
                        try {
                            $fs.Seek($info.Length - $CbsTailBytes, 'Begin') | Out-Null
                            $out = [System.IO.File]::Open($dest, 'Create', 'Write')
                            try { $fs.CopyTo($out) } finally { $out.Dispose() }
                        } finally { $fs.Dispose() }
                    }
                }
                $result.Artifacts += @{
                    path        = 'raw/cbs/CBS.log'
                    category    = 'cbs_log'
                    type        = 'raw'
                    description = if ($info.Length -gt $CbsTailBytes) { "Tail of CBS.log (last $CbsTailBytes bytes)" } else { 'CBS.log' }
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagPatching'; artifact = 'raw/cbs/CBS.log'; reason = $_.Exception.Message; severity = 'warning' }
            }
        }

        $cbsArchives = Get-ChildItem -Path (Join-Path $env:windir 'Logs\CBS') -Filter 'CbsPersist_*.log' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 2
        foreach ($a in $cbsArchives) {
            try {
                $dest = Join-Path $WorkingDirectory ('raw\cbs\' + $a.Name)
                if ($a.Length -le $CbsTailBytes) {
                    Copy-Item -LiteralPath $a.FullName -Destination $dest -Force
                    $desc = 'Recent CbsPersist archive'
                } else {
                    $fs = [System.IO.File]::Open($a.FullName, 'Open', 'Read', 'ReadWrite')
                    try {
                        $fs.Seek($a.Length - $CbsTailBytes, 'Begin') | Out-Null
                        $out = [System.IO.File]::Open($dest, 'Create', 'Write')
                        try { $fs.CopyTo($out) } finally { $out.Dispose() }
                    } finally { $fs.Dispose() }
                    $desc = "Tail of CbsPersist archive (last $CbsTailBytes bytes)"
                }
                $result.Artifacts += @{
                    path        = "raw/cbs/$($a.Name)"
                    category    = 'cbs_archive'
                    type        = 'raw'
                    description = $desc
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagPatching'; artifact = "raw/cbs/$($a.Name)"; reason = $_.Exception.Message; severity = 'warning' }
            }
        }

        $wuLogDir = Join-Path $env:windir 'Logs\WindowsUpdate'
        if (Test-Path -LiteralPath $wuLogDir) {
            $etls = Get-ChildItem -Path $wuLogDir -Filter '*.etl' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 5
            foreach ($e in $etls) {
                try {
                    $dest = Join-Path $WorkingDirectory ('raw\windowsupdate\' + $e.Name)
                    Copy-Item -LiteralPath $e.FullName -Destination $dest -Force
                    $result.Artifacts += @{
                        path        = "raw/windowsupdate/$($e.Name)"
                        category    = 'windowsupdate_etl'
                        type        = 'raw'
                        description = 'WindowsUpdate ETL trace'
                    }
                } catch {
                    $result.Errors += @{ collector = 'Get-DiagPatching'; artifact = "raw/windowsupdate/$($e.Name)"; reason = $_.Exception.Message; severity = 'warning' }
                }
            }
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagPatching'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
