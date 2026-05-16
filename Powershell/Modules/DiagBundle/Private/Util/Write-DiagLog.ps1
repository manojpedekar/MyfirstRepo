function Write-DiagLog {
    <#
    .SYNOPSIS
        Append a structured JSON log entry to the bundle collector log.

    .DESCRIPTION
        Writes one compact JSON line per call to the collector log file used by
        every collector in the DiagBundle pipeline. The orchestrator
        (Invoke-DiagBundle) sets $script:DiagLogPath at the start of a run; this
        function reads that variable when LogPath is not supplied, and falls
        back to verbose-only output when neither is set. The log is later
        attached to the bundle as transcript/collector.log so the analyst can
        reconstruct exactly what each collector did and when.

    .PARAMETER Severity
        Log level. Mandatory. One of info, warning, error. Severity error means
        the calling collector produced no usable output for its category.

    .PARAMETER Message
        Free-form message text. Mandatory. Positional parameter 0 so callers
        can write Write-DiagLog "..." -Severity info.

    .PARAMETER Collector
        Short name of the calling collector (for example Get-DiagPatching).
        Optional; defaults to an empty string when the caller is the
        orchestrator itself.

    .PARAMETER LogPath
        Explicit log file path. Optional. When omitted, the function reads
        $script:DiagLogPath. When that is also unset, the entry is written only
        to the verbose stream and not persisted to disk.

    .INPUTS
        None.

    .OUTPUTS
        None. The function writes to the log file and the verbose stream.

    .EXAMPLE
        # Record a routine progress message from a collector.
        Write-DiagLog -Severity info -Collector 'Get-DiagPatching' -Message 'starting'

    .NOTES
        Each line is a single ConvertTo-Json -Compress object with ts (UTC),
        severity, collector, message. The line-delimited JSON shape is what the
        downstream agent expects when parsing collector.log. This function does
        not throw on write failures from Add-Content; if the log path is bad
        the call still completes and the verbose entry is still emitted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('info', 'warning', 'error')]
        [string] $Severity,

        [Parameter(Mandatory, Position = 0)]
        [string] $Message,

        [Parameter()]
        [string] $Collector = '',

        [Parameter()]
        [string] $LogPath,

        # Optional structured fields for timing entries. Invoke-DiagTimed
        # populates Step, DurationMs, and ExitCode; the timings summary
        # builder reads those out of collector.log to populate manifest.timings.
        [Parameter()]
        [string] $Step,

        [Parameter()]
        [Nullable[long]] $DurationMs,

        [Parameter()]
        [Nullable[int]] $ExitCode,

        # Catch-all bag for one-off structured fields. Merged into the entry
        # alongside the named fields above.
        [Parameter()]
        [System.Collections.IDictionary] $Data
    )

    if (-not $LogPath) {
        $LogPath = (Get-Variable -Name DiagLogPath -Scope Script -ValueOnly -ErrorAction SilentlyContinue)
    }

    $entry = [ordered]@{
        ts        = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        severity  = $Severity
        collector = $Collector
        message   = $Message
    }
    if ($PSBoundParameters.ContainsKey('Step'))       { $entry['step']        = $Step }
    if ($PSBoundParameters.ContainsKey('DurationMs')) { $entry['duration_ms'] = $DurationMs }
    if ($PSBoundParameters.ContainsKey('ExitCode'))   { $entry['exit_code']   = $ExitCode }
    if ($Data) {
        foreach ($k in $Data.Keys) { $entry[$k] = $Data[$k] }
    }

    if ($LogPath) {
        $line = ($entry | ConvertTo-Json -Compress -Depth 5)
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    }

    Write-Verbose "[$Severity] $Collector $Message"
}
