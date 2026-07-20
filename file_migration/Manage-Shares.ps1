<#
=====================================================================
 Manage-Shares.ps1 - one tool for share/folder migration & DR tasks.
 Run as Administrator for the share actions. Windows Server 2012+.

 ACTIONS
   FolderSizes    One-level folder sizes under -Path (name, path, size).
   Permissions    Export share-level ACLs for every share.
   Disable        Back up all shares to JSON, then remove them (DR).
   Enable         Restore shares from a backup JSON.

 EXAMPLES
   .\Manage-Shares.ps1 -Action FolderSizes -Path "G:\Group_Windt132k\Shared"
   .\Manage-Shares.ps1 -Action Permissions
   .\Manage-Shares.ps1 -Action Disable
   .\Manage-Shares.ps1 -Action Enable -BackupFile "C:\ShareBackup\Shares_Backup_20260720_101500.json"

 TARGET SPECIFIC SHARES (Permissions / Disable / Enable)
   Use -ShareName to work on only certain shares instead of all of them.
   Accepts a comma-separated list and wildcards (*).
   .\Manage-Shares.ps1 -Action Permissions -ShareName Finance,HR
   .\Manage-Shares.ps1 -Action Disable     -ShareName "Proj_*"
   .\Manage-Shares.ps1 -Action Enable      -ShareName Finance -BackupFile "C:\ShareBackup\Shares_Backup_20260720_101500.json"
=====================================================================
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('FolderSizes','Permissions','Disable','Enable')]
    [string]$Action,

    # FolderSizes
    [string]$Path,

    # Disable / Enable
    [string]$BackupDir  = "C:\ShareBackup",
    [string]$BackupFile,
    [switch]$IncludeAdminShares,   # include C$, ADMIN$, IPC$ ... (default: excluded)

    # Target specific shares (Permissions / Disable / Enable). List + wildcards ok.
    # Omit to work on ALL shares.
    [string[]]$ShareName,

    # Common
    [string]$OutCsv               # optional CSV output path for FolderSizes/Permissions
)

$ErrorActionPreference = "Stop"

# --------------------------------------------------------------------
# Shared helpers
# --------------------------------------------------------------------
function Test-NameMatch {
    # True if $name matches any of the -ShareName patterns (wildcards ok),
    # or if no patterns were supplied (i.e. work on all).
    param([string]$Name, [string[]]$Patterns)
    if (-not $Patterns) { return $true }
    foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }
    return $false
}

function Get-UserShares {
    param([switch]$IncludeAdmin, [string[]]$NameFilter)
    $s = Get-SmbShare
    if (-not $IncludeAdmin) { $s = $s | Where-Object { -not $_.Special } }
    if ($NameFilter)        { $s = $s | Where-Object { Test-NameMatch -Name $_.Name -Patterns $NameFilter } }
    $s
}

function Save-Report {
    param($Report, [string]$DefaultName, [string]$OutPath)
    $Report | Format-Table -AutoSize | Out-Host
    $target = if ($OutPath) { $OutPath } else { Join-Path (Get-Location) $DefaultName }
    $Report | Export-Csv -Path $target -NoTypeInformation
    Write-Host "`nSaved $($Report.Count) rows to $target"
}

# --------------------------------------------------------------------
# Actions
# --------------------------------------------------------------------
function Invoke-FolderSizes {
    if (-not $Path) { throw "FolderSizes requires -Path <directory>." }

    $report = Get-ChildItem -Path $Path -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $totalSize = (Get-ChildItem $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                      Measure-Object -Property Length -Sum).Sum
        [PSCustomObject]@{
            FolderName = $_.Name
            FolderPath = $_.FullName
            SizeGB     = "{0:N2}" -f ($totalSize / 1GB)
        }
    }
    Save-Report -Report $report -DefaultName "ShareFolder_Sizes.csv" -OutPath $OutCsv
}

function Invoke-Permissions {
    $shares = Get-UserShares -IncludeAdmin:$IncludeAdminShares -NameFilter $ShareName
    if (-not $shares) { Write-Warning "No shares matched the -ShareName filter."; return }
    $report = foreach ($share in $shares) {
        Get-SmbShareAccess -Name $share.Name -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                ShareName   = $share.Name
                SharePath   = $share.Path
                Description = $share.Description
                Account     = $_.AccountName
                AccessType  = "$($_.AccessControlType)"
                AccessRight = "$($_.AccessRight)"
            }
        }
    }
    Save-Report -Report $report -DefaultName "Share_Permissions.csv" -OutPath $OutCsv
}

