<#
.SYNOPSIS
    Detects and (optionally) removes NTFS Alternate Data Streams (ADS) that block
    file copies to storage platforms which do not support named streams
    (e.g. Pure Storage FlashBlade / object-backed SMB).

.DESCRIPTION
    Robocopy and Explorer copy a file's alternate data streams along with its
    primary ':$DATA' stream. When the destination filesystem cannot create a
    named stream, the copy fails with:
        Win32 ERROR 123 (0x7B) ERROR_INVALID_NAME          (Robocopy)
        "The file name you specified is not valid or too long"  (Explorer)
    even though the file's real content and its name/path are perfectly valid.

    Common sources of these streams:
        * Zone.Identifier                         Mark-of-the-Web (downloaded files)
        * <random name> + {4c8cc155-6c1e-11d1-... }   Antivirus scan-cache (e.g. Kaspersky)
        * AFP_AfpInfo / com.apple.*               Mac/AFP interop metadata
    None of these are part of the user's actual file content; removing them is a
    metadata operation on the primary file and is safe. AV scan caches regenerate
    automatically on next access.

    This tool ALWAYS runs in audit mode unless -Remediate is specified. Audit mode
    inspects every target file, reports which alternate streams exist, and changes
    nothing. -Remediate removes the matching streams and honours -WhatIf / -Confirm.

    Targets can be supplied two ways:
        * -InputFile   A text file containing one full path per line (e.g. the list
                       of files that failed a Robocopy run). Blank lines and lines
                       beginning with '#' are ignored; surrounding quotes are stripped.
        * -Path        One or more files and/or folders. Use -Recurse to descend into
                       folders; without it, only the folder's immediate files are read.

    Output:
        * A timestamped CSV report of every file inspected (streams found, action taken,
          bytes reclaimed) in -OutputDir (default C:\temp).
        * A timestamped run log in the same folder.
        * PSCustomObjects returned to the pipeline for further automation.

.PARAMETER Path
    One or more files or folders to inspect. Combine with -Recurse for folder trees.

.PARAMETER Recurse
    When -Path contains folders, descend into all sub-folders. Ignored for file paths.

.PARAMETER InputFile
    Path to a UTF-8/ANSI text file listing one target file path per line. Blank lines
    and '#' comment lines are ignored. Ideal for feeding a Robocopy failure list.

.PARAMETER Remediate
    Remove the matching alternate data streams. Without this switch the script only
    audits (reports) and never modifies any file. Supports -WhatIf and -Confirm.

.PARAMETER StreamName
    Optional wildcard filter of stream names to act on (e.g. 'Zone.Identifier',
    'AFP_*'). When omitted, ALL non-primary streams are targeted. The primary
    ':$DATA' stream is never touched.

.PARAMETER ThrottleLimit
    Maximum files processed concurrently during -Remediate. Requires PowerShell 7+.
    Default 1 (sequential). Values >1 on PowerShell 7 enable parallel stream removal
    for large data sets; keep modest to avoid overloading the file server.

.PARAMETER OutputDir
    Directory for the CSV report and run log. Default C:\temp. Created if missing.

.PARAMETER Force
    Suppress the per-file confirmation prompt during -Remediate (sets ConfirmPreference
    to None for this run). Required for unattended remediation. -WhatIf still overrides.

.EXAMPLE
    # 1. Audit the exact files that failed the Robocopy run (no changes):
    .\Repair-AdsForMigration_v1.ps1 -InputFile C:\temp\failed_files.txt

.EXAMPLE
    # 2. Review the CSV in C:\temp, then strip the streams from those same files:
    .\Repair-AdsForMigration_v1.ps1 -InputFile C:\temp\failed_files.txt -Remediate -Force

.EXAMPLE
    # 3. Audit a parent folder tree (your "run only on the parent folder" approach):
    .\Repair-AdsForMigration_v1.ps1 -Path 'D:\Homedirs\dt72023\home\kr\Personal' -Recurse

