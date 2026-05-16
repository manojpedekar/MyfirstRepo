function _ResolveEventMessage {
    <#
    .SYNOPSIS
        Render an event's message text, falling back to joined EventData
        when the formatted message is empty.
    .DESCRIPTION
        Get-WinEvent renders the event message via the provider's localized
        message resource. When the provider's binary registration is
        missing on this host (third-party providers, providers shipped by
        an installer that did not register message resources, etc.) the
        $Event.Message field comes back empty even though the EventData
        block contains the actual content.

        Gap 13 fix (2026-05-11 review, D9 path): when Message is empty,
        return the joined EventData property values as a usable
        substitute. Confirmed against raw EVTX for the `cloudbase-init`
        provider: Message empty, EventData carried "cloudbase-init",
        "Stopping service" / "Starting service" / "Child process ended".
    .PARAMETER Event
        Event record (typically Get-WinEvent output).
    .PARAMETER MaxChars
        Max chars to retain. 0 = no truncation.
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Event,
        [Parameter()] [int] $MaxChars = 400
    )

    $text = $null
    if ($Event.Message -and -not [string]::IsNullOrWhiteSpace($Event.Message)) {
        $text = ($Event.Message -split "`r?`n")[0]
    } else {
        try {
            $parts = @($Event.Properties | ForEach-Object { [string]$_.Value } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($parts.Count -gt 0) {
                $text = ($parts -join ' | ')
            }
        } catch { }
    }
    if (-not $text) { return '' }
    if ($MaxChars -gt 0 -and $text.Length -gt $MaxChars) {
        return $text.Substring(0, $MaxChars)
    }
    return $text
}