function Invoke-Disable {
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
    $stamp      = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $BackupDir "Shares_Backup_$stamp.json"

    $shares = Get-UserShares -IncludeAdmin:$IncludeAdminShares -NameFilter $ShareName
    if (-not $shares) { Write-Warning "No shares matched the -ShareName filter."; return }
    Write-Host "Found $($shares.Count) shares to back up and remove."
    if ($ShareName) { Write-Host "(Filtered to: $($ShareName -join ', '))" }

    $backup = foreach ($share in $shares) {
        $acls = Get-SmbShareAccess -Name $share.Name | ForEach-Object {
            [PSCustomObject]@{
                AccountName       = $_.AccountName
                AccessControlType = "$($_.AccessControlType)"
                AccessRight       = "$($_.AccessRight)"
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
    $backup | ConvertTo-Json -Depth 5 | Out-File -FilePath $backupPath -Encoding UTF8
    Write-Host "Backup written to: $backupPath"

    $confirm = Read-Host "Backup complete. Type YES to REMOVE all $($shares.Count) shares now"
    if ($confirm -ne "YES") {
        Write-Host "Aborted. No shares removed. Backup kept at $backupPath"
        return
    }

    $removed = 0
    foreach ($share in $shares) {
        try   { Remove-SmbShare -Name $share.Name -Force; $removed++ }
        catch { Write-Warning "Failed to remove '$($share.Name)': $_" }
    }
    Write-Host "`nRemoved $removed of $($shares.Count) shares."
    Write-Host "Restore with: .\Manage-Shares.ps1 -Action Enable -BackupFile `"$backupPath`""
}

function Invoke-Enable {
    $file = $BackupFile
    if (-not $file) {
        $file = Get-ChildItem -Path $BackupDir -Filter "Shares_Backup_*.json" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $file -or -not (Test-Path $file)) { throw "Backup file not found. Specify -BackupFile." }

    Write-Host "Restoring shares from: $file"
    $backup = Get-Content -Path $file -Raw | ConvertFrom-Json

    if ($ShareName) {
        $backup = $backup | Where-Object { Test-NameMatch -Name $_.Name -Patterns $ShareName }
        if (-not $backup) { Write-Warning "No shares in the backup matched the -ShareName filter."; return }
        Write-Host "(Filtered to: $($ShareName -join ', '))"
    }

    $created = 0; $skipped = 0
    foreach ($share in $backup) {
        if (Get-SmbShare -Name $share.Name -ErrorAction SilentlyContinue) {
            Write-Warning "Share '$($share.Name)' already exists - skipping."; $skipped++; continue
        }
        if (-not (Test-Path $share.Path)) {
            Write-Warning "Path '$($share.Path)' for '$($share.Name)' missing - skipping."; $skipped++; continue
        }
        try {
            New-SmbShare -Name $share.Name -Path $share.Path `
                -Description $share.Description `
                -FolderEnumerationMode $share.FolderEnumMode `
                -CachingMode $share.CachingMode `
                -FullAccess "Administrators" | Out-Null
            Revoke-SmbShareAccess -Name $share.Name -AccountName "Administrators" -Force -ErrorAction SilentlyContinue | Out-Null

            foreach ($ace in $share.Access) {
                if ($ace.AccessControlType -eq "Allow") {
                    Grant-SmbShareAccess -Name $share.Name -AccountName $ace.AccountName `
                        -AccessRight $ace.AccessRight -Force | Out-Null
                } else {
                    Block-SmbShareAccess -Name $share.Name -AccountName $ace.AccountName -Force | Out-Null
                }
            }
            $created++
        }
        catch { Write-Warning "Failed to restore '$($share.Name)': $_" }
    }
    Write-Host "`nRestored $created shares. Skipped $skipped."
}

# --------------------------------------------------------------------
# Dispatch
# --------------------------------------------------------------------
switch ($Action) {
    'FolderSizes' { Invoke-FolderSizes }
    'Permissions' { Invoke-Permissions }
    'Disable'     { Invoke-Disable }
    'Enable'      { Invoke-Enable }
}
