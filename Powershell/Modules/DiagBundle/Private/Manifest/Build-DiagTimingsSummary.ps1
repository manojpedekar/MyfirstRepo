function Build-DiagTimingsSummary {
    <#
    .SYNOPSIS
        Read the line-delimited collector log and build the manifest.timings
        block: per-collector aggregate seconds plus a steps[] list of every
        timed step sorted by duration descending.
    .DESCRIPTION
        Invoke-DiagTimed writes one JSON line per timed step into
        transcript/collector.log with message="timing", step, duration_ms,
        and (optionally) exit_code. This function reads those lines, groups
        by collector for the per-collector totals, and emits the steps[]
        array in slowest-first order so the most expensive operations of
        the run are at the top of the list.

        Designed to run at finalize time, AFTER all collectors have written
        their timing entries and BEFORE Complete-DiagManifest seals the
        manifest. Pure read of the on-disk log file; never mutates it.

        Returns $null when the log file is absent or unreadable. The
        orchestrator treats $null as "no timings recorded" and omits the
        manifest.timings block in that case.
    .PARAMETER LogPath
        Mandatory. Absolute path to the bundle's transcript/collector.log.
    .INPUTS
        None.
    .OUTPUTS
        [ordered] hashtable with by_collector_seconds (ordered map) and
        steps (array sorted by duration_ms desc), or $null on read failure.
    .EXAMPLE
        $t = Build-DiagTimingsSummary -LogPath $logPath
        $manifest['timings'] = $t
    .NOTES
        Lines that fail JSON parse are skipped silently; this is by
        design (the log is also written by other code paths and we do
        not want a single bad line to abort the timings summary). Lines
        without message="timing" are ignored.

        Step ordering inside by_collector_seconds is insertion order
        matching the per-collector run order in the orchestrator. Step
        ordering inside steps[] is duration_ms descending.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $LogPath
    )

    if (-not (Test-Path -LiteralPath $LogPath)) { return $null }

    $entries = New-Object System.Collections.ArrayList
    try {
        foreach ($line in [System.IO.File]::ReadAllLines($LogPath, [System.Text.UTF8Encoding]::new($false))) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
            } catch { continue }
            if ($obj.message -ne 'timing') { continue }
            if ($null -eq $obj.duration_ms) { continue }
            [void]$entries.Add([ordered]@{
                collector   = [string]$obj.collector
                step        = [string]$obj.step
                duration_ms = [long]$obj.duration_ms
                exit_code   = if ($null -ne $obj.exit_code) { [int]$obj.exit_code } else { $null }
                ts          = [string]$obj.ts
            })
        }
    } catch { return $null }

    if ($entries.Count -eq 0) { return $null }

    # Per-collector aggregate. Use a Hashtable keyed by collector name; sum
    # in ms then convert to seconds at the end. PowerShell 5.1 Sort/Group
    # against [ordered] keys is unsafe, so iterate explicitly.
    $byCollectorMs = @{}
    foreach ($e in $entries) {
        $key = $e.collector
        if (-not $byCollectorMs.ContainsKey($key)) { $byCollectorMs[$key] = 0L }
        $byCollectorMs[$key] = [long]$byCollectorMs[$key] + [long]$e.duration_ms
    }

    # Order the per-collector map by total time descending so the slowest
    # collector is the first key when an analyst opens the manifest.
    $byCollector = [ordered]@{}
    $byCollectorMs.GetEnumerator() |
        Sort-Object -Property @{ Expression = { [long]$_.Value }; Descending = $true } |
        ForEach-Object {
            # AwayFromZero rounding so "2500ms" reads as 3 seconds, not 2.
            # Default banker's rounding rounds .5 to the nearest even integer
            # which surprises operators looking at the manifest.
            $byCollector[$_.Key] = [int][math]::Round($_.Value / 1000.0, 0, [System.MidpointRounding]::AwayFromZero)
        }

    # Steps list sorted by duration desc. Preserve all entries; consumers can
    # filter or take the head as they need.
    $stepsSorted = $entries |
        Sort-Object -Property @{ Expression = { [long]$_.duration_ms }; Descending = $true } |
        ForEach-Object {
            $row = [ordered]@{
                collector   = $_.collector
                step        = $_.step
                duration_ms = $_.duration_ms
            }
            if ($null -ne $_.exit_code) { $row['exit_code'] = $_.exit_code }
            $row['ts'] = $_.ts
            $row
        }

    return [ordered]@{
        by_collector_seconds = $byCollector
        steps                = @($stepsSorted)
    }
}
