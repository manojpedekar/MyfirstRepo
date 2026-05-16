#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs CLAWS on Windows Server with IIS.

.DESCRIPTION
    This script performs a new installation of the CLAWS web application.
    It verifies prerequisites, creates the IIS website and application pool,
    deploys application files, and configures folder permissions.

.PARAMETER ConfigFile
    Path to a JSON configuration file for non-interactive installation.

.PARAMETER SiteName
    IIS site name. Default: CLAWS

.PARAMETER Port
    HTTPS port. Default: 443

.PARAMETER CertThumbprint
    SSL certificate thumbprint for HTTPS binding.

.PARAMETER AppPoolIdentity
    Service account (domain\user) for app pool. Leave empty for ApplicationPoolIdentity.

.PARAMETER InstallPath
    Installation directory. Default: C:\inetpub\CLAWS

.PARAMETER SqlServer
    SQL Server instance (optional, can configure via UI later).

.PARAMETER Database
    Database name (optional, can configure via UI later).

.PARAMETER InstallRequiredFeatures
    Automatically install missing Windows features (IIS) if prerequisites check fails.

.PARAMETER WhatIf
    Show what would be done without making changes.

.EXAMPLE
    .\Install-CLAWS.ps1 -SiteName "CLAWS" -Port 443

.EXAMPLE
    .\Install-CLAWS.ps1 -ConfigFile .\config.json

.EXAMPLE
    .\Install-CLAWS.ps1 -InstallRequiredFeatures -SourcePath .\publish
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigFile,
    [string]$SiteName = "CLAWS",
    [int]$Port = 443,
    [string]$CertThumbprint,
    [string]$AppPoolIdentity,
    [string]$InstallPath = "C:\inetpub\CLAWS",
    [string]$SqlServer,
    [string]$Database,
    [string]$SourcePath = ".\publish",
    [switch]$InstallRequiredFeatures
)

$ErrorActionPreference = "Stop"
$LogFile = "CLAWS-Install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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

function Test-Prerequisites {
    param([switch]$ReturnMissing)

    Write-Log "Checking prerequisites..."

    $missing = @{
        IISFeatures = $false
        DotNetHosting = $false
        AspNetCoreModule = $false
    }

    # Check Windows Server version
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.Caption -notlike "*Windows Server*") {
        Write-Log "Warning: This script is designed for Windows Server. Current OS: $($os.Caption)" "WARNING"
    }

    # Check IIS
    $iis = Get-WindowsFeature Web-Server -ErrorAction SilentlyContinue
    if (-not $iis -or -not $iis.Installed) {
        Write-Log "IIS is not installed. Required features:" "ERROR"
        Write-Log "  - Web-Server, Web-WebServer, Web-Common-Http" "ERROR"
        Write-Log "  - Web-Security, Web-Filtering, Web-App-Dev" "ERROR"
        Write-Log "  - Web-Net-Ext45, Web-Asp-Net45, Web-ISAPI-Ext, Web-ISAPI-Filter" "ERROR"
        $missing.IISFeatures = $true
    }
    else {
        Write-Log "IIS is installed" "SUCCESS"
    }

    # Check .NET 8 Hosting Bundle
    $dotnetPath = "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\8.*"
    if (-not (Test-Path $dotnetPath)) {
        Write-Log ".NET 8 Hosting Bundle not found. Please install from: https://dotnet.microsoft.com/download/dotnet/8.0" "ERROR"
        $missing.DotNetHosting = $true
    }
    else {
        Write-Log ".NET 8 Hosting Bundle is installed" "SUCCESS"
    }

    # Check ASP.NET Core Module - use multiple detection methods
    $ancmInstalled = $false

    # Method 1: Check IIS global modules (most reliable)
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        $ancmModule = Get-WebGlobalModule -Name "AspNetCoreModuleV2" -ErrorAction SilentlyContinue
        if ($ancmModule) {
            $ancmInstalled = $true
        }
    }
    catch {
        # WebAdministration module not available, try other methods
    }

    # Method 2: Check common DLL locations
    if (-not $ancmInstalled) {
        $ancmPaths = @(
            "C:\Windows\System32\inetsrv\aspnetcorev2.dll",
            "C:\Program Files\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll",
            "C:\Program Files\IIS\Asp.Net Core Module\V2\aspnetcorev2_outofprocess.dll"
        )
        foreach ($path in $ancmPaths) {
            if (Test-Path $path) {
                $ancmInstalled = $true
                break
            }
        }
    }

    # Method 3: Check registry
    if (-not $ancmInstalled) {
        $regPath = "HKLM:\SOFTWARE\Microsoft\IIS Extensions\IIS AspNetCore Module V2"
        if (Test-Path $regPath) {
            $ancmInstalled = $true
        }
    }

    if (-not $ancmInstalled) {
        Write-Log "ASP.NET Core Module v2 not found" "ERROR"
        Write-Log "  Checked: IIS modules, common DLL paths, and registry" "ERROR"
        $missing.AspNetCoreModule = $true
    }
    else {
        Write-Log "ASP.NET Core Module v2 is installed" "SUCCESS"
    }

    if ($ReturnMissing) {
        return $missing
    }

    return (-not $missing.IISFeatures -and -not $missing.DotNetHosting -and -not $missing.AspNetCoreModule)
}

