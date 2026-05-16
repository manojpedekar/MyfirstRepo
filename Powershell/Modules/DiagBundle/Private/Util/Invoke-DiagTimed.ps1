function Invoke-DiagTimed {
    <#
    .SYNOPSIS
        Run a scriptblock under a stopwatch, log the duration as a structured
        JSON entry in transcript/collector.log, and return the scriptblock's
        result transparently.
    .DESCRIPTION
        Wraps an external command or expensive PowerShell call in a
        Stopwatch + structured log entry. Intended for the dozen or so calls
        per collector that dominate runtime (gpresult, dcdiag, wevtutil epl,
        Get-Counter, Get-WinEvent, COM Microsoft.Update.Session queries, etc).

        Every entry lands in collector.log as a single JSON line with
        message="timing" and the named fields step/duration_ms/exit_code.
        Build-DiagTimingsSummary reads these at finalize time to populate
        manifest.timings so analysts can answer "what was slow this run"
        without re-running and fighting OS file caches.

        $LASTEXITCODE is captured immediately after the scriptblock returns
        and before any other PowerShell statement runs, so external-command
        exit codes survive the wrapper and are available to the caller via
        $LASTEXITCODE on the next line.
    .PARAMETER Collector
        Mandatory. Short name of the calling collector (for example
        Get-DiagAD). Same convention as Write-DiagLog -Collector.
    .PARAMETER Step
        Mandatory. Short label for what this stopwatch covers (for example
        "gpresult /h", "wevtutil epl Security", "Get-Counter 60s sample").
        Free-form but stable across runs so fleet-wide aggregation can
        group by step.
    .PARAMETER Action
        Mandatory. Scriptblock to invoke. The block's output value is
        returned to the caller. Stdout and pipeline output pass through
        unchanged.
    .PARAMETER Severity
        Optional. Log entry severity. Defaults to info. Override to warning
        when the timed step is itself a warning condition.
    .INPUTS
        None.
    .OUTPUTS
        Whatever the Action scriptblock outputs. Pipeline-friendly.
    .EXAMPLE
        $stderr = Invoke-DiagTimed -Collector 'Get-DiagAD' -Step 'gpresult /h' -Action {
            & gpresult /h $shortHtml /f 2>&1
        }
    .NOTES
        Overhead per call is sub-millisecond (one Stopwatch + one Add-Content
        line). Negligible against any timed step worth wrapping. The Action
        block must end with the call whose exit code matters; a trailing
        statement (assignment, pipe, etc) would clobber $LASTEXITCODE before
        the wrapper can capture it.

        Never throws on its own. If the Action throws, the exception
        propagates after the timing entry is written.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]      $Collector,
        [Parameter(Mandatory)] [string]      $Step,
        [Parameter(Mandatory)] [scriptblock] $Action,

        [Parameter()]
        [ValidateSet('info', 'warning', 'error')]
        [string] $Severity = 'info'
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $exitCode = $null
    try {
        $value = & $Action
        # Capture LASTEXITCODE on the very next line so a non-PowerShell
        # exit code survives back to the caller. PowerShell-only Actions
        # leave $LASTEXITCODE alone; null is the right value to log.
        if ($null -ne (Get-Variable -Name LASTEXITCODE -Scope Global -ValueOnly -ErrorAction SilentlyContinue)) {
            $exitCode = [int]$global:LASTEXITCODE
        }
        return $value
    }
    finally {
        $sw.Stop()
        $logArgs = @{
            Severity   = $Severity
            Collector  = $Collector
            Message    = 'timing'
            Step       = $Step
            DurationMs = [long]$sw.Elapsed.TotalMilliseconds
        }
        if ($null -ne $exitCode) { $logArgs['ExitCode'] = $exitCode }
        Write-DiagLog @logArgs
    }
}
