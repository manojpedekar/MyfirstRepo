function Get-DiagRoleSQL {
    <#
    .SYNOPSIS
        Collect SQL Server service inventory, instance metadata, ERRORLOG copies, and recent SQL self-dumps.

    .DESCRIPTION
        Detect SQL Server by enumerating MSSQL*, SQLAgent$*, and SQLBrowser services
        OR by reading HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\InstalledInstances
        (and the WOW6432Node equivalent). When detected, write a services projection,
        enumerate instances from the registry, resolve each instance's ERRORLOG path
        from MSSQLServer\Parameters (-e value), and copy ERRORLOG files plus any
        recent SQLDump<NNNN>.* files that live alongside ERRORLOG. Each ERRORLOG set
        is capped at 50 MB total per instance; SQL self-dumps are capped separately
        at SqlDumpCapBytes per instance with the .txt and .log companions copied
        before the larger .mdmp binary. Per-artifact failures append to Errors but
        do not abort the collector.

    .PARAMETER WorkingDirectory
        Absolute path to the bundle staging directory. Artifacts write under
        raw\role_specific\sql, raw\role_specific\sql_errorlog, and
        raw\role_specific\sql_dumps beneath it.

    .PARAMETER WindowHours
        Lookback window in hours. Reserved for future ERRORLOG filtering; default 24.

    .PARAMETER SqlDumpWindowDays
        Maximum age in days for a SQL self-dump file to be eligible for copy.
        Defaults to 7 (matches Get-DiagWER's WindowDays).

    .PARAMETER SqlDumpCapBytes
        Per-instance size budget for SQL self-dump copies. Defaults to 100 MB.
        Companions (.txt, .log) are processed first newest-first so they ship even
        when a single .mdmp would consume the rest of the budget.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with path/category/type/description and per-type metadata), Errors (array of hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        $r = Get-DiagRoleSQL -WorkingDirectory 'C:\ProgramData\DiagBundle\work\bundle1'

    .EXAMPLE
        # Generous SQL dump budget for forensic preservation
        $r = Get-DiagRoleSQL -WorkingDirectory $work -SqlDumpCapBytes 500MB -SqlDumpWindowDays 30

    .NOTES
        Detection signal: any service whose Name matches MSSQL*, SQLAgent$*, or
        equals SQLBrowser, OR the registry value
        HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\InstalledInstances
        (or its WOW6432Node sibling). When neither is present, return Success=$true
        with empty Artifacts. This is "not applicable", not failure.

        InstalledInstances is a REG_MULTI_SZ *value*, not a subkey -- the collector
        reads it via Get-ItemProperty -Name. (Earlier versions used Test-Path
        against the value path, which always returns $false and silently skipped
        instance enumeration; this is fixed.)

        ERRORLOG paths come from each instance's
        HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\<instance_id>\MSSQLServer\Parameters,
        specifically the value beginning with "-e". ERRORLOG files may be locked
        open by the engine; the collector opens them with FileShare.ReadWrite to
        read past the lock. When a file exceeds the remaining per-instance budget,
        the collector seeks to (Length - remaining) and copies the tail; the
        artifact description records that the file was tailed.

        SQL self-dumps live in the same directory as ERRORLOG. SQL writes them as
        SQLDump<NNNN>.mdmp (binary minidump), SQLDump<NNNN>.txt (plain-text stack
        and short-stack signatures, the high-value triage file), and
        SQLDump<NNNN>.log (additional companion log). The collector copies
        companions first newest-first so the cheap text artifacts always ship,
        then minidumps newest-first while the per-instance dump budget allows.
        Skipped dumps are recorded as info-severity entries in Errors.

        Artifacts written under raw/role_specific/:
          - raw/role_specific/sql/services.json
          - raw/role_specific/sql/instances.json
          - raw/role_specific/sql_errorlog/<instance>/ERRORLOG
          - raw/role_specific/sql_errorlog/<instance>/ERRORLOG.<n>  (archives,
            current ERRORLOG processed first, 50 MB total cap per instance)
          - raw/role_specific/sql_dumps/<instance>/SQLDump<NNNN>.{mdmp,txt,log}
            (within SqlDumpWindowDays, capped at SqlDumpCapBytes per instance)

        Get-DiagRoles is the dispatcher and is responsible for calling this only
        when the role is detected; this collector also self-checks defensively and
        returns a no-op result when SQL Server is absent.

        The collector never throws. Per-artifact failures append to Errors with
        severity 'warning'. On fatal abort it returns Success=$false with populated
        Errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter()]
        [int] $WindowHours = 24,

        [Parameter()]
        [int] $SqlDumpWindowDays = 7,

        [Parameter()]
        [long] $SqlDumpCapBytes = 100MB
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
        $sqlServices = @()
        try {
            $sqlServices = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop |
                Where-Object { $_.Name -like 'MSSQL*' -or $_.Name -like 'SQLAgent$*' -or $_.Name -eq 'SQLBrowser' })
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleSQL'; reason = "Win32_Service query failed: $($_.Exception.Message)"; severity = 'warning' }
        }

        $instancesRegKey = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server'
        $instancesRegKeyWow = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server'
        $hasInstalledInstances = $false
        try {
            $hasInstalledInstances = (Test-Path "$instancesRegKey\InstalledInstances") -or (Test-Path "$instancesRegKeyWow\InstalledInstances")
        } catch { }

        if ($sqlServices.Count -eq 0 -and -not $hasInstalledInstances) {
            $result.Success = $true
            return $result
        }

        $rawSqlDir = Join-Path $WorkingDirectory 'raw\role_specific\sql'
        if (-not (Test-Path $rawSqlDir)) {
            try { New-Item -ItemType Directory -Path $rawSqlDir -Force | Out-Null } catch { }
        }

        $servicesProjected = @($sqlServices | ForEach-Object {
            [ordered]@{
                name         = "$($_.Name)"
                display_name = "$($_.DisplayName)"
                state        = "$($_.State)"
                start_mode   = "$($_.StartMode)"
                start_name   = "$($_.StartName)"
                path_name    = "$($_.PathName)"
                process_id   = [int]$_.ProcessId
            }
        })

        try {
            $svcData = [ordered]@{
                schema_version = '1.0'
                host           = @{ computer_name = $env:COMPUTERNAME }
                collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
                data           = [ordered]@{
                    count    = $servicesProjected.Count
                    services = $servicesProjected
                }
            }
            $svcPath = Join-Path $rawSqlDir 'services.json'
            $svcJson = $svcData | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($svcPath, $svcJson, [System.Text.UTF8Encoding]::new($false))

            $result.Artifacts += @{
                path           = 'raw/role_specific/sql/services.json'
                category       = 'sql_services'
                schema_version = '1.0'
                type           = 'derived'
                description    = 'SQL-related Windows services (engine, Agent, Browser)'
                row_count      = $servicesProjected.Count
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleSQL'; artifact = 'raw/role_specific/sql/services.json'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $instances = @()
        foreach ($baseKey in @($instancesRegKey, $instancesRegKeyWow)) {
            # InstalledInstances is a REG_MULTI_SZ *value* on the SQL Server
            # key, not a subkey. Test-Path against a value path returns false,
            # so check the parent key exists and then read the named value.
            if (-not (Test-Path $baseKey)) { continue }

            $instanceNames = @()
            try {
                $instanceNames = @((Get-ItemProperty -Path $baseKey -Name InstalledInstances -ErrorAction Stop).InstalledInstances)
            } catch {
                # InstalledInstances value absent on this hive (e.g. WOW6432Node
                # mirror has no SQL). Not an error -- just skip this hive.
                continue
            }
            if ($instanceNames.Count -eq 0) { continue }

            foreach ($instName in $instanceNames) {
                $instanceId = $null
                $errorLogPath = $null
                $logDir = $null

                try {
                    $namesKey = "$baseKey\Instance Names\SQL"
                    if (Test-Path $namesKey) {
                        $namesVals = Get-ItemProperty -Path $namesKey -ErrorAction Stop
                        $prop = $namesVals.PSObject.Properties | Where-Object { $_.Name -eq $instName } | Select-Object -First 1
                        if ($prop) { $instanceId = "$($prop.Value)" }
                    }
                } catch {
                    $result.Errors += @{ collector = 'Get-DiagRoleSQL'; reason = "Instance name lookup for '$instName' failed: $($_.Exception.Message)"; severity = 'warning' }
                }

                if ($instanceId) {
                    try {
                        $paramsKey = "$baseKey\$instanceId\MSSQLServer\Parameters"
                        if (Test-Path $paramsKey) {
                            $paramsVals = Get-ItemProperty -Path $paramsKey -ErrorAction Stop
                            $eArg = $paramsVals.PSObject.Properties |
                                Where-Object { $_.Name -notmatch '^PS' -and "$($_.Value)" -like '-e*' } |
                                Select-Object -First 1
                            if ($eArg) {
                                $errorLogPath = "$($eArg.Value)".Substring(2)
                                if ($errorLogPath) { $logDir = Split-Path -Parent $errorLogPath }
                            }
                        }
                    } catch {
                        $result.Errors += @{ collector = 'Get-DiagRoleSQL'; reason = "Parameters lookup for '$instanceId' failed: $($_.Exception.Message)"; severity = 'warning' }
                    }
                }

                $instances += [ordered]@{
                    instance_name   = "$instName"
                    registry_key    = $baseKey
                    instance_id     = $instanceId
                    error_log_path  = $errorLogPath
                    log_directory   = $logDir
                }
            }
        }

        try {
            $instData = [ordered]@{
                schema_version = '1.0'
                host           = @{ computer_name = $env:COMPUTERNAME }
                collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
                data           = [ordered]@{
                    count     = $instances.Count
                    instances = $instances
                }
            }
            $instPath = Join-Path $rawSqlDir 'instances.json'
            $instJson = $instData | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($instPath, $instJson, [System.Text.UTF8Encoding]::new($false))

            $result.Artifacts += @{
                path           = 'raw/role_specific/sql/instances.json'
                category       = 'sql_instances'
                schema_version = '1.0'
                type           = 'derived'
                description    = 'Detected SQL Server instances with registry-derived log paths'
                row_count      = $instances.Count
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleSQL'; artifact = 'raw/role_specific/sql/instances.json'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $perInstanceCapBytes = 50MB
        foreach ($inst in $instances) {
            if (-not $inst.log_directory -or -not (Test-Path $inst.log_directory)) { continue }

            $safeName = ($inst.instance_name -replace '[^A-Za-z0-9_\-]', '_')
            $destDir = Join-Path $WorkingDirectory ("raw\role_specific\sql_errorlog\$safeName")
            try {
                if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagRoleSQL'; reason = "Could not create $destDir : $($_.Exception.Message)"; severity = 'warning' }
                continue
            }

            $logFiles = @()
            try {
                $logFiles = @(Get-ChildItem -Path $inst.log_directory -ErrorAction Stop |
                    Where-Object { $_.Name -eq 'ERRORLOG' -or $_.Name -match '^ERRORLOG\.\d+$' } |
                    Sort-Object @{ Expression = { if ($_.Name -eq 'ERRORLOG') { -1 } else { [int]($_.Name -replace '^ERRORLOG\.', '') } } })
            } catch {
                $result.Errors += @{ collector = 'Get-DiagRoleSQL'; reason = "Listing ERRORLOG files in $($inst.log_directory) failed: $($_.Exception.Message)"; severity = 'warning' }
                continue
            }

            $remaining = $perInstanceCapBytes
            foreach ($lf in $logFiles) {
                if ($remaining -le 0) { break }

                $destFile = Join-Path $destDir $lf.Name
                $bytesCopied = 0
                $tailed = $false

                try {
                    $copyStart = 0L
                    if ($lf.Length -gt $remaining) {
                        $copyStart = [int64]($lf.Length - $remaining)
                        $tailed = $true
                    }

                    $src = [System.IO.File]::Open($lf.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        if ($copyStart -gt 0) { [void]$src.Seek($copyStart, [System.IO.SeekOrigin]::Begin) }
                        $dst = [System.IO.File]::Open($destFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                        try {
                            $src.CopyTo($dst)
                            $bytesCopied = $dst.Length
                        } finally {
                            $dst.Dispose()
                        }
                    } finally {
                        $src.Dispose()
                    }

                    $remaining -= $bytesCopied

                    $desc = if ($tailed) { "ERRORLOG tail (last $bytesCopied bytes of $($lf.Length))" } else { "ERRORLOG full copy ($bytesCopied bytes)" }
                    $result.Artifacts += @{
                        path        = "raw/role_specific/sql_errorlog/$safeName/$($lf.Name)"
                        category    = 'sql_errorlog'
                        type        = 'raw'
                        description = $desc
                    }
                } catch {
                    $result.Errors += @{
                        collector = 'Get-DiagRoleSQL'
                        artifact  = "raw/role_specific/sql_errorlog/$safeName/$($lf.Name)"
                        reason    = $_.Exception.Message
                        severity  = 'warning'
                    }
                }
            }
        }

        # SQL self-dumps (SQLDump<NNNN>.mdmp/.txt/.log) live in the same LOG dir
        # as ERRORLOG. The .txt companion is the high-value triage file (plain
        # text SQL stack at the moment of the exception); .mdmp is the binary
        # minidump and can be hundreds of MB. Always copy companions; copy
        # .mdmp files only while the per-instance budget allows.
        $dumpCutoff = (Get-Date).AddDays(-$SqlDumpWindowDays)
        foreach ($inst in $instances) {
            if (-not $inst.log_directory -or -not (Test-Path $inst.log_directory)) { continue }

            $dumpFiles = @()
            try {
                $dumpFiles = @(Get-ChildItem -Path $inst.log_directory -Filter 'SQLDump*' -File -ErrorAction Stop |
                    Where-Object { $_.LastWriteTime -ge $dumpCutoff })
            } catch {
                $result.Errors += @{ collector = 'Get-DiagRoleSQL'; reason = "Listing SQLDump files in $($inst.log_directory) failed: $($_.Exception.Message)"; severity = 'warning' }
                continue
            }
            if ($dumpFiles.Count -eq 0) { continue }

            $safeName = ($inst.instance_name -replace '[^A-Za-z0-9_\-]', '_')
            $dumpDestDir = Join-Path $WorkingDirectory ("raw\role_specific\sql_dumps\$safeName")
            try {
                if (-not (Test-Path $dumpDestDir)) { New-Item -ItemType Directory -Path $dumpDestDir -Force | Out-Null }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagRoleSQL'; reason = "Could not create $dumpDestDir : $($_.Exception.Message)"; severity = 'warning' }
                continue
            }

            # Companions first (small text), then minidumps newest-first.
            $companions = @($dumpFiles | Where-Object { $_.Extension -ne '.mdmp' } | Sort-Object LastWriteTime -Descending)
            $minidumps  = @($dumpFiles | Where-Object { $_.Extension -eq '.mdmp' } | Sort-Object LastWriteTime -Descending)

            $dumpRemaining = $SqlDumpCapBytes
            foreach ($df in (@($companions) + @($minidumps))) {
                if (($dumpRemaining - $df.Length) -lt 0) {
                    $result.Errors += @{
                        collector = 'Get-DiagRoleSQL'
                        artifact  = "raw/role_specific/sql_dumps/$safeName/$($df.Name)"
                        reason    = "SQL dump skipped: $($df.Length) bytes would breach per-instance cap of $SqlDumpCapBytes"
                        severity  = 'info'
                    }
                    continue
                }

                $destFile = Join-Path $dumpDestDir $df.Name
                try {
                    $src = [System.IO.File]::Open($df.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        $dst = [System.IO.File]::Open($destFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                        try {
                            $src.CopyTo($dst)
                        } finally { $dst.Dispose() }
                    } finally { $src.Dispose() }

                    $dumpRemaining -= $df.Length
                    $result.Artifacts += @{
                        path        = "raw/role_specific/sql_dumps/$safeName/$($df.Name)"
                        category    = 'sql_dump'
                        type        = 'raw'
                        description = "SQL self-dump $($df.Name) modified $($df.LastWriteTimeUtc.ToString($fmt))"
                    }
                } catch {
                    $result.Errors += @{
                        collector = 'Get-DiagRoleSQL'
                        artifact  = "raw/role_specific/sql_dumps/$safeName/$($df.Name)"
                        reason    = $_.Exception.Message
                        severity  = 'warning'
                    }
                }
            }
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{
            collector = 'Get-DiagRoleSQL'
            reason    = $_.Exception.Message
            severity  = 'error'
        }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
