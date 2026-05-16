function Update-DiagBaseline {
    <#
    .SYNOPSIS
        Capture a fresh known-good baseline snapshot to disk.
    .DESCRIPTION
        Inventory services (Win32_Service), scheduled tasks
        (Get-ScheduledTask), autoruns (Win32_StartupCommand), and the top
        50 processes by working set, then serialize the result as
        baseline.json. Compare-DiagBaseline diffs against this snapshot on
        the next bundle run. Create the baseline directory if it does not
        already exist.
    .PARAMETER BaselineRoot
        Directory to write baseline.json into. Defaults to
        C:\ProgramData\DiagBundle\baseline. Created if missing.
    .INPUTS
        None.
    .OUTPUTS
        System.String. Absolute path of the baseline.json file just
        written.
    .EXAMPLE
        Update-DiagBaseline
    .NOTES
        Not called from Invoke-DiagBundle. Operators run this manually
        after a clean state, or opportunistically (open item #7).
        Get-ScheduledTask is skipped on hosts where the cmdlet is missing
        (older Server SKUs); the rest of the snapshot still captures.
        Timestamps use ISO-8601 with .fff precision and a Z suffix.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $BaselineRoot = 'C:\ProgramData\DiagBundle\baseline'
    )

    if (-not (Test-Path -LiteralPath $BaselineRoot)) {
        New-Item -ItemType Directory -Path $BaselineRoot -Force | Out-Null
    }

    $services = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Select-Object Name, DisplayName, State, StartMode, StartName, PathName

    $tasks = @()
    if (Get-Command -Name Get-ScheduledTask -ErrorAction SilentlyContinue) {
        $tasks = Get-ScheduledTask | Select-Object TaskPath, TaskName, State,
            @{n = 'Author'; e = { $_.Author } },
            @{n = 'Actions'; e = { ($_.Actions | ForEach-Object { $_.Execute }) -join '|' } }
    }

    $autoruns = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
        Select-Object Name, Command, Location, User

    $procs = Get-Process | Sort-Object -Property WorkingSet64 -Descending |
        Select-Object -First 50 -Property Name, Id,
            @{n = 'WorkingSetMB'; e = { [math]::Round($_.WorkingSet64 / 1MB, 1) } },
            @{n = 'Handles';      e = { $_.HandleCount } }

    $fmt = 'yyyy-MM-ddTHH:mm:ss.fffZ'
    $obj = [ordered]@{
        schema_version = '1.0'
        captured_utc   = (Get-Date).ToUniversalTime().ToString($fmt)
        host           = $env:COMPUTERNAME
        services       = @($services)
        scheduled_tasks = @($tasks)
        autoruns       = @($autoruns)
        top_processes  = @($procs)
    }

    $path = Join-Path $BaselineRoot 'baseline.json'
    $json = $obj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))

    $path
}
