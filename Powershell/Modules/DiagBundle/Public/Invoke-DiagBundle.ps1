function Invoke-DiagBundle {
    <#
    .SYNOPSIS
        Collect a one-shot Windows Server diagnostic bundle as a single ZIP.

    .DESCRIPTION
        Runs every collector in the DiagBundle pipeline against the local host,
        assembles a manifest, applies redactions, enforces the size budget, and
        writes one ZIP file suitable for AI-assisted analysis or human triage.
        This is the only public entry point in the module; everything else under
        Private/ is invoked from here. Call this on demand from a console, Salt
        state, or WinRM session. The ZIP contains pre-aggregated summary JSON,
        raw forensic artifacts (EVTX, CBS, perf BLG, etc.), a transcript, and a
        SHA256 checksum file.

    .PARAMETER WindowHours
        Lookback window in hours for time-bounded collectors (event logs, WER,
        update history). Integer between 1 and 720. Defaults to 24.

    .PARAMETER OutputPath
        Directory the final ZIP is written to. Created if it does not exist.
        Must not be null or empty. Defaults to C:\ProgramData\DiagBundle\output.

    .PARAMETER Scenario
        Scenario hint stamped into manifest.collection.scenario_hint so the
        downstream agent knows the caller's intent. One of post_patch,
        performance, general, forensic. Defaults to general.

    .PARAMETER SkipCollector
        Array of collector names to skip by short name (for example Performance,
        WER, or Salt). Skipped collectors are logged to manifest.collection_errors
        with severity info. Defaults to an empty array (run everything).

    .PARAMETER IncludeCrashArtifacts
        When true, include WER cabs and minidumps that fall within one week of
        the collection time and within the size cap. When false, only an index
        is written. Defaults to true.

    .PARAMETER MaxBundleBytes
        Hard ceiling on uncompressed raw artifact bytes. Must be between 100MB
        and 10GB. When the raw tree exceeds this, files are trimmed oldest
        first and the trims are logged in manifest.size_budget.truncations.
        Defaults to 2GB.

    .PARAMETER LkrCopyCapBytes
        Per-file size cap (raw bytes) for LiveKernelReports copy. In-window
        files at or below the cap are copied into raw/dumps/livekernelreports/.
        Files above the cap remain index-only in
        summary/crashes_wer.json -> kernel_dumps -> live_kernel_reports ->
        files[] with skip_reason 'over_per_file_cap', so the operator can pull
        them manually. Range 0 to 10 GB; 0 disables copying entirely (every
        in-window file gets skip_reason 'over_per_file_cap'). Defaults to 1GB,
        sized so a single LKR plus the rest of the bundle fits inside the
        MaxBundleBytes raw ceiling without triggering trim-oldest.

    .PARAMETER SkipNetworkTests
        When true, collectors that issue outbound network probes (currently
        Get-DiagPatching's WSUS interrogation) skip those probes and emit a
        skipped_by_parameter verdict. Defaults to false. Set to true in
        environments where outbound HTTP from the collector is not allowed.

    .PARAMETER ProblemDescription
        Optional free-form text from the operator describing what they are
        investigating. Stamped into manifest.collection.problem_description so
        the analyst (human or AI) starts with operator context, not just data.
        Capped at 8 KB UTF-8; control characters except CR/LF/TAB are stripped;
        passed through Invoke-DiagRedaction. Mutually exclusive with
        ProblemDescriptionFile.

    .PARAMETER ProblemDescriptionFile
        Path to a UTF-8 text file holding the problem description. Useful when
        the operator drafted the writeup in their editor or when the text is
        too long for a parameter. Mutually exclusive with ProblemDescription.
        File size cap 1 MB; resulting text obeys the same 8 KB final cap.

    .PARAMETER PromptForProblem
        Open a modal GUI textbox so the operator can type a long-form
        description interactively. Requires an interactive desktop session;
        throws under SYSTEM / Salt / WinRM / SSM. May be combined with
        ProblemDescription or ProblemDescriptionFile (they prefill the
        textbox). Cancel records source = prompt_cancelled with empty text.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        [pscustomobject] with fields BundleId, ZipPath, ZipBytes, StartedUtc,
        CompletedUtc, and DurationSeconds.

    .EXAMPLE
        # Default 24-hour collection to C:\ProgramData\DiagBundle\output.
        Invoke-DiagBundle

    .EXAMPLE
        # Three-day window flagged as a post-patch investigation.
        Invoke-DiagBundle -WindowHours 72 -Scenario post_patch

    .EXAMPLE
        # Skip the slow collectors and write the ZIP to a different drive.
        Invoke-DiagBundle -SkipCollector Performance,WER -OutputPath D:\bundles

    .NOTES
        Designed for PowerShell 5.1 on Windows Server 2016 and newer. The
        Performance collector blocks for roughly 60 seconds while it samples
        Get-Counter; expect total runtime in the low minutes. Each collector is
        isolated -- one failing collector never aborts the bundle, it only adds
        an entry to manifest.collection_errors. The function sets
        $script:DiagLogPath so collectors can call Write-DiagLog without
        threading the path through every parameter list.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(1, 720)]
        [int] $WindowHours = 24,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $OutputPath = 'C:\ProgramData\DiagBundle\output',

        [Parameter()]
        [ValidateSet('post_patch', 'performance', 'general', 'forensic')]
        [string] $Scenario = 'general',

        [Parameter()]
        [string[]] $SkipCollector = @(),

        [Parameter()]
        [bool] $IncludeCrashArtifacts = $true,

        [Parameter()]
        [ValidateRange(100MB, 10GB)]
        [long] $MaxBundleBytes = 2GB,

        [Parameter()]
        [ValidateRange(0, 10GB)]
        [long] $LkrCopyCapBytes = 1GB,

        [Parameter()]
        [bool] $SkipNetworkTests = $false,

        [Parameter()]
        [string] $ProblemDescription,

        [Parameter()]
        [string] $ProblemDescriptionFile,

        [Parameter()]
        [switch] $PromptForProblem
    )

    $startedUtc      = [DateTime]::UtcNow
    $bundleId        = [guid]::NewGuid().ToString()
    $hostname        = $env:COMPUTERNAME
    $stamp           = $startedUtc.ToString('yyyyMMdd-HHmmss')
    $bundleName      = "${hostname}_${stamp}_diagbundle"
    $collectorVersion = (Get-Module DiagBundle).Version.ToString()

    # Resolve operator problem description up front so parameter validation
    # (mutually-exclusive params, missing file, non-interactive prompt) fails
    # before any working directory is created. The local variable must NOT
    # be named $problemDescription -- PowerShell variable names are case
    # insensitive, and assigning the resolver's OrderedDictionary result back
    # into the [string]-typed $ProblemDescription parameter coerces it to
    # "System.Collections.Specialized.OrderedDictionary" via ToString().
    $resolvedProblem = Resolve-DiagProblemDescription `
        -ProblemDescription     $ProblemDescription `
        -ProblemDescriptionFile $ProblemDescriptionFile `
        -PromptForProblem       ([bool]$PromptForProblem) `
        -UserInteractive        ([System.Environment]::UserInteractive)

    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    $elevation = if ($id.User.Value -eq 'S-1-5-18') {
        'SYSTEM'
    } elseif ($principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        'Administrator'
    } else {
        'User'
    }

    $workRoot   = Join-Path ([System.IO.Path]::GetTempPath()) "DiagBundle\$bundleId"
    $bundleRoot = Join-Path $workRoot $bundleName

    $subdirs = @(
        'summary'
        'raw'
        'raw\eventlogs'
        'raw\cbs'
        'raw\windowsupdate'
        'raw\perf'
        'raw\wer'
        'raw\wer\cabs'
        'raw\netsh'
        'raw\gpo'
        'raw\registry'
        'raw\tasks'
        'raw\dumps'
        'raw\role_specific'
        'raw\role_specific\iis'
        'raw\role_specific\iis_w3svc_lastday'
        'raw\role_specific\sql'
        'raw\role_specific\sql_errorlog'
        'raw\role_specific\sql_dumps'
        'raw\role_specific\dfsr'
        'raw\drivers'
        'raw\salt'
        'transcript'
    )
    foreach ($s in $subdirs) {
        New-Item -ItemType Directory -Force -Path (Join-Path $bundleRoot $s) | Out-Null
    }

    $logPath = Join-Path $bundleRoot 'transcript\collector.log'
    Set-Content -Path $logPath -Value '' -Encoding UTF8 -Force
    $script:DiagLogPath = $logPath
    $script:DiagPerfFromUtc = $null
    $script:DiagPerfToUtc   = $null

    $transcriptPath = Join-Path $bundleRoot 'transcript\transcript.txt'
    $transcriptStarted = $false
    try {
        Start-Transcript -Path $transcriptPath -Force -ErrorAction Stop | Out-Null
        $transcriptStarted = $true
    } catch {
        Write-DiagLog -Severity warning -Collector 'Invoke-DiagBundle' -Message "Start-Transcript failed: $($_.Exception.Message)"
    }

    Write-DiagLog -Severity info -Collector 'Invoke-DiagBundle' -Message "Bundle $bundleId starting; window=${WindowHours}h scenario=$Scenario elevation=$elevation"

    $manifest = Initialize-DiagManifest `
        -BundleId         $bundleId `
        -StartedUtc       $startedUtc `
        -WindowHours      $WindowHours `
        -Scenario         $Scenario `
        -CollectorVersion $collectorVersion `
        -Elevation        $elevation

    if ($null -ne $resolvedProblem) {
        # Cast to PSCustomObject. ConvertTo-Json serializes an OrderedDictionary
        # value held in another OrderedDictionary slot as the type-name string
        # instead of expanding. PSCustomObject round-trips correctly and
        # preserves key order when constructed from an [ordered] hashtable.
        $manifest.collection['problem_description'] = [pscustomobject]$resolvedProblem
        Write-DiagLog -Severity info -Collector 'Invoke-DiagBundle' -Message "problem_description supplied: source=$($resolvedProblem.source) bytes=$($resolvedProblem.text.Length)"
    }

    $collectors = @(
        @{ Name = 'Inventory';      Function = 'Get-DiagInventory'      }
        @{ Name = 'Drivers';        Function = 'Get-DiagDrivers'        }
        @{ Name = 'Patching';       Function = 'Get-DiagPatching'       }
        @{ Name = 'Services';       Function = 'Get-DiagServices'       }
        @{ Name = 'Processes';      Function = 'Get-DiagProcesses'      }
        @{ Name = 'Storage';        Function = 'Get-DiagStorage'        }
        @{ Name = 'Network';        Function = 'Get-DiagNetwork'        }
        @{ Name = 'AD';             Function = 'Get-DiagAD'             }
        @{ Name = 'Registry';       Function = 'Get-DiagRegistry'       }
        @{ Name = 'ScheduledTasks'; Function = 'Get-DiagScheduledTasks' }
        @{ Name = 'EventLogs';      Function = 'Get-DiagEventLogs'      }
        @{ Name = 'WER';            Function = 'Get-DiagWER'            }
        @{ Name = 'Salt';           Function = 'Get-DiagSalt'           }
        @{ Name = 'Roles';          Function = 'Get-DiagRoles'          }
        @{ Name = 'Performance';    Function = 'Get-DiagPerformance'    }
    )

    $postSteps  = @('Baseline diff', 'Redaction', 'Size budget', 'Finalize manifest', 'Checksums', 'Compress')
    $totalSteps = $collectors.Count + $postSteps.Count
    $stepIndex  = 0
    $progressActivity = "DiagBundle ($hostname)"

    foreach ($c in $collectors) {
        $stepIndex++
        $pct = [int](($stepIndex / $totalSteps) * 100)

        if ($SkipCollector -contains $c.Name) {
            Write-Progress -Id 1 -Activity $progressActivity -Status "[$stepIndex/$totalSteps] $($c.Name) (skipped)" -PercentComplete $pct
            Write-DiagLog -Severity info -Collector $c.Function -Message 'skipped by parameter'
            [void]$manifest.collection_errors.Add(@{
                collector = $c.Function
                reason    = 'skipped via -SkipCollector'
                severity  = 'info'
            })
            continue
        }

        Write-Progress -Id 1 -Activity $progressActivity -Status "[$stepIndex/$totalSteps] $($c.Name)" -PercentComplete $pct
        Write-DiagLog -Severity info -Collector $c.Function -Message 'starting'
        $r = $null
        try {
            $cmd = Get-Command -Name $c.Function -ErrorAction Stop
            $params = @{ WorkingDirectory = $bundleRoot }
            if ($cmd.Parameters.ContainsKey('WindowHours'))           { $params['WindowHours']           = $WindowHours }
            if ($cmd.Parameters.ContainsKey('IncludeCrashArtifacts')) { $params['IncludeCrashArtifacts'] = $IncludeCrashArtifacts }
            if ($cmd.Parameters.ContainsKey('LkrCopyCapBytes'))       { $params['LkrCopyCapBytes']       = $LkrCopyCapBytes }
            if ($cmd.Parameters.ContainsKey('SkipNetworkTests'))      { $params['SkipNetworkTests']      = $SkipNetworkTests }
            $r = & $c.Function @params
        } catch {
            [void]$manifest.collection_errors.Add(@{
                collector = $c.Function
                reason    = "uncaught: $($_.Exception.Message)"
                severity  = 'error'
            })
            Write-DiagLog -Severity error -Collector $c.Function -Message $_.Exception.Message
            continue
        }

        if ($null -ne $r) {
            foreach ($a in @($r.Artifacts)) { Add-DiagArtifact -Manifest $manifest -Artifact $a }
            foreach ($e in @($r.Errors))    { [void]$manifest.collection_errors.Add($e) }
            Write-DiagLog -Severity info -Collector $c.Function -Message ("done success={0} duration_s={1} artifacts={2} errors={3}" -f $r.Success, $r.DurationSeconds, ($r.Artifacts | Measure-Object).Count, ($r.Errors | Measure-Object).Count)
        }
    }

    if ($null -ne $script:DiagPerfFromUtc -and $null -ne $script:DiagPerfToUtc) {
        $fmt = 'yyyy-MM-ddTHH:mm:ss.fffZ'
        $manifest.time_window.perf_from_utc = $script:DiagPerfFromUtc.ToString($fmt)
        $manifest.time_window.perf_to_utc   = $script:DiagPerfToUtc.ToString($fmt)
    }

    # Gap 12 reconciliation (2026-05-11 review). On some virtualized hosts
    # (notably OpenShift Virtualization / KVM with RTC-in-localtime quirks)
    # Win32_OperatingSystem.LastBootUpTime is stamped at boot from a wall
    # clock that gets NTP-corrected mid-boot, so the CIM value can be hours
    # off from the kernel's authoritative boot event (Kernel-General 12).
    # boot_timeline reads event 12 directly from the EVTX and is therefore
    # canonical. Reconcile here: if the two disagree by more than 60 seconds,
    # patch both manifest.host.last_boot_utc and summary/inventory.json from
    # boot_timeline, and record the original CIM value for traceability.
    try {
        $btPath  = Join-Path $bundleRoot 'summary\boot_timeline.json'
        $invPath = Join-Path $bundleRoot 'summary\inventory.json'
        if ((Test-Path -LiteralPath $btPath) -and (Test-Path -LiteralPath $invPath)) {
            $bt  = Get-Content -LiteralPath $btPath  -Raw | ConvertFrom-Json
            $inv = Get-Content -LiteralPath $invPath -Raw | ConvertFrom-Json
            $lastBoot = $null
            if ($bt.boots -and $bt.boots.Count -gt 0) {
                # Latest boot is the one we are inside.
                $lastBoot = $bt.boots[$bt.boots.Count - 1].start_utc
            }
            $cimLast = $inv.host.last_boot_utc
            if ($lastBoot -and $cimLast) {
                $a = [DateTime]::Parse($lastBoot,  [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                $b = [DateTime]::Parse($cimLast,   [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                $delta = [Math]::Abs(($a - $b).TotalSeconds)
                if ($delta -gt 60) {
                    $fmt = 'yyyy-MM-ddTHH:mm:ss.fffZ'
                    $authoritative = $a.ToUniversalTime().ToString($fmt)
                    Write-DiagLog -Severity warning -Collector 'Invoke-DiagBundle' -Message "last_boot_utc reconciliation: CIM said $cimLast, boot_timeline (Kernel-General 12) said $lastBoot, delta=$([int]$delta)s. Trusting boot_timeline."
                    # Patch the manifest host block.
                    $manifest.host.last_boot_utc = $authoritative
                    # Patch the on-disk inventory.json -- add a note explaining the reconciliation.
                    $inv.host.last_boot_utc = $authoritative
                    if (-not $inv.data.PSObject.Properties['last_boot_reconciled']) {
                        $inv.data | Add-Member -NotePropertyName 'last_boot_reconciled' -NotePropertyValue $true -Force
                    } else {
                        $inv.data.last_boot_reconciled = $true
                    }
                    if (-not $inv.data.PSObject.Properties['last_boot_cim_value']) {
                        $inv.data | Add-Member -NotePropertyName 'last_boot_cim_value' -NotePropertyValue $cimLast -Force
                    } else {
                        $inv.data.last_boot_cim_value = $cimLast
                    }
                    if (-not $inv.data.PSObject.Properties['last_boot_reconciliation_delta_seconds']) {
                        $inv.data | Add-Member -NotePropertyName 'last_boot_reconciliation_delta_seconds' -NotePropertyValue ([int]$delta) -Force
                    } else {
                        $inv.data.last_boot_reconciliation_delta_seconds = [int]$delta
                    }
                    [System.IO.File]::WriteAllText($invPath, ($inv | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
                    [void]$manifest.collection_errors.Add(@{
                        collector = 'Invoke-DiagBundle'
                        reason    = "last_boot_utc reconciled from boot_timeline (CIM disagreed by $([int]$delta)s). CIM stamps boot time from a possibly-uncorrected wall clock on this host class."
                        severity  = 'info'
                        artifact  = 'summary/inventory.json'
                    })
                }
            }
        }
    } catch {
        Write-DiagLog -Severity warning -Collector 'Invoke-DiagBundle' -Message "last_boot reconciliation failed: $($_.Exception.Message)"
    }

    $stepIndex++
    Write-Progress -Id 1 -Activity $progressActivity -Status "[$stepIndex/$totalSteps] Baseline diff" -PercentComplete ([int](($stepIndex / $totalSteps) * 100))
    try {
        $baseline = Get-DiagBaseline
        if ($baseline) {
            $diffPath = Compare-DiagBaseline -Baseline $baseline -BundleRoot $bundleRoot
            Add-DiagArtifact -Manifest $manifest -Artifact @{
                path           = $diffPath
                category       = 'baseline_diff'
                schema_version = '1.0'
                type           = 'derived'
                description    = 'Diff of services, scheduled_tasks, autoruns vs last baseline'
            }
            $manifest['baseline'] = [ordered]@{
                available     = $true
                captured_utc  = [string]$baseline.captured_utc
                diff_artifact = $diffPath
            }
        } else {
            $manifest['baseline'] = [ordered]@{ available = $false }
        }
    } catch {
        $manifest['baseline'] = [ordered]@{ available = $false }
        [void]$manifest.collection_errors.Add(@{
            collector = 'Compare-DiagBaseline'
            reason    = $_.Exception.Message
            severity  = 'warning'
        })
    }

    $stepIndex++
    Write-Progress -Id 1 -Activity $progressActivity -Status "[$stepIndex/$totalSteps] Redaction" -PercentComplete ([int](($stepIndex / $totalSteps) * 100))
    try {
        Invoke-DiagRedaction -Manifest $manifest -BundleRoot $bundleRoot
    } catch {
        [void]$manifest.collection_errors.Add(@{
            collector = 'Invoke-DiagRedaction'
            reason    = $_.Exception.Message
            severity  = 'warning'
        })
    }

    $stepIndex++
    Write-Progress -Id 1 -Activity $progressActivity -Status "[$stepIndex/$totalSteps] Size budget" -PercentComplete ([int](($stepIndex / $totalSteps) * 100))
    $rawDir = Join-Path $bundleRoot 'raw'
    if (Test-Path -LiteralPath $rawDir) {
        $rawSize = (Get-ChildItem -Path $rawDir -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if ($null -ne $rawSize -and $rawSize -gt $MaxBundleBytes) {
            $excess = $rawSize - $MaxBundleBytes
            $candidates = Get-ChildItem -Path $rawDir -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime
            foreach ($c in $candidates) {
                if ($excess -le 0) { break }
                $rel = ($c.FullName.Substring($bundleRoot.Length + 1)) -replace '\\', '/'
                $manifest.artifacts = [System.Collections.ArrayList]::new(@($manifest.artifacts | Where-Object { $_['path'] -ne $rel }))
                [void]$manifest.size_budget.truncations.Add(@{
                    artifact            = $rel
                    reason              = 'budget_overflow'
                    original_size_bytes = $c.Length
                    trimmed_size_bytes  = 0
                })
                $excess -= $c.Length
                try { Remove-Item -LiteralPath $c.FullName -Force } catch { }
                Write-DiagLog -Severity warning -Collector 'Invoke-DiagBundle' -Message "Trimmed for budget: $rel"
            }
        }
    }

    # Static documentation: README + prompt scaffolds ship verbatim in every
    # bundle so a cold consumer (no module source, no CLAUDE.md) can navigate.
    try {
        $resourceRoot = Join-Path (Get-Module DiagBundle).ModuleBase 'Resources'
        if (Test-Path -LiteralPath $resourceRoot) {
            $readmeSrc = Join-Path $resourceRoot 'README.md'
            if (Test-Path -LiteralPath $readmeSrc) {
                Copy-Item -LiteralPath $readmeSrc -Destination (Join-Path $bundleRoot 'README.md') -Force
                Add-DiagArtifact -Manifest $manifest -Artifact @{
                    path        = 'README.md'
                    category    = 'documentation'
                    type        = 'raw'
                    description = 'Bundle orientation: read order, drill-down recipes, severity vocabulary, caveats'
                }
            }
            $promptsSrc = Join-Path $resourceRoot 'prompts'
            if (Test-Path -LiteralPath $promptsSrc) {
                $promptsDest = Join-Path $bundleRoot 'prompts'
                New-Item -ItemType Directory -Force -Path $promptsDest | Out-Null
                Get-ChildItem -Path $promptsSrc -Filter '*.md' -File -ErrorAction SilentlyContinue | ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $promptsDest $_.Name) -Force
                    Add-DiagArtifact -Manifest $manifest -Artifact @{
                        path        = "prompts/$($_.Name)"
                        category    = 'prompt'
                        type        = 'raw'
                        description = "Investigation scaffold: $($_.BaseName -replace '_', ' ')"
                    }
                }
            }
        }
    } catch {
        [void]$manifest.collection_errors.Add(@{
            collector = 'Invoke-DiagBundle'
            reason    = "Resources copy failed: $($_.Exception.Message)"
            severity  = 'warning'
        })
    }

    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }

    if (Test-Path -LiteralPath $transcriptPath) {
        Add-DiagArtifact -Manifest $manifest -Artifact @{
            path        = 'transcript/transcript.txt'
            category    = 'transcript'
            type        = 'raw'
            description = 'PowerShell Start-Transcript output'
        }
    }
    if (Test-Path -LiteralPath $logPath) {
        Add-DiagArtifact -Manifest $manifest -Artifact @{
            path        = 'transcript/collector.log'
            category    = 'collector_log'
            type        = 'raw'
            description = 'Structured per-event collector log (one JSON line per entry)'
        }
    }

    # Build the timings summary from the on-disk collector log before sealing
    # the manifest. Failure here is non-fatal -- omit the timings block but
    # still ship the bundle.
    try {
        $timings = Build-DiagTimingsSummary -LogPath $logPath
        if ($null -ne $timings) { $manifest['timings'] = $timings }
    } catch {
        Write-DiagLog -Severity warning -Collector 'Invoke-DiagBundle' -Message "Build-DiagTimingsSummary failed: $($_.Exception.Message)"
    }

    $stepIndex++
    Write-Progress -Id 1 -Activity $progressActivity -Status "[$stepIndex/$totalSteps] Finalize manifest" -PercentComplete ([int](($stepIndex / $totalSteps) * 100))
    # Defense-in-depth re-cast. ConvertTo-Json serializes an OrderedDictionary
    # value held in another OrderedDictionary slot as the type-name string
    # instead of expanding it; PSCustomObject round-trips correctly. The cast
    # at insertion (above) handles the normal path; this re-cast covers any
    # collector or post-step that might have replaced the slot.
    if ($manifest.collection.Contains('problem_description') -and $null -ne $manifest.collection['problem_description']) {
        $manifest.collection['problem_description'] = [pscustomobject]$manifest.collection['problem_description']
    }
    $completedUtc = [DateTime]::UtcNow
    $manifestPath = Complete-DiagManifest -Manifest $manifest -BundleRoot $bundleRoot -CompletedUtc $completedUtc

    $stepIndex++
    Write-Progress -Id 1 -Activity $progressActivity -Status "[$stepIndex/$totalSteps] Checksums" -PercentComplete ([int](($stepIndex / $totalSteps) * 100))
    $checksumsPath = Join-Path $bundleRoot 'checksums.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -Path $bundleRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $checksumsPath } |
        Sort-Object FullName |
        ForEach-Object {
            $rel = ($_.FullName.Substring($bundleRoot.Length + 1)) -replace '\\', '/'
            $sha = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $lines.Add("$sha  $rel") | Out-Null
        }
    [System.IO.File]::WriteAllText($checksumsPath, [string]::Join("`r`n", $lines), [System.Text.UTF8Encoding]::new($false))

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    }
    $stepIndex++
    Write-Progress -Id 1 -Activity $progressActivity -Status "[$stepIndex/$totalSteps] Compressing" -PercentComplete ([int](($stepIndex / $totalSteps) * 100))
    $zipPath = Join-Path $OutputPath "$bundleName.zip"
    $zipSize = Compress-DiagBundle -Source $bundleRoot -Destination $zipPath

    try { Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction Stop } catch {
        Write-Verbose "Could not remove working dir $workRoot : $($_.Exception.Message)"
    }

    $script:DiagLogPath = $null
    Write-Progress -Id 1 -Activity $progressActivity -Completed

    [pscustomobject]@{
        BundleId    = $bundleId
        ZipPath     = $zipPath
        ZipBytes    = [long]$zipSize
        StartedUtc  = $startedUtc
        CompletedUtc = $completedUtc
        DurationSeconds = [int]($completedUtc - $startedUtc).TotalSeconds
    }
}
