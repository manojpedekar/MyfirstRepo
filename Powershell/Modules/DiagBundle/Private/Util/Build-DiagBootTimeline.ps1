function Build-DiagBootTimeline {
    <#
    .SYNOPSIS
        Reconstruct a boot/shutdown timeline with anomaly detection from System EVTX events.
    .DESCRIPTION
        Walks a list of System-channel events, splits them into boot sessions on
        EventLog 6005 boundaries, and produces a structured per-boot record plus
        a list of gaps and anomalies (incomplete_boot, missing_shutdown_event,
        abnormal_gap). The agent reads this to understand reboot history without
        having to pair events itself. The classifier respects the org-specific
        renamed built-in Administrator account by SID (RID 500), with name-based
        fallback when the account cannot be resolved.
    .PARAMETER SystemEvents
        Array of System-channel event records (typically the unfiltered output
        of Get-WinEvent -FilterHashtable for the System log). The function
        filters internally to the boot-relevant event ID set, so callers can
        pass everything they have.
    .PARAMETER FromUtc
        Start of the collection window in UTC. Drives the inferred-shutdown
        gap detection (a 6008 prior-shutdown timestamp before this is ignored).
    .PARAMETER ToUtc
        End of the collection window in UTC. The current uptime of the last
        boot is computed against this.
    .INPUTS
        None.
    .OUTPUTS
        [ordered] hashtable with keys boots (array), gaps (array), anomalies
        (array), summary (counts).
    .EXAMPLE
        $tl = Build-DiagBootTimeline -SystemEvents $events -FromUtc $from -ToUtc $to
    .NOTES
        Boot ID set: EventLog 6005, 6006, 6008, 6013; User32 1074, 1076;
        Kernel-General 12, 13; Kernel-Power 41, 109; Kernel-Boot 18, 20, 21,
        24, 27; BugCheck 1001. Provider name match is substring-tolerant so it
        works on both pre- and post-WPP provider names.

        Gap thresholds: > 4h warning, > 12h critical. The first observed boot
        also reports an inferred gap if its session contains a 6008 with a
        parseable prior-shutdown local timestamp.

        Shutdown initiator taxonomy:
          interactive_admin_console / interactive_admin_session
          interactive_user_console / interactive_user_session
          cloudbase_init    (process path contains \Cloudbase Solutions\Cloudbase-Init\ or user is *\cloudbase-init; matched before python.exe -> salt_orchestrator)
          salt_orchestrator (process = python.exe, not cloudbase-init)
          windows_update    (process = TrustedInstaller.exe)
          service_initiated (process = svchost.exe)
          winlogon_initiated (process = winlogon.exe)
          other_process_initiated
          kernel_initiated  (109 with no preceding 1074)
          unexpected        (no stop event, mid-bundle)
          bugcheck          (1001 in session)
          unknown
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $SystemEvents,

        [Parameter(Mandatory)]
        [DateTime] $FromUtc,

        [Parameter(Mandatory)]
        [DateTime] $ToUtc
    )

    $fmt = 'yyyy-MM-ddTHH:mm:ss.fffZ'
    $bootIds = 6005, 6006, 6008, 6013, 1074, 1076, 12, 13, 41, 109, 18, 20, 21, 24, 27, 1001

    # Defensive Kind normalization. The function's name implies UTC inputs, but
    # PowerShell's '[DateTime]"...Z"' parses to Kind=Local, and accepting any
    # Kind here keeps the function callable from tests that did not normalize.
    $FromUtc = _NormalizeToUtc $FromUtc
    $ToUtc   = _NormalizeToUtc $ToUtc

    $relevant = @($SystemEvents | Where-Object { $_ -ne $null -and ($bootIds -contains [int]$_.Id) } |
        Sort-Object TimeCreated)

    # ---------- session split ----------
    # On a real boot, Kernel-General 12 and Kernel-Power 41 fire BEFORE the
    # EventLog service comes up (= 6005). Anchoring sessions on 6005 alone
    # would discard the early-boot evidence. Use Kernel-General 12 as the
    # primary boot-start marker; fall back to 6005 only when no Kernel-General
    # 12 fired within 60 seconds before it (deduplicates the marker pair).
    $kg12 = @($relevant | Where-Object { [int]$_.Id -eq 12 -and $_.ProviderName -like '*Kernel-General*' })
    $el05 = @($relevant | Where-Object { [int]$_.Id -eq 6005 -and $_.ProviderName -like '*EventLog*' })

    $bootStarts = New-Object System.Collections.ArrayList
    foreach ($g in $kg12) { [void]$bootStarts.Add(@{ Time = $g.TimeCreated; StartEvent = $g }) }
    foreach ($e in $el05) {
        $covered = $false
        foreach ($bs in $bootStarts) {
            $diff = ($e.TimeCreated - $bs.Time).TotalSeconds
            if ($diff -ge 0 -and $diff -le 60) { $covered = $true; break }
        }
        if (-not $covered) { [void]$bootStarts.Add(@{ Time = $e.TimeCreated; StartEvent = $e }) }
    }
    $bootStartsSorted = @($bootStarts | Sort-Object { $_.Time })

    $sessions = New-Object System.Collections.ArrayList
    foreach ($bs in $bootStartsSorted) {
        [void]$sessions.Add([ordered]@{
            start_event = $bs.StartEvent
            events      = New-Object System.Collections.ArrayList
        })
    }

    # Assign each event to the latest boot-start whose timestamp is <= the
    # event's. Events earlier than the first boot-start are dropped (they
    # belong to a prior boot whose start is outside the window).
    foreach ($e in $relevant) {
        $assigned = -1
        for ($i = $bootStartsSorted.Count - 1; $i -ge 0; $i--) {
            if ($e.TimeCreated -ge $bootStartsSorted[$i].Time) { $assigned = $i; break }
        }
        if ($assigned -ge 0) {
            [void]$sessions[$assigned].events.Add($e)
        }
    }

    # ---------- per-boot records ----------
    $boots = New-Object System.Collections.ArrayList
    $bootIndex = 0
    foreach ($sess in $sessions) {
        $bootIndex++
        $sessEvents = @($sess.events)

        $kernelStart = $sessEvents | Where-Object {
            [int]$_.Id -eq 12 -and $_.ProviderName -like '*Kernel-General*'
        } | Sort-Object TimeCreated | Select-Object -First 1

        if ($kernelStart) {
            $startUtc = $kernelStart.TimeCreated.ToUniversalTime()
            $startEvidence = [ordered]@{ event_id = 12; provider = $kernelStart.ProviderName }
        } else {
            $startUtc = $sess.start_event.TimeCreated.ToUniversalTime()
            $startEvidence = [ordered]@{ event_id = 6005; provider = $sess.start_event.ProviderName }
        }

        $stopEvent = $sessEvents | Where-Object {
            (([int]$_.Id -eq 6006) -and ($_.ProviderName -like '*EventLog*')) -or
            (([int]$_.Id -eq 109)  -and ($_.ProviderName -like '*Kernel-Power*')) -or
            (([int]$_.Id -eq 13)   -and ($_.ProviderName -like '*Kernel-General*'))
        } | Sort-Object TimeCreated -Descending | Select-Object -First 1

        $shutdownUtc = $null
        $shutdownEvidence = $null
        if ($stopEvent) {
            $shutdownUtc = $stopEvent.TimeCreated.ToUniversalTime()
            $shutdownEvidence = [ordered]@{
                event_id = [int]$stopEvent.Id
                provider = $stopEvent.ProviderName
            }
        }

        $kp41   = $sessEvents | Where-Object { [int]$_.Id -eq 41   -and $_.ProviderName -like '*Kernel-Power*' } | Select-Object -First 1
        $ev6008 = $sessEvents | Where-Object { [int]$_.Id -eq 6008 -and $_.ProviderName -like '*EventLog*' }    | Select-Object -First 1

        $bootType = 'clean'
        $bootTypeEvidenceParts = New-Object System.Collections.ArrayList
        if ($kp41 -or $ev6008) {
            $bootType = 'dirty'
            if ($kp41)   { [void]$bootTypeEvidenceParts.Add('Kernel-Power 41 (rebooted without clean shutdown)') }
            if ($ev6008) { [void]$bootTypeEvidenceParts.Add('EventLog 6008 (previous shutdown was unexpected)') }
        }

        $f8       = @($sessEvents | Where-Object { [int]$_.Id -eq 24 -and $_.ProviderName -like '*Kernel-Boot*' })
        $bootMenu = @($sessEvents | Where-Object { [int]$_.Id -eq 21 -and $_.ProviderName -like '*Kernel-Boot*' })
        $operatorInteracted = ($f8.Count -gt 0) -or ($bootMenu.Count -gt 0)
        $operatorEvidenceParts = New-Object System.Collections.ArrayList
        if ($f8.Count       -gt 0) { [void]$operatorEvidenceParts.Add("Kernel-Boot 24 (F8 pressed) x$($f8.Count)") }
        if ($bootMenu.Count -gt 0) { [void]$operatorEvidenceParts.Add('Kernel-Boot 21 (boot menu shown)') }

        $event1074 = $sessEvents | Where-Object { [int]$_.Id -eq 1074 } | Sort-Object TimeCreated | Select-Object -First 1
        $bugCheck  = $sessEvents | Where-Object { [int]$_.Id -eq 1001 -and $_.ProviderName -like '*BugCheck*' } | Select-Object -First 1

        $shutdownInitiator     = 'unknown'
        $shutdownInitiatorUser = $null
        $shutdownReason        = $null
        $shutdownInitiatorProc = $null
        $shutdownType          = if ($stopEvent) { 'clean' } else { 'ongoing' }

        if ($event1074) {
            $parsed = _ParseUser32_1074 $event1074.Message
            $shutdownInitiatorUser = $parsed.User
            $shutdownInitiatorProc = $parsed.Process
            $shutdownReason        = $parsed.Reason
            $isAdminRid500         = _IsBuiltInAdminAccount -AccountName $parsed.User
            $shutdownInitiator     = _ClassifyInitiator -Process $parsed.Process -User $parsed.User -IsAdminRid500 $isAdminRid500
        } elseif ($stopEvent -and [int]$stopEvent.Id -eq 109) {
            $shutdownInitiator = 'kernel_initiated'
        }

        if ($bugCheck) {
            $shutdownInitiator = 'bugcheck'
        }

        $uptimeSeconds = $null
        if ($shutdownUtc) {
            $uptimeSeconds = [int]($shutdownUtc - $startUtc).TotalSeconds
        } elseif ($bootIndex -eq $sessions.Count) {
            $uptimeSeconds = [int]($ToUtc - $startUtc).TotalSeconds
            $shutdownType  = 'ongoing'
        } else {
            # Mid-bundle session with no stop event -- next session began without a clean shutdown.
            $shutdownType = 'abrupt'
            if ($shutdownInitiator -eq 'unknown') { $shutdownInitiator = 'unexpected' }
        }

        [void]$boots.Add([ordered]@{
            boot_index                   = $bootIndex
            start_utc                    = $startUtc.ToString($fmt)
            start_evidence               = $startEvidence
            shutdown_utc                 = if ($shutdownUtc) { $shutdownUtc.ToString($fmt) } else { $null }
            shutdown_evidence            = $shutdownEvidence
            uptime_seconds               = $uptimeSeconds
            uptime_human                 = _HumanDuration $uptimeSeconds
            boot_type                    = $bootType
            boot_type_evidence           = ($bootTypeEvidenceParts -join '; ')
            operator_console_interaction = $operatorInteracted
            operator_console_evidence    = ($operatorEvidenceParts -join '; ')
            shutdown_type                = $shutdownType
            shutdown_initiator           = $shutdownInitiator
            shutdown_initiator_process   = $shutdownInitiatorProc
            shutdown_initiator_user      = $shutdownInitiatorUser
            shutdown_reason              = $shutdownReason
        })
    }

    # ---------- gaps + anomalies ----------
    $gaps      = New-Object System.Collections.ArrayList
    $anomalies = New-Object System.Collections.ArrayList

    # Inferred-shutdown gap for the first observed boot, if its session has a 6008
    if ($sessions.Count -gt 0 -and $boots.Count -gt 0) {
        $firstSessEvents = @($sessions[0].events)
        $firstSess6008 = $firstSessEvents | Where-Object { [int]$_.Id -eq 6008 -and $_.ProviderName -like '*EventLog*' } | Select-Object -First 1
        if ($firstSess6008) {
            $priorShutdownUtc = _ParsePriorShutdownTime $firstSess6008.Message
            if ($priorShutdownUtc -and $priorShutdownUtc -ge $FromUtc -and $priorShutdownUtc -lt [DateTime]::Parse($boots[0].start_utc).ToUniversalTime()) {
                $firstStartUtc = [DateTime]::Parse($boots[0].start_utc).ToUniversalTime()
                $gapSec = [int]($firstStartUtc - $priorShutdownUtc).TotalSeconds
                [void]$gaps.Add([ordered]@{
                    from_utc         = $priorShutdownUtc.ToString($fmt)
                    from_evidence    = 'EventLog 6008 prior-shutdown timestamp (converted from local time using host TZ)'
                    to_utc           = $boots[0].start_utc
                    to_evidence      = "boot $($boots[0].boot_index) start_evidence"
                    duration_seconds = $gapSec
                    duration_human   = _HumanDuration $gapSec
                    interpretation   = 'no kernel-level evidence in this window. Either host was off, or boot attempts hung before EventLog/Kernel-General could write. Cross-reference hypervisor / out-of-band power log.'
                })
                if ($gapSec -gt 1800) {
                    [void]$anomalies.Add([ordered]@{
                        type           = 'incomplete_boot'
                        boot_index     = 0
                        from_utc       = $priorShutdownUtc.ToString($fmt)
                        to_utc         = $boots[0].start_utc
                        duration_human = _HumanDuration $gapSec
                        description    = "Boot inferred to start near $($priorShutdownUtc.ToString($fmt)) never reached EventLog start. No Kernel-General 12 within $(_HumanDuration $gapSec) -- boot likely hung."
                        severity       = if ($gapSec -gt 43200) { 'critical' } elseif ($gapSec -gt 14400) { 'critical' } else { 'warning' }
                    })
                }
            }
        }
    }

    # Pairwise gaps between consecutive boots
    for ($i = 0; $i -lt ($boots.Count - 1); $i++) {
        $cur  = $boots[$i]
        $next = $boots[$i + 1]
        if (-not $cur.shutdown_utc -or -not $next.start_utc) { continue }
        $curEnd  = [DateTime]::Parse($cur.shutdown_utc).ToUniversalTime()
        $nextSt  = [DateTime]::Parse($next.start_utc).ToUniversalTime()
        $gapSec  = [int]($nextSt - $curEnd).TotalSeconds
        $gap = [ordered]@{
            from_utc         = $cur.shutdown_utc
            from_evidence    = "boot $($cur.boot_index) shutdown_evidence"
            to_utc           = $next.start_utc
            to_evidence      = "boot $($next.boot_index) start_evidence"
            duration_seconds = $gapSec
            duration_human   = _HumanDuration $gapSec
            interpretation   = 'reboot interval'
        }
        [void]$gaps.Add($gap)

        if ($gapSec -gt 43200) {
            [void]$anomalies.Add([ordered]@{
                type             = 'abnormal_gap'
                boot_index       = $next.boot_index
                from_utc         = $gap.from_utc
                to_utc           = $gap.to_utc
                duration_human   = $gap.duration_human
                threshold_used   = 'gap > 12h between clean shutdown and next boot'
                severity         = 'critical'
            })
        } elseif ($gapSec -gt 14400) {
            [void]$anomalies.Add([ordered]@{
                type             = 'abnormal_gap'
                boot_index       = $next.boot_index
                from_utc         = $gap.from_utc
                to_utc           = $gap.to_utc
                duration_human   = $gap.duration_human
                threshold_used   = 'gap > 4h between clean shutdown and next boot'
                severity         = 'warning'
            })
        }
    }

    # Missing shutdown events
    for ($i = 0; $i -lt $boots.Count; $i++) {
        $b = $boots[$i]
        if (-not $b.shutdown_utc -and $i -lt ($boots.Count - 1)) {
            [void]$anomalies.Add([ordered]@{
                type         = 'missing_shutdown_event'
                boot_index   = $b.boot_index
                description  = "Boot $($b.boot_index) at $($b.start_utc) has no clean shutdown event (no 6006 / Kernel-Power 109 / Kernel-General 13) before the next session began. Prior session ended unexpectedly."
                severity     = 'warning'
            })
        }
    }

    # Summary block
    $cleanCount  = @($boots | Where-Object { $_.boot_type -eq 'clean' }).Count
    $dirtyCount  = @($boots | Where-Object { $_.boot_type -eq 'dirty' }).Count
    $longestGap  = 0
    foreach ($g in $gaps) { if ($g.duration_seconds -gt $longestGap) { $longestGap = $g.duration_seconds } }
    $lastUptime  = $null
    if ($boots.Count -gt 0) {
        $lastBoot = $boots[$boots.Count - 1]
        if ($lastBoot.uptime_seconds) { $lastUptime = $lastBoot.uptime_seconds }
    }

    return [ordered]@{
        boots     = @($boots)
        gaps      = @($gaps)
        anomalies = @($anomalies)
        summary   = [ordered]@{
            total_boots_in_window         = $boots.Count
            clean_boots                   = $cleanCount
            dirty_boots                   = $dirtyCount
            longest_gap_seconds           = $longestGap
            longest_gap_human             = _HumanDuration $longestGap
            uptime_at_collection_seconds  = $lastUptime
            uptime_at_collection_human    = _HumanDuration $lastUptime
        }
    }
}

