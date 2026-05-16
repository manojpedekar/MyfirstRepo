function Get-DiagTimezone {
    <#
    .SYNOPSIS
        Build a structured timezone description for inventory and timestamp conversion.
    .DESCRIPTION
        Wraps [System.TimeZoneInfo]::Local with the fields downstream consumers
        need to convert local-time strings (e.g. EVTX 6008 message text, CBS.log
        timestamps) into UTC. Computes the current offset, the offset at the
        start of the collection window, and a flag for whether DST transitioned
        inside the window. Used by Get-DiagInventory (writes the structured
        time_zone block) and by Build-DiagBootTimeline (resolves 6008
        prior-shutdown timestamps).
    .PARAMETER WindowHours
        Lookback window in hours from now. Used to compute
        window_start_utc_offset_minutes and detect DST transitions in window.
        Defaults to 24.
    .INPUTS
        None.
    .OUTPUTS
        [ordered] hashtable with id, display_name, current_utc_offset_minutes,
        currently_in_daylight_time, supports_daylight_saving_time, standard_name,
        daylight_name, window_start_utc_offset_minutes, window_end_utc_offset_minutes,
        dst_transition_in_window, note.
    .EXAMPLE
        $tz = Get-DiagTimezone -WindowHours 120
    .NOTES
        Never throws. On failure to read TimeZoneInfo (very unusual) returns
        an object with id='unknown' and the structural fields nulled.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int] $WindowHours = 24
    )

    $now      = [DateTime]::UtcNow
    $winStart = $now.AddHours(-$WindowHours)

    try {
        $tz = [System.TimeZoneInfo]::Local
        $nowOffset      = $tz.GetUtcOffset($now)
        $winStartOffset = $tz.GetUtcOffset($winStart)
        # ConvertTimeFromUtc gives a kind=Unspecified DateTime in the local tz;
        # IsDaylightSavingTime needs an unspecified or local DateTime to work.
        $nowLocal      = [System.TimeZoneInfo]::ConvertTimeFromUtc($now,      $tz)
        $winStartLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc($winStart, $tz)

        return [ordered]@{
            id                              = $tz.Id
            display_name                    = $tz.DisplayName
            supports_daylight_saving_time   = $tz.SupportsDaylightSavingTime
            current_utc_offset_minutes      = [int]$nowOffset.TotalMinutes
            currently_in_daylight_time      = $tz.IsDaylightSavingTime($nowLocal)
            standard_name                   = $tz.StandardName
            daylight_name                   = $tz.DaylightName
            window_start_utc_offset_minutes = [int]$winStartOffset.TotalMinutes
            window_end_utc_offset_minutes   = [int]$nowOffset.TotalMinutes
            dst_transition_in_window        = ($nowOffset.TotalMinutes -ne $winStartOffset.TotalMinutes)
            note                            = 'EVTX event message text and CBS.log timestamps are written in local time per this zone. JSON fields with Z suffix are UTC.'
        }
    } catch {
        return [ordered]@{
            id                              = 'unknown'
            display_name                    = $null
            supports_daylight_saving_time   = $null
            current_utc_offset_minutes      = $null
            currently_in_daylight_time      = $null
            standard_name                   = $null
            daylight_name                   = $null
            window_start_utc_offset_minutes = $null
            window_end_utc_offset_minutes   = $null
            dst_transition_in_window        = $false
            note                            = "Get-DiagTimezone failed: $($_.Exception.Message)"
        }
    }
}

function ConvertFrom-DiagLocalTime {
    <#
    .SYNOPSIS
        Convert a local-time DateTime into UTC using the host's local timezone.
    .DESCRIPTION
        Wraps [System.TimeZoneInfo]::ConvertTimeToUtc with explicit Local
        timezone. Use when parsing local-time strings out of EVTX message
        text, CBS.log lines, or anywhere else Windows wrote a wall-clock
        timestamp without a UTC marker. Returns $null on input that is
        already kind=Utc, since converting that would silently double-shift.
    .PARAMETER LocalDateTime
        A DateTime whose Kind should be Unspecified or Local. If Kind=Utc,
        returns $null (callers should treat that as a parse error).
    .INPUTS
        None.
    .OUTPUTS
        [DateTime] in UTC, or $null if the input is already UTC.
    .EXAMPLE
        $local = [DateTime]::ParseExact('4/26/2026 3:30:20 AM', 'M/d/yyyy h:mm:ss tt', $null)
        $utc   = ConvertFrom-DiagLocalTime -LocalDateTime $local
    .NOTES
        Uses the running session's [System.TimeZoneInfo]::Local. The collector
        runs on the host being inventoried, so this is the right zone for
        interpreting that host's local-time strings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [DateTime] $LocalDateTime
    )

    if ($LocalDateTime.Kind -eq [DateTimeKind]::Utc) { return $null }

    try {
        $unspec = [DateTime]::SpecifyKind($LocalDateTime, [DateTimeKind]::Unspecified)
        return [System.TimeZoneInfo]::ConvertTimeToUtc($unspec, [System.TimeZoneInfo]::Local)
    } catch {
        return $null
    }
}