function Install-RequiredFeatures {
    Write-Log "Installing required Windows features..."

    $features = @(
        "Web-Server",
        "Web-WebServer",
        "Web-Common-Http",
        "Web-Default-Doc",
        "Web-Dir-Browsing",
        "Web-Http-Errors",
        "Web-Static-Content",
        "Web-Health",
        "Web-Http-Logging",
        "Web-Performance",
        "Web-Stat-Compression",
        "Web-Dyn-Compression",
        "Web-Security",
        "Web-Filtering",
        "Web-Windows-Auth",
        "Web-App-Dev",
        "Web-Net-Ext45",
        "Web-Asp-Net45",
        "Web-ISAPI-Ext",
        "Web-ISAPI-Filter",
        "Web-Mgmt-Tools",
        "Web-Mgmt-Console"
    )

    if ($PSCmdlet.ShouldProcess("Windows Features", "Install IIS and related features")) {
        # Build list of missing features
        $missingFeatures = @()
        foreach ($feature in $features) {
            $featureState = Get-WindowsFeature -Name $feature -ErrorAction SilentlyContinue
            if ($featureState -and -not $featureState.Installed) {
                $missingFeatures += $feature
            }
        }

        if ($missingFeatures.Count -gt 0) {
            Write-Log "Installing $($missingFeatures.Count) missing features: $($missingFeatures -join ', ')"
            Install-WindowsFeature -Name $missingFeatures -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Windows features installation complete" "SUCCESS"
        }
        else {
            Write-Log "All required Windows features are already installed" "SUCCESS"
        }

        Write-Log "NOTE: A server restart may be required for all features to work correctly" "WARNING"
    }

    return $true
}

function New-AppPool {
    param([string]$Name, [string]$Identity)

    Import-Module WebAdministration

    if (Test-Path "IIS:\AppPools\$Name") {
        Write-Log "Application pool '$Name' already exists" "WARNING"
        return
    }

    if ($PSCmdlet.ShouldProcess($Name, "Create application pool")) {
        Write-Log "Creating application pool: $Name"
        $pool = New-Item "IIS:\AppPools\$Name"
        $pool.managedRuntimeVersion = ""  # No Managed Code
        $pool.startMode = "AlwaysRunning"
        $pool.processModel.idleTimeout = [TimeSpan]::FromMinutes(0)

        if ($Identity) {
            $pool.processModel.identityType = "SpecificUser"
            $pool.processModel.userName = $Identity
            # Password would need to be provided securely
        }

        $pool | Set-Item
        Write-Log "Application pool created" "SUCCESS"
    }
}

