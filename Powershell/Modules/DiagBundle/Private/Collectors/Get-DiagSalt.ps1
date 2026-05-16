function _ParseSaltMinionYaml {
    <#
    .SYNOPSIS
        Tolerant minion-config YAML parser that handles scalar, inline-list,
        and block-list forms of every directive we care about.

    .DESCRIPTION
        PowerShell 5.1 has no built-in YAML parser. The PowerShell-Yaml
        module is not part of WMF and we cannot assume it is installed on
        the fleet. The previous regex-based extractor handled scalar
        `master: host` but silently failed in edge cases (BOM, trailing
        whitespace, quoted scalars). Replace with a small line-oriented
        parser that recognises three forms for each multi-value directive:

            master: host.example.com               # scalar
            master: [a, b]                         # inline list
            master:                                # block list
              - a
              - b

        Returns a hashtable with id, master (array), log_file, saltenv,
        verify_master_pubkey_sign, autosign_grains. Unknown keys are
        ignored. Comments (#) are stripped. Quoted scalars are unquoted.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Text)

    $result = @{
        id                        = $null
        master                    = @()
        log_file                  = $null
        saltenv                   = $null
        verify_master_pubkey_sign = $false
        autosign_grains           = @()
    }

    if ([string]::IsNullOrEmpty($Text)) { return $result }

    $lines = $Text -split "`r?`n"
    $inMasterBlock   = $false
    $inAutosignBlock = $false

    foreach ($raw in $lines) {
        $line = $raw

        # Strip end-of-line comment (but leave quoted # alone). Cheap
        # approximation: only strip when # is preceded by whitespace.
        $line = $line -replace '\s+#.*$', ''
        $line = $line.TrimEnd()
        if ([string]::IsNullOrWhiteSpace($line)) {
            # Blank line ends any open block-list context
            $inMasterBlock   = $false
            $inAutosignBlock = $false
            continue
        }

        # Top-level key (no indentation): "key:" or "key: value"
        if ($line -match '^(?<k>[A-Za-z_][\w]*)\s*:\s*(?<v>.*)$') {
            $key = $matches['k']
            $val = $matches['v'].Trim()
            $inMasterBlock   = $false
            $inAutosignBlock = $false

            if ([string]::IsNullOrEmpty($val)) {
                # Possible block-list opener
                switch ($key) {
                    'master'          { $inMasterBlock   = $true }
                    'autosign_grains' { $inAutosignBlock = $true }
                }
                continue
            }

            # Inline list: [a, b, c]
            if ($val -match '^\[(?<body>.*)\]$') {
                $items = @($matches['body'] -split ',' | ForEach-Object { ($_.Trim()).Trim('"').Trim("'") } | Where-Object { $_ })
                switch ($key) {
                    'master'          { $result.master          = $items }
                    'autosign_grains' { $result.autosign_grains = $items }
                }
                continue
            }

            # Scalar
            $clean = $val.Trim('"').Trim("'")
            switch ($key) {
                'id'                        { $result.id       = $clean }
                'master'                    { $result.master   = @($clean) }
                'log_file'                  { $result.log_file = $clean }
                'saltenv'                   { $result.saltenv  = $clean }
                'verify_master_pubkey_sign' { $result.verify_master_pubkey_sign = ($clean -match '^(?i)(true|yes|on|1)$') }
            }
            continue
        }

        # Block-list item: "  - value"
        if ($line -match '^\s*-\s*(?<v>.+)$') {
            $item = ($matches['v']).Trim().Trim('"').Trim("'")
            if ($inMasterBlock) {
                $result.master += $item
            } elseif ($inAutosignBlock) {
                $result.autosign_grains += $item
            }
        }
    }

    return $result
}

function _ProbeSaltTcp {
    <#
    .SYNOPSIS
        TCP-probe a Salt master port with measured RTT. Used for ports
        4505 (publish) and 4506 (request). Mirrors the WSUS probe pattern
        in _ProbeDiagWsus.
    .OUTPUTS
        OrderedDictionary with host, resolved_ip, port, tcp_ok, rtt_ms.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $HostName,
        [Parameter(Mandatory)] [int]    $Port,
        [Parameter()] [int] $TimeoutSec = 3
    )

    $entry = [ordered]@{
        host         = $HostName
        resolved_ip  = $null
        port         = $Port
        tcp_ok       = $false
        rtt_ms       = -1
    }

    try {
        $ips = [System.Net.Dns]::GetHostAddresses($HostName) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
        if ($ips -and $ips.Count -gt 0) {
            $entry.resolved_ip = [string]$ips[0]
        }
    } catch {
        $entry.dns_error = $_.Exception.Message
        return $entry
    }

    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $task = $client.ConnectAsync($HostName, $Port)
        if ($task.Wait([TimeSpan]::FromSeconds($TimeoutSec))) {
            $sw.Stop()
            $entry.tcp_ok = [bool]$client.Connected
            $entry.rtt_ms = [int]$sw.ElapsedMilliseconds
        } else {
            $sw.Stop()
            $entry.rtt_ms = $TimeoutSec * 1000
        }
    } catch {
        $entry.error = $_.Exception.Message
    } finally {
        if ($client) { $client.Close() }
    }

    return $entry
}