function _NormalizeToUtc {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [DateTime] $Value)
    switch ($Value.Kind) {
        ([DateTimeKind]::Utc)         { return $Value }
        ([DateTimeKind]::Local)       { return $Value.ToUniversalTime() }
        ([DateTimeKind]::Unspecified) { return [DateTime]::SpecifyKind($Value, [DateTimeKind]::Utc) }
    }
}

function _ParseUser32_1074 {
    [CmdletBinding()]
    param([string] $Message)

    $out = [ordered]@{ Process = $null; User = $null; Reason = $null }
    if ([string]::IsNullOrEmpty($Message)) { return $out }

    # "The process X (Y) has initiated the restart of computer Z on behalf of user A for the following reason: B"
    # Process token can include a path with spaces inside parens; capture the first parenthesised token form.
    if ($Message -match 'The process\s+(.+?)\s+has initiated the (?:restart|shutdown)') {
        $procToken = $matches[1].Trim()
        # Strip a trailing parenthesised hostname if present: "C:\Windows\Explorer.EXE (HOST)"
        if ($procToken -match '^(.+?)\s+\([^)]+\)\s*$') { $procToken = $matches[1].Trim() }
        $out.Process = $procToken
    }
    if ($Message -match 'on behalf of user\s+(\S+)') {
        $out.User = $matches[1]
    }
    if ($Message -match 'for the following reason:\s*(.+?)(?:\r|\n|$)') {
        $out.Reason = $matches[1].Trim()
    }
    return $out
}

