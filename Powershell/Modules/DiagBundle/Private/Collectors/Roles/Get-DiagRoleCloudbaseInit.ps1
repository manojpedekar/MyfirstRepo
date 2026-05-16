function Get-DiagRoleCloudbaseInit {
    <#
    .SYNOPSIS
        Capture Cloudbase-Init install state, configuration, last-run log,
        LocalScripts inventory, and a parsed summary of plugin and script
        outcomes from the most recent run.

    .DESCRIPTION
        Cloudbase-Init is the OpenStack-family first-boot provisioning agent
        for Windows (the analog of cloud-init). On OpenShift Virtualization,
        OpenStack, and many KVM-based clouds it is the agent that renames
        the host, joins the domain, sets up the cloud user, runs userdata,
        and triggers downstream orchestrators (Salt, Puppet, Chef). When it
        misfires the symptom is usually a host stuck in a half-built state.

        Detection is install-path based and not gated on hypervisor: any
        host that has the Cloudbase-Init install directory or service is
        a candidate, regardless of whether Win32_ComputerSystem reports
        KVM, VMware, or anything else. Image lineage means a VM converted
        from KVM to another hypervisor can still have cloudbase-init
        artifacts worth collecting.

        Captures:
          - log\cloudbase-init.log (5 MB tail) and cloudbase-init-unattend.log (1 MB tail)
          - conf\cloudbase-init.conf and cloudbase-init-unattend.conf
          - LocalScripts\ inventory (name, size, sha256) AND file contents
            (these scripts are static, small, and define what runs at boot)
          - Userdata payload if still present on disk (best-effort; NoCloud
            cidata is typically unmounted post-boot so absence is normal).
            Captured userdata is redacted via Invoke-DiagRedaction.

        Derives summary/cloudbase_init.json with:
          - version, last_run_started_utc, last_run_completed_utc
          - last_run_outcome: succeeded | failed | unknown (succeeded iff
            log ends with "Plugins execution done")
          - plugins[]: name, stage, started_utc, ended_utc parsed from log
          - local_scripts[]: name, exit_code, stdout_bytes, stderr_bytes,
            stderr_had_content. A script with exit_code == 0 but non-empty
            stderr is flagged as a warning in collection_errors -- this is
            the pattern that masks a real failure as a benign exit.
          - metadata_service (e.g. NoCloudConfigDriveService)
          - instance_id (cloud instance UUID)
          - reboots_initiated[]: timestamps of "Rebooting" lines

    .PARAMETER WorkingDirectory
        Mandatory. Bundle staging root. Writes into raw\cloudbase_init\
        and summary\cloudbase_init.json.

    .PARAMETER WindowHours
        Optional. Lookback in hours, accepted for pipeline symmetry. Not
        used: cloudbase-init writes a single log per run cycle, not
        time-bucketed records.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success, Artifacts, Errors, DurationSeconds.

    .EXAMPLE
        Get-DiagRoleCloudbaseInit -WorkingDirectory $bundleRoot

    .NOTES
        Never throws. Returns Success=$true with empty Artifacts when
        cloudbase-init is not installed (Get-DiagRoles uses presence of
        artifacts, not Success, to decide whether to record dispatch).
        The userdata file (when present) is added to
        Invoke-DiagRedaction's candidate list separately.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter()]
        [int] $WindowHours = 24
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
        $installRoot = 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init'
        $svc = Get-Service -Name 'cloudbase-init' -ErrorAction SilentlyContinue

        $present = (Test-Path -LiteralPath $installRoot) -or $svc
        if (-not $present) {
            $result.Success = $true
            return $result
        }

        $rawDir = Join-Path $WorkingDirectory 'raw\cloudbase_init'
        if (-not (Test-Path -LiteralPath $rawDir)) {
            New-Item -ItemType Directory -Force -Path $rawDir | Out-Null
        }

        $cbData = [ordered]@{
            installed                = (Test-Path -LiteralPath $installRoot)
            install_path             = if (Test-Path -LiteralPath $installRoot) { $installRoot } else { $null }
            service_state            = if ($svc) { [string]$svc.Status }    else { $null }
            service_start_type       = if ($svc) { [string]$svc.StartType } else { $null }
            version                  = $null
            last_run_started_utc     = $null
            last_run_completed_utc   = $null
            last_run_outcome         = 'unknown'
            metadata_service         = $null
            instance_id              = $null
            plugins                  = @()
            local_scripts            = @()
            reboots_initiated        = @()
            userdata_captured        = $false
            userdata_redacted        = $false
            log_present              = $false
            log_size_bytes           = $null
            log_modified_utc         = $null
        }

        # ---------- Config files ----------
        $confSrc = Join-Path $installRoot 'conf'
        if (Test-Path -LiteralPath $confSrc) {
            $confDest = Join-Path $rawDir 'conf'
            if (-not (Test-Path -LiteralPath $confDest)) {
                New-Item -ItemType Directory -Force -Path $confDest | Out-Null
            }
            foreach ($name in @('cloudbase-init.conf', 'cloudbase-init-unattend.conf')) {
                $src = Join-Path $confSrc $name
                if (Test-Path -LiteralPath $src) {
                    try {
                        Copy-Item -LiteralPath $src -Destination (Join-Path $confDest $name) -Force -ErrorAction Stop
                        $result.Artifacts += @{
                            path        = "raw/cloudbase_init/conf/$name"
                            category    = 'cloudbase_init_config'
                            type        = 'raw'
                            description = "Cloudbase-Init configuration file: $name"
                        }
                    } catch {
                        $result.Errors += @{ collector = 'Get-DiagRoleCloudbaseInit'; artifact = "raw/cloudbase_init/conf/$name"; reason = $_.Exception.Message; severity = 'warning' }
                    }
                }
            }
        }

        # ---------- LocalScripts inventory + contents ----------
        $scriptsSrc = Join-Path $installRoot 'LocalScripts'
        if (Test-Path -LiteralPath $scriptsSrc) {
            $scriptsDest = Join-Path $rawDir 'LocalScripts'
            if (-not (Test-Path -LiteralPath $scriptsDest)) {
                New-Item -ItemType Directory -Force -Path $scriptsDest | Out-Null
            }
            $scriptInventory = New-Object System.Collections.ArrayList
            foreach ($f in (Get-ChildItem -LiteralPath $scriptsSrc -File -ErrorAction SilentlyContinue)) {
                $sha = $null
                try { $sha = (Get-FileHash -Path $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() } catch { }
                [void]$scriptInventory.Add([ordered]@{
                    name         = $f.Name
                    size_bytes   = [long]$f.Length
                    modified_utc = $f.LastWriteTimeUtc.ToString($fmt)
                    sha256       = $sha
                })
                try {
                    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $scriptsDest $f.Name) -Force -ErrorAction Stop
                    $result.Artifacts += @{
                        path        = "raw/cloudbase_init/LocalScripts/$($f.Name)"
                        category    = 'cloudbase_init_localscript'
                        type        = 'raw'
                        description = "Cloudbase-Init LocalScript: $($f.Name)"
                        sha256      = $sha
                    }
                } catch {
                    $result.Errors += @{ collector = 'Get-DiagRoleCloudbaseInit'; artifact = "raw/cloudbase_init/LocalScripts/$($f.Name)"; reason = $_.Exception.Message; severity = 'warning' }
                }
            }
            $cbData.local_scripts_inventory = @($scriptInventory)
        }

        # ---------- Log files ----------
        $logSrc = Join-Path $installRoot 'log'
        $mainLogPath = $null
        if (Test-Path -LiteralPath $logSrc) {
            $logDest = Join-Path $rawDir 'log'
            if (-not (Test-Path -LiteralPath $logDest)) {
                New-Item -ItemType Directory -Force -Path $logDest | Out-Null
            }
            foreach ($spec in @(
                @{ Name = 'cloudbase-init.log';          Cap = 5MB; Primary = $true  }
                @{ Name = 'cloudbase-init-unattend.log'; Cap = 1MB; Primary = $false }
            )) {
                $src = Join-Path $logSrc $spec.Name
                if (-not (Test-Path -LiteralPath $src)) { continue }
                try {
                    $li = Get-Item -LiteralPath $src -ErrorAction Stop
                    if ($spec.Primary) {
                        $cbData.log_present      = $true
                        $cbData.log_size_bytes   = [long]$li.Length
                        $cbData.log_modified_utc = $li.LastWriteTimeUtc.ToString($fmt)
                    }
                    $dest = Join-Path $logDest $spec.Name
                    if ($li.Length -le $spec.Cap) {
                        Copy-Item -LiteralPath $src -Destination $dest -Force -ErrorAction Stop
                    } else {
                        $fs = [System.IO.File]::Open($src, 'Open', 'Read', 'ReadWrite')
                        try {
                            $fs.Seek(-$spec.Cap, 'End') | Out-Null
                            $bytes = New-Object byte[] $spec.Cap
                            $read  = $fs.Read($bytes, 0, $spec.Cap)
                            $first = [Array]::IndexOf($bytes, [byte]10)
                            if ($first -gt 0 -and $first -lt $read - 1) {
                                [System.IO.File]::WriteAllBytes($dest, $bytes[($first + 1)..($read - 1)])
                            } else {
                                [System.IO.File]::WriteAllBytes($dest, $bytes[0..($read - 1)])
                            }
                        } finally { $fs.Dispose() }
                    }
                    if ($spec.Primary) { $mainLogPath = $dest }
                    $result.Artifacts += @{
                        path        = "raw/cloudbase_init/log/$($spec.Name)"
                        category    = 'cloudbase_init_log'
                        type        = 'raw'
                        description = "Cloudbase-Init log: $($spec.Name) (tail capped at $([math]::Round($spec.Cap/1MB,1)) MB)"
                    }
                } catch {
                    $result.Errors += @{ collector = 'Get-DiagRoleCloudbaseInit'; artifact = "raw/cloudbase_init/log/$($spec.Name)"; reason = $_.Exception.Message; severity = 'warning' }
                }
            }
        }

        # ---------- Parse the main log for summary fields ----------
        if ($mainLogPath -and (Test-Path -LiteralPath $mainLogPath)) {
            try {
                # Read full tail (already capped to 5MB on copy). Line-by-line
                # parser tracks the last "version" line as the start of the
                # most recent run, then collects plugins, script outcomes,
                # reboots, and the closing "Plugins execution done" sentinel.
                $lines = [System.IO.File]::ReadAllLines($mainLogPath)

                $rxTs       = '^(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})'
                $rxVersion  = "$rxTs.* INFO cloudbaseinit\.init \[-\] Cloudbase-Init version: (?<v>\S+)"
                $rxPlugin   = "$rxTs.* INFO cloudbaseinit\.init \[-\] Executing plugin '(?<n>[^']+)'"
                $rxStage    = "$rxTs.* INFO cloudbaseinit\.init \[-\] Executing plugins for stage '(?<s>[^']+)'"
                $rxScript   = "$rxTs.* INFO cloudbaseinit\.plugins\.common\.fileexecutils \[-\] Script ""(?<p>[^""]+)"" ended with exit code: (?<c>-?\d+)"
                $rxStdout   = '^.+\] User_data stdout:\s*$'
                $rxStderr   = '^.+\] User_data stderr:\s*$'
                $rxBytes    = "^b['""]"
                $rxReboot   = "$rxTs.* INFO cloudbaseinit\.init \[-\] Rebooting"
                $rxDone     = "$rxTs.* INFO cloudbaseinit\.init \[-\] Plugins execution done"
                $rxMeta     = "$rxTs.* INFO cloudbaseinit\.init \[-\] Metadata service loaded: '(?<m>[^']+)'"
                $rxInstance = "$rxTs.* DEBUG cloudbaseinit\.init \[-\] Instance id: (?<i>\S+)"

                $version       = $null
                $lastStart     = $null
                $lastComplete  = $null
                $metadataSvc   = $null
                $instanceId    = $null
                $currentStage  = $null
                $plugins       = New-Object System.Collections.ArrayList
                $scripts       = New-Object System.Collections.ArrayList
                $reboots       = New-Object System.Collections.ArrayList

                # Two-pass: locate the LAST version line; everything after it is
                # "the most recent run". Cloudbase-init reboots mid-flight and
                # respawns, so the same log may contain several boot cycles.
                # The user-visible run is the last cycle.
                $startIdx = 0
                for ($i = $lines.Length - 1; $i -ge 0; $i--) {
                    if ($lines[$i] -match $rxVersion) {
                        $startIdx = $i
                        if (-not $version) { $version = $matches['v'] }
                        if (-not $lastStart) { $lastStart = $matches['ts'] }
                        break
                    }
                }
                # If no version banner found, walk the whole tail.

                # Track script user_data stdout/stderr sections to count bytes
                $captureMode = $null    # 'stdout' or 'stderr'
                $captureBuf  = [System.Text.StringBuilder]::new()
                $captureFor  = $null    # script path the capture is associated with (best-effort: previous script line)
                $pendingScriptStdout = $null
                $pendingScriptStderr = $null

                for ($i = $startIdx; $i -lt $lines.Length; $i++) {
                    $line = $lines[$i]
                    if ($null -eq $line) { continue }

                    if ($line -match $rxStage) {
                        $currentStage = $matches['s']
                        continue
                    }
                    if ($line -match $rxPlugin) {
                        [void]$plugins.Add([ordered]@{
                            name      = $matches['n']
                            stage     = $currentStage
                            started_utc = $matches['ts']
                        })
                        continue
                    }
                    if ($line -match $rxMeta) {
                        $metadataSvc = $matches['m']
                        continue
                    }
                    if ($line -match $rxInstance) {
                        $instanceId = $matches['i']
                        continue
                    }
                    if ($line -match $rxReboot) {
                        [void]$reboots.Add($matches['ts'])
                        continue
                    }
                    if ($line -match $rxDone) {
                        $lastComplete = $matches['ts']
                        continue
                    }
                    if ($line -match $rxStdout) {
                        $captureMode = 'stdout'
                        $captureBuf.Clear() | Out-Null
                        continue
                    }
                    if ($line -match $rxStderr) {
                        $captureMode = 'stderr'
                        $captureBuf.Clear() | Out-Null
                        continue
                    }
                    if ($captureMode -and ($line -match $rxBytes -or $line -notmatch $rxTs)) {
                        # Body of the user_data block. Cloudbase-init writes
                        # the Python bytes-repr starting with b' or b" and
                        # the body can span multiple lines without timestamps.
                        [void]$captureBuf.Append($line)
                        [void]$captureBuf.Append("`n")
                        continue
                    }
                    if ($captureMode) {
                        # A new timestamped line ends the capture region.
                        if ($captureMode -eq 'stdout') {
                            $pendingScriptStdout = $captureBuf.Length
                        } else {
                            $pendingScriptStderr = $captureBuf.Length
                        }
                        $captureMode = $null
                        $captureBuf.Clear() | Out-Null
                        # Fall through to check this line for other patterns
                    }
                    if ($line -match $rxScript) {
                        $stderrBytes = if ($null -ne $pendingScriptStderr) { $pendingScriptStderr } else { 0 }
                        $stdoutBytes = if ($null -ne $pendingScriptStdout) { $pendingScriptStdout } else { 0 }
                        $exitCode    = [int]$matches['c']
                        $scriptPath  = $matches['p']
                        $scriptName  = Split-Path -Path $scriptPath -Leaf
                        [void]$scripts.Add([ordered]@{
                            name              = $scriptName
                            path              = $scriptPath
                            exit_code         = $exitCode
                            stdout_bytes      = $stdoutBytes
                            stderr_bytes      = $stderrBytes
                            stderr_had_content = ($stderrBytes -gt 0)
                            ended_utc         = $matches['ts']
                        })
                        # Flag the silent-failure pattern (exit 0 but stderr non-empty)
                        if ($exitCode -eq 0 -and $stderrBytes -gt 0) {
                            $result.Errors += @{
                                collector = 'Get-DiagRoleCloudbaseInit'
                                reason    = "LocalScript '$scriptName' exited 0 but wrote $stderrBytes bytes to stderr. Cloudbase-Init swallows this error; investigate."
                                severity  = 'warning'
                                artifact  = "raw/cloudbase_init/log/cloudbase-init.log"
                            }
                        }
                        $pendingScriptStdout = $null
                        $pendingScriptStderr = $null
                    }
                }

                $cbData.version                = $version
                $cbData.last_run_started_utc   = $lastStart
                $cbData.last_run_completed_utc = $lastComplete
                $cbData.last_run_outcome       = if ($lastComplete) { 'succeeded' } elseif ($lastStart) { 'failed' } else { 'unknown' }
                $cbData.metadata_service       = $metadataSvc
                $cbData.instance_id            = $instanceId
                $cbData.plugins                = @($plugins)
                $cbData.local_scripts          = @($scripts)
                $cbData.reboots_initiated      = @($reboots)
            } catch {
                $result.Errors += @{ collector = 'Get-DiagRoleCloudbaseInit'; reason = "Log parse failed: $($_.Exception.Message)"; severity = 'warning' }
            }
        }

        # ---------- Userdata (best-effort) ----------
        # NoCloud cidata is typically unmounted post-boot. Check a few known
        # cache locations; absence is normal and not an error.
        $userdataCandidates = @(
            'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\UserData\userdata',
            'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\UserData\user-data',
            'C:\ProgramData\Cloudbase Solutions\Cloudbase-Init\userdata',
            'C:\ProgramData\Cloudbase Solutions\Cloudbase-Init\user-data'
        )
        foreach ($cand in $userdataCandidates) {
            if (Test-Path -LiteralPath $cand) {
                try {
                    $dest = Join-Path $rawDir 'userdata.txt'
                    Copy-Item -LiteralPath $cand -Destination $dest -Force -ErrorAction Stop
                    $cbData.userdata_captured = $true
                    # Redaction runs centrally via Invoke-DiagRedaction; flag intent here.
                    $cbData.userdata_redacted = $true
                    $result.Artifacts += @{
                        path        = 'raw/cloudbase_init/userdata.txt'
                        category    = 'cloudbase_init_userdata'
                        type        = 'raw'
                        description = "Cloudbase-Init userdata payload (redacted via Invoke-DiagRedaction)"
                    }
                    break
                } catch {
                    $result.Errors += @{ collector = 'Get-DiagRoleCloudbaseInit'; artifact = 'raw/cloudbase_init/userdata.txt'; reason = $_.Exception.Message; severity = 'warning' }
                }
            }
        }

        # ---------- Write summary ----------
        $sumData = [ordered]@{
            schema_version = '1.0'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data           = $cbData
        }
        $sumPath = Join-Path $WorkingDirectory 'summary\cloudbase_init.json'
        [System.IO.File]::WriteAllText($sumPath, ($sumData | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
        $result.Artifacts += @{
            path           = 'summary/cloudbase_init.json'
            category       = 'cloudbase_init'
            schema_version = '1.0'
            type           = 'derived'
            description    = "Cloudbase-Init last-run summary: version=$($cbData.version), outcome=$($cbData.last_run_outcome), scripts=$(@($cbData.local_scripts).Count)"
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagRoleCloudbaseInit'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