function Install-WebsiteWithBindings {
    param(
        [string]$Name,
        [string]$PhysicalPath,
        [string]$AppPool,
        [int]$Port,
        [string]$CertThumbprint
    )

    Import-Module WebAdministration

    if (Test-Path "IIS:\Sites\$Name") {
        Write-Log "Website '$Name' already exists" "WARNING"
        return
    }

    if ($PSCmdlet.ShouldProcess($Name, "Create website")) {
        Write-Log "Creating website: $Name"

        # Create directory if needed
        if (-not (Test-Path $PhysicalPath)) {
            New-Item -ItemType Directory -Path $PhysicalPath -Force | Out-Null
        }

        # Create the site with HTTPS binding
        if ($CertThumbprint) {
            WebAdministration\New-Website -Name $Name `
                -PhysicalPath $PhysicalPath `
                -ApplicationPool $AppPool `
                -Port $Port `
                -Ssl | Out-Null

            # Bind SSL certificate
            $binding = Get-WebBinding -Name $Name -Protocol "https"
            $binding.AddSslCertificate($CertThumbprint, "My")
        }
        else {
            # Create with HTTP for now
            WebAdministration\New-Website -Name $Name `
                -PhysicalPath $PhysicalPath `
                -ApplicationPool $AppPool `
                -Port 80 | Out-Null

            Write-Log "No SSL certificate specified. Site created with HTTP binding." "WARNING"
        }

        Write-Log "Website created" "SUCCESS"
    }
}

function Set-IISRequestLimits {
    param([string]$SiteName)

    if ($PSCmdlet.ShouldProcess($SiteName, "Configure request limits")) {
        Write-Log "Configuring IIS request limits for large uploads..."

        try {
            # Set maxAllowedContentLength (3 GB in bytes)
            $maxContentLength = 3221225472
            Set-WebConfigurationProperty -pspath "IIS:\Sites\$SiteName" `
                -filter "system.webServer/security/requestFiltering/requestLimits" `
                -name "maxAllowedContentLength" `
                -value $maxContentLength

            # Set connection timeout
            Set-WebConfigurationProperty -pspath "IIS:\Sites\$SiteName" `
                -filter "system.webServer/serverRuntime" `
                -name "uploadReadAheadSize" `
                -value 0

            Write-Log "Request limits configured" "SUCCESS"
        }
        catch {
            Write-Log "Could not configure IIS request limits at site level (section may be locked)." "WARNING"
            Write-Log "The application's web.config already contains the required settings." "INFO"
            Write-Log "If uploads fail, you may need to unlock the requestFiltering section in IIS Manager." "INFO"
        }
    }
}

function Deploy-ApplicationFiles {
    param([string]$Source, [string]$Destination)

    if (-not (Test-Path $Source)) {
        Write-Log "Source path not found: $Source" "ERROR"
        return $false
    }

    if ($PSCmdlet.ShouldProcess($Destination, "Deploy application files")) {
        Write-Log "Deploying application files from $Source to $Destination"

        if (-not (Test-Path $Destination)) {
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        }

        Copy-Item -Path "$Source\*" -Destination $Destination -Recurse -Force
        Write-Log "Application files deployed" "SUCCESS"
    }

    return $true
}

function New-StorageDirectories {
    param([string]$BasePath)

    $directories = @(
        "$BasePath\ImportData\Uploads",
        "$BasePath\ImportData\Extraction",
        "$BasePath\ImportData\Completed",
        "$BasePath\ImportData\Errors",
        "$BasePath\Logs"
    )

    if ($PSCmdlet.ShouldProcess($BasePath, "Create storage directories")) {
        Write-Log "Creating storage directories..."
        foreach ($dir in $directories) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Log "Created: $dir"
            }
        }
        Write-Log "Storage directories created" "SUCCESS"
    }
}

function Set-FolderPermissions {
    param([string]$Path, [string]$Identity)

    if ($PSCmdlet.ShouldProcess($Path, "Set folder permissions for $Identity")) {
        Write-Log "Setting folder permissions for $Identity on $Path"

        $acl = Get-Acl $Path
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Identity,
            "Modify",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.AddAccessRule($rule)
        Set-Acl -Path $Path -AclObject $acl

        Write-Log "Folder permissions set" "SUCCESS"
    }
}

# Main execution
try {
    Write-Log "=========================================="
    Write-Log "CLAWS Installation"
    Write-Log "=========================================="

    # Load config file if specified
    if ($ConfigFile -and (Test-Path $ConfigFile)) {
        Write-Log "Loading configuration from: $ConfigFile"
        $config = Get-Content $ConfigFile | ConvertFrom-Json
        if ($config.SiteName) { $SiteName = $config.SiteName }
        if ($config.Port) { $Port = $config.Port }
        if ($config.CertThumbprint) { $CertThumbprint = $config.CertThumbprint }
        if ($config.AppPoolIdentity) { $AppPoolIdentity = $config.AppPoolIdentity }
        if ($config.InstallPath) { $InstallPath = $config.InstallPath }
        if ($config.SqlServer) { $SqlServer = $config.SqlServer }
        if ($config.Database) { $Database = $config.Database }
    }

    # Check prerequisites
    $missing = Test-Prerequisites -ReturnMissing
    $prereqFailed = $missing.IISFeatures -or $missing.DotNetHosting -or $missing.AspNetCoreModule

    if ($prereqFailed) {
        if ($InstallRequiredFeatures -and $missing.IISFeatures) {
            Write-Log "Installing missing Windows features..." "INFO"
            Install-RequiredFeatures

            # Re-check after installation
            $missing = Test-Prerequisites -ReturnMissing
        }

        # Check if .NET Hosting Bundle is still missing (can't auto-install)
        if ($missing.DotNetHosting -or $missing.AspNetCoreModule) {
            Write-Log "Prerequisites check failed." "ERROR"
            if ($missing.DotNetHosting) {
                Write-Log "The .NET 8 Hosting Bundle must be installed manually." "ERROR"
                Write-Log "Download from: https://dotnet.microsoft.com/download/dotnet/8.0" "ERROR"
            }
            exit 1
        }

        # Check if IIS is still missing after attempted install
        if ($missing.IISFeatures) {
            Write-Log "Prerequisites check failed. IIS features could not be installed." "ERROR"
            Write-Log "Try running with -InstallRequiredFeatures to auto-install, or install manually." "ERROR"
            exit 1
        }
    }

    # Determine app pool identity
    $poolIdentity = if ($AppPoolIdentity) { $AppPoolIdentity } else { "IIS AppPool\$SiteName" }

    # Create application pool
    New-AppPool -Name $SiteName -Identity $AppPoolIdentity

    # Deploy application files
    if (-not (Deploy-ApplicationFiles -Source $SourcePath -Destination $InstallPath)) {
        Write-Log "Failed to deploy application files" "ERROR"
        exit 1
    }

    # Create storage directories
    New-StorageDirectories -BasePath $InstallPath

    # Set folder permissions
    Set-FolderPermissions -Path $InstallPath -Identity $poolIdentity
    Set-FolderPermissions -Path "$InstallPath\ImportData" -Identity $poolIdentity
    Set-FolderPermissions -Path "$InstallPath\Logs" -Identity $poolIdentity

    # Create website
    Install-WebsiteWithBindings -Name $SiteName -PhysicalPath $InstallPath -AppPool $SiteName -Port $Port -CertThumbprint $CertThumbprint

    # Configure IIS request limits
    Set-IISRequestLimits -SiteName $SiteName

    # Start the site
    if ($PSCmdlet.ShouldProcess($SiteName, "Start website")) {
        Start-Website -Name $SiteName
        Write-Log "Website started" "SUCCESS"
    }

    Write-Log "=========================================="
    Write-Log "Installation Complete!" "SUCCESS"
    Write-Log "=========================================="
    Write-Log ""
    Write-Log "Next Steps:"
    Write-Log "1. Access the application at https://localhost:$Port"
    Write-Log "2. Configure SQL Server connection in Settings"
    Write-Log "3. Configure authorization AD groups"
    Write-Log "4. (Recommended) Move import storage to a dedicated volume"
    Write-Log ""
    Write-Log "Log file: $LogFile"

    exit 0
}
catch {
    Write-Log "Installation failed: $_" "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}
