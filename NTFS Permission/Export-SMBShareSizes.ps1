# Export all SMB shares with size details — requires PowerShell 3+ / Server 2012+
#
# Usage — local machine:
#   .\Export-SMBShareSizes.ps1
#
# Usage — remote server:
#   .\Export-SMBShareSizes.ps1 -Server "FILESERVER01"
#
# Usage — multiple servers:
#   .\Export-SMBShareSizes.ps1 -Server "FS01","FS02","FS03"
#
# Note: Size calculation may take time on large shares.
#       Use -SkipSize to export quickly without size data.
#       Each share is written to the CSV as soon as it finishes processing,
#       so partial results are available even if a later share is slow or fails.

param(
    [string[]]$Server     = @($env:COMPUTERNAME),
    [string]  $OutputDir  = "C:\temp",
    [switch]  $IncludeAdmin,   # include built-in admin shares (C$, ADMIN$, IPC$)
    [switch]  $SkipSize        # skip size calculation for faster export
)

# --- Validate output drive exists before doing any work ---
if (-not (Test-Path (Split-Path $OutputDir -Qualifier))) {
    Write-Error "Output drive does not exist: $OutputDir"
    exit 1
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# --- Is the target the machine we're running on? (run directly, no WinRM) ---
function Test-IsLocal {
    param([string]$Server)
    $local = @($env:COMPUTERNAME, "localhost", ".", $env:COMPUTERNAME + "." + $env:USERDNSDOMAIN)
    return ($Server -in $local) -or ([string]::IsNullOrWhiteSpace($Server))
}

# --- The size measurement itself (runs wherever it's invoked) ---
$sizeScriptBlock = {
    param($path)
    if (-not (Test-Path $path)) {
        return [PSCustomObject]@{ SizeBytes = $null; FileCount = $null; Error = "Path not found" }
    }
    # Stream the recursion so we don't hold the whole file list in memory on large shares
    $bytes = [long]0
    $files = [long]0
    Get-ChildItem -Path $path -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
        $bytes += $_.Length
        $files++
    }
    [PSCustomObject]@{ SizeBytes = $bytes; FileCount = $files; Error = $null }
}

# --- Helper: calculate folder size; runs locally when possible, else via remoting ---
function Get-ShareSize {
    param(
        [string]$Server,
        [string]$LocalPath
    )

    if (-not $LocalPath) {
        return [PSCustomObject]@{ SizeBytes = $null; SizeGB = $null; FileCount = $null; Error = "No path" }
    }

    try {
        if (Test-IsLocal -Server $Server) {
            # Running directly on the server — invoke the measurement in-process (no WinRM)
            $result = & $sizeScriptBlock $LocalPath
        } else {
            # Remote server — use PowerShell remoting
            $result = Invoke-Command -ComputerName $Server -ErrorAction Stop `
                        -ScriptBlock $sizeScriptBlock -ArgumentList $LocalPath
        }

        $sizeBytes = $result.SizeBytes
        [PSCustomObject]@{
            SizeBytes = $sizeBytes
            SizeGB    = if ($null -ne $sizeBytes) { [math]::Round($sizeBytes / 1GB, 2) } else { $null }
            FileCount = $result.FileCount
            Error     = $result.Error
        }
    }
    catch {
        [PSCustomObject]@{ SizeBytes = $null; SizeGB = $null; FileCount = $null; Error = $_.Exception.Message }
    }
}

# --- Output file (created lazily on the first exported row) ---
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDir "SMBShares_$timestamp.csv"
$exported   = 0

# --- Main collection: export each share as soon as it completes ---
foreach ($srv in $Server) {
    Write-Host "`nQuerying shares on '$srv'..."

    try {
        # Query shares locally when running on the server itself, else over CIM
        $shares = if (Test-IsLocal -Server $srv) {
            Get-SmbShare -ErrorAction Stop
        } else {
            Get-SmbShare -CimSession $srv -ErrorAction Stop
        }

        if (-not $IncludeAdmin) {
            # Special = $true marks built-in admin shares (C$, ADMIN$, IPC$).
            # Some default shares (print$, NETLOGON, SYSVOL, FAX$) report Special = $false,
            # so exclude those by name too. User-created hidden shares (e.g. MyShare$) are kept.
            $systemShares = @('print$', 'NETLOGON', 'SYSVOL', 'FAX$')
            $shares = $shares | Where-Object {
                $_.Special -eq $false -and $_.Name -notin $systemShares
            }
        }

        foreach ($share in $shares) {
            Write-Host "  Processing share: $($share.Name)"

            # --- Size calculation ---
            $sizeInfo = if ($SkipSize) {
                [PSCustomObject]@{ SizeBytes = "Skipped"; SizeGB = "Skipped"; FileCount = "Skipped"; Error = $null }
            } else {
                Write-Host "    Calculating size for '$($share.Path)'..." -ForegroundColor DarkGray
                Get-ShareSize -Server $srv -LocalPath $share.Path
            }

            if ($sizeInfo.Error) {
                Write-Warning "    Size error on '$($share.Name)': $($sizeInfo.Error)"
            }

            $row = [PSCustomObject]@{
                Server      = $srv
                ShareName   = $share.Name
                LocalPath   = $share.Path
                UNCPath     = "\\$srv\$($share.Name)"
                Description = $share.Description
                ShareState  = $share.ShareState
                Special     = $share.Special
                SizeBytes   = $sizeInfo.SizeBytes
                SizeGB      = $sizeInfo.SizeGB
                FileCount   = $sizeInfo.FileCount
                SizeError   = $sizeInfo.Error
            }

            # --- Write this share immediately (append after the first row) ---
            $row | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8 -Delimiter "`t" -Append
            $exported++

            # --- One clean summary line per share ---
            $sizeText  = if ($SkipSize) { "size skipped" } else { "$($row.SizeGB) GB" }
            $countText = if ($SkipSize) { "" } else { ", $($row.FileCount) files" }
            Write-Host ("    -> {0} ({1}{2})" -f $row.ShareName, $sizeText, $countText) -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "  Failed on '$srv': $_"
    }
}

if ($exported -eq 0) {
    Write-Warning "No shares found."
    return
}

Write-Host "`nExported $exported share(s) -> $outputFile" -ForegroundColor Green
