function Get-DiagWER {
    <#
    .SYNOPSIS
        Inventory WER ReportArchive/ReportQueue and Windows minidumps, and optionally include each in-window report directory's full contents and recent minidumps under a size cap.

    .DESCRIPTION
        Walks %ProgramData%\Microsoft\Windows\WER\ReportArchive and ReportQueue and writes a directory-level CSV index. Walks %windir%\Minidump and writes a per-file CSV index with size and modified time. When IncludeCrashArtifacts is $true, copies the contents of every report directory modified within WindowDays into raw\wer\reports\<dirname>\ (Report.wer text manifest plus any cab, sysdata.xml, memory.hdmp, etc.) and minidumps newer than the cutoff into raw\dumps\. Two caps apply to report-file inclusion: PerReportCapBytes (default 5MB) and the overall CrashSizeCapBytes (default 50MB). Report directories are processed newest-first; oversized files are skipped, smaller siblings still ship. The minidump pass uses whatever overall budget remains after the report-file pass. Indexes are produced even when content inclusion is off, so the agent always sees what exists.

    .PARAMETER WorkingDirectory
        Root of the staging tree. Artifacts land under summary\, raw\wer\, and raw\dumps\ inside this path.

    .PARAMETER IncludeCrashArtifacts
        When $true (default), copies eligible report-directory contents and minidumps into the bundle. When $false, only the indexes are produced.

    .PARAMETER CrashSizeCapBytes
        Overall size budget shared by report-file copies and minidump copies. Defaults to 50MB. The dump pass uses whatever budget the report-file pass left behind.

    .PARAMETER PerReportCapBytes
        Per-report-directory size cap. Defaults to 5MB. Prevents one large memory.hdmp from consuming the whole bundle budget on its own.

    .PARAMETER WindowDays
        Maximum age in days for a report directory or dump to be eligible for copy. Defaults to 7, matching locked decision #5.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with path/category/type/description and per-type metadata), Errors (array of hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagWER -WorkingDirectory 'C:\ProgramData\DiagBundle\work\bundle-001' -WindowDays 7

    .NOTES
        Artifacts written:
          summary/crashes_wer.json
          raw/wer/ReportArchive_index.csv
          raw/dumps/minidump_index.csv
          raw/wer/reports/<dirname>/<file>  (per-report contents when IncludeCrashArtifacts=$true and within window/caps)
          raw/dumps/<file>.dmp              (only when IncludeCrashArtifacts=$true and within window/cap)

        Per locked decision #5, only entries dated within WindowDays count toward inclusion, and total copied bytes are capped at CrashSizeCapBytes with newest-first ordering and per-file skip when the budget is exhausted. Inside a report directory, files are processed smallest-first so the cheap text manifest (Report.wer) lands even when a big memory.hdmp blows the per-report cap. Indexes are always produced.

        LiveKernelReports inventory and copy: every file under %windir%\LiveKernelReports is recorded in kernel_dumps.live_kernel_reports.files[] with name, size, mtime, in_window flag, copied flag, and skip_reason when not copied. In-window files under LkrCopyCapBytes are copied to raw\dumps\livekernelreports\. Files exceeding the cap remain index-only so the operator can pull them manually from the host. The cap is sized to the bundle's raw 2 GB ceiling: a single 1 GB LKR leaves room for the rest of the bundle without triggering trim-oldest.

        Schema note: summary/crashes_wer.json is at schema_version 1.3. 1.0 -> 1.1 renamed cabs_* to report_files_* and added per_report_cap_bytes when the inclusion path was generalised from cab-only to full report directories. 1.1 -> 1.2 added the kernel_dumps section (CrashControl policy + Minidump and LiveKernelReports directory inventory + page-file adequacy verdict). 1.2 -> 1.3 added per-file LiveKernelReports inventory and in-window copy logic (files[], copied_count, copied_bytes, copy_cap_per_file_bytes).

        The collector never throws. On fatal abort it returns Success=$false with populated Errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter()]
        [bool] $IncludeCrashArtifacts = $true,

        [Parameter()]
        [long] $CrashSizeCapBytes = 50MB,

        [Parameter()]
        [long] $PerReportCapBytes = 5MB,

        [Parameter()]
        [int] $WindowDays = 7,

        [Parameter()]
        [ValidateRange(0, 10GB)]
        [long] $LkrCopyCapBytes = 1GB
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
        $cutoff = (Get-Date).AddDays(-$WindowDays)

        $werRoots = @(
            Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'
            Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'
        )

        $reports = Invoke-DiagTimed -Collector 'Get-DiagWER' -Step 'WER ReportArchive + ReportQueue tree walk' -Action {
            $acc = @()
            foreach ($root in $werRoots) {
                if (-not (Test-Path -LiteralPath $root)) { continue }
                Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $acc += [ordered]@{
                        path         = $_.FullName
                        parent       = Split-Path -Leaf $root
                        name         = $_.Name
                        modified_utc = $_.LastWriteTimeUtc.ToString($fmt)
                        cab_count    = (Get-ChildItem -Path $_.FullName -Filter '*.cab' -ErrorAction SilentlyContinue | Measure-Object).Count
                        file_count   = (Get-ChildItem -Path $_.FullName -ErrorAction SilentlyContinue | Measure-Object).Count
                    }
                }
            }
            , $acc
        }
        if ($null -eq $reports) { $reports = @() }

        # Skip the index entirely when there are no reports. Export-Csv on an
        # empty pipeline writes only the UTF-8 BOM (3 bytes), producing a
        # misleading "index" artifact. dumps_total / wer_report_count in the
        # summary already conveys "nothing here".
        if ($reports.Count -gt 0) {
            $reportIndexPath = Join-Path $WorkingDirectory 'raw\wer\ReportArchive_index.csv'
            $reports | ForEach-Object { New-Object PSObject -Property $_ } |
                Export-Csv -Path $reportIndexPath -NoTypeInformation -Encoding UTF8
            $result.Artifacts += @{
                path        = 'raw/wer/ReportArchive_index.csv'
                category    = 'wer_index'
                type        = 'raw'
                description = 'WER report directory inventory'
                row_count   = $reports.Count
            }
        }

        # Walk report directories within window and copy every file inside (the
        # text manifest Report.wer is the high-value artifact when WER did not
        # assemble a cab, plus the cab itself, sysdata.xml, memory.hdmp, etc.).
        # Two caps apply: per-report (PerReportCapBytes) and overall
        # (CrashSizeCapBytes). Files that would breach either cap are skipped
        # (newest report dirs are processed first).
        $reportFilesIncluded   = 0
        $reportFilesSkipped    = 0
        $reportFilesTotalBytes = 0L
        $reportsIncluded       = 0
        if ($IncludeCrashArtifacts) {
            $reportsDest = Join-Path $WorkingDirectory 'raw\wer\reports'
            $eligibleDirs = @()
            foreach ($root in $werRoots) {
                if (-not (Test-Path -LiteralPath $root)) { continue }
                $eligibleDirs += Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -ge $cutoff }
            }
            foreach ($dir in ($eligibleDirs | Sort-Object LastWriteTime -Descending)) {
                $perReportBytes = 0L
                $thisDirIncluded = $false
                $destDir = Join-Path $reportsDest $dir.Name
                $files = Get-ChildItem -LiteralPath $dir.FullName -File -ErrorAction SilentlyContinue
                foreach ($f in ($files | Sort-Object Length)) {
                    if (($reportFilesTotalBytes + $f.Length) -gt $CrashSizeCapBytes) { $reportFilesSkipped++; continue }
                    if (($perReportBytes + $f.Length) -gt $PerReportCapBytes)        { $reportFilesSkipped++; continue }
                    if (-not (Test-Path -LiteralPath $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }
                    $destFile = Join-Path $destDir $f.Name
                    try {
                        Copy-Item -LiteralPath $f.FullName -Destination $destFile -Force -ErrorAction Stop
                        $reportFilesIncluded++
                        $reportFilesTotalBytes += $f.Length
                        $perReportBytes += $f.Length
                        $thisDirIncluded = $true
                        $result.Artifacts += @{
                            path        = "raw/wer/reports/$($dir.Name)/$($f.Name)"
                            category    = 'wer_report_file'
                            type        = 'raw'
                            description = "WER report $($dir.Name) -> $($f.Name)"
                        }
                    } catch {
                        $result.Errors += @{ collector = 'Get-DiagWER'; artifact = "raw/wer/reports/$($dir.Name)/$($f.Name)"; reason = $_.Exception.Message; severity = 'warning' }
                    }
                }
                if ($thisDirIncluded) { $reportsIncluded++ }
            }
        }

        $minidumpDir = Join-Path $env:windir 'Minidump'
        $dumps = @()
        $dumpsCopied = 0
        $dumpsSkipped = 0
        $dumpsTotalBytes = 0L
        if (Test-Path -LiteralPath $minidumpDir) {
            $dumps = @(Get-ChildItem -Path $minidumpDir -Filter '*.dmp' -ErrorAction SilentlyContinue | ForEach-Object {
                [ordered]@{
                    name         = $_.Name
                    size_mb      = [math]::Round($_.Length / 1MB, 1)
                    modified_utc = $_.LastWriteTimeUtc.ToString($fmt)
                    in_window    = ($_.LastWriteTime -ge $cutoff)
                }
            })

            # Skip the index entirely when there are no dumps. Export-Csv on
            # an empty pipeline writes only the UTF-8 BOM (3 bytes), producing
            # a misleading "index" artifact. summary.dumps_total = 0 already
            # conveys "no dumps here".
            if ($dumps.Count -gt 0) {
                $dumpIndexPath = Join-Path $WorkingDirectory 'raw\dumps\minidump_index.csv'
                $dumps | ForEach-Object { New-Object PSObject -Property $_ } |
                    Export-Csv -Path $dumpIndexPath -NoTypeInformation -Encoding UTF8
                $result.Artifacts += @{
                    path        = 'raw/dumps/minidump_index.csv'
                    category    = 'minidump_index'
                    type        = 'raw'
                    description = 'Minidump inventory'
                    row_count   = $dumps.Count
                }
            }

            if ($IncludeCrashArtifacts) {
                $remainingCap = [Math]::Max(0L, $CrashSizeCapBytes - $reportFilesTotalBytes)
                $eligible = Get-ChildItem -Path $minidumpDir -Filter '*.dmp' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -ge $cutoff } |
                    Sort-Object LastWriteTime -Descending
                foreach ($d in $eligible) {
                    if (($dumpsTotalBytes + $d.Length) -gt $remainingCap) { $dumpsSkipped++; continue }
                    $destFile = Join-Path $WorkingDirectory ('raw\dumps\' + $d.Name)
                    try {
                        Copy-Item -LiteralPath $d.FullName -Destination $destFile -Force -ErrorAction Stop
                        $dumpsCopied++
                        $dumpsTotalBytes += $d.Length
                        $result.Artifacts += @{
                            path        = "raw/dumps/$($d.Name)"
                            category    = 'minidump'
                            type        = 'raw'
                            description = "Minidump modified $($d.LastWriteTimeUtc.ToString($fmt))"
                        }
                    } catch {
                        $result.Errors += @{ collector = 'Get-DiagWER'; artifact = "raw/dumps/$($d.Name)"; reason = $_.Exception.Message; severity = 'warning' }
                    }
                }
            }
        }

        # ---------- kernel_dumps inventory ----------
        # Surface the host's CrashControl policy and the actual contents of the
        # default Minidump and LiveKernelReports directories so the agent can
        # tell "dumps disabled" from "dumps enabled but never produced".
        # Cross-reference the page file size against the configured dump type
        # for an early answer to "would a future bugcheck even produce a dump".
        $kdInv = _BuildKernelDumpsInventory `
            -Cutoff                $cutoff `
            -Fmt                   $fmt `
            -WorkingDirectory      $WorkingDirectory `
            -IncludeCrashArtifacts $IncludeCrashArtifacts `
            -LkrCopyCapBytes       $LkrCopyCapBytes
        $kernelDumps = $kdInv.KernelDumps
        foreach ($a in @($kdInv.Artifacts)) { $result.Artifacts += $a }
        foreach ($e in @($kdInv.Errors))    { $result.Errors    += $e }

        $data = [ordered]@{
            schema_version = '1.3'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data           = [ordered]@{
                wer_report_count          = $reports.Count
                reports_dirs_included     = $reportsIncluded
                report_files_included     = $reportFilesIncluded
                report_files_skipped_budget = $reportFilesSkipped
                report_files_total_bytes  = $reportFilesTotalBytes
                window_days               = $WindowDays
                per_report_cap_bytes      = $PerReportCapBytes
                size_cap_bytes            = $CrashSizeCapBytes
                dumps_total               = $dumps.Count
                dumps_in_window           = ($dumps | Where-Object { $_.in_window } | Measure-Object).Count
                dumps_included            = $dumpsCopied
                dumps_skipped_budget      = $dumpsSkipped
                kernel_dumps              = $kernelDumps
            }
        }

        $sumPath = Join-Path $WorkingDirectory 'summary\crashes_wer.json'
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($sumPath, $json, [System.Text.UTF8Encoding]::new($false))

        $result.Artifacts += @{
            path           = 'summary/crashes_wer.json'
            category       = 'crashes_wer'
            schema_version = '1.3'
            type           = 'derived'
            description    = 'WER and minidump inventory, dump inclusion stats, kernel dump policy and page-file adequacy'
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagWER'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}

function _BuildKernelDumpsInventory {
    <#
    Read CrashControl policy, walk Minidump and LiveKernelReports directories,
    check page-file adequacy for the configured dump type, and (when
    IncludeCrashArtifacts is true) copy in-window LKR files under the per-file
    cap into raw\dumps\livekernelreports\. Returns a pscustomobject with three
    fields: KernelDumps (the ordered hashtable of inventory data), Artifacts
    (artifact entries for any files copied), and Errors (warnings encountered
    during read or copy). The caller merges Artifacts and Errors into its own
    $result. Never throws.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [DateTime] $Cutoff,
        [Parameter(Mandatory)] [string]   $Fmt,
        [Parameter()]          [string]   $WorkingDirectory,
        [Parameter()]          [bool]     $IncludeCrashArtifacts = $false,
        [Parameter()]          [long]     $LkrCopyCapBytes = 1GB
    )

    $artifacts = @()
    $errors    = @()

    # CrashControl policy
    $policy = [ordered]@{
        crash_dump_enabled       = $null
        crash_dump_enabled_label = 'unknown'
        dump_file                = $null
        minidump_dir             = $null
        minidumps_count          = $null
        overwrite                = $null
        log_event                = $null
        send_alert               = $null
        auto_reboot              = $null
        filter_pages             = $null
    }
    $labelMap = @{
        0 = 'none'
        1 = 'complete'
        2 = 'kernel'
        3 = 'small (minidump only)'
        7 = 'automatic'
    }
    try {
        $cc = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction Stop
        if ($null -ne $cc.CrashDumpEnabled) {
            $policy.crash_dump_enabled       = [int]$cc.CrashDumpEnabled
            $policy.crash_dump_enabled_label = if ($labelMap.ContainsKey([int]$cc.CrashDumpEnabled)) { $labelMap[[int]$cc.CrashDumpEnabled] } else { "unknown ($($cc.CrashDumpEnabled))" }
        }
        if ($null -ne $cc.DumpFile)        { $policy.dump_file       = [Environment]::ExpandEnvironmentVariables([string]$cc.DumpFile) }
        if ($null -ne $cc.MinidumpDir)     { $policy.minidump_dir    = [Environment]::ExpandEnvironmentVariables([string]$cc.MinidumpDir) }
        if ($null -ne $cc.MinidumpsCount)  { $policy.minidumps_count = [int]$cc.MinidumpsCount }
        if ($null -ne $cc.Overwrite)       { $policy.overwrite       = [int]$cc.Overwrite }
        if ($null -ne $cc.LogEvent)        { $policy.log_event       = [int]$cc.LogEvent }
        if ($null -ne $cc.SendAlert)       { $policy.send_alert      = [int]$cc.SendAlert }
        if ($null -ne $cc.AutoReboot)      { $policy.auto_reboot     = [int]$cc.AutoReboot }
        if ($null -ne $cc.FilterPages)     { $policy.filter_pages    = [int]$cc.FilterPages }
    } catch {
        $errors += @{ collector = 'Get-DiagWER'; artifact = 'summary/crashes_wer.json:kernel_dumps.policy'; reason = "CrashControl read failed: $($_.Exception.Message)"; severity = 'warning' }
    }

    # MEMORY.DMP (full kernel/complete dump)
    $memDmp = [ordered]@{
        exists               = $false
        path                 = $null
        size_bytes           = 0
        modified_utc         = $null
        in_collection_window = $false
    }
    $dumpFilePath = if ($policy.dump_file) { $policy.dump_file } else { Join-Path $env:windir 'MEMORY.DMP' }
    if (Test-Path -LiteralPath $dumpFilePath) {
        try {
            $f = Get-Item -LiteralPath $dumpFilePath -ErrorAction Stop
            $memDmp.exists               = $true
            $memDmp.path                 = $f.FullName
            $memDmp.size_bytes           = [long]$f.Length
            $memDmp.modified_utc         = $f.LastWriteTimeUtc.ToString($Fmt)
            $memDmp.in_collection_window = ($f.LastWriteTime -ge $Cutoff)
        } catch { }
    }

    # Minidump directory
    $miniDir = [ordered]@{
        path                = $null
        is_default_location = $true
        exists              = $false
        file_count          = 0
        in_window_count     = 0
        total_bytes         = 0
        newest_utc          = $null
        oldest_utc          = $null
    }
    $miniPath = if ($policy.minidump_dir) { $policy.minidump_dir } else { Join-Path $env:windir 'Minidump' }
    $miniDir.path                = $miniPath
    $miniDir.is_default_location = ($miniPath -ieq (Join-Path $env:windir 'Minidump'))
    if (Test-Path -LiteralPath $miniPath) {
        $miniDir.exists = $true
        try {
            $files = @(Get-ChildItem -LiteralPath $miniPath -File -ErrorAction Stop)
            $miniDir.file_count      = $files.Count
            $miniDir.in_window_count = @($files | Where-Object { $_.LastWriteTime -ge $Cutoff }).Count
            $miniDir.total_bytes     = [long](($files | Measure-Object -Property Length -Sum).Sum)
            if ($files.Count -gt 0) {
                $sorted = $files | Sort-Object LastWriteTimeUtc
                $miniDir.oldest_utc = $sorted[0].LastWriteTimeUtc.ToString($Fmt)
                $miniDir.newest_utc = $sorted[$sorted.Count - 1].LastWriteTimeUtc.ToString($Fmt)
            }
        } catch { }
    }

    # LiveKernelReports directory (live kernel reports, not crash dumps).
    # Records every file under %windir%\LiveKernelReports as a per-file entry
    # in $lkrDir.files with name, size, mtime, in_window and copied flags, and
    # skip_reason when not copied. When IncludeCrashArtifacts is true, copies
    # in-window files under LkrCopyCapBytes into raw\dumps\livekernelreports\.
    # The cap is enforced on raw size because the bundle's 2 GB hard ceiling
    # (locked decision #8) is enforced on raw bytes; a single 1 GB LKR leaves
    # room for the rest of the bundle without triggering trim-oldest.
    $lkrDir = [ordered]@{
        path                     = $null
        exists                   = $false
        file_count               = 0
        in_window_count          = 0
        total_bytes              = 0
        newest_utc               = $null
        copied_count             = 0
        copied_bytes             = 0
        copy_cap_per_file_bytes  = $LkrCopyCapBytes
        files                    = @()
    }
    $lkrPath = Join-Path $env:windir 'LiveKernelReports'
    $lkrDir.path = $lkrPath
    if (Test-Path -LiteralPath $lkrPath) {
        $lkrDir.exists = $true

        $lkrDest = $null
        if ($IncludeCrashArtifacts -and $WorkingDirectory) {
            $lkrDest = Join-Path $WorkingDirectory 'raw\dumps\livekernelreports'
            try {
                if (-not (Test-Path -LiteralPath $lkrDest)) {
                    New-Item -ItemType Directory -Force -Path $lkrDest | Out-Null
                }
            } catch {
                $errors += @{ collector = 'Get-DiagWER'; artifact = 'raw/dumps/livekernelreports'; reason = "create dir failed: $($_.Exception.Message)"; severity = 'warning' }
                $lkrDest = $null
            }
        }

        try {
            # Sort newest-first so the most recent reports are processed first
            # and end up adjacent in the inventory regardless of file_count.
            $files = @(Get-ChildItem -LiteralPath $lkrPath -File -Recurse -ErrorAction Stop |
                Sort-Object LastWriteTimeUtc -Descending)

            $lkrDir.file_count      = $files.Count
            $lkrDir.in_window_count = @($files | Where-Object { $_.LastWriteTime -ge $Cutoff }).Count
            $lkrDir.total_bytes     = [long](($files | Measure-Object -Property Length -Sum).Sum)
            if ($files.Count -gt 0) {
                $lkrDir.newest_utc = $files[0].LastWriteTimeUtc.ToString($Fmt)
            }

            $perFile = @()
            foreach ($f in $files) {
                # Path relative to the LiveKernelReports root, forward-slashed,
                # so subdirectory layout (WATCHDOG\, USERMODE\, etc.) survives
                # the inventory.
                $rel = $f.FullName.Substring($lkrPath.Length).TrimStart('\') -replace '\\','/'
                $inWindow = ($f.LastWriteTime -ge $Cutoff)
                $entry = [ordered]@{
                    name          = $f.Name
                    relative_path = $rel
                    size_bytes    = [long]$f.Length
                    modified_utc  = $f.LastWriteTimeUtc.ToString($Fmt)
                    in_window     = $inWindow
                    copied        = $false
                    skip_reason   = $null
                }
                if (-not $IncludeCrashArtifacts) {
                    $entry.skip_reason = 'crash_artifacts_disabled'
                } elseif (-not $inWindow) {
                    $entry.skip_reason = 'out_of_window'
                } elseif ($f.Length -gt $LkrCopyCapBytes) {
                    $entry.skip_reason = 'over_per_file_cap'
                } elseif (-not $lkrDest) {
                    $entry.skip_reason = 'copy_failed'
                } else {
                    # Copy with a flat destination layout. Subdirectory paths
                    # in LiveKernelReports collide rarely; if they do, the
                    # second copy returns an "already exists" error which
                    # surfaces below.
                    $destFile = Join-Path $lkrDest $f.Name
                    try {
                        Copy-Item -LiteralPath $f.FullName -Destination $destFile -Force -ErrorAction Stop
                        $entry.copied = $true
                        $lkrDir.copied_count++
                        $lkrDir.copied_bytes += $f.Length
                        $artifacts += @{
                            path        = "raw/dumps/livekernelreports/$($f.Name)"
                            category    = 'live_kernel_report'
                            type        = 'raw'
                            description = "LiveKernelReport modified $($f.LastWriteTimeUtc.ToString($Fmt))"
                            size_bytes  = [long]$f.Length
                        }
                    } catch {
                        $entry.skip_reason = 'copy_failed'
                        $errors += @{ collector = 'Get-DiagWER'; artifact = "raw/dumps/livekernelreports/$($f.Name)"; reason = $_.Exception.Message; severity = 'warning' }
                    }
                }
                $perFile += ,$entry
            }
            $lkrDir.files = $perFile
        } catch {
            $errors += @{ collector = 'Get-DiagWER'; artifact = 'summary/crashes_wer.json:kernel_dumps.live_kernel_reports'; reason = "LiveKernelReports walk failed: $($_.Exception.Message)"; severity = 'warning' }
        }
    }

    # Page-file adequacy check for the configured dump type.
    # Sources:
    #   crash_dump_enabled      0 disabled, 1 complete, 2 kernel, 3 small, 7 automatic
    #   physical memory bytes   Win32_ComputerSystem.TotalPhysicalMemory
    #   page file actual bytes  Win32_PageFileUsage.AllocatedBaseSize (MB)
    # Rules used (Microsoft guidance for dump file generation):
    #   complete  : page file >= phys mem + 257 MB   (we use phys + 256 MB)
    #   kernel    : page file >= phys mem            (heuristic; Microsoft uses a
    #               formula based on used kernel memory; physical is a safe upper
    #               bound and avoids false negatives on small servers)
    #   small     : page file >= 2 MB                (effectively always)
    #   automatic : system manages -- skip the check
    #   disabled  : N/A
    $pageFile = [ordered]@{
        adequate                  = $null
        verdict                   = 'unknown'
        physical_memory_mb        = $null
        configured_initial_mb     = $null
        allocated_base_mb         = $null
        required_min_mb_for_type  = $null
    }
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $physMb = [long]([math]::Round($cs.TotalPhysicalMemory / 1MB, 0))
        $pageFile.physical_memory_mb = $physMb

        # Sum across all page files (Win32_PageFileUsage rows). Returns nothing
        # when the system uses 100% system-managed page file with current use 0.
        $pf = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
        if ($pf) {
            $pageFile.allocated_base_mb = [int](@($pf | Measure-Object -Property AllocatedBaseSize -Sum).Sum)
        }
        $pfs = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
        if ($pfs) {
            $pageFile.configured_initial_mb = [int](@($pfs | Measure-Object -Property InitialSize -Sum).Sum)
        }

        switch ([int]$policy.crash_dump_enabled) {
            0 { $pageFile.verdict = 'not_applicable'; $pageFile.adequate = $true }
            1 { # complete
                $required = $physMb + 256
                $pageFile.required_min_mb_for_type = $required
                $actual = if ($pageFile.allocated_base_mb) { $pageFile.allocated_base_mb } else { $pageFile.configured_initial_mb }
                if ($null -ne $actual) {
                    $pageFile.adequate = ($actual -ge $required)
                    $pageFile.verdict = if ($actual -ge $required) { 'adequate' } else { 'too_small_for_complete_dump' }
                }
              }
            2 { # kernel
                $required = $physMb
                $pageFile.required_min_mb_for_type = $required
                $actual = if ($pageFile.allocated_base_mb) { $pageFile.allocated_base_mb } else { $pageFile.configured_initial_mb }
                if ($null -ne $actual) {
                    $pageFile.adequate = ($actual -ge $required)
                    $pageFile.verdict = if ($actual -ge $required) { 'adequate' } else { 'small_for_kernel_dump_under_load' }
                }
              }
            3 { # small / minidump
                $pageFile.required_min_mb_for_type = 2
                $pageFile.adequate = $true
                $pageFile.verdict  = 'adequate'
              }
            7 { # automatic
                $pageFile.verdict  = 'system_managed'
                $pageFile.adequate = $null
              }
            default { $pageFile.verdict = 'unknown_dump_type' }
        }
    } catch {
        $errors += @{ collector = 'Get-DiagWER'; artifact = 'summary/crashes_wer.json:kernel_dumps.page_file'; reason = "page-file adequacy check failed: $($_.Exception.Message)"; severity = 'warning' }
    }

    # Top-level interpretation -- a one-line answer to "are kernel dumps even possible here"
    $interpretation = ''
    if ($null -eq $policy.crash_dump_enabled) {
        $interpretation = 'CrashControl key not readable; kernel dump policy unknown.'
    } elseif ([int]$policy.crash_dump_enabled -eq 0) {
        $interpretation = 'Kernel dumps DISABLED (CrashDumpEnabled=0). The host will not produce a MEMORY.DMP or minidump on bugcheck.'
    } else {
        $reasons = New-Object System.Collections.ArrayList
        [void]$reasons.Add("CrashDumpEnabled=$($policy.crash_dump_enabled) ($($policy.crash_dump_enabled_label)).")
        if (-not $miniDir.exists) {
            [void]$reasons.Add("Minidump directory does not exist (Windows creates it on first bugcheck) -- no kernel crash has ever occurred on this host.")
        } elseif ($miniDir.file_count -eq 0) {
            [void]$reasons.Add("Minidump directory exists but is empty (no bugcheck since the last cleanup, or no bugcheck has occurred).")
        } elseif ($miniDir.in_window_count -gt 0) {
            [void]$reasons.Add("$($miniDir.in_window_count) minidump(s) in collection window.")
        } else {
            [void]$reasons.Add("$($miniDir.file_count) minidump(s) on disk; none within the collection window (newest $($miniDir.newest_utc)).")
        }
        if ($memDmp.exists -and -not $memDmp.in_collection_window) {
            [void]$reasons.Add("MEMORY.DMP present from $($memDmp.modified_utc) (older than collection window).")
        } elseif ($memDmp.exists -and $memDmp.in_collection_window) {
            [void]$reasons.Add("MEMORY.DMP present and dated within window: $($memDmp.modified_utc).")
        }
        if ($pageFile.verdict -eq 'too_small_for_complete_dump') {
            [void]$reasons.Add("Page file is too small to capture the complete dump the host is configured for.")
        } elseif ($pageFile.verdict -eq 'small_for_kernel_dump_under_load') {
            [void]$reasons.Add("Page file may be too small for a kernel dump under load.")
        }
        $interpretation = ($reasons -join ' ')
    }

    $dumpsDisabled = ($null -ne $policy.crash_dump_enabled -and [int]$policy.crash_dump_enabled -eq 0)

    $kernelDumps = [ordered]@{
        policy              = $policy
        memory_dmp          = $memDmp
        minidump_dir        = $miniDir
        live_kernel_reports = $lkrDir
        page_file           = $pageFile
        dumps_disabled      = $dumpsDisabled
        interpretation      = $interpretation
    }

    return [pscustomobject]@{
        KernelDumps = $kernelDumps
        Artifacts   = $artifacts
        Errors      = $errors
    }
}
