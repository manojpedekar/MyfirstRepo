#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads and installs the .NET 8 Hosting Bundle.

.DESCRIPTION
    This script downloads the .NET 8 Windows Hosting Bundle from Microsoft
    and runs the installer. The hosting bundle includes the ASP.NET Core
    Runtime and the IIS Module required to run ASP.NET Core applications
    behind IIS.

.PARAMETER Version
    The .NET 8 version to install. Default: 8.0.11 (latest LTS at time of writing).
    Check https://dotnet.microsoft.com/download/dotnet/8.0 for latest version.

.PARAMETER DownloadPath
    Where to save the installer. Default: Current directory.

.PARAMETER Silent
    Run the installer silently without user interaction.

.PARAMETER NoRestart
    Prevent automatic restart after installation.

.EXAMPLE
    .\Install-DotNetHostingBundle.ps1

.EXAMPLE
    .\Install-DotNetHostingBundle.ps1 -Silent -NoRestart

.EXAMPLE
    .\Install-DotNetHostingBundle.ps1 -Version "8.0.11"
#>

[CmdletBinding()]
param(
    [string]$Version = "8.0.11",
    [string]$DownloadPath = ".",
    [switch]$Silent,
    [switch]$NoRestart
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    switch ($Level) {
        "INFO"    { Write-Host "[$timestamp] $Message" -ForegroundColor White }
        "SUCCESS" { Write-Host "[$timestamp] $Message" -ForegroundColor Green }
        "WARNING" { Write-Host "[$timestamp] $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "[$timestamp] $Message" -ForegroundColor Red }
    }
}

function Get-DotNetHostingBundleUrl {
    param([string]$Version)

    # Microsoft's download URL pattern for hosting bundle
    # The actual URL requires looking up the redirect, so we use the dotnet-install approach
    # or the known CDN pattern

    # Try to get the latest download link from the releases page
    $releasesUrl = "https://dotnetcli.azureedge.net/dotnet/aspnetcore/Runtime/$Version/dotnet-hosting-$Version-win.exe"

    return $releasesUrl
}

function Test-DotNet8Installed {
    $dotnetPath = "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\8.*"
    return Test-Path $dotnetPath
}

function Get-InstalledDotNetVersions {
    $aspnetPath = "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App"
    if (Test-Path $aspnetPath) {
        Get-ChildItem $aspnetPath -Directory | ForEach-Object { $_.Name }
    }
}

# Main execution
try {
    Write-Log "=========================================="
    Write-Log ".NET 8 Hosting Bundle Installer"
    Write-Log "=========================================="

    # Check if already installed
    if (Test-DotNet8Installed) {
        $versions = Get-InstalledDotNetVersions | Where-Object { $_ -like "8.*" }
        Write-Log "ASP.NET Core 8.x is already installed. Found versions:" "WARNING"
        $versions | ForEach-Object { Write-Log "  - $_" "INFO" }

        $response = Read-Host "Do you want to continue with installation anyway? (y/N)"
        if ($response -notmatch '^[Yy]') {
            Write-Log "Installation cancelled." "INFO"
            exit 0
        }
    }

    # Get download URL
    $downloadUrl = Get-DotNetHostingBundleUrl -Version $Version
    $installerName = "dotnet-hosting-$Version-win.exe"
    $installerPath = Join-Path $DownloadPath $installerName

    Write-Log "Version: $Version"
    Write-Log "Download URL: $downloadUrl"
    Write-Log "Installer path: $installerPath"
    Write-Log ""

    # Download the installer
    Write-Log "Downloading .NET 8 Hosting Bundle..."

    try {
        # Use TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($downloadUrl, $installerPath)

        Write-Log "Download complete" "SUCCESS"
    }
    catch {
        Write-Log "Failed to download from primary URL. Trying alternative..." "WARNING"

        # Alternative: Use the VS download URL pattern
        $altUrl = "https://download.visualstudio.microsoft.com/download/pr/hosting-bundle/dotnet-hosting-$Version-win.exe"

        try {
            $webClient.DownloadFile($altUrl, $installerPath)
            Write-Log "Download complete (alternative URL)" "SUCCESS"
        }
        catch {
            Write-Log "Download failed. Please download manually from:" "ERROR"
            Write-Log "https://dotnet.microsoft.com/download/dotnet/8.0" "ERROR"
            Write-Log ""
            Write-Log "Look for 'Hosting Bundle' under ASP.NET Core Runtime section." "INFO"
            exit 1
        }
    }

    # Verify download
    if (-not (Test-Path $installerPath)) {
        Write-Log "Installer file not found after download." "ERROR"
        exit 1
    }

    $fileSize = (Get-Item $installerPath).Length / 1MB
    Write-Log "Downloaded file size: $([math]::Round($fileSize, 2)) MB"

    if ($fileSize -lt 50) {
        Write-Log "Downloaded file seems too small. It may be an error page." "WARNING"
        Write-Log "Please verify the file or download manually from:" "WARNING"
        Write-Log "https://dotnet.microsoft.com/download/dotnet/8.0" "INFO"
    }

    # Build installer arguments
    $installerArgs = @()

    if ($Silent) {
        $installerArgs += "/quiet"
        $installerArgs += "/norestart"
    }

    if ($NoRestart) {
        if ($installerArgs -notcontains "/norestart") {
            $installerArgs += "/norestart"
        }
    }

    # Run the installer
    Write-Log ""
    Write-Log "Starting installation..."

    if ($Silent) {
        Write-Log "Running in silent mode..."
        $process = Start-Process -FilePath $installerPath -ArgumentList $installerArgs -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Log "Installation completed successfully!" "SUCCESS"
        }
        elseif ($process.ExitCode -eq 3010) {
            Write-Log "Installation completed. A restart is required." "WARNING"
        }
        else {
            Write-Log "Installation finished with exit code: $($process.ExitCode)" "WARNING"
        }
    }
    else {
        Write-Log "Launching installer UI..."
        Start-Process -FilePath $installerPath -ArgumentList $installerArgs
        Write-Log "Installer launched. Please follow the on-screen instructions." "INFO"
    }

    Write-Log ""
    Write-Log "=========================================="
    Write-Log "Next Steps:"
    Write-Log "=========================================="
    Write-Log "1. If prompted, restart the server"
    Write-Log "2. Run iisreset after installation"
    Write-Log "3. Continue with Install-CLAWS.ps1"
    Write-Log ""

    exit 0
}
catch {
    Write-Log "Error: $_" "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}
