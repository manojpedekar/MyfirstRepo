
# =====================================================================
# DISABLE (remove) all shares for DR - with full backup for restore.
# Run as Administrator. Requires Windows Server 2012+ (SMB cmdlets).
#
# This does two things:
#   1. Exports EVERY non-admin share (name, path, description, ACL)
#      to a timestamped backup file.
#   2. Removes those shares from the server.
#
# To bring the shares back, run Windows_Shares_Enable.ps1 and point it
# at the backup file this script creates.
# =====================================================================

$ErrorActionPreference = "Stop"

# Where to keep the backup. Keep this folder SAFE - it's your only way back.
$backupDir  = "C:\ShareBackup"
$stamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = Join-Path $backupDir "Shares_Backup_$stamp.json"

if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

# Only user shares - never touch admin/special shares (C$, ADMIN$, IPC$...)
$shares = Get-SmbShare | Where-Object { -not $_.Special }

Write-Host "Found $($shares.Count) user shares to back up and remove."

# ---- 1. BACK UP ----
$backup = foreach ($share in $shares) {
    $acls = Get-SmbShareAccess -Name $share.Name | ForEach-Object {
        [PSCustomObject]@{
            AccountName        = $_.AccountName
            AccessControlType  = "$($_.AccessControlType)"   # Allow / Deny
            AccessRight        = "$($_.AccessRight)"          # Full / Change / Read
        }
    }
    [PSCustomObject]@{
        Name           = $share.Name
        Path           = $share.Path
        Description    = $share.Description
        FolderEnumMode = "$($share.FolderEnumerationMode)"
        CachingMode    = "$($share.CachingMode)"
        Access         = $acls
    }
}

$backup | ConvertTo-Json -Depth 5 | Out-File -FilePath $backupFile -Encoding UTF8
Write-Host "Backup written to: $backupFile"

# ---- 2. REMOVE ----
# Safety gate: you must type YES to actually remove the shares.
$confirm = Read-Host "Backup complete. Type YES to REMOVE all $($shares.Count) shares now"
if ($confirm -ne "YES") {
    Write-Host "Aborted. No shares were removed. Backup is kept at $backupFile"
    return
}

$removed = 0
foreach ($share in $shares) {
    try {
        Remove-SmbShare -Name $share.Name -Force
        $removed++
    }
    catch {
        Write-Warning "Failed to remove share '$($share.Name)': $_"
    }
}

Write-Host "`nRemoved $removed of $($shares.Count) shares."
Write-Host "Restore with: Windows_Shares_Enable.ps1 -BackupFile `"$backupFile`""
