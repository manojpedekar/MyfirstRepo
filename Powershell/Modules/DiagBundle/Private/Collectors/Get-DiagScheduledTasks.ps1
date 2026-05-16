function Get-DiagScheduledTasks {
    <#
    .SYNOPSIS
        Export every scheduled task to XML and check a known-expected
        task list for absences, recording a derived summary.

    .DESCRIPTION
        Invokes schtasks.exe /query /xml ONE to produce one consolidated
        XML document for every task on the host (triggers, actions,
        principals, settings). Writes the result to
        raw/tasks/scheduled_tasks.xml.

        Schema 1.0 addition (2026-05-11 review, Gap 9): also reads
        Resources/expected_tasks.json (org-specific list of tasks that
        should exist on every healthy host) and checks each entry via
        Get-ScheduledTask. Emits a derived summary/scheduled_tasks.json
        with the per-name present/last_run/result/state and flags
        absences as warnings in manifest.collection_errors. The list is
        data-driven so image owners can extend it without code changes.

        Reading tasks owned by other users (or the SYSTEM-only set)
        requires administrator privileges; a non-admin run still emits
        XML but with reduced coverage.

    .PARAMETER WorkingDirectory
        Mandatory. Absolute path to the bundle staging root. The
        collector writes into raw\tasks\ and summary\.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success, Artifacts, Errors, DurationSeconds.

    .EXAMPLE
        Get-DiagScheduledTasks -WorkingDirectory $bundleRoot

    .NOTES
        Writes:
          - raw/tasks/scheduled_tasks.xml
          - summary/scheduled_tasks.json (expected_tasks check)

        Never throws; populates Errors and returns Success=$false on
        fatal abort. Missing Resources/expected_tasks.json degrades
        gracefully (the expected_tasks block is omitted, no warnings).
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
        # ---------- Raw XML dump ----------
        $out = Join-Path $WorkingDirectory 'raw\tasks\scheduled_tasks.xml'
        $xml = Invoke-DiagTimed -Collector 'Get-DiagScheduledTasks' -Step 'schtasks /query /xml ONE' -Action { & schtasks.exe /query /xml ONE 2>&1 }
        if ($LASTEXITCODE -ne 0) {
            $result.Errors += @{ collector = 'Get-DiagScheduledTasks'; artifact = 'raw/tasks/scheduled_tasks.xml'; reason = "schtasks exit $LASTEXITCODE"; severity = 'warning' }
        } else {
            [System.IO.File]::WriteAllText($out, ($xml -join "`r`n"), [System.Text.UTF8Encoding]::new($false))
            $result.Artifacts += @{
                path        = 'raw/tasks/scheduled_tasks.xml'
                category    = 'scheduled_tasks'
                type        = 'raw'
                description = 'schtasks /query /xml ONE'
            }
        }

        # ---------- Expected-tasks absence check ----------
        $resourceFile = $null
        $modBase = (Get-Module DiagBundle).ModuleBase
        if ($modBase) {
            $resourceFile = Join-Path $modBase 'Resources\expected_tasks.json'
        }

        $expectedTasksReport = $null
        if ($resourceFile -and (Test-Path -LiteralPath $resourceFile)) {
            try {
                $cfg = Get-Content -LiteralPath $resourceFile -Raw | ConvertFrom-Json -ErrorAction Stop
                $expected = @($cfg.expected_tasks)

                $report = New-Object System.Collections.ArrayList
                foreach ($entry in $expected) {
                    $name = [string]$entry.name
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }

                    $present = $false
                    $state   = $null
                    $lastRun = $null
                    $lastRes = $null
                    try {
                        $t = Get-ScheduledTask -TaskName $name -ErrorAction Stop
                        $present = $true
                        $state   = [string]$t.State
                        try {
                            $info = Get-ScheduledTaskInfo -TaskName $name -ErrorAction Stop
                            if ($info.LastRunTime -and $info.LastRunTime.Year -gt 1900) {
                                $lastRun = $info.LastRunTime.ToUniversalTime().ToString($fmt)
                            }
                            $lastRes = [int]$info.LastTaskResult
                        } catch { }
                    } catch {
                        $present = $false
                    }

                    [void]$report.Add([ordered]@{
                        name          = $name
                        present       = $present
                        state         = $state
                        last_run_utc  = $lastRun
                        last_result   = $lastRes
                        rationale     = [string]$entry.rationale
                    })

                    if (-not $present) {
                        $result.Errors += @{
                            collector = 'Get-DiagScheduledTasks'
                            reason    = "Expected scheduled task '$name' is not registered on this host. $([string]$entry.rationale)"
                            severity  = 'warning'
                            artifact  = 'summary/scheduled_tasks.json'
                        }
                    }
                }

                $expectedTasksReport = @($report)
            } catch {
                $result.Errors += @{ collector = 'Get-DiagScheduledTasks'; artifact = 'Resources/expected_tasks.json'; reason = "Failed to read expected_tasks.json: $($_.Exception.Message)"; severity = 'warning' }
            }
        }

        if ($null -ne $expectedTasksReport) {
            $sumData = [ordered]@{
                schema_version = '1.0'
                host           = @{ computer_name = $env:COMPUTERNAME }
                collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
                data           = [ordered]@{
                    expected_tasks_source     = 'Resources/expected_tasks.json'
                    expected_tasks            = $expectedTasksReport
                    expected_tasks_total      = $expectedTasksReport.Count
                    expected_tasks_present    = @($expectedTasksReport | Where-Object { $_.present }).Count
                    expected_tasks_missing    = @($expectedTasksReport | Where-Object { -not $_.present }).Count
                }
            }
            $sumPath = Join-Path $WorkingDirectory 'summary\scheduled_tasks.json'
            [System.IO.File]::WriteAllText($sumPath, ($sumData | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
            $result.Artifacts += @{
                path           = 'summary/scheduled_tasks.json'
                category       = 'scheduled_tasks_expected'
                schema_version = '1.0'
                type           = 'derived'
                description    = "Expected-tasks absence check: $($sumData.data.expected_tasks_missing) missing of $($sumData.data.expected_tasks_total)"
            }
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagScheduledTasks'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
