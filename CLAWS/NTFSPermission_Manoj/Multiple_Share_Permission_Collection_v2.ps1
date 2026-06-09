# Collect NTFS permissions for all disk shares on a server (or from a CSV fallback)
#
# Usage — auto-discover shares on local machine:
#   .\Batch-CollectNTFSPerms.ps1
#
# Usage — target a remote server:
#   .\Batch-CollectNTFSPerms.ps1 -Server "FILESERVER01"
#
# Usage — use an existing CSV instead of WMI:
#   .\Batch-CollectNTFSPerms.ps1 -CsvPath "C:\temp\folders.csv"

param(
    [string]$Server    = $env:COMPUTERNAME,
    [string]$CsvPath   = "",
    [string]$ExePath   = "C:\Temp\CollectNTFSPerms\CollectNTFSPerms.exe",
    [string]$OutputDir = "C:\temp\permissions"
)

# ── Validate exe ────────────────────────────────────────────────────────────
if (-not (Test-Path $ExePath)) {
    Write-Error "Executable not found: $ExePath"
    exit 1
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# ── Build folder list ────────────────────────────────────────────────────────
$folderPaths = @()

if ($CsvPath -ne "") {
    # Manual CSV mode (one path per line, no header)
    if (-not (Test-Path $CsvPath)) {
        Write-Error "CSV not found: $CsvPath"
        exit 1
    }
    $folderPaths = Get-Content $CsvPath | Where-Object { $_.Trim() -ne "" } |
                   ForEach-Object { $_.Trim() }
    Write-Host "Mode : CSV ($CsvPath)"
}
else {
    # Auto-discover disk shares via WMI (Type=0 = disk shares only)
    Write-Host "Mode : WMI share discovery on '$Server'"
    try {
        $shares = Get-WmiObject -ComputerName $Server `
                    -Query "SELECT * FROM Win32_Share WHERE Type=0" |
                  Select-Object -ExpandProperty Path |
                  Where-Object { $_ -ne "" }

        if ($shares.Count -eq 0) {
            Write-Warning "No disk shares found on '$Server'."
            exit 0
        }

        $folderPaths = $shares
    }
    catch {
        Write-Error "WMI query failed on '$Server': $_"
        exit 1
    }
}

# ── Process each path ────────────────────────────────────────────────────────
$total  = $folderPaths.Count
$index  = 0
$errors = @()

Write-Host "Found $total folder(s) to process.`n"

foreach ($folderPath in $folderPaths) {
    $index++

    $safeName = $folderPath -replace '[\\/:*?"<>|]', '_' -replace '^_+|_+$', ''
    $dbFile   = Join-Path $OutputDir "${safeName}_permissions.db"

    Write-Host "[$index/$total] $folderPath"

    if (-not (Test-Path $folderPath)) {
        Write-Warning "  Path not found — skipping."
        $errors += $folderPath
        continue
    }

    try {
        & $ExePath $folderPath $dbFile
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Done -> $dbFile" -ForegroundColor Green
        } else {
            Write-Warning "  Exited with code $LASTEXITCODE"
            $errors += $folderPath
        }
    }
    catch {
        Write-Warning "  Error: $_"
        $errors += $folderPath
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n--- Summary ---"
Write-Host "Server    : $Server"
Write-Host "Processed : $total"
Write-Host "Errors    : $($errors.Count)"

if ($errors.Count -gt 0) {
    Write-Host "`nFailed paths:"
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}