.EXAMPLE
    # 4. Remediate several parent folders in parallel (PowerShell 7):
    .\Repair-AdsForMigration_v1.ps1 -Path 'D:\Homedirs\dt60532','D:\Homedirs\dt67762' `
        -Recurse -Remediate -ThrottleLimit 8 -Force

.EXAMPLE
    # 5. Preview exactly what would be removed, without removing anything:
    .\Repair-AdsForMigration_v1.ps1 -InputFile C:\temp\failed_files.txt -Remediate -WhatIf

.NOTES
    Run this ON the server that owns the source volume (paths are interpreted locally).
    Recommended migration pattern for change control: Robocopy source -> NTFS staging,
    remediate the staging copy, then Robocopy staging -> Pure. That leaves the production
    source pristine until sign-off. Remediating the source directly is also safe (streams
    are non-content metadata) if your change window permits.

    COMPATIBILITY
        * Requires PowerShell 3.0+ for provider stream access (-Stream). Verified on
          Windows PowerShell 5.1 and PowerShell 7.x.
        * Parallel remediation (-ThrottleLimit > 1) requires PowerShell 7+; on 5.1 the
          script automatically falls back to sequential processing.
        * Windows Server 2008 R2 must be running WMF 5.1 (PowerShell 5.1). Native
          PowerShell 2.0 cannot access alternate streams via the provider.

    LIMITATIONS
        * Paths exceeding 260 characters require long-path support (Windows 10/Server 2016+
          with LongPathsEnabled, or PowerShell 7). Such paths are reported as errors rather
          than silently skipped.
        * Directory alternate streams are not processed; only file streams are handled.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Path')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
    [string[]]$Path,

    [Parameter(ParameterSetName = 'Path')]
    [switch]$Recurse,

    [Parameter(Mandatory, ParameterSetName = 'InputFile')]
    [string]$InputFile,

    [switch]$Remediate,

    [string[]]$StreamName,

    [ValidateRange(1, 256)]
    [int]$ThrottleLimit = 1,

    [string]$OutputDir = 'C:\temp',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

#region --------------------------------------------------------------- Logging / setup

$script:RunStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogFile  = $null

function Write-Log {
    <#
        Writes a timestamped line to the console and, once initialized, to the run log.
        Level controls the console stream (INFO/WARN/ERROR); every level is persisted.
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    switch ($Level) {
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line }
    }
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
        catch { Write-Warning "Could not write to log file '$script:LogFile': $_" }
    }
}

function Initialize-OutputDir {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }
    $script:LogFile = Join-Path $Dir ('Repair-AdsForMigration_{0}.log' -f $script:RunStamp)
}

#endregion

#region --------------------------------------------------------------- Target resolution

function Resolve-TargetFile {
    <#
        Expands the -Path / -InputFile inputs into a flat, de-duplicated list of file
        paths to inspect. Folders are expanded (respecting -Recurse); missing paths are
        logged as warnings and skipped so a single bad entry never aborts the run.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Path,
        [switch]$Recurse,
        [string]$InputFile
    )

    $rawEntries = New-Object System.Collections.Generic.List[string]

    if ($PSCmdlet.ParameterSetName -eq 'InputFile' -or $InputFile) {
        if (-not (Test-Path -LiteralPath $InputFile)) {
            throw "InputFile not found: $InputFile"
        }
        foreach ($raw in Get-Content -LiteralPath $InputFile) {
            $entry = $raw.Trim().Trim('"')
            if (-not $entry -or $entry.StartsWith('#')) { continue }
            $rawEntries.Add($entry)
        }
    }
    else {
        foreach ($p in $Path) { $rawEntries.Add($p) }
    }

    $files = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $rawEntries) {
        try {
            if (-not (Test-Path -LiteralPath $entry)) {
                Write-Log "Target not found, skipping: $entry" -Level WARN
                continue
            }
            $item = Get-Item -LiteralPath $entry -Force
            if ($item.PSIsContainer) {
                $childParams = @{ LiteralPath = $entry; File = $true; Force = $true; ErrorAction = 'Stop' }
                if ($Recurse) { $childParams['Recurse'] = $true }
                foreach ($child in Get-ChildItem @childParams) { $files.Add($child.FullName) }
            }
            else {
                $files.Add($item.FullName)
            }
        }
        catch {
            Write-Log "Failed to resolve '$entry': $($_.Exception.Message)" -Level WARN
        }
    }

    # De-duplicate (the failure list contains repeats) while preserving order.
    $seen = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($f in $files) { if ($seen.Add($f)) { $result.Add($f) } }
    return $result
}

#endregion

#region --------------------------------------------------------------- Core worker

# Self-contained so it can run unchanged inside a PowerShell 7 parallel runspace.
# Returns a PSCustomObject describing what was found and (when $DoRemove) what was removed.
# Performs NO logging and NO ShouldProcess (the caller owns confirmation and logging).
$WorkerScript = {
    param(
        [string]$FilePath,
        [string[]]$StreamNameFilter,
        [bool]$DoRemove
    )

    $result = [pscustomobject]@{
        Path             = $FilePath
        PrimaryBytes     = $null
        ExtraStreamCount = 0
        ExtraStreams     = ''
        Action           = 'Clean'      # Clean | Audit | Removed | Error
        StreamsRemoved   = 0
        BytesReclaimed   = 0
        Error            = ''
    }

    try {
        $streams = Get-Item -LiteralPath $FilePath -Stream * -ErrorAction Stop
        $primary = $streams | Where-Object { $_.Stream -eq ':$DATA' } | Select-Object -First 1
        if ($primary) { $result.PrimaryBytes = $primary.Length }

        $extra = $streams | Where-Object { $_.Stream -ne ':$DATA' }
        if ($StreamNameFilter) {
            $extra = $extra | Where-Object {
                $name = $_.Stream
                @($StreamNameFilter | Where-Object { $name -like $_ }).Count -gt 0
            }
        }

        if (-not $extra) { return $result }   # nothing to do; Action stays 'Clean'

        $result.ExtraStreamCount = @($extra).Count
        $result.ExtraStreams     = ($extra | ForEach-Object { '{0}({1})' -f $_.Stream, $_.Length }) -join '; '

        if (-not $DoRemove) {
            $result.Action = 'Audit'
            return $result
        }

        $removed = 0
        $bytes   = 0
        foreach ($s in $extra) {
            Remove-Item -LiteralPath $FilePath -Stream $s.Stream -ErrorAction Stop
            $removed++
            $bytes += [int64]$s.Length
        }
        $result.Action         = 'Removed'
        $result.StreamsRemoved = $removed
        $result.BytesReclaimed = $bytes
    }
    catch {
        $result.Action = 'Error'
        $result.Error  = $_.Exception.Message
    }

    return $result
}

#endregion

#region --------------------------------------------------------------- Main

$report = $null
try {
    Initialize-OutputDir -Dir $OutputDir
    $mode = if ($Remediate) { 'REMEDIATE' } else { 'AUDIT (read-only)' }
    Write-Log "=== Repair-AdsForMigration started | Mode: $mode | PS $($PSVersionTable.PSVersion) ==="

    $targets = Resolve-TargetFile -Path $Path -Recurse:$Recurse -InputFile $InputFile
    Write-Log ("Resolved {0} unique file(s) to inspect." -f $targets.Count)
    if ($targets.Count -eq 0) {
        Write-Log 'No files to process. Exiting.' -Level WARN
        return
    }

    $doRemove   = [bool]$Remediate
    $useParallel = $false

    if ($doRemove) {
        # Confirmation is required to modify files. In parallel mode we confirm once for
        # the whole batch; in sequential mode we confirm per file (finer control).
        if ($ThrottleLimit -gt 1 -and $PSVersionTable.PSVersion.Major -ge 7 -and -not $WhatIfPreference) {
            $useParallel = $true
            if (-not $PSCmdlet.ShouldProcess(
                    ("{0} file(s)" -f $targets.Count),
                    'Remove alternate data stream(s)')) {
                Write-Log 'Remediation declined at confirmation prompt. No changes made.' -Level WARN
                $doRemove = $false
            }
        }
        elseif ($ThrottleLimit -gt 1) {
            Write-Log 'Parallel mode requires PowerShell 7+ (and not -WhatIf); falling back to sequential.' -Level WARN
        }
    }

    $results = New-Object System.Collections.Generic.List[object]

    if ($useParallel -and $doRemove) {
        Write-Log ("Removing streams in parallel (ThrottleLimit={0})..." -f $ThrottleLimit)
        $funcText = $WorkerScript.ToString()
        $parallelResults = $targets | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            $worker = [scriptblock]::Create($using:funcText)
            & $worker -FilePath $_ -StreamNameFilter $using:StreamName -DoRemove $true
        }
        foreach ($r in $parallelResults) { $results.Add($r) }
    }
    else {
        foreach ($file in $targets) {
            $performRemove = $false
            if ($doRemove) {
                # Per-file ShouldProcess: honours -WhatIf, -Confirm, and -Force (ConfirmPreference).
                if ($PSCmdlet.ShouldProcess($file, 'Remove alternate data stream(s)')) {
                    $performRemove = $true
                }
            }
            $r = & $WorkerScript -FilePath $file -StreamNameFilter $StreamName -DoRemove $performRemove

            switch ($r.Action) {
                'Removed' { Write-Log ("Removed {0} stream(s) [{1}] from {2}" -f $r.StreamsRemoved, $r.ExtraStreams, $r.Path) }
                'Audit'   { Write-Log ("Found {0} stream(s) [{1}] on {2}"     -f $r.ExtraStreamCount, $r.ExtraStreams, $r.Path) }
                'Error'   { Write-Log ("ERROR on {0}: {1}" -f $r.Path, $r.Error) -Level ERROR }
                default   { }   # 'Clean' - no console noise; still recorded in the CSV
            }
            $results.Add($r)
        }
    }

    $report = $results.ToArray()

    # ---- Summary ----
    $withStreams = @($report | Where-Object { $_.ExtraStreamCount -gt 0 })
    $removedRows = @($report | Where-Object { $_.Action -eq 'Removed' })
    $errorRows   = @($report | Where-Object { $_.Action -eq 'Error' })
    $bytesFreed  = ($removedRows | Measure-Object -Property BytesReclaimed -Sum).Sum

    Write-Log '--------------------------------------------------------------'
    Write-Log ("Files inspected      : {0}" -f $report.Count)
    Write-Log ("Files with ADS       : {0}" -f $withStreams.Count)
    Write-Log ("Files remediated     : {0}" -f $removedRows.Count)
    Write-Log ("Streams reclaimed    : {0} bytes" -f ([int64]$bytesFreed))
    Write-Log ("Errors               : {0}" -f $errorRows.Count) -Level $(if ($errorRows.Count) { 'WARN' } else { 'INFO' })
    if (-not $Remediate) {
        Write-Log 'AUDIT ONLY - no files were modified. Re-run with -Remediate to strip the streams.'
    }

    $csv = Join-Path $OutputDir ('AdsRepair_{0}.csv' -f $script:RunStamp)
    $report | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    Write-Log ("Report written to {0}" -f $csv)
    Write-Log '=== Repair-AdsForMigration finished ==='
}
catch {
    Write-Log ("Fatal error: {0}" -f $_.Exception.Message) -Level ERROR
    throw
}

# Return objects to the pipeline for downstream automation.
$report

#endregion
