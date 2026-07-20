
# =====================================================================
# ENABLE (restore) all shares from a backup created by
# Windows_Shares_Disable.ps1.
# Run as Administrator. Requires Windows Server 2012+ (SMB cmdlets).
#
# Usage:
#   .\Windows_Shares_Enable.ps1 -BackupFile "C:\ShareBackup\Shares_Backup_20260720_101500.json"
# If -BackupFile is omitted, the newest backup in C:\ShareBackup is used.
# =====================================================================

param(
    [string]$BackupFile
)

$ErrorActionPreference = "Stop"
$backupDir = "C:\ShareBackup"

# Pick the newest backup if none specified
if (-not $BackupFile) {
    $BackupFile = Get-ChildItem -Path $backupDir -Filter "Shares_Backup_*.json" |
                  Sort-Object LastWriteTime -Descending |
                  Select-Object -First 1 -ExpandProperty FullName
}

if (-not $BackupFile -or -not (Test-Path $BackupFile)) {
    throw "Backup file not found. Specify one with -BackupFile."
}

Write-Host "Restoring shares from: $BackupFile"
$backup = Get-Content -Path $BackupFile -Raw | ConvertFrom-Json

$created = 0
$skipped = 0
foreach ($share in $backup) {

    # Skip if the share already exists
    if (Get-SmbShare -Name $share.Name -ErrorAction SilentlyContinue) {
        Write-Warning "Share '$($share.Name)' already exists - skipping."
        $skipped++
        continue
    }

    # Make sure the target folder still exists
    if (-not (Test-Path $share.Path)) {
        Write-Warning "Path '$($share.Path)' for share '$($share.Name)' is missing - skipping."
        $skipped++
        continue
    }

    try {
        # Recreate the share (no default Everyone grant - we apply the saved ACL next)
        New-SmbShare -Name $share.Name -Path $share.Path `
            -Description $share.Description `
            -FolderEnumerationMode $share.FolderEnumMode `
            -CachingMode $share.CachingMode `
            -FullAccess "Administrators" | Out-Null

        # Remove the temporary Administrators grant, then apply the saved ACL exactly
        Revoke-SmbShareAccess -Name $share.Name -AccountName "Administrators" -Force -ErrorAction SilentlyContinue | Out-Null

        foreach ($ace in $share.Access) {
            if ($ace.AccessControlType -eq "Allow") {
                Grant-SmbShareAccess -Name $share.Name -AccountName $ace.AccountName `
                    -AccessRight $ace.AccessRight -Force | Out-Null
            }
            else {
                Block-SmbShareAccess -Name $share.Name -AccountName $ace.AccountName -Force | Out-Null
            }
        }

        $created++
    }
    catch {
        Write-Warning "Failed to restore share '$($share.Name)': $_"
    }
}

Write-Host "`nRestored $created shares. Skipped $skipped."