function _IsBuiltInAdminAccount {
    [CmdletBinding()]
    param([string] $AccountName)

    if ([string]::IsNullOrWhiteSpace($AccountName)) { return $false }
    try {
        $nt   = New-Object System.Security.Principal.NTAccount($AccountName)
        $sid  = $nt.Translate([System.Security.Principal.SecurityIdentifier]).Value
        if ($sid -match '-500$') { return $true }
    } catch { }

    # Name-based fallback for the org's renamed-Administrator pattern (leading-underscore convention)
    # and for the literal builtin name across locales.
    $leaf = $AccountName
    if ($leaf -match '^[^\\]+\\(.+)$') { $leaf = $matches[1] }
    if ($leaf -match '^_') { return $true }
    if ($leaf -ieq 'Administrator') { return $true }
    return $false
}

function _ClassifyInitiator {
    [CmdletBinding()]
    param(
        [string] $Process,
        [string] $User,
        [bool]   $IsAdminRid500
    )

    if ([string]::IsNullOrEmpty($Process)) { return 'unknown' }

    # Gap 11 fix (2026-05-11 review): match cloudbase-init BEFORE the
    # python.exe -> salt_orchestrator rule. Cloudbase-Init is a Python
    # service whose executable leaf is python.exe; without the full-path
    # / user check, every reboot it triggers during a fresh provision
    # was being mislabelled as a Salt-initiated reboot. The match is
    # case-insensitive on both the path and the user; either signal
    # individually is sufficient.
    if ($Process -match '(?i)\\Cloudbase Solutions\\Cloudbase-Init\\') {
        return 'cloudbase_init'
    }
    if ($User -and $User -match '(?i)\\cloudbase-init$') {
        return 'cloudbase_init'
    }

    $leaf = Split-Path -Leaf $Process
    switch -Wildcard ($leaf) {
        'Explorer.EXE'         { return $(if ($IsAdminRid500) { 'interactive_admin_console' } else { 'interactive_user_console' }) }
        'explorer.exe'         { return $(if ($IsAdminRid500) { 'interactive_admin_console' } else { 'interactive_user_console' }) }
        'cmd.exe'              { return $(if ($IsAdminRid500) { 'interactive_admin_session' } else { 'interactive_user_session' }) }
        'powershell.exe'       { return $(if ($IsAdminRid500) { 'interactive_admin_session' } else { 'interactive_user_session' }) }
        'pwsh.exe'             { return $(if ($IsAdminRid500) { 'interactive_admin_session' } else { 'interactive_user_session' }) }
        'python.exe'           { return 'salt_orchestrator' }
        'TrustedInstaller.exe' { return 'windows_update' }
        'svchost.exe'          { return 'service_initiated' }
        'winlogon.exe'         { return 'winlogon_initiated' }
        'shutdown.exe'         { return $(if ($IsAdminRid500) { 'interactive_admin_session' } else { 'interactive_user_session' }) }
        default                { return 'other_process_initiated' }
    }
}