function _RunSaltCallProbe {
    <#
    .SYNOPSIS
        Run a salt-call --local or salt-call (master-touching) probe with
        a timeout. Returns the captured stdout text plus exit code and
        elapsed ms. Used by Get-DiagSalt to exercise the minion at
        collection time.
    .OUTPUTS
        Hashtable with success, exit_code, stdout, stderr, duration_ms, timed_out.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $SaltCallExe,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter()] [int] $TimeoutSec = 15
    )

    $entry = @{
        success     = $false
        exit_code   = $null
        stdout      = ''
        stderr      = ''
        duration_ms = 0
        timed_out   = $false
    }

    # ProcessStartInfo.ArgumentList is .NET Core / 5+ only. PowerShell 5.1
    # runs on .NET Framework 4.x which exposes only .Arguments (single
    # string). Build a quoted-and-joined argument string instead.
    $quoted = $Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName               = $SaltCallExe
    $proc.StartInfo.Arguments              = ($quoted -join ' ')
    $proc.StartInfo.UseShellExecute        = $false
    $proc.StartInfo.RedirectStandardOutput = $true
    $proc.StartInfo.RedirectStandardError  = $true
    $proc.StartInfo.CreateNoWindow         = $true

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        [void]$proc.Start()
        $stdoutBuf = New-Object System.Text.StringBuilder
        $stderrBuf = New-Object System.Text.StringBuilder
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        if ($proc.WaitForExit($TimeoutSec * 1000)) {
            [void]$stdoutBuf.Append($stdoutTask.Result)
            [void]$stderrBuf.Append($stderrTask.Result)
            $entry.exit_code = $proc.ExitCode
            $entry.success   = ($proc.ExitCode -eq 0)
        } else {
            $entry.timed_out = $true
            try { $proc.Kill() } catch { }
            $entry.exit_code = -1
        }
        $sw.Stop()
        $entry.duration_ms = [int]$sw.ElapsedMilliseconds
        $entry.stdout = $stdoutBuf.ToString()
        $entry.stderr = $stderrBuf.ToString()
    } catch {
        $sw.Stop()
        $entry.duration_ms = [int]$sw.ElapsedMilliseconds
        $entry.error = $_.Exception.Message
    } finally {
        try { $proc.Dispose() } catch { }
    }

    return $entry
}