function Get-DiagEventLogs {
    <#
    .SYNOPSIS
        Export filtered EVTX files for a fixed channel set and emit a summary JSON with counts, top events, timeline buckets, and boot markers.

    .DESCRIPTION
        For each target channel, runs wevtutil epl to produce a per-channel EVTX in raw\eventlogs\, then queries the same window with Get-WinEvent to build per-channel aggregates: total/error/warning counts, top 50 EventID+Provider groups with first/last timestamps and a representative message, a 5-minute timeline histogram, and (System only) boot markers for event IDs 6005, 6006, 6008, and 1074. Boot markers are never truncated. Channel names with a forward slash are mapped to the on-disk form by replacing '/' with '%4'. Channels missing from Get-WinEvent -ListLog are skipped at info severity. The Get-WinEvent message "No events were found" inside the window is treated as empty and is not an error.

        Channels marked SummaryMode='minimal' (currently Security only) skip the per-event aggregation entirely. Get-WinEvent's per-record materialization dominates the runtime on busy logs (measured 645+ seconds on a 192MB / 323k-event Security log) and the resulting top-events / timeline aggregates have low diagnostic value for Security specifically: the top events are always 4624/4634 logon noise and the 5-minute timeline is always saturated. In minimal mode the collector emits only channel metadata (live-log RecordCount + FileSize, raw artifact path, drill-down hint). The raw EVTX is still exported with the standard XPath time filter, so the agent can run wevtutil qe queries against it for any actual investigation. Aggregation cost on busy Security logs drops from ~10 minutes to a few seconds.

    .PARAMETER WorkingDirectory
        Root of the staging tree. Artifacts land under summary\ and raw\eventlogs\ inside this path.

    .PARAMETER WindowHours
        Lookback in hours from now for both the EVTX XPath filter and the summary aggregation. Defaults to 24.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with path/category/type/description and per-type metadata), Errors (array of hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagEventLogs -WorkingDirectory 'C:\ProgramData\DiagBundle\work\bundle-001' -WindowHours 48

    .NOTES
        Channels collected (10 base, plus auto-discovered platform-specific):
          System
          Application
          Security
          Setup
          Microsoft-Windows-WindowsUpdateClient/Operational
          Microsoft-Windows-Servicing/Operational
          Microsoft-Windows-Kernel-PnP/Configuration
          Microsoft-Windows-Kernel-Boot/Operational
          Microsoft-Windows-WMI-Activity/Operational
          Microsoft-Windows-PrintService/Operational

        On a virtualized guest, additional channels matching the detected
        hypervisor are auto-added when present and non-empty (e.g.
        Microsoft-Windows-Hyper-V-* on Hyper-V, VMware/* on VMware Tools
        hosts that publish them). Detection reuses Win32_ComputerSystem
        manufacturer signatures.

        Artifacts written:
          summary/events_summary.json
          raw/eventlogs/<channel>.evtx     (one per present channel; '/' becomes '%4')

        events_summary.json schema 1.1 adds:
          - data.detected_platform: 'vmware' | 'hyperv' | 'kvm' | 'xen' | 'aws' | 'unknown'
          - data.interesting_providers: flat index of (channel, event_id, provider, count, first_utc, last_utc, level, message) for providers that may fall below per-channel top-50 truncation. Sourced from base provider list plus the detected hypervisor's contribution. Always populated; empty array when nothing matched.

        Emits a child Write-Progress (Id=2 -ParentId 1) per channel for orchestrator UI nesting.

        The collector never throws. On fatal abort it returns Success=$false with populated Errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter()]
        [int] $WindowHours = 24
    )

    $started = Get-Date
    $result = [pscustomobject]@{
        Success         = $false
        Artifacts       = @()
        Errors          = @()
        DurationSeconds = 0
    }
    $fmt    = 'yyyy-MM-ddTHH:mm:ss.fffZ'
    $nowUtc = (Get-Date).ToUniversalTime()
    $fromUtc = $nowUtc.AddHours(-$WindowHours)

    # Per-channel knobs.
    #   Critical    = $true means a wevtutil export failure for this channel
    #                 surfaces as 'error' severity (otherwise 'info').
    #   SummaryMode = 'full' (default) builds the standard top-events,
    #                 timeline, and boot-markers aggregate by reading every
    #                 event in the window via Get-WinEvent.
    #               = 'minimal' skips the per-event scan and emits only
    #                 channel metadata. Use for channels where the scan cost
    #                 dominates and the aggregate has low value (Security).
    #                 Raw EVTX is still exported.
    $channels = @(
        @{ Name = 'System';                                                          Critical = $true;  SummaryMode = 'full'    }
        @{ Name = 'Application';                                                     Critical = $true;  SummaryMode = 'full'    }
        @{ Name = 'Security';                                                        Critical = $false; SummaryMode = 'minimal' }
        @{ Name = 'Setup';                                                           Critical = $true;  SummaryMode = 'full'    }
        @{ Name = 'Microsoft-Windows-WindowsUpdateClient/Operational';               Critical = $true;  SummaryMode = 'full'    }
        @{ Name = 'Microsoft-Windows-Servicing/Operational';                         Critical = $true;  SummaryMode = 'full'    }
        @{ Name = 'Microsoft-Windows-Kernel-PnP/Configuration';                      Critical = $false; SummaryMode = 'full'    }
        @{ Name = 'Microsoft-Windows-Kernel-Boot/Operational';                       Critical = $false; SummaryMode = 'full'    }
        @{ Name = 'Microsoft-Windows-WMI-Activity/Operational';                      Critical = $false; SummaryMode = 'full'    }
        @{ Name = 'Microsoft-Windows-PrintService/Operational';                      Critical = $false; SummaryMode = 'full'    }
    )

    # Per-platform EVTX registry. Each row supplies the manufacturer signatures
    # for detection (Win32_ComputerSystem.Manufacturer matched with -like),
    # additional channel-discovery globs queried via Get-WinEvent -ListLog,
    # and the provider names whose events should always be surfaced regardless
    # of per-channel top-50 truncation. Adding a new hypervisor is a single new
    # row. The detection logic intentionally duplicates A22's
    # Get-DiagRoleHypervisor table because EventLogs runs before Roles in the
    # dispatch order and cannot read A22's output. Refactor candidates noted in
    # docs/plans.
    $hvEvtxRegistry = @(
        @{
            Platform                   = 'vmware'
            ManufacturerLike           = @('VMware*')
            ChannelDiscovery           = @('VMware*', 'Microsoft-Windows-VMware*', 'Applications and Services Logs/VMware/*')
            InterestingProviders       = @('VMUpgradeHelper','VMTools','VGAuthService','vmci','vmxnet3','vmxnet3ndis6','pvscsi','vsock','vm3dmp')
        }
        @{
            Platform                   = 'hyperv'
            ManufacturerLike           = @('Microsoft Corporation')
            ChannelDiscovery           = @('Microsoft-Windows-Hyper-V-*', 'Microsoft-Windows-VHDMP*')
            InterestingProviders       = @('Microsoft-Windows-Hyper-V-Integration-*','Microsoft-Windows-Hyper-V-VID*','Microsoft-Windows-Hyper-V-Worker-*','Microsoft-Windows-Hyper-V-VmSwitch-*','vmbus','VMBus','vmbusr','netvsc','storvsc','VMICTimeProvider')
        }
        @{
            Platform                   = 'kvm'
            ManufacturerLike           = @('Red Hat*','QEMU*','Bochs')
            ChannelDiscovery           = @('Microsoft-Windows-Hyper-V-Integration-*')
            InterestingProviders       = @('viostor','vioscsi','netkvm','vioser','vioinput','balloon','viogpudo','viorng','qemu-ga','QemuGA','virtio-win-installer')
        }
        @{
            Platform                   = 'xen'
            ManufacturerLike           = @('Xen*')
            ChannelDiscovery           = @()
            InterestingProviders       = @('xenbus','xenvbd','xennet','xenvif')
        }
        @{
            Platform                   = 'aws'
            ManufacturerLike           = @('Amazon*')
            ChannelDiscovery           = @()
            InterestingProviders       = @('EC2Config','AmazonSSMAgent','EC2Launch')
        }
    )

    # Always-on (non-platform-specific) providers. Surface these regardless of
    # per-channel top-50 cutoff because their events are typically low-volume
    # but high-signal during patch / boot / WU investigations.
    $baseInterestingProviders = @(
        'TrustedInstaller','CBS','WindowsUpdateClient',
        'Microsoft-Windows-Servicing','Microsoft-Windows-WindowsUpdateClient',
        'Microsoft-Windows-WER-SystemErrorReporting',
        'Microsoft-Windows-Wininit','Microsoft-Windows-Winlogon',
        'Microsoft-Windows-User Profile Service',
        'Microsoft-Windows-Kernel-Power','Microsoft-Windows-Kernel-Boot',
        'EventLog','User32','Service Control Manager'
    )

    $bootMarkerIds = 6005, 6006, 6008, 1074

    function _ChannelFile([string]$channelName) {
        ($channelName -replace '/', '%4') + '.evtx'
    }

    try {
        $availableChannels = @{}
        try {
            Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
                $availableChannels[$_.LogName] = $true
            }
        } catch { }

        # Hypervisor detection. One CIM call. Match the first row whose
        # manufacturer pattern matches; ties are unlikely because the patterns
        # are mutually exclusive in practice.
        $platformRow = $null
        $detectedPlatform = 'unknown'
        try {
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            if ($cs) {
                foreach ($row in $hvEvtxRegistry) {
                    foreach ($pat in @($row.ManufacturerLike) | Where-Object { $_ }) {
                        if ($cs.Manufacturer -like $pat) {
                            $platformRow = $row
                            $detectedPlatform = $row.Platform
                            break
                        }
                    }
                    if ($platformRow) { break }
                }
            }
        } catch {
            $result.Errors += @{
                collector = 'Get-DiagEventLogs'
                reason    = "Win32_ComputerSystem read failed during hypervisor detection: $($_.Exception.Message)"
                severity  = 'info'
            }
        }

        # Discover platform-specific channels. Iterate the hypervisor's
        # ChannelDiscovery globs against Get-WinEvent -ListLog. Only add
        # channels with non-zero RecordCount -- empty channels add no value
        # and would only inflate the bundle.
        if ($platformRow -and @($platformRow.ChannelDiscovery).Count -gt 0) {
            $discovered = @()
            foreach ($glob in @($platformRow.ChannelDiscovery)) {
                try {
                    $matches = Get-WinEvent -ListLog $glob -ErrorAction SilentlyContinue |
                        Where-Object { $_.RecordCount -gt 0 }
                    foreach ($m in @($matches)) {
                        # Skip entries already in the base channel list to
                        # avoid duplicate processing.
                        $alreadyListed = $false
                        foreach ($existing in $channels) {
                            if ($existing.Name -eq $m.LogName) { $alreadyListed = $true; break }
                        }
                        if (-not $alreadyListed) {
                            $discovered += @{ Name = $m.LogName; Critical = $false; SummaryMode = 'full' }
                        }
                    }
                } catch { }
            }
            if (@($discovered).Count -gt 0) {
                $channels += $discovered
                Write-DiagLog -Severity info -Collector 'Get-DiagEventLogs' `
                    -Message ("Added {0} {1}-published channels: {2}" -f @($discovered).Count, $detectedPlatform, (@($discovered | ForEach-Object { $_.Name }) -join ', '))
            }
        }

        # Compose the final interesting-providers list for the post-loop pass.
        # Base list is always present; platform contribution merges on top.
        $interestingProviders = @($baseInterestingProviders)
        if ($platformRow) {
            $interestingProviders += @($platformRow.InterestingProviders)
        }
        $interestingProviders = @($interestingProviders | Sort-Object -Unique)

        $perChannel = @()
        $chIndex = 0
        $chTotal = $channels.Count

        # Stash the loaded System events for the boot-timeline pass after the
        # per-channel loop. Keeps memory bounded (one channel's events at a
        # time) but avoids a second Get-WinEvent call against System.
        $systemEventsForTimeline = $null

        foreach ($c in $channels) {
            $chIndex++
            $name = $c.Name
            $critical = $c.Critical
            $summaryMode = if ($c.ContainsKey('SummaryMode')) { [string]$c.SummaryMode } else { 'full' }
            $rawName  = _ChannelFile $name
            $rawPath  = Join-Path $WorkingDirectory ('raw\eventlogs\' + $rawName)

            Write-Progress -Id 2 -ParentId 1 -Activity 'EventLogs' -Status "[$chIndex/$chTotal] $name" -PercentComplete ([int](($chIndex / $chTotal) * 100))

            if (-not $availableChannels.ContainsKey($name)) {
                $result.Errors += @{
                    collector = 'Get-DiagEventLogs'
                    artifact  = "raw/eventlogs/$rawName"
                    reason    = "channel not present on this host"
                    severity  = 'info'
                }
                continue
            }

            $fromIso = $fromUtc.ToString('yyyy-MM-ddTHH:mm:ss.000Z')
            $toIso   = $nowUtc.ToString('yyyy-MM-ddTHH:mm:ss.000Z')
            $xpath   = "*[System[TimeCreated[@SystemTime>='$fromIso' and @SystemTime<='$toIso']]]"

            $exitOk = $true
            try {
                $stderr = Invoke-DiagTimed -Collector 'Get-DiagEventLogs' -Step "wevtutil epl $name" -Action { & wevtutil epl $name $rawPath "/q:$xpath" /ow:true 2>&1 }
                if ($LASTEXITCODE -ne 0) {
                    $exitOk = $false
                    $sev = if ($critical) { 'error' } else { 'info' }
                    $result.Errors += @{
                        collector = 'Get-DiagEventLogs'
                        artifact  = "raw/eventlogs/$rawName"
                        reason    = "wevtutil epl exit ${LASTEXITCODE}: $($stderr -join '; ')"
                        severity  = $sev
                    }
                }
            } catch {
                $exitOk = $false
                $result.Errors += @{
                    collector = 'Get-DiagEventLogs'
                    artifact  = "raw/eventlogs/$rawName"
                    reason    = $_.Exception.Message
                    severity  = if ($critical) { 'error' } else { 'info' }
                }
            }

            if ($exitOk -and (Test-Path -LiteralPath $rawPath)) {
                $artifact = [ordered]@{
                    path            = "raw/eventlogs/$rawName"
                    category        = 'eventlog_raw'
                    type            = 'raw'
                    channel         = $name
                    events_from_utc = $fromUtc.ToString($fmt)
                    events_to_utc   = $nowUtc.ToString($fmt)
                    description     = "EVTX export for channel $name (window-filtered)"
                }
                if ($summaryMode -eq 'minimal') { $artifact['summary_mode'] = 'minimal' }
                $result.Artifacts += $artifact
            }

            # Minimal-summary channels (Security): skip the per-event scan
            # entirely. The raw EVTX is already exported above; emit a tiny
            # metadata-only summary block so the agent knows the channel was
            # collected and where to find the raw file. Pull RecordCount and
            # FileSize from Get-WinEvent -ListLog (live log metadata, O(1) --
            # not a scan).
            if ($summaryMode -eq 'minimal') {
                $liveCount = $null
                $liveBytes = $null
                $liveOldest = $null
                try {
                    $logInfo = Invoke-DiagTimed -Collector 'Get-DiagEventLogs' -Step "Get-WinEvent -ListLog $name (minimal)" -Action {
                        Get-WinEvent -ListLog $name -ErrorAction Stop
                    }
                    if ($logInfo) {
                        $liveCount  = [long]$logInfo.RecordCount
                        $liveBytes  = [long]$logInfo.FileSize
                        $liveOldest = if ($logInfo.OldestRecordNumber) { [long]$logInfo.OldestRecordNumber } else { $null }
                    }
                } catch { }

                $perChannel += [ordered]@{
                    channel                  = $name
                    summary_mode             = 'minimal_metadata_only'
                    total                    = $null
                    error_count              = $null
                    warning_count            = $null
                    top_events               = @()
                    timeline_5min            = @()
                    boot_markers             = @()
                    live_log_record_count    = $liveCount
                    live_log_file_size_bytes = $liveBytes
                    live_log_oldest_record_number = $liveOldest
                    raw_artifact             = "raw/eventlogs/$rawName"
                    note                     = "Per-event aggregation skipped for $name (Get-WinEvent scan dominates total runtime; ~10 min on busy hosts). Run wevtutil qe against the raw EVTX for drill-down: see README 'Drill-down recipes' -> EVTX."
                }
                continue
            }

            $events = @()
            try {
                $events = @(Invoke-DiagTimed -Collector 'Get-DiagEventLogs' -Step "Get-WinEvent $name (window scan)" -Action {
                    Get-WinEvent -FilterHashtable @{
                        LogName   = $name
                        StartTime = $fromUtc.ToLocalTime()
                        EndTime   = $nowUtc.ToLocalTime()
                    } -ErrorAction Stop
                })
            } catch [System.Exception] {
                # "No events were found" is non-fatal: empty channel for the window.
                if ($_.Exception.Message -notlike '*No events were found*') {
                    if ($critical) {
                        $result.Errors += @{
                            collector = 'Get-DiagEventLogs'
                            artifact  = "summary entry for $name"
                            reason    = $_.Exception.Message
                            severity  = 'warning'
                        }
                    }
                }
            }

            $errorCount   = ($events | Where-Object { $_.LevelDisplayName -eq 'Error' }   | Measure-Object).Count
            $warningCount = ($events | Where-Object { $_.LevelDisplayName -eq 'Warning' } | Measure-Object).Count

            $topByCount = $events | Group-Object -Property Id, ProviderName |
                Sort-Object -Property Count -Descending |
                Select-Object -First 50 |
                ForEach-Object {
                    $first = $_.Group | Sort-Object TimeCreated | Select-Object -First 1
                    $last  = $_.Group | Sort-Object TimeCreated | Select-Object -Last 1
                    [ordered]@{
                        event_id   = $first.Id
                        provider   = $first.ProviderName
                        count      = $_.Count
                        first_utc  = $first.TimeCreated.ToUniversalTime().ToString($fmt)
                        last_utc   = $last.TimeCreated.ToUniversalTime().ToString($fmt)
                        level      = $first.LevelDisplayName
                        message    = _ResolveEventMessage -Event $first -MaxChars 400
                    }
                }

            $timeline = $events |
                Group-Object -Property { $_.TimeCreated.ToUniversalTime().AddMinutes(-($_.TimeCreated.Minute % 5)).ToString('yyyy-MM-ddTHH:mm:00Z') } |
                Sort-Object Name |
                ForEach-Object { [ordered]@{ bucket_utc = $_.Name; count = $_.Count } }

            $bootMarkers = @()
            if ($name -eq 'System') {
                $bootMarkers = $events | Where-Object { $bootMarkerIds -contains $_.Id } |
                    Sort-Object TimeCreated |
                    ForEach-Object {
                        [ordered]@{
                            event_id  = $_.Id
                            time_utc  = $_.TimeCreated.ToUniversalTime().ToString($fmt)
                            provider  = $_.ProviderName
                            message   = _ResolveEventMessage -Event $_ -MaxChars 0
                        }
                    }
            }

            if ($name -eq 'System') {
                $systemEventsForTimeline = $events
            }

            $perChannel += [ordered]@{
                channel        = $name
                total          = $events.Count
                error_count    = $errorCount
                warning_count  = $warningCount
                top_events     = @($topByCount)
                timeline_5min  = @($timeline)
                boot_markers   = @($bootMarkers)
            }
        }

        # Build the interesting-providers index. Two sources:
        #
        #   1. Existing per-channel top_events: any entry whose provider
        #      matches one of $interestingProviders gets pulled into the flat
        #      index, regardless of its rank in the per-channel top-50.
        #
        #   2. Targeted re-scan with -ProviderName: catches sub-top-50
        #      providers that fell off the per-channel cutoff. Bounded to
        #      MaxEvents 200 per channel; "no events were found" is normal
        #      and silent.
        #
        # Dedupe by (channel, event_id, provider). The result is always an
        # array (possibly empty).
        $providerIndex = @()
        $providerIndexKeys = @{}
        foreach ($ch in $perChannel) {
            if ($ch.summary_mode -eq 'minimal_metadata_only') { continue }
            foreach ($evt in @($ch.top_events)) {
                $matched = $false
                foreach ($pat in $interestingProviders) {
                    if ($evt.provider -like $pat) { $matched = $true; break }
                }
                if ($matched) {
                    $key = '{0}|{1}|{2}' -f $ch.channel, $evt.event_id, $evt.provider
                    if (-not $providerIndexKeys.ContainsKey($key)) {
                        $providerIndexKeys[$key] = $true
                        $entry = [ordered]@{
                            channel    = $ch.channel
                            event_id   = $evt.event_id
                            provider   = $evt.provider
                            count      = $evt.count
                            first_utc  = $evt.first_utc
                            last_utc   = $evt.last_utc
                            level      = $evt.level
                            message    = $evt.message
                            source     = 'top_events'
                        }
                        $providerIndex += ,$entry
                    }
                }
            }
        }

        # Targeted re-scan to catch sub-top-50 entries from interesting
        # providers. Skip channels that ran in minimal mode (Security): a
        # rescan there would defeat the purpose of skipping aggregation.
        foreach ($ch in $perChannel) {
            if ($ch.summary_mode -eq 'minimal_metadata_only') { continue }
            try {
                $extra = Invoke-DiagTimed -Collector 'Get-DiagEventLogs' -Step "interesting-providers rescan $($ch.channel)" -Action {
                    Get-WinEvent -FilterHashtable @{
                        LogName      = $ch.channel
                        ProviderName = $interestingProviders
                        StartTime    = $fromUtc.ToLocalTime()
                        EndTime      = $nowUtc.ToLocalTime()
                    } -MaxEvents 200 -ErrorAction Stop
                }
                $grouped = $extra | Group-Object -Property Id, ProviderName
                foreach ($g in @($grouped)) {
                    $first = $g.Group | Sort-Object TimeCreated | Select-Object -First 1
                    $last  = $g.Group | Sort-Object TimeCreated | Select-Object -Last 1
                    $key = '{0}|{1}|{2}' -f $ch.channel, $first.Id, $first.ProviderName
                    if (-not $providerIndexKeys.ContainsKey($key)) {
                        $providerIndexKeys[$key] = $true
                        $msg = _ResolveEventMessage -Event $first -MaxChars 400
                        $entry = [ordered]@{
                            channel    = $ch.channel
                            event_id   = $first.Id
                            provider   = $first.ProviderName
                            count      = $g.Count
                            first_utc  = $first.TimeCreated.ToUniversalTime().ToString($fmt)
                            last_utc   = $last.TimeCreated.ToUniversalTime().ToString($fmt)
                            level      = $first.LevelDisplayName
                            message    = $msg
                            source     = 'rescan'
                        }
                        $providerIndex += ,$entry
                    }
                }
            } catch {
                # "No events were found" inside the window is normal and not
                # an error condition for the index. Anything else gets logged
                # at info severity (not warning) because the index is best-
                # effort secondary signal.
                if ($_.Exception.Message -notlike '*No events were found*') {
                    $result.Errors += @{
                        collector = 'Get-DiagEventLogs'
                        artifact  = "summary/events_summary.json:interesting_providers ($($ch.channel))"
                        reason    = $_.Exception.Message
                        severity  = 'info'
                    }
                }
            }
        }

        $data = [ordered]@{
            schema_version    = '1.1'
            host              = @{ computer_name = $env:COMPUTERNAME }
            collected_utc     = (Get-Date).ToUniversalTime().ToString($fmt)
            window            = [ordered]@{
                from_utc     = $fromUtc.ToString($fmt)
                to_utc       = $nowUtc.ToString($fmt)
                window_hours = $WindowHours
            }
            detected_platform     = $detectedPlatform
            interesting_providers = @($providerIndex)
            channels              = $perChannel
        }

        $sumPath = Join-Path $WorkingDirectory 'summary\events_summary.json'
        $json = $data | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($sumPath, $json, [System.Text.UTF8Encoding]::new($false))

        $result.Artifacts += @{
            path             = 'summary/events_summary.json'
            category         = 'events_summary'
            schema_version   = '1.1'
            type             = 'derived'
            description      = "Per-channel counts, top EventID/Provider (50), 5-min timeline, boot markers, hypervisor-aware interesting-provider index; window $WindowHours h"
            source_artifacts = @($perChannel | ForEach-Object { "raw/eventlogs/" + (_ChannelFile $_.channel) })
            row_count        = (@($perChannel | ForEach-Object { [int]$_.total }) | Measure-Object -Sum).Sum
        }

        # Boot timeline pass: derive per-boot records, gaps, and anomalies from
        # the System events already loaded above. Failure here must not abort
        # the overall collector -- log a warning and continue.
        if ($null -ne $systemEventsForTimeline) {
            try {
                $tz = Get-DiagTimezone -WindowHours $WindowHours
                $tl = Build-DiagBootTimeline -SystemEvents $systemEventsForTimeline -FromUtc $fromUtc -ToUtc $nowUtc

                $tlData = [ordered]@{
                    schema_version    = '1.0'
                    host              = @{ computer_name = $env:COMPUTERNAME }
                    collected_utc     = (Get-Date).ToUniversalTime().ToString($fmt)
                    window            = [ordered]@{
                        from_utc     = $fromUtc.ToString($fmt)
                        to_utc       = $nowUtc.ToString($fmt)
                        window_hours = $WindowHours
                    }
                    host_timezone     = $tz
                    summary           = $tl.summary
                    anomalies         = $tl.anomalies
                    boots             = $tl.boots
                    gaps              = $tl.gaps
                }

                $tlPath = Join-Path $WorkingDirectory 'summary\boot_timeline.json'
                $tlJson = $tlData | ConvertTo-Json -Depth 12
                [System.IO.File]::WriteAllText($tlPath, $tlJson, [System.Text.UTF8Encoding]::new($false))

                $result.Artifacts += @{
                    path             = 'summary/boot_timeline.json'
                    category         = 'boot_timeline'
                    schema_version   = '1.0'
                    type             = 'derived'
                    description      = "Per-boot records, gaps, and anomalies (incomplete_boot, missing_shutdown_event, abnormal_gap); window $WindowHours h"
                    source_artifacts = @('raw/eventlogs/System.evtx')
                    row_count        = $tl.boots.Count
                }
            } catch {
                $result.Errors += @{
                    collector = 'Get-DiagEventLogs'
                    artifact  = 'summary/boot_timeline.json'
                    reason    = "Build-DiagBootTimeline failed: $($_.Exception.Message)"
                    severity  = 'warning'
                }
            }
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagEventLogs'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        Write-Progress -Id 2 -ParentId 1 -Activity 'EventLogs' -Completed
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