function _ParsePriorShutdownTime {
    <#
    Parse a 6008 message text and return the prior-shutdown timestamp in UTC.
    Returns $null on parse failure (locale mismatch, modified message text, etc.).
    The 6008 message is rendered in the host's local timezone; we strip Unicode
    LRM marks (U+200E) commonly inserted by Windows around dates, then convert
    via the host's TimeZoneInfo.Local.
    #>
    [CmdletBinding()]
    param([string] $Message)

    if ([string]::IsNullOrEmpty($Message)) { return $null }

    # Strip any Unicode LRM/RLM marks Windows may have inserted around date parts.
    # The .NET regex engine interprets \uXXXX escapes inside the pattern string,
    # so a single-quoted PS literal stays ASCII while still matching LRM/RLM.
    $clean = $Message -replace '[\u200e\u200f]', ''

    # en-US default: "The previous system shutdown at 3:30:20 AM on 4/26/2026 was unexpected."
    if ($clean -match 'at\s+(\d{1,2}:\d{2}:\d{2}\s+(?:AM|PM))\s+on\s+(\d{1,2}/\d{1,2}/\d{4})') {
        $combined = "$($matches[2]) $($matches[1])"
        try {
            $local = [DateTime]::ParseExact($combined,
                'M/d/yyyy h:mm:ss tt',
                [System.Globalization.CultureInfo]::InvariantCulture)
            return ConvertFrom-DiagLocalTime -LocalDateTime $local
        } catch { }
    }

    # 24h variant: "at 03:30:20 on 4/26/2026"
    if ($clean -match 'at\s+(\d{1,2}:\d{2}:\d{2})\s+on\s+(\d{1,2}/\d{1,2}/\d{4})') {
        $combined = "$($matches[2]) $($matches[1])"
        try {
            $local = [DateTime]::ParseExact($combined,
                'M/d/yyyy H:mm:ss',
                [System.Globalization.CultureInfo]::InvariantCulture)
            return ConvertFrom-DiagLocalTime -LocalDateTime $local
        } catch { }
    }

    return $null
}

function _HumanDuration {
    [CmdletBinding()]
    param([Nullable[int]] $Seconds)

    if ($null -eq $Seconds) { return $null }
    if ($Seconds -lt 0)     { return $null }

    $ts = [TimeSpan]::FromSeconds($Seconds)
    $parts = New-Object System.Collections.ArrayList
    if ($ts.Days    -gt 0) { [void]$parts.Add("$($ts.Days)d") }
    if ($ts.Hours   -gt 0) { [void]$parts.Add("$($ts.Hours)h") }
    if ($ts.Minutes -gt 0) { [void]$parts.Add("$($ts.Minutes)m") }
    if ($ts.Seconds -gt 0 -or $parts.Count -eq 0) { [void]$parts.Add("$($ts.Seconds)s") }
    return ($parts -join ' ')
}