function Get-DiagSalt {
    <#
    .SYNOPSIS
        Inventory the Salt minion installation, exercise it with live
        salt-call probes, capture configuration / logs / grains / PKI
        state, and probe TCP reachability to the configured master. Also
        detects peer orchestrator agents (PDQ).

    .DESCRIPTION
        Schema 1.2 changes (2026-05-11 review):
          - Tolerant YAML parser handles scalar/inline-list/block-list
            forms of `master:`, `id:`, etc. (Gap 3).
          - Always probes the default Windows log path even when
            log_file is not explicitly set in the config (Gap 2).
          - Captures cached minion_id file and conf/minion.d drop-ins
            (Gap 7); these were partially captured before.
          - Captures static grains file at conf/grains and conf/grains.d/
            and runs salt-call --local grains.items, flagging an empty
            ssnc_server_role grain as a warning -- that is the field that
            decides top.sls targeting on this org's fleet (Gap 6).
          - Live probes: test.ping, grains.items, state.show_top for the
            active saltenv AND base, saltutil.is_running (Gap 8). On by
            default per D7. State.show_top assignment count of 0 in the
            active env is flagged as a warning -- the canonical "host
            matches no states" signal.
          - PKI inventory: presence and sha256 of minion.pem/minion.pub/
            minion_master.pub/master_sign.pub. When the config sets
            verify_master_pubkey_sign:True and master_sign.pub is
            missing, raise an error per D3 (every published job would be
            silently rejected) (Gap 4).
          - TCP probes to ports 4505 and 4506 of each configured master
            with measured RTT, honouring -SkipNetworkTests (Gap 5).

        SECURITY: never reads or copies the PKI private key
        (`conf\pki\minion\minion.pem`). PKI inventory captures size and
        sha256 only; no key material leaves the host. Pillar data is
        never executed -- pillar.items is rendered with secrets by design
        and is not safe to include in a diagnostic bundle.

    .PARAMETER WorkingDirectory
        Mandatory. Absolute path to the bundle staging root.

    .PARAMETER WindowHours
        Optional. Lookback in hours for "recent" jobs filtering. Default 24.

    .PARAMETER SkipNetworkTests
        Optional. When $true, skip the TCP probes to the Salt master.
        Live salt-call --local probes still run (they are process-local).
        Default $false.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success, Artifacts, Errors, DurationSeconds.

    .NOTES
        Never throws. Returns Success=$true with installed=false in the
        summary when Salt is not present so the orchestrator does not
        flag the absence as a collection failure. PDQ detection runs
        unconditionally.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter()]
        [int] $WindowHours = 24,

        [Parameter()]
        [bool] $SkipNetworkTests = $false
    )

    $started = Get-Date
    $result = [pscustomobject]@{
        Success         = $false
        Artifacts       = @()
        Errors          = @()
        DurationSeconds = 0
    }
    $fmt    = 'yyyy-MM-ddTHH:mm:ss.fffZ'
    $cutoff = (Get-Date).AddHours(-$WindowHours)

    try {
        $rawDir = Join-Path $WorkingDirectory 'raw\salt'
        if (-not (Test-Path -LiteralPath $rawDir)) {
            New-Item -ItemType Directory -Force -Path $rawDir | Out-Null
        }

        # ---------- Salt install detection ----------
        $candidates = @(
            @{ InstallPath = 'C:\Program Files\Salt Project\Salt'; ConfRoot = 'C:\Program Files\Salt Project\Salt\conf'; VarRoot = 'C:\Program Files\Salt Project\Salt\var'; Layout = 'onedir' }
            @{ InstallPath = 'C:\salt';                            ConfRoot = 'C:\salt\conf';                            VarRoot = 'C:\salt\var';                            Layout = 'legacy' }
        )

        # The onedir installer commonly stages conf and var under
        # C:\ProgramData\Salt Project\Salt rather than under Program Files.
        # Detect that layout too. ProgramData paths are the canonical
        # writable locations on Windows; many fleets use them.
        $programDataConf = 'C:\ProgramData\Salt Project\Salt\conf'
        $programDataVar  = 'C:\ProgramData\Salt Project\Salt\var'

        $salt = $null
        foreach ($cand in $candidates) {
            if (Test-Path -LiteralPath $cand.InstallPath) {
                $salt = [hashtable]$cand
                # Prefer ProgramData layout when present.
                if ($cand.Layout -eq 'onedir' -and (Test-Path -LiteralPath $programDataConf)) {
                    $salt.ConfRoot = $programDataConf
                }
                if ($cand.Layout -eq 'onedir' -and (Test-Path -LiteralPath $programDataVar)) {
                    $salt.VarRoot = $programDataVar
                }
                break
            }
        }

        $svc = Get-Service -Name 'salt-minion' -ErrorAction SilentlyContinue

        $saltData = [ordered]@{
            installed                    = $false
            install_path                 = $null
            install_layout               = $null
            conf_root                    = $null
            var_root                     = $null
            version                      = $null
            minion_id                    = $null
            minion_id_cached             = $null
            masters_configured           = @()
            saltenv_configured           = $null
            verify_master_pubkey_sign_required = $false
            verify_master_pubkey_sign_satisfiable = $null
            service_state                = if ($svc) { [string]$svc.Status }    else { $null }
            service_start_type           = if ($svc) { [string]$svc.StartType } else { $null }
            minion_pid                   = $null
            log_path                     = $null
            log_size_bytes               = $null
            log_modified_utc             = $null
            recent_jobs_count            = 0
            log_archive_count            = 0
            minion_d_files               = @()
            pki_dir                      = $null
            pki_files                    = @()
            master_connectivity          = @()
            static_grains_present        = $false
            static_grains_size_bytes     = $null
            org_grains                   = [ordered]@{
                ssnc_org              = $null
                ssnc_environment      = $null
                ssnc_server_role      = $null
                ssnc_app              = $null
                ssnc_cloud_image      = $null
                ssnc_cloud_platform   = $null
                ssnc_datacenter       = $null
            }
            probes                       = [ordered]@{
                test_ping_ok                              = $null
                is_running_jobs                           = @()
                show_top_active_env                       = $null
                show_top_active_env_assignments           = @()
                show_top_active_env_assignment_count      = $null
                show_top_base_assignments                 = @()
                show_top_base_assignment_count            = $null
            }
            patching_logs                = [ordered]@{
                directory               = 'C:\salt_custom_logs\patching_automation'
                directory_exists        = $false
                active_log_path         = $null
                active_log_size_bytes   = $null
                active_log_modified_utc = $null
                rotated_log_count       = 0
                rotated_logs            = @()
                total_bytes             = 0
            }
            other_orchestrators_detected = @()
            agentless_orchestrators_note = 'Bolt and Ansible run agentlessly against Windows targets via WinRM and have no persistent install footprint. Detection is intentionally not attempted; absence of these tools cannot be inferred from this bundle.'
        }

        # ---------- Salt collection ----------
        $saltCall = $null
        $parsedConf = $null

        if ($salt) {
            $saltData.installed      = $true
            $saltData.install_path   = $salt.InstallPath
            $saltData.install_layout = $salt.Layout
            $saltData.conf_root      = $salt.ConfRoot
            $saltData.var_root       = $salt.VarRoot

            # Locate salt-call.exe -- needed for version + live probes
            foreach ($cand in @('salt-call.exe', 'salt-call.bat')) {
                $p = Join-Path $salt.InstallPath $cand
                if (Test-Path -LiteralPath $p) { $saltCall = $p; break }
            }

            # ---------- Version ----------
            if ($saltCall) {
                try {
                    $verOut = Invoke-DiagTimed -Collector 'Get-DiagSalt' -Step 'salt-call --version' -Action { & $saltCall '--version' 2>&1 }
                    if ($LASTEXITCODE -eq 0 -and $verOut) {
                        $verPath = Join-Path $rawDir 'installed_version.txt'
                        [System.IO.File]::WriteAllText($verPath, ($verOut -join "`r`n"), [System.Text.UTF8Encoding]::new($false))
                        $result.Artifacts += @{
                            path        = 'raw/salt/installed_version.txt'
                            category    = 'salt_version'
                            type        = 'raw'
                            description = 'salt-call --version output'
                        }
                        $verLine = ($verOut | Where-Object { $_ -match 'salt-call\s+(\S+)' } | Select-Object -First 1)
                        if ($verLine -and $verLine -match 'salt-call\s+(\S+)') {
                            $saltData.version = $matches[1]
                        }
                    }
                } catch {
                    $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/installed_version.txt'; reason = $_.Exception.Message; severity = 'warning' }
                }
            }

            # ---------- Minion config copy + tolerant parse ----------
            try {
                $minionConf = Join-Path $salt.ConfRoot 'minion'
                if (Test-Path -LiteralPath $minionConf) {
                    $destConf = Join-Path $rawDir 'conf'
                    if (-not (Test-Path -LiteralPath $destConf)) {
                        New-Item -ItemType Directory -Force -Path $destConf | Out-Null
                    }
                    Copy-Item -LiteralPath $minionConf -Destination (Join-Path $destConf 'minion') -Force
                    $result.Artifacts += @{
                        path        = 'raw/salt/conf/minion'
                        category    = 'salt_config'
                        type        = 'raw'
                        description = 'Minion main configuration file (post-redaction scan applied)'
                    }

                    try {
                        $confText = [System.IO.File]::ReadAllText($minionConf)
                        $parsedConf = _ParseSaltMinionYaml -Text $confText
                        if ($parsedConf.id)      { $saltData.minion_id = $parsedConf.id }
                        if ($parsedConf.master.Count -gt 0) {
                            $saltData.masters_configured = @($parsedConf.master | Select-Object -Unique)
                        }
                        if ($parsedConf.saltenv) { $saltData.saltenv_configured = $parsedConf.saltenv }
                        $saltData.verify_master_pubkey_sign_required = [bool]$parsedConf.verify_master_pubkey_sign
                    } catch {
                        $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/conf/minion'; reason = "YAML parse failed: $($_.Exception.Message)"; severity = 'warning' }
                    }
                }

                # Cached minion ID file is what the running minion actually uses
                $minionIdFile = Join-Path $salt.ConfRoot 'minion_id'
                if (Test-Path -LiteralPath $minionIdFile) {
                    try {
                        $cachedId = ([System.IO.File]::ReadAllText($minionIdFile)).Trim()
                        $saltData.minion_id_cached = $cachedId
                        Copy-Item -LiteralPath $minionIdFile -Destination (Join-Path (Join-Path $rawDir 'conf') 'minion_id') -Force
                        $result.Artifacts += @{
                            path        = 'raw/salt/conf/minion_id'
                            category    = 'salt_config'
                            type        = 'raw'
                            description = 'Cached minion identity (the value the running minion actually uses)'
                        }
                    } catch {
                        $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/conf/minion_id'; reason = $_.Exception.Message; severity = 'warning' }
                    }
                }

                # minion.d drop-ins
                $minionD = Join-Path $salt.ConfRoot 'minion.d'
                if (Test-Path -LiteralPath $minionD) {
                    $destD = Join-Path $rawDir 'conf\minion.d'
                    if (-not (Test-Path -LiteralPath $destD)) {
                        New-Item -ItemType Directory -Force -Path $destD | Out-Null
                    }
                    $dropIns = New-Object System.Collections.ArrayList
                    foreach ($f in (Get-ChildItem -LiteralPath $minionD -Filter '*.conf' -File -ErrorAction SilentlyContinue)) {
                        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $destD $f.Name) -Force
                        $sha = $null
                        try { $sha = (Get-FileHash -Path $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() } catch { }
                        [void]$dropIns.Add([ordered]@{
                            name       = $f.Name
                            size_bytes = [long]$f.Length
                            sha256     = $sha
                        })
                        $result.Artifacts += @{
                            path        = "raw/salt/conf/minion.d/$($f.Name)"
                            category    = 'salt_config'
                            type        = 'raw'
                            description = "Minion drop-in config (post-redaction scan applied)"
                        }
                    }
                    $saltData.minion_d_files = @($dropIns)
                }

                # Static grains file
                $grainsFile = Join-Path $salt.ConfRoot 'grains'
                if (Test-Path -LiteralPath $grainsFile) {
                    try {
                        $gi = Get-Item -LiteralPath $grainsFile
                        $saltData.static_grains_present    = $true
                        $saltData.static_grains_size_bytes = [long]$gi.Length
                        $destGrains = Join-Path $rawDir 'conf\grains'
                        Copy-Item -LiteralPath $grainsFile -Destination $destGrains -Force
                        $result.Artifacts += @{
                            path        = 'raw/salt/conf/grains'
                            category    = 'salt_grains_static'
                            type        = 'raw'
                            description = 'Static grains file (org-specific custom grains, may include ssnc_server_role)'
                        }
                    } catch {
                        $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/conf/grains'; reason = $_.Exception.Message; severity = 'warning' }
                    }
                }
                $grainsD = Join-Path $salt.ConfRoot 'grains.d'
                if (Test-Path -LiteralPath $grainsD) {
                    $destGd = Join-Path $rawDir 'conf\grains.d'
                    if (-not (Test-Path -LiteralPath $destGd)) {
                        New-Item -ItemType Directory -Force -Path $destGd | Out-Null
                    }
                    foreach ($f in (Get-ChildItem -LiteralPath $grainsD -File -ErrorAction SilentlyContinue)) {
                        try {
                            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $destGd $f.Name) -Force
                            $result.Artifacts += @{
                                path        = "raw/salt/conf/grains.d/$($f.Name)"
                                category    = 'salt_grains_static'
                                type        = 'raw'
                                description = "Static grains drop-in: $($f.Name)"
                            }
                        } catch {
                            $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = "raw/salt/conf/grains.d/$($f.Name)"; reason = $_.Exception.Message; severity = 'warning' }
                        }
                    }
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/conf/'; reason = $_.Exception.Message; severity = 'warning' }
            }

            # ---------- PKI inventory (size + sha256 only; never read .pem private key) ----------
            try {
                $pkiRoot = Join-Path $salt.ConfRoot 'pki\minion'
                if (Test-Path -LiteralPath $pkiRoot) {
                    $saltData.pki_dir = $pkiRoot
                    $pkiList = New-Object System.Collections.ArrayList
                    foreach ($name in @('minion.pem', 'minion.pub', 'minion_master.pub', 'master_sign.pub')) {
                        $p = Join-Path $pkiRoot $name
                        if (Test-Path -LiteralPath $p) {
                            $fi = Get-Item -LiteralPath $p
                            # Public keys: hash for forensic identity. Private key:
                            # length only, never hash content (defense-in-depth
                            # against future "we always hash" refactors).
                            $sha = $null
                            if ($name -ne 'minion.pem') {
                                try { $sha = (Get-FileHash -Path $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() } catch { }
                            }
                            [void]$pkiList.Add([ordered]@{
                                name        = $name
                                size_bytes  = [long]$fi.Length
                                mtime_utc   = $fi.LastWriteTimeUtc.ToString($fmt)
                                sha256      = $sha
                            })
                        } else {
                            [void]$pkiList.Add([ordered]@{
                                name        = $name
                                size_bytes  = $null
                                mtime_utc   = $null
                                sha256      = $null
                                present     = $false
                            })
                        }
                    }
                    $saltData.pki_files = @($pkiList)

                    # D3: verify_master_pubkey_sign:True without master_sign.pub
                    # is non-functional. Error severity.
                    if ($saltData.verify_master_pubkey_sign_required) {
                        $msPub = $pkiList | Where-Object { $_.name -eq 'master_sign.pub' } | Select-Object -First 1
                        $hasSign = ($msPub -and $msPub.size_bytes)
                        $saltData.verify_master_pubkey_sign_satisfiable = [bool]$hasSign
                        if (-not $hasSign) {
                            $result.Errors += @{
                                collector = 'Get-DiagSalt'
                                reason    = "verify_master_pubkey_sign is True but master_sign.pub is missing under $pkiRoot. Every published job will be silently rejected."
                                severity  = 'error'
                                artifact  = 'summary/salt.json'
                            }
                        }
                    }
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/pki_inventory'; reason = $_.Exception.Message; severity = 'warning' }
            }

            # ---------- Log capture ----------
            # Probe the default Windows path AND any log_file from the parsed
            # config. Earlier versions skipped this when log_file was unset.
            try {
                $logCandidates = New-Object System.Collections.ArrayList
                $defaultLog = Join-Path $salt.VarRoot 'log\salt\minion'
                [void]$logCandidates.Add($defaultLog)
                if ($parsedConf -and $parsedConf.log_file) {
                    [void]$logCandidates.Add($parsedConf.log_file)
                }
                $logFile = $null
                foreach ($cand in $logCandidates) {
                    if ($cand -and (Test-Path -LiteralPath $cand)) { $logFile = $cand; break }
                }
                if ($logFile) {
                    $li = Get-Item -LiteralPath $logFile -ErrorAction Stop
                    $saltData.log_path         = $li.FullName
                    $saltData.log_size_bytes   = [long]$li.Length
                    $saltData.log_modified_utc = $li.LastWriteTimeUtc.ToString($fmt)

                    $tailDest = Join-Path $rawDir 'minion_log_tail.log'
                    $tailMax  = 20MB
                    try {
                        if ($li.Length -le $tailMax) {
                            Copy-Item -LiteralPath $logFile -Destination $tailDest -Force
                        } else {
                            $fs = [System.IO.File]::Open($logFile, 'Open', 'Read', 'ReadWrite')
                            try {
                                $fs.Seek(-$tailMax, 'End') | Out-Null
                                $bytes = New-Object byte[] $tailMax
                                $read  = $fs.Read($bytes, 0, $tailMax)
                                $first = [Array]::IndexOf($bytes, [byte]10)
                                if ($first -gt 0 -and $first -lt $read - 1) {
                                    [System.IO.File]::WriteAllBytes($tailDest, $bytes[($first + 1)..($read - 1)])
                                } else {
                                    [System.IO.File]::WriteAllBytes($tailDest, $bytes[0..($read - 1)])
                                }
                            } finally { $fs.Dispose() }
                        }
                        $result.Artifacts += @{
                            path        = 'raw/salt/minion_log_tail.log'
                            category    = 'salt_log'
                            type        = 'raw'
                            description = "Tail (last $([math]::Round($tailMax/1MB,1))MB) of Salt minion log"
                        }
                    } catch {
                        $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/minion_log_tail.log'; reason = $_.Exception.Message; severity = 'warning' }
                    }
                }

                # Archive index (rotated logs)
                $logDir = Join-Path $salt.VarRoot 'log\salt'
                if (Test-Path -LiteralPath $logDir) {
                    $archives = @(Get-ChildItem -LiteralPath $logDir -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match '^minion(\.|$)' -and $_.Name -ne 'minion' })
                    if ($archives.Count -gt 0) {
                        $idxPath = Join-Path $rawDir 'minion_log_archive_index.csv'
                        $archives | ForEach-Object {
                            [pscustomobject]@{
                                Name         = $_.Name
                                SizeBytes    = $_.Length
                                ModifiedUtc  = $_.LastWriteTimeUtc.ToString($fmt)
                                FullPath     = $_.FullName
                            }
                        } | Export-Csv -Path $idxPath -NoTypeInformation -Encoding UTF8
                        $saltData.log_archive_count = $archives.Count
                        $result.Artifacts += @{
                            path        = 'raw/salt/minion_log_archive_index.csv'
                            category    = 'salt_log_index'
                            type        = 'raw'
                            description = 'Inventory of rotated/archived minion logs (path + size + mtime, content not included)'
                            row_count   = $archives.Count
                        }
                    }
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/minion_log_*'; reason = $_.Exception.Message; severity = 'warning' }
            }

            # ---------- Recent jobs cache index ----------
            try {
                $procDir = Join-Path $salt.VarRoot 'cache\salt\minion\proc'
                if (Test-Path -LiteralPath $procDir) {
                    $jobs = @(Get-ChildItem -LiteralPath $procDir -File -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            [pscustomobject]@{
                                Jid         = $_.Name
                                SizeBytes   = $_.Length
                                ModifiedUtc = $_.LastWriteTimeUtc.ToString($fmt)
                                InWindow    = ($_.LastWriteTime -ge $cutoff)
                            }
                        })
                    if ($jobs.Count -gt 0) {
                        $jobsPath = Join-Path $rawDir 'jobs_recent.csv'
                        $jobs | Export-Csv -Path $jobsPath -NoTypeInformation -Encoding UTF8
                        $saltData.recent_jobs_count = @($jobs | Where-Object { $_.InWindow }).Count
                        $result.Artifacts += @{
                            path        = 'raw/salt/jobs_recent.csv'
                            category    = 'salt_jobs_index'
                            type        = 'raw'
                            description = 'Inventory of jobs in minion proc cache (JID + size + mtime, payload not included)'
                            row_count   = $jobs.Count
                        }
                    }
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/jobs_recent.csv'; reason = $_.Exception.Message; severity = 'warning' }
            }

            # ---------- Minion PID ----------
            try {
                $minionProc = Get-CimInstance Win32_Process -Filter "Name = 'salt-minion.exe' OR Name = 'python.exe'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.CommandLine -and ($_.CommandLine -like '*salt-minion*' -or $_.CommandLine -like '*minion.py*') } |
                    Select-Object -First 1
                if ($minionProc) {
                    $saltData.minion_pid = [int]$minionProc.ProcessId
                }
            } catch { }

            # ---------- Master TCP connectivity probes ----------
            if (-not $SkipNetworkTests -and $saltData.masters_configured.Count -gt 0) {
                $connList = New-Object System.Collections.ArrayList
                foreach ($masterHost in $saltData.masters_configured) {
                    foreach ($port in @(4505, 4506)) {
                        $r = Invoke-DiagTimed -Collector 'Get-DiagSalt' -Step "TCP probe ${masterHost}:${port}" -Action {
                            _ProbeSaltTcp -HostName $masterHost -Port $port -TimeoutSec 3
                        }
                        [void]$connList.Add($r)
                    }
                }
                $saltData.master_connectivity = @($connList)
            } elseif ($SkipNetworkTests) {
                $saltData.master_connectivity = @(@{ skipped = $true; reason = '-SkipNetworkTests' })
            }

            # ---------- Live salt-call probes (Gap 8) ----------
            if ($saltCall) {
                $probesDir = Join-Path $rawDir 'probes'
                if (-not (Test-Path -LiteralPath $probesDir)) {
                    New-Item -ItemType Directory -Force -Path $probesDir | Out-Null
                }

                # test.ping (10s) -- minion-local sanity check
                try {
                    $r = Invoke-DiagTimed -Collector 'Get-DiagSalt' -Step 'salt-call --local test.ping' -Action {
                        _RunSaltCallProbe -SaltCallExe $saltCall -Arguments @('--local', '--out=json', 'test.ping') -TimeoutSec 10
                    }
                    [System.IO.File]::WriteAllText((Join-Path $probesDir 'test_ping.json'), $r.stdout, [System.Text.UTF8Encoding]::new($false))
                    $result.Artifacts += @{
                        path        = 'raw/salt/probes/test_ping.json'
                        category    = 'salt_probe'
                        type        = 'raw'
                        description = "salt-call --local test.ping (exit=$($r.exit_code), $($r.duration_ms)ms)"
                    }
                    $saltData.probes.test_ping_ok = ($r.success -and $r.stdout -match '(?i)true')
                } catch {
                    $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/probes/test_ping.json'; reason = $_.Exception.Message; severity = 'warning' }
                }

                # grains.items (15s) -- populates summary/salt_grains.json
                try {
                    $r = Invoke-DiagTimed -Collector 'Get-DiagSalt' -Step 'salt-call --local grains.items' -Action {
                        _RunSaltCallProbe -SaltCallExe $saltCall -Arguments @('--local', '--out=json', 'grains.items') -TimeoutSec 15
                    }
                    if ($r.success -and $r.stdout) {
                        $grainsRaw = $r.stdout
                        [System.IO.File]::WriteAllText((Join-Path $probesDir 'grains_items.json'), $grainsRaw, [System.Text.UTF8Encoding]::new($false))
                        $result.Artifacts += @{
                            path        = 'raw/salt/probes/grains_items.json'
                            category    = 'salt_probe'
                            type        = 'raw'
                            description = "salt-call --local grains.items raw output"
                        }
                        # Pre-extract org-specific grains for easy reading
                        try {
                            $obj = $grainsRaw | ConvertFrom-Json -ErrorAction Stop
                            $grains = $obj.local
                            foreach ($k in @('ssnc_org','ssnc_environment','ssnc_server_role','ssnc_app','ssnc_cloud_image','ssnc_cloud_platform','ssnc_datacenter')) {
                                if ($grains.PSObject.Properties[$k]) {
                                    $saltData.org_grains[$k] = [string]$grains.$k
                                }
                            }
                            # Build derived summary/salt_grains.json
                            $grainsSummary = [ordered]@{
                                schema_version = '1.0'
                                host           = @{ computer_name = $env:COMPUTERNAME }
                                collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
                                data           = $grains
                            }
                            $gsPath = Join-Path $WorkingDirectory 'summary\salt_grains.json'
                            [System.IO.File]::WriteAllText($gsPath, ($grainsSummary | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
                            $result.Artifacts += @{
                                path           = 'summary/salt_grains.json'
                                category       = 'salt_grains'
                                schema_version = '1.0'
                                type           = 'derived'
                                description    = 'Full grains.items output as JSON'
                            }

                            # Flag empty ssnc_server_role -- the field that
                            # decides top.sls targeting on this org's fleet.
                            if ([string]::IsNullOrWhiteSpace([string]$saltData.org_grains.ssnc_server_role)) {
                                $result.Errors += @{
                                    collector = 'Get-DiagSalt'
                                    reason    = "Grain ssnc_server_role is empty. This is the grain that gates top.sls targeting on this fleet; an empty value typically means highstate will apply no states."
                                    severity  = 'warning'
                                    artifact  = 'summary/salt.json'
                                }
                            }
                        } catch {
                            $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'summary/salt_grains.json'; reason = "grains JSON parse failed: $($_.Exception.Message)"; severity = 'warning' }
                        }
                    } else {
                        $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/probes/grains_items.json'; reason = "grains.items failed: exit=$($r.exit_code), timed_out=$($r.timed_out)"; severity = 'warning' }
                    }
                } catch {
                    $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/probes/grains_items.json'; reason = $_.Exception.Message; severity = 'warning' }
                }

                # saltutil.is_running (10s)
                try {
                    $r = Invoke-DiagTimed -Collector 'Get-DiagSalt' -Step 'salt-call --local saltutil.is_running' -Action {
                        _RunSaltCallProbe -SaltCallExe $saltCall -Arguments @('--local', '--out=json', 'saltutil.is_running') -TimeoutSec 10
                    }
                    if ($r.success -and $r.stdout) {
                        [System.IO.File]::WriteAllText((Join-Path $probesDir 'is_running.json'), $r.stdout, [System.Text.UTF8Encoding]::new($false))
                        $result.Artifacts += @{
                            path        = 'raw/salt/probes/is_running.json'
                            category    = 'salt_probe'
                            type        = 'raw'
                            description = "salt-call --local saltutil.is_running"
                        }
                        try {
                            $obj = $r.stdout | ConvertFrom-Json -ErrorAction Stop
                            if ($obj.local) { $saltData.probes.is_running_jobs = @($obj.local) }
                        } catch { }
                    }
                } catch {
                    $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/probes/is_running.json'; reason = $_.Exception.Message; severity = 'warning' }
                }

                # state.show_top for the active saltenv (D2) and base
                $envsToProbe = New-Object System.Collections.ArrayList
                $activeEnv = if ($saltData.saltenv_configured) { $saltData.saltenv_configured } else { 'base' }
                $saltData.probes.show_top_active_env = $activeEnv
                [void]$envsToProbe.Add($activeEnv)
                if ($activeEnv -ne 'base') { [void]$envsToProbe.Add('base') }

                foreach ($env in $envsToProbe) {
                    try {
                        $r = Invoke-DiagTimed -Collector 'Get-DiagSalt' -Step "salt-call state.show_top saltenv=$env" -Action {
                            _RunSaltCallProbe -SaltCallExe $saltCall -Arguments @('--out=json', 'state.show_top', "saltenv=$env") -TimeoutSec 45
                        }
                        $fname = "state_show_top_${env}.json"
                        if ($r.stdout) {
                            [System.IO.File]::WriteAllText((Join-Path $probesDir $fname), $r.stdout, [System.Text.UTF8Encoding]::new($false))
                            $result.Artifacts += @{
                                path        = "raw/salt/probes/$fname"
                                category    = 'salt_probe'
                                type        = 'raw'
                                description = "salt-call state.show_top saltenv=$env (exit=$($r.exit_code), $($r.duration_ms)ms)"
                            }
                        }
                        # Parse assignment list
                        $assignments = @()
                        if ($r.success -and $r.stdout) {
                            try {
                                $obj = $r.stdout | ConvertFrom-Json -ErrorAction Stop
                                $envBlock = $obj.local.$env
                                if ($envBlock) { $assignments = @($envBlock) }
                            } catch { }
                        }
                        if ($env -eq $activeEnv) {
                            $saltData.probes.show_top_active_env_assignments      = $assignments
                            $saltData.probes.show_top_active_env_assignment_count = $assignments.Count
                            # Flag the canonical "no states match this host" signal
                            if ($r.success -and $assignments.Count -eq 0) {
                                $result.Errors += @{
                                    collector = 'Get-DiagSalt'
                                    reason    = "state.show_top against active saltenv '$env' returned 0 state assignments for this host. Highstate would apply nothing; check ssnc_server_role grain and the master's top.sls targeting."
                                    severity  = 'warning'
                                    artifact  = 'summary/salt.json'
                                }
                            }
                        }
                        if ($env -eq 'base') {
                            $saltData.probes.show_top_base_assignments      = $assignments
                            $saltData.probes.show_top_base_assignment_count = $assignments.Count
                        }
                    } catch {
                        $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = "raw/salt/probes/state_show_top_${env}.json"; reason = $_.Exception.Message; severity = 'warning' }
                    }
                }
            }

            # Verify PKI was NOT touched. Defensive sanity check that fires a
            # warning into the bundle if a future code change accidentally
            # writes anything under raw/salt/conf/pki/.
            $pkiCopy = Join-Path $rawDir 'conf\pki'
            if (Test-Path -LiteralPath $pkiCopy) {
                $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/conf/pki'; reason = 'PKI directory found in bundle output -- this is a serious safety regression. Audit Get-DiagSalt copy paths.'; severity = 'error' }
            }
        }

        # ---------- Patching automation logs (independent of Salt install detection) ----------
        $patchLogsDir = 'C:\salt_custom_logs\patching_automation'
        if (Test-Path -LiteralPath $patchLogsDir) {
            $saltData.patching_logs.directory_exists = $true
            try {
                $files = @(Get-ChildItem -LiteralPath $patchLogsDir -File -ErrorAction Stop)
                if ($files.Count -gt 0) {
                    $destDir = Join-Path $rawDir 'patching_automation'
                    if (-not (Test-Path -LiteralPath $destDir)) {
                        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                    }
                    Invoke-DiagTimed -Collector 'Get-DiagSalt' -Step 'copy patching_automation logs' -Action {
                        foreach ($f in $files) {
                            try {
                                Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $destDir $f.Name) -Force -ErrorAction Stop
                            } catch {
                                $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = "raw/salt/patching_automation/$($f.Name)"; reason = $_.Exception.Message; severity = 'warning' }
                            }
                        }
                    }

                    $rotated = New-Object System.Collections.ArrayList
                    $totalBytes = 0L
                    foreach ($f in $files) {
                        $totalBytes += [long]$f.Length
                        if ($f.Name -ieq 'patching.log') {
                            $saltData.patching_logs.active_log_path         = $f.FullName
                            $saltData.patching_logs.active_log_size_bytes   = [long]$f.Length
                            $saltData.patching_logs.active_log_modified_utc = $f.LastWriteTimeUtc.ToString($fmt)
                        } else {
                            [void]$rotated.Add([ordered]@{
                                name         = $f.Name
                                size_bytes   = [long]$f.Length
                                modified_utc = $f.LastWriteTimeUtc.ToString($fmt)
                            })
                        }

                        $result.Artifacts += @{
                            path        = "raw/salt/patching_automation/$($f.Name)"
                            category    = 'salt_patching_log'
                            type        = 'raw'
                            description = if ($f.Name -ieq 'patching.log') {
                                "Active Salt patching automation log (operator-decisions layer)"
                            } else {
                                "Rotated Salt patching automation log ($($f.Name -replace '^patching\.log\.',''))"
                            }
                        }
                    }
                    $saltData.patching_logs.rotated_log_count = $rotated.Count
                    $saltData.patching_logs.rotated_logs      = @($rotated)
                    $saltData.patching_logs.total_bytes       = $totalBytes
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagSalt'; artifact = 'raw/salt/patching_automation/*'; reason = $_.Exception.Message; severity = 'warning' }
            }
        }

        # ---------- Other orchestrator detection (PDQ) ----------
        $other = New-Object System.Collections.ArrayList
        foreach ($svcName in @('PDQDeployRunner', 'PDQInventoryRunner')) {
            $s = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($s) {
                [void]$other.Add([ordered]@{
                    name        = $svcName
                    product     = if ($svcName -like '*Deploy*') { 'PDQ Deploy' } else { 'PDQ Inventory' }
                    state       = [string]$s.Status
                    start_type  = [string]$s.StartType
                    note        = 'Service detected. Configuration and logs NOT collected by this version.'
                })
            }
        }
        $saltData.other_orchestrators_detected = @($other)

        # ---------- Write summary ----------
        $sumData = [ordered]@{
            schema_version = '1.2'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            window         = [ordered]@{
                window_hours = $WindowHours
            }
            data           = $saltData
        }
        $sumPath = Join-Path $WorkingDirectory 'summary\salt.json'
        $json    = $sumData | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($sumPath, $json, [System.Text.UTF8Encoding]::new($false))
        $result.Artifacts += @{
            path           = 'summary/salt.json'
            category       = 'salt'
            schema_version = '1.2'
            type           = 'derived'
            description    = 'Salt minion install state, version, masters, PKI inventory, master TCP connectivity, live salt-call probes (test.ping, grains.items, state.show_top), patching automation logs metadata; other orchestrator (PDQ) detection'
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagSalt'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
