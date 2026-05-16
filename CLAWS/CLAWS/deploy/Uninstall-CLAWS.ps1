#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls CLAWS.

.DESCRIPTION
    This script removes the CLAWS web application from IIS
    and optionally removes application files and database objects.

.PARAMETER SiteName
    IIS site name. Default: CLAWS

.PARAMETER RemoveFiles
    Remove application files.

.PARAMETER RemoveData
    Remove import data folders.

.PARAMETER RemoveDatabase
    Remove database tables (requires confirmation).

.PARAMETER Force
    Skip confirmation prompts.

.PARAMETER WhatIf
    Show what would be done without making changes.

.EXAMPLE
    .\Uninstall-CLAWS.ps1 -RemoveFiles

.EXAMPLE
    .\Uninstall-CLAWS.ps1 -RemoveFiles -RemoveData -Force
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SiteName = "CLAWS",
    [switch]$RemoveFiles,
    [switch]$RemoveData,
    [switch]$RemoveDatabase,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$LogFile = "CLAWS-Uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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

function Remove-IISSite {
    param([string]$SiteName)

    Import-Module WebAdministration

    if (-not (Test-Path "IIS:\Sites\$SiteName")) {
        Write-Log "Website '$SiteName' not found" "WARNING"
        return $null
    }

    $site = Get-Website -Name $SiteName
    $installPath = $site.PhysicalPath
    $appPoolName = $site.ApplicationPool

    if ($PSCmdlet.ShouldProcess($SiteName, "Remove website")) {
        Write-Log "Stopping and removing website: $SiteName"

        # Stop site and pool
        if ($site.State -eq "Started") {
            Stop-Website -Name $SiteName
        }

        $pool = Get-Item "IIS:\AppPools\$appPoolName"
        if ($pool.State -eq "Started") {
            Stop-WebAppPool -Name $appPoolName
        }

        # Wait for processes to stop
        Start-Sleep -Seconds 5

        # Remove site
        Remove-Website -Name $SiteName
        Write-Log "Website removed" "SUCCESS"

        # Remove app pool if not used by other sites
        $otherSites = Get-Website | Where-Object { $_.ApplicationPool -eq $appPoolName -and $_.Name -ne $SiteName }
        if (-not $otherSites) {
            Remove-WebAppPool -Name $appPoolName
            Write-Log "Application pool removed" "SUCCESS"
        }
        else {
            Write-Log "Application pool '$appPoolName' is used by other sites, not removed" "WARNING"
        }
    }

    return $installPath
}

function Remove-ApplicationFiles {
    param([string]$InstallPath, [switch]$IncludeData)

    if (-not (Test-Path $InstallPath)) {
        Write-Log "Installation path not found: $InstallPath" "WARNING"
        return
    }

    if ($PSCmdlet.ShouldProcess($InstallPath, "Remove application files")) {
        Write-Log "Removing application files from: $InstallPath"

        if ($IncludeData) {
            # Remove everything
            Remove-Item $InstallPath -Recurse -Force
            Write-Log "All files removed including data" "SUCCESS"
        }
        else {
            # Keep ImportData folder
            Get-ChildItem $InstallPath -Exclude "ImportData" | ForEach-Object {
                Remove-Item $_.FullName -Recurse -Force
            }
            Write-Log "Application files removed (ImportData preserved)" "SUCCESS"
        }
    }
}

function Remove-DatabaseObjects {
    param([string]$SqlServer, [string]$Database)

    # This would need the connection string from appsettings.json
    Write-Log "Database removal not implemented in this version" "WARNING"
    Write-Log "Please manually remove the [app] schema and tables from database: $Database" "WARNING"
}

# Main execution
try {
    Write-Log "=========================================="
    Write-Log "CLAWS Uninstallation"
    Write-Log "=========================================="

    Import-Module WebAdministration

    # Confirm uninstall
    if (-not $Force) {
        $confirm = Read-Host "Are you sure you want to uninstall CLAWS? (y/n)"
        if ($confirm -ne "y") {
            Write-Log "Uninstall cancelled by user"
            exit 0
        }
    }

    # Get installation path before removing site
    $site = Get-Website -Name $SiteName
    $installPath = if ($site) { $site.PhysicalPath } else { $null }

    # Remove IIS site and app pool
    $path = Remove-IISSite -SiteName $SiteName
    if ($path) { $installPath = $path }

    # Remove application files
    if ($RemoveFiles -and $installPath) {
        Remove-ApplicationFiles -InstallPath $installPath -IncludeData:$RemoveData
    }

    # Remove database objects
    if ($RemoveDatabase) {
        if (-not $Force) {
            $confirm = Read-Host "This will permanently delete database tables. Are you sure? (yes/no)"
            if ($confirm -ne "yes") {
                Write-Log "Database removal cancelled"
            }
            else {
                Remove-DatabaseObjects
            }
        }
        else {
            Remove-DatabaseObjects
        }
    }

    Write-Log "=========================================="
    Write-Log "Uninstallation Complete!" "SUCCESS"
    Write-Log "=========================================="

    if (-not $RemoveData -and $installPath) {
        Write-Log ""
        Write-Log "Note: Import data was preserved at: $installPath\ImportData"
    }

    Write-Log ""
    Write-Log "Log file: $LogFile"

    exit 0
}
catch {
    Write-Log "Uninstallation failed: $_" "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}
