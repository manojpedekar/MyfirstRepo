#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Updates CLAWS to a new version.

.DESCRIPTION
    This script performs an in-place update of the CLAWS web application.
    It backs up the current installation, deploys new files, and restarts the site.

.PARAMETER SourcePath
    Path to new version files.

.PARAMETER BackupPath
    Where to store backup. Default: C:\Backups\CLAWS

.PARAMETER SiteName
    IIS site name. Default: CLAWS

.PARAMETER SkipBackup
    Skip backup (not recommended).

.PARAMETER Force
    Skip confirmation prompts.

.PARAMETER Rollback
    Restore previous version from backup.

.PARAMETER WhatIf
    Show what would be done without making changes.

.EXAMPLE
    .\Update-CLAWS.ps1 -SourcePath .\publish

.EXAMPLE
    .\Update-CLAWS.ps1 -Rollback
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SourcePath = ".\publish",
    [string]$BackupPath = "C:\Backups\CLAWS",
    [string]$SiteName = "CLAWS",
    [switch]$SkipBackup,
    [switch]$Force,
    [switch]$Rollback
)

$ErrorActionPreference = "Stop"
$LogFile = "CLAWS-Update-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logMessage

    switch ($Level) {
        "INFO"    { Write-Host $Message -ForegroundColor White }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
        "WARNING" { Write-Host $Message -ForegroundColor Yellow }
        "ERROR"   { Write-Host $Message -ForegroundColor Red }
    }
}

function Get-SitePhysicalPath {
    param([string]$SiteName)
    Import-Module WebAdministration
    return (Get-Website -Name $SiteName).PhysicalPath
}

function Stop-SiteAndPool {
    param([string]$SiteName)

    Import-Module WebAdministration

    if ($PSCmdlet.ShouldProcess($SiteName, "Stop website and app pool")) {
        Write-Log "Stopping website: $SiteName"

        $site = Get-Website -Name $SiteName
        if ($site.State -eq "Started") {
            Stop-Website -Name $SiteName
        }

        $poolName = $site.ApplicationPool
        $pool = Get-Item "IIS:\AppPools\$poolName"
        if ($pool.State -eq "Started") {
            Stop-WebAppPool -Name $poolName
        }

        # Wait for processes to stop
        Start-Sleep -Seconds 5

        Write-Log "Website and app pool stopped" "SUCCESS"
    }
}

function Start-SiteAndPool {
    param([string]$SiteName)

    Import-Module WebAdministration

    if ($PSCmdlet.ShouldProcess($SiteName, "Start website and app pool")) {
        Write-Log "Starting website: $SiteName"

        $site = Get-Website -Name $SiteName
        $poolName = $site.ApplicationPool

        Start-WebAppPool -Name $poolName
        Start-Website -Name $SiteName

        Write-Log "Website and app pool started" "SUCCESS"
    }
}

function Backup-Installation {
    param(
        [string]$InstallPath,
        [string]$BackupPath
    )

    $backupFolder = Join-Path $BackupPath (Get-Date -Format "yyyyMMdd-HHmmss")

    if ($PSCmdlet.ShouldProcess($InstallPath, "Backup to $backupFolder")) {
        Write-Log "Creating backup at: $backupFolder"

        if (-not (Test-Path $BackupPath)) {
            New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        }

        # Copy all files except logs and import data
        $excludeDirs = @("Logs", "ImportData")
        New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null

        Get-ChildItem $InstallPath -Exclude $excludeDirs | ForEach-Object {
            Copy-Item $_.FullName -Destination $backupFolder -Recurse -Force
        }

        # Backup appsettings.json specifically
        $appSettings = Join-Path $InstallPath "appsettings.json"
        if (Test-Path $appSettings) {
            Copy-Item $appSettings -Destination (Join-Path $backupFolder "appsettings.json.backup")
        }

        Write-Log "Backup created successfully" "SUCCESS"

        # Clean up old backups (keep last 3)
        $allBackups = Get-ChildItem $BackupPath -Directory | Sort-Object LastWriteTime -Descending
        if ($allBackups.Count -gt 3) {
            $toDelete = $allBackups | Select-Object -Skip 3
            foreach ($old in $toDelete) {
                Write-Log "Removing old backup: $($old.Name)"
                Remove-Item $old.FullName -Recurse -Force
            }
        }

        return $backupFolder
    }

    return $null
}

