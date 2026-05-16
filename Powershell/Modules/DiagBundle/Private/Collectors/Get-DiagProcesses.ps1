function Get-DiagProcesses {
    <#
    .SYNOPSIS
        Capture top processes by CPU, memory, handles, and threads.

    .DESCRIPTION
        Join Get-Process metrics with Win32_Process for executable path, command
        line, parent PID, and owner. Emit summary/processes.json with a total
        count and four top-N lists (top_by_cpu_seconds, top_by_workingset_mb,
        top_by_handles, top_by_threads). Command lines ship verbatim here and
        pass through Invoke-DiagRedaction at finalize. Runs in parallel with peer
        collectors. Standard user privileges work for owned processes; admin is
        needed to read paths, command lines, and owners across all sessions.

    .PARAMETER WorkingDirectory
        Mandatory. Absolute path to the bundle staging root. The collector writes
        into the existing summary\ subdirectory.

    .PARAMETER TopN
        Optional. Integer count of rows kept per dimension. Default 50. Lower
        values shrink the artifact; higher values lengthen it.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with
        path/category/type/description and per-type metadata), Errors (array of
        hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagProcesses -WorkingDirectory $bundleRoot

    .EXAMPLE
        Get-DiagProcesses -WorkingDirectory $bundleRoot -TopN 100

    .NOTES
        Writes:
          - summary/processes.json

        Owner lookup uses GetOwner on Win32_Process and may fail per-process under
        non-admin contexts; the row still ships with user=$null. Never throws;
        populates Errors and returns Success=$false on fatal abort.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter()]
        [int] $TopN = 50
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
        $cim = @{}
        $cimProcs = Invoke-DiagTimed -Collector 'Get-DiagProcesses' -Step 'Get-CimInstance Win32_Process' -Action {
            Get-CimInstance Win32_Process -ErrorAction Stop
        }
        foreach ($p in $cimProcs) {
            $cim[[int]$p.ProcessId] = $p
        }

        $procs = @()
        foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
            $cp = $cim[$p.Id]
            $procs += [ordered]@{
                pid           = $p.Id
                name          = $p.ProcessName
                path          = if ($cp) { [string]$cp.ExecutablePath } else { $null }
                command_line  = if ($cp) { [string]$cp.CommandLine }    else { $null }
                parent_pid    = if ($cp) { [int]$cp.ParentProcessId }   else { 0 }
                cpu_seconds   = if ($null -ne $p.CPU) { [math]::Round([double]$p.CPU, 2) } else { $null }
                workingset_mb = [math]::Round($p.WorkingSet64 / 1MB, 1)
                privatemem_mb = [math]::Round($p.PrivateMemorySize64 / 1MB, 1)
                handles       = $p.HandleCount
                threads       = $p.Threads.Count
                start_time    = if ($p.StartTime) { $p.StartTime.ToUniversalTime().ToString($fmt) } else { $null }
                user          = if ($cp) { try { ($cp | Invoke-CimMethod -MethodName GetOwner -ErrorAction SilentlyContinue).User } catch { $null } } else { $null }
            }
        }

        function _Top($list, $key, $n) {
            # Sort-Object -Property cannot reach OrderedDictionary keys via
            # property reflection in PS 5.1, so the original direct sort
            # silently no-ops. Use a calculated property to access the value
            # explicitly. [double] keeps numeric ordering correct and turns
            # null into 0, which sinks under -Descending.
            ,@($list | Sort-Object -Property @{Expression = { [double]($_[$key]) }} -Descending | Select-Object -First $n)
        }

        $data = [ordered]@{
            schema_version = '1.0'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data           = [ordered]@{
                total_count          = $procs.Count
                truncated_to         = $TopN
                sort_key             = 'top_n_per_dimension'
                top_by_cpu_seconds   = _Top $procs 'cpu_seconds'   $TopN
                top_by_workingset_mb = _Top $procs 'workingset_mb' $TopN
                top_by_handles       = _Top $procs 'handles'       $TopN
                top_by_threads       = _Top $procs 'threads'       $TopN
            }
        }

        $path = Join-Path $WorkingDirectory 'summary\processes.json'
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))

        $result.Artifacts += @{
            path           = 'summary/processes.json'
            category       = 'processes'
            schema_version = '1.0'
            type           = 'derived'
            description    = "Top $TopN processes per dimension (CPU, memory, handles, threads)"
            row_count      = $procs.Count
        }
        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagProcesses'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
