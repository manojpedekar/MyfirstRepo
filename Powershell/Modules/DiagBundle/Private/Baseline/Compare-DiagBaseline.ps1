function Compare-DiagBaseline {
    <#
    .SYNOPSIS
        Diff a saved baseline against the current host state.
    .DESCRIPTION
        Re-inventory services, scheduled tasks, and autoruns, then compute
        added and removed entries against the supplied baseline by
        identity key (service Name, TaskPath+TaskName, autorun
        Location+Name). Write the result to summary/baseline_diff.json
        inside the bundle. Invoke-DiagBundle calls this only when
        Get-DiagBaseline returned a non-null baseline.
    .PARAMETER Baseline
        The parsed baseline object returned by Get-DiagBaseline. Expected
        to expose services, scheduled_tasks, autoruns, and captured_utc.
    .PARAMETER BundleRoot
        Absolute path to the staged bundle root. The output file lands at
        BundleRoot\summary\baseline_diff.json.
    .INPUTS
        None.
    .OUTPUTS
        System.String. The forward-slash relative path
        summary/baseline_diff.json, suitable for passing straight into
        Add-DiagArtifact.
    .EXAMPLE
        $rel = Compare-DiagBaseline -Baseline $baseline -BundleRoot $workDir
        Add-DiagArtifact -Manifest $manifest -Artifact @{
            path = $rel; category = 'baseline_diff'; type = 'derived'
        }
    .NOTES
        Diffs are name/key based -- a service whose StartMode changed but
        whose Name stayed the same does not show up as added or removed.
        Output object always carries added and removed arrays for each
        category, even when both are empty.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Baseline,
        [Parameter(Mandatory)] [string] $BundleRoot
    )

    function _Diff([object[]]$Old, [object[]]$New, [string]$Key) {
        $oldMap = @{}
        foreach ($o in @($Old)) {
            if ($null -ne $o -and $null -ne $o.$Key) { $oldMap[[string]$o.$Key] = $o }
        }
        $newMap = @{}
        foreach ($n in @($New)) {
            if ($null -ne $n -and $null -ne $n.$Key) { $newMap[[string]$n.$Key] = $n }
        }

        $added   = @($newMap.Keys | Where-Object { -not $oldMap.ContainsKey($_) } | Sort-Object)
        $removed = @($oldMap.Keys | Where-Object { -not $newMap.ContainsKey($_) } | Sort-Object)
        @{ added = $added; removed = $removed }
    }

    $services = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Select-Object Name, State, StartMode

    $tasks = @()
    if (Get-Command -Name Get-ScheduledTask -ErrorAction SilentlyContinue) {
        $tasks = Get-ScheduledTask | Select-Object TaskPath, TaskName, State,
            @{n = 'Key'; e = { "$($_.TaskPath)$($_.TaskName)" } }
    }

    $autoruns = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
        Select-Object Name, Command, Location, User,
            @{n = 'Key'; e = { "$($_.Location)|$($_.Name)" } }

    $svcDiff   = _Diff $Baseline.services @($services)        'Name'
    $taskDiff  = _Diff $Baseline.scheduled_tasks @($tasks)    'Key'
    $autoDiff  = _Diff $Baseline.autoruns @($autoruns)        'Key'

    $fmt = 'yyyy-MM-ddTHH:mm:ss.fffZ'
    $diff = [ordered]@{
        schema_version = '1.0'
        baseline_captured_utc = $Baseline.captured_utc
        compared_utc          = (Get-Date).ToUniversalTime().ToString($fmt)
        services        = $svcDiff
        scheduled_tasks = $taskDiff
        autoruns        = $autoDiff
    }

    $outPath = Join-Path $BundleRoot 'summary\baseline_diff.json'
    $json = $diff | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($outPath, $json, [System.Text.UTF8Encoding]::new($false))

    'summary/baseline_diff.json'
}
