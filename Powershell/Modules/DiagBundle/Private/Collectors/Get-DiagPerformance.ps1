function Get-DiagPerformance {
    <#
    .SYNOPSIS
        Capture a Get-Counter snapshot covering CPU, memory, disk, network, and TCP, then export both a BLG and a per-counter aggregate JSON.

    .DESCRIPTION
        Calls Get-Counter against a fixed counter set with -SampleInterval $SampleIntervalSeconds and -MaxSamples derived from $SampleSeconds, then writes the raw samples to raw\perf\snapshot.blg via Export-Counter and emits min/avg/max/p95 per counter to summary\perf_summary.json. The counter set covers \Processor, \Memory, \System, \PhysicalDisk, \Network Interface, and \TCPv4. Blocks the calling pipeline for the duration of $SampleSeconds; for that reason the collector runs LAST in the orchestrator pipeline. Sets $script:DiagPerfFromUtc and $script:DiagPerfToUtc so the orchestrator can stamp time_window.perf_from_utc and time_window.perf_to_utc in the bundle manifest.

    .PARAMETER WorkingDirectory
        Root of the staging tree. Artifacts land under summary\ and raw\perf\ inside this path.

    .PARAMETER SampleSeconds
        Length of the sample window in seconds. Defaults to 60. The collector blocks for this duration.

    .PARAMETER SampleIntervalSeconds
        Get-Counter sample interval in seconds. Defaults to 1.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with path/category/type/description and per-type metadata), Errors (array of hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagPerformance -WorkingDirectory 'C:\ProgramData\DiagBundle\work\bundle-001' -SampleSeconds 60

    .NOTES
        Artifacts written:
          raw/perf/snapshot.blg
          summary/perf_summary.json

        Emits a Write-Progress message stating the collector is blocking for the sample window so callers see why the pipeline pauses.

        Sets script-scoped $script:DiagPerfFromUtc and $script:DiagPerfToUtc for the orchestrator to read after the call returns.

        The collector never throws. On fatal abort it returns Success=$false with populated Errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter()]
        [int] $SampleSeconds = 60,

        [Parameter()]
        [int] $SampleIntervalSeconds = 1
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
        $counters = @(
            '\Processor(_Total)\% Processor Time'
            '\Memory\Available MBytes'
            '\Memory\Pages/sec'
            '\Memory\Committed Bytes'
            '\System\Processor Queue Length'
            '\System\Context Switches/sec'
            '\PhysicalDisk(_Total)\% Disk Time'
            '\PhysicalDisk(_Total)\Avg. Disk sec/Read'
            '\PhysicalDisk(_Total)\Avg. Disk sec/Write'
            '\PhysicalDisk(_Total)\Disk Reads/sec'
            '\PhysicalDisk(_Total)\Disk Writes/sec'
            '\Network Interface(*)\Bytes Total/sec'
            '\Network Interface(*)\Output Queue Length'
            '\TCPv4\Connections Established'
            '\TCPv4\Segments Retransmitted/sec'
        )

        $maxSamples = [Math]::Max(1, [int]($SampleSeconds / [Math]::Max(1, $SampleIntervalSeconds)))
        $perfFromUtc = (Get-Date).ToUniversalTime()

        Write-Progress -Id 2 -ParentId 1 -Activity 'Performance' -Status "Sampling counters for ${SampleSeconds}s (blocking)" -PercentComplete 0
        $samples = Invoke-DiagTimed -Collector 'Get-DiagPerformance' -Step "Get-Counter ${SampleSeconds}s sample" -Action {
            Get-Counter -Counter $counters -SampleInterval $SampleIntervalSeconds -MaxSamples $maxSamples -ErrorAction Stop
        }
        Write-Progress -Id 2 -ParentId 1 -Activity 'Performance' -Completed

        $perfToUtc = (Get-Date).ToUniversalTime()

        $blgPath = Join-Path $WorkingDirectory 'raw\perf\snapshot.blg'
        try {
            Invoke-DiagTimed -Collector 'Get-DiagPerformance' -Step 'Export-Counter BLG' -Action {
                $samples | Export-Counter -Path $blgPath -FileFormat BLG -Force -ErrorAction Stop
            }
            $result.Artifacts += @{
                path        = 'raw/perf/snapshot.blg'
                category    = 'perf_raw'
                type        = 'raw'
                description = "Get-Counter snapshot, ${SampleSeconds}s window, ${SampleIntervalSeconds}s interval"
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagPerformance'; artifact = 'raw/perf/snapshot.blg'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $byCounter = @{}
        foreach ($s in $samples) {
            foreach ($cs in $s.CounterSamples) {
                $key = $cs.Path
                if (-not $byCounter.ContainsKey($key)) { $byCounter[$key] = [System.Collections.ArrayList]::new() }
                [void]$byCounter[$key].Add([double]$cs.CookedValue)
            }
        }

        $aggregates = @()
        foreach ($k in ($byCounter.Keys | Sort-Object)) {
            $vals = $byCounter[$k]
            $stats = $vals | Measure-Object -Average -Maximum -Minimum
            $sorted = $vals | Sort-Object
            $p95 = $sorted[[Math]::Min($sorted.Count - 1, [int][Math]::Ceiling($sorted.Count * 0.95) - 1)]
            $aggregates += [ordered]@{
                counter = $k
                samples = $vals.Count
                min     = [math]::Round($stats.Minimum, 4)
                avg     = [math]::Round($stats.Average, 4)
                max     = [math]::Round($stats.Maximum, 4)
                p95     = [math]::Round([double]$p95, 4)
            }
        }

        $data = [ordered]@{
            schema_version = '1.0'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            window         = [ordered]@{
                from_utc          = $perfFromUtc.ToString($fmt)
                to_utc            = $perfToUtc.ToString($fmt)
                sample_seconds    = $SampleSeconds
                sample_interval_s = $SampleIntervalSeconds
            }
            counters = $aggregates
        }

        $sumPath = Join-Path $WorkingDirectory 'summary\perf_summary.json'
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($sumPath, $json, [System.Text.UTF8Encoding]::new($false))

        $result.Artifacts += @{
            path             = 'summary/perf_summary.json'
            category         = 'perf_summary'
            schema_version   = '1.0'
            type             = 'derived'
            description      = "Per-counter min/avg/max/p95 over ${SampleSeconds}s window"
            source_artifacts = @('raw/perf/snapshot.blg')
            row_count        = $aggregates.Count
        }

        $script:DiagPerfFromUtc = $perfFromUtc
        $script:DiagPerfToUtc   = $perfToUtc

        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagPerformance'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
