function Get-DiagServices {
    <#
    .SYNOPSIS
        Inventory all services with state, startup, account, and dependency map.

    .DESCRIPTION
        Query Win32_Service for the full service list and Win32_DependentService to
        build a per-service depends_on map. Emit summary/services.json with totals,
        running count, stopped-but-Auto count and names, and a row per service
        (name, display, state, start mode, start account, binary path, PID,
        delayed-auto flag, dependencies). Runs in parallel with peer collectors.
        Standard user privileges suffice; CIM read access is required.

    .PARAMETER WorkingDirectory
        Mandatory. Absolute path to the bundle staging root. The collector writes
        into the existing summary\ subdirectory.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with
        path/category/type/description and per-type metadata), Errors (array of
        hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagServices -WorkingDirectory $bundleRoot

    .NOTES
        Writes:
          - summary/services.json

        Dependency map failures are swallowed; the services list still ships with
        empty depends_on arrays. Never throws; populates Errors and returns
        Success=$false on fatal abort.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory
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
        $svcs = @(Invoke-DiagTimed -Collector 'Get-DiagServices' -Step 'Get-CimInstance Win32_Service' -Action {
            Get-CimInstance -ClassName Win32_Service -ErrorAction Stop
        } | ForEach-Object {
            [ordered]@{
                name          = $_.Name
                display_name  = $_.DisplayName
                state         = $_.State
                start_mode    = $_.StartMode
                start_name    = $_.StartName
                path_name     = $_.PathName
                process_id    = [int]$_.ProcessId
                description   = $_.Description
                delayed_auto  = [bool]$_.DelayedAutoStart
            }
        })

        $depMap = @{}
        try {
            $deps = Get-CimInstance Win32_DependentService -ErrorAction SilentlyContinue
            foreach ($d in $deps) {
                $antecedentName = ($d.Antecedent -split 'Name=\"')[1] -replace '\".*', ''
                $dependentName  = ($d.Dependent  -split 'Name=\"')[1] -replace '\".*', ''
                if (-not $depMap.ContainsKey($dependentName)) { $depMap[$dependentName] = @() }
                $depMap[$dependentName] += $antecedentName
            }
        } catch { }
        foreach ($s in $svcs) {
            $s.depends_on = if ($depMap.ContainsKey($s.name)) { @($depMap[$s.name] | Sort-Object -Unique) } else { @() }
        }

        $running = @($svcs | Where-Object { $_.state -eq 'Running' })
        $stoppedAuto = @($svcs | Where-Object { $_.state -ne 'Running' -and $_.start_mode -eq 'Auto' })

        $data = [ordered]@{
            schema_version = '1.0'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data           = [ordered]@{
                total_count          = $svcs.Count
                running_count        = $running.Count
                stopped_auto_count   = $stoppedAuto.Count
                stopped_auto_names   = @($stoppedAuto | ForEach-Object { $_.name })
                services             = $svcs
            }
        }

        $path = Join-Path $WorkingDirectory 'summary\services.json'
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))

        $result.Artifacts += @{
            path           = 'summary/services.json'
            category       = 'services'
            schema_version = '1.0'
            type           = 'derived'
            description    = 'All services with state, startup, account, dependencies'
            row_count      = $svcs.Count
        }
        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagServices'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