function Deploy-NewFiles {
    param(
        [string]$SourcePath,
        [string]$InstallPath
    )

    if ($PSCmdlet.ShouldProcess($InstallPath, "Deploy new files from $SourcePath")) {
        Write-Log "Deploying new files..."

        # Preserve appsettings.json
        $appSettingsPath = Join-Path $InstallPath "appsettings.json"
        $tempAppSettings = $null
        if (Test-Path $appSettingsPath) {
            $tempAppSettings = Get-Content $appSettingsPath -Raw
        }

        # Copy new files (exclude certain files that should be preserved)
        $preserveFiles = @("appsettings.json", "appsettings.Development.json", "web.config")

        Get-ChildItem $SourcePath -File | Where-Object { $_.Name -notin $preserveFiles } | ForEach-Object {
            Copy-Item $_.FullName -Destination $InstallPath -Force
        }

        Get-ChildItem $SourcePath -Directory | ForEach-Object {
            Copy-Item $_.FullName -Destination $InstallPath -Recurse -Force
        }

        # Restore appsettings.json if it was preserved
        if ($tempAppSettings) {
            Set-Content -Path $appSettingsPath -Value $tempAppSettings -Force
            Write-Log "Preserved existing appsettings.json"
        }

        Write-Log "Files deployed successfully" "SUCCESS"
    }
}

function Invoke-Rollback {
    param(
        [string]$BackupPath,
        [string]$InstallPath
    )

    $latestBackup = Get-ChildItem $BackupPath -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $latestBackup) {
        Write-Log "No backup found to rollback from" "ERROR"
        return $false
    }

    if ($PSCmdlet.ShouldProcess($latestBackup.FullName, "Rollback from backup")) {
        Write-Log "Rolling back from: $($latestBackup.FullName)"

        # Stop the site
        Stop-SiteAndPool -SiteName $SiteName

        # Restore files (preserve logs and import data)
        $excludeDirs = @("Logs", "ImportData")

        Get-ChildItem $InstallPath -Exclude $excludeDirs | ForEach-Object {
            if ($_.PSIsContainer) {
                Remove-Item $_.FullName -Recurse -Force
            } else {
                Remove-Item $_.FullName -Force
            }
        }

        Get-ChildItem $latestBackup.FullName | ForEach-Object {
            Copy-Item $_.FullName -Destination $InstallPath -Recurse -Force
        }

        # Start the site
        Start-SiteAndPool -SiteName $SiteName

        Write-Log "Rollback completed successfully" "SUCCESS"
        return $true
    }

    return $false
}

function Test-SiteHealth {
    param([string]$SiteName)

    Write-Log "Testing site health..."

    try {
        # Give the site a moment to start
        Start-Sleep -Seconds 10

        $site = Get-Website -Name $SiteName
        $binding = $site.Bindings.Collection | Select-Object -First 1

        $protocol = if ($binding.protocol -eq "https") { "https" } else { "http" }
        $port = $binding.bindingInformation.Split(":")[-1]
        $url = "$($protocol)://localhost:$port/api/v1/health"

        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -SkipCertificateCheck -TimeoutSec 30
        if ($response.StatusCode -eq 200) {
            Write-Log "Health check passed" "SUCCESS"
            return $true
        }
    }
    catch {
        Write-Log "Health check failed: $_" "WARNING"
    }

    return $false
}

# Main execution
try {
    Write-Log "=========================================="
    Write-Log "CLAWS Update"
    Write-Log "=========================================="

    Import-Module WebAdministration

    # Verify site exists
    $site = Get-Website -Name $SiteName
    if (-not $site) {
        Write-Log "Website '$SiteName' not found" "ERROR"
        exit 1
    }

    $installPath = $site.PhysicalPath
    Write-Log "Installation path: $installPath"

    if ($Rollback) {
        if (Invoke-Rollback -BackupPath $BackupPath -InstallPath $installPath) {
            Write-Log "Rollback completed successfully" "SUCCESS"
            exit 0
        } else {
            exit 1
        }
    }

    # Verify source exists
    if (-not (Test-Path $SourcePath)) {
        Write-Log "Source path not found: $SourcePath" "ERROR"
        exit 1
    }

    # Confirm update
    if (-not $Force) {
        $confirm = Read-Host "Update CLAWS at $installPath? (y/n)"
        if ($confirm -ne "y") {
            Write-Log "Update cancelled by user"
            exit 0
        }
    }

    # Create backup
    $backupFolder = $null
    if (-not $SkipBackup) {
        $backupFolder = Backup-Installation -InstallPath $installPath -BackupPath $BackupPath
    }
    else {
        Write-Log "Skipping backup (not recommended)" "WARNING"
    }

    # Stop the site
    Stop-SiteAndPool -SiteName $SiteName

    # Deploy new files
    Deploy-NewFiles -SourcePath $SourcePath -InstallPath $installPath

    # Start the site
    Start-SiteAndPool -SiteName $SiteName

    # Health check
    $healthy = Test-SiteHealth -SiteName $SiteName
    if (-not $healthy) {
        Write-Log "Health check failed. Consider rolling back." "WARNING"
        if ($backupFolder) {
            Write-Log "To rollback, run: .\Update-CLAWS.ps1 -Rollback"
        }
    }

    Write-Log "=========================================="
    Write-Log "Update Complete!" "SUCCESS"
    Write-Log "=========================================="
    Write-Log ""
    Write-Log "Log file: $LogFile"

    exit 0
}
catch {
    Write-Log "Update failed: $_" "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"

    # Attempt to start site if it's stopped
    try {
        Start-SiteAndPool -SiteName $SiteName
    } catch {}

    exit 1
}
