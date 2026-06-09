param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,

    [string]$ExePath   = "C:\Temp\CollectNTFSPerms\CollectNTFSPerms.exe",
    [string]$OutputDir = "C:\temp\permissions"
)

if (-not (Test-Path $ExePath)) {
    Write-Error "Executable not found: $ExePath"
    exit 1
}

if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    exit 1
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$paths  = Get-Content $CsvPath | Where-Object { $_.Trim() -ne "" }
$total  = $paths.Count
$index  = 0
$errors = @()

Write-Host "Found $total folder(s) to process.`n"

foreach ($folderPath in $paths) {
    $folderPath = $folderPath.Trim()
    $index++

    # Build a safe output filename from the folder path
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

Write-Host "`n--- Summary ---"
Write-Host "Processed : $total"
Write-Host "Errors    : $($errors.Count)"

if ($errors.Count -gt 0) {
    Write-Host "`nFailed paths:"
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}
