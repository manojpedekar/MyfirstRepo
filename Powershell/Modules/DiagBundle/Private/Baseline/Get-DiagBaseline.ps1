function Get-DiagBaseline {
    <#
    .SYNOPSIS
        Load the saved baseline snapshot if one exists.
    .DESCRIPTION
        Read baseline.json from the baseline directory and return the
        parsed object. Invoke-DiagBundle calls this near the start of a
        run; if the result is non-null, Compare-DiagBaseline runs later to
        emit summary/baseline_diff.json. A missing or unreadable baseline
        is normal -- the collection proceeds without diff output.
    .PARAMETER BaselineRoot
        Directory holding baseline.json. Defaults to
        C:\ProgramData\DiagBundle\baseline. The function reads
        BaselineRoot\baseline.json.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject parsed from the
        baseline JSON, or $null when the directory or file is missing or
        the JSON cannot be parsed.
    .EXAMPLE
        $baseline = Get-DiagBaseline
        if ($baseline) { Compare-DiagBaseline -Baseline $baseline -BundleRoot $workDir }
    .NOTES
        $null is a normal state, not an error. No baseline ships out of
        the box; an operator runs Update-DiagBaseline manually or
        opportunistically (open item #7). Parse failures are swallowed and
        also return $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $BaselineRoot = 'C:\ProgramData\DiagBundle\baseline'
    )

    if (-not (Test-Path -LiteralPath $BaselineRoot)) { return $null }

    $candidate = Join-Path $BaselineRoot 'baseline.json'
    if (-not (Test-Path -LiteralPath $candidate)) { return $null }

    try {
        $raw = [System.IO.File]::ReadAllText($candidate)
        $obj = $raw | ConvertFrom-Json
        $obj
    }
    catch {
        $null
    }
}
