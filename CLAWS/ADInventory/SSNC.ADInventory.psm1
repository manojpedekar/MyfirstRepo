#Requires -Version 5.1

<#
.SYNOPSIS
    SSNC Active Directory Inventory Module

.DESCRIPTION
    PowerShell module for collecting Active Directory inventory and exporting to SQLite,
    with SQL Server import capability.

.NOTES
    Module Name: SSNC.ADInventory
    Author: SSNC
    Version: 1.1.0
    Requires: PowerShell 5.1+, PSSQLite module
#>

# Stop on errors
$ErrorActionPreference = 'Stop'

# Get module root path
$ModuleRoot = $PSScriptRoot

# Get module version from manifest (available module-wide via $Script:ModuleVersion)
$Script:ModuleVersion = try {
    $manifestPath = Join-Path $ModuleRoot 'SSNC.ADInventory.psd1'
    if (Test-Path $manifestPath) {
        $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        if ($manifest) {
            $manifest.Version.ToString()
        } else {
            '1.0.0'  # Default fallback
        }
    } else {
        '1.0.0'  # Default fallback
    }
} catch {
    '1.0.0'  # Default fallback on any error
}

#region PSSQLite Module Loading with 4-Step Fallback Chain
# CRITICAL: PSSQLite MUST be loaded BEFORE any classes that use [SQLiteConnection]
# PowerShell classes are compiled at parse time, so the type must exist first

<#
.SYNOPSIS
    Tests if the current user can install PowerShell modules.

.DESCRIPTION
    Checks multiple conditions to determine if module installation is possible:
    - PowerShellGet module availability
    - Write access to user module directory
    - PSGallery repository accessibility

.OUTPUTS
    [bool] True if module installation is possible, False otherwise.
#>
function Test-ModuleInstallCapability {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Write-Verbose "  Testing module installation capability..."

    # Check if PowerShellGet is available
    $powerShellGet = Get-Module -ListAvailable -Name 'PowerShellGet' | Select-Object -First 1
    if (-not $powerShellGet) {
        Write-Verbose "    PowerShellGet module not available"
        return $false
    }

    # Check if we can write to user module directory
    $userModulePath = $env:PSModulePath -split [IO.Path]::PathSeparator |
        Where-Object { $_ -like "*$env:USERPROFILE*" -or $_ -like "*$env:HOME*" } |
        Select-Object -First 1

    if (-not $userModulePath) {
        # Try the default user module paths
        if ($IsWindows -or (-not (Test-Path variable:IsWindows))) {
            $userModulePath = Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules'
            if (-not (Test-Path $userModulePath)) {
                $userModulePath = Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules'
            }
        }
        else {
            $userModulePath = Join-Path $env:HOME '.local/share/powershell/Modules'
        }
    }

    if ($userModulePath) {
        # Create test directory if parent exists
        $parentPath = Split-Path $userModulePath -Parent
        if (Test-Path $parentPath) {
            try {
                # Try to create a test file to verify write access
                $testPath = if (Test-Path $userModulePath) {
                    Join-Path $userModulePath '.pssqlite_install_test'
                }
                else {
                    # Try to create the module directory
                    New-Item -Path $userModulePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    Join-Path $userModulePath '.pssqlite_install_test'
                }

                [System.IO.File]::WriteAllText($testPath, 'test')
                Remove-Item -Path $testPath -Force -ErrorAction SilentlyContinue
                Write-Verbose "    User has write access to module directory: $userModulePath"
                return $true
            }
            catch {
                Write-Verbose "    No write access to user module directory: $($_.Exception.Message)"
                return $false
            }
        }
    }

    Write-Verbose "    Could not determine user module path"
    return $false
}

<#
.SYNOPSIS
    Loads the PSSQLite module with 4-step fallback chain.

.DESCRIPTION
    Attempts to load PSSQLite in the following order:
    Step 1: Already Loaded - Use existing module (fastest)
    Step 2: Installed Module - Import from system (standard)
    Step 3: Auto-Install - Install from PSGallery if capable
    Step 4: Bundled Fallback - Load from ExternalModules/PSSQLite/1.1.0

.NOTES
    This ensures the script can run even in restricted environments where
    module installation is not permitted.
#>
function Initialize-PSSQLiteModule {
    [CmdletBinding()]
    param()

    $moduleName = 'PSSQLite'
    $localModulePath = Join-Path $ModuleRoot 'ExternalModules\PSSQLite\1.1.0\PSSQLite.psd1'

    Write-Verbose "Initializing PSSQLite module (4-step fallback chain)..."

    # Step 1: Check if module is already loaded (fastest)
    if (Get-Module -Name $moduleName) {
        Write-Verbose "  Step 1: PSSQLite module is already loaded"
        return $true
    }

    # Step 2: Check if module is available in installed modules (standard)
    $installedModule = Get-Module -ListAvailable -Name $moduleName | Select-Object -First 1
    if ($installedModule) {
        Write-Verbose "  Step 2: Found installed PSSQLite module at: $($installedModule.ModuleBase)"
        try {
            Import-Module -Name $moduleName -ErrorAction Stop
            Write-Verbose "  Step 2: Successfully imported installed PSSQLite module"
            return $true
        }
        catch {
            Write-Warning "  Step 2: Failed to import installed PSSQLite module: $($_.Exception.Message)"
        }
    }

    # Step 3: Check if we can install modules and attempt installation
    $canInstallModules = Test-ModuleInstallCapability
    if ($canInstallModules) {
        Write-Verbose "  Step 3: Attempting to install PSSQLite from PSGallery..."
        try {
            # Check if PSGallery is available
            $psGallery = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
            if ($psGallery) {
                Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
                Import-Module -Name $moduleName -ErrorAction Stop
                Write-Verbose "  Step 3: Successfully installed and imported PSSQLite from PSGallery"
                return $true
            }
            else {
                Write-Verbose "  Step 3: PSGallery repository not available"
            }
        }
        catch {
            Write-Warning "  Step 3: Failed to install PSSQLite from PSGallery: $($_.Exception.Message)"
        }
    }
    else {
        Write-Verbose "  Step 3: Module installation not available (restricted environment or insufficient permissions)"
    }

    # Step 4: Fall back to bundled local copy
    if (Test-Path $localModulePath) {
        Write-Verbose "  Step 4: Loading PSSQLite from bundled copy at: $localModulePath"
        try {
            Import-Module -Name $localModulePath -ErrorAction Stop
            Write-Verbose "  Step 4: Successfully imported PSSQLite from local ExternalModules folder"
            return $true
        }
        catch {
            Write-Error "  Step 4: Failed to import bundled PSSQLite module: $($_.Exception.Message)"
            return $false
        }
    }
    else {
        Write-Error "  Step 4: Bundled PSSQLite module not found at: $localModulePath"
        return $false
    }
}

# Initialize PSSQLite module FIRST (before any classes that use [SQLiteConnection])
$psSqliteLoaded = Initialize-PSSQLiteModule
if (-not $psSqliteLoaded) {
    throw "Failed to load PSSQLite module. The module is required for database operations. Please ensure either: 1) Install-Module -Name PSSQLite -Scope CurrentUser, or 2) The ExternalModules\PSSQLite folder exists in the module directory."
}

Write-Verbose "PSSQLite module loaded successfully"

#endregion

#region Load Private Functions

Write-Verbose "Loading private functions..."

# IMPORTANT: Load ALL functions BEFORE loading classes
# PowerShell classes are compiled at parse time, so all function dependencies
# (especially Write-ADInventoryLog) must exist before class compilation

# Transform functions
Get-ChildItem (Join-Path $ModuleRoot "Private\Transform\*.ps1") | ForEach-Object {
    Write-Verbose "  Loading $($_.Name)"
    . $_.FullName
}

# Utility functions (includes Write-ADInventoryLog - required by classes)
Get-ChildItem (Join-Path $ModuleRoot "Private\Utility\*.ps1") | ForEach-Object {
    Write-Verbose "  Loading $($_.Name)"
    . $_.FullName
}

# Connection functions
Get-ChildItem (Join-Path $ModuleRoot "Private\Connection\*.ps1") | ForEach-Object {
    Write-Verbose "  Loading $($_.Name)"
    . $_.FullName
}

# LDAP functions
Get-ChildItem (Join-Path $ModuleRoot "Private\LDAP\*.ps1") | ForEach-Object {
    Write-Verbose "  Loading $($_.Name)"
    . $_.FullName
}

# SQLite functions
Get-ChildItem (Join-Path $ModuleRoot "Private\SQLite\*.ps1") | ForEach-Object {
    Write-Verbose "  Loading $($_.Name)"
    . $_.FullName
}

# Sites & Services functions
$sitesAndServicesPath = Join-Path $ModuleRoot "Private\SitesAndServices\*.ps1"
if (Test-Path $sitesAndServicesPath) {
    Get-ChildItem $sitesAndServicesPath | ForEach-Object {
        Write-Verbose "  Loading $($_.Name)"
        . $_.FullName
    }
}

# Domain Health functions (SYSVOL replication, GPO health, Optional Features)
$domainHealthPath = Join-Path $ModuleRoot "Private\DomainHealth\*.ps1"
if (Test-Path $domainHealthPath) {
    Get-ChildItem $domainHealthPath | ForEach-Object {
        Write-Verbose "  Loading $($_.Name)"
        . $_.FullName
    }
}

# KMS Service Discovery functions
$kmsPath = Join-Path $ModuleRoot "Private\KMS\*.ps1"
if (Test-Path $kmsPath) {
    Get-ChildItem $kmsPath | ForEach-Object {
        Write-Verbose "  Loading $($_.Name)"
        . $_.FullName
    }
}

# ADFS Configuration functions
$adfsPath = Join-Path $ModuleRoot "Private\ADFS\*.ps1"
if (Test-Path $adfsPath) {
    Get-ChildItem $adfsPath | ForEach-Object {
        Write-Verbose "  Loading $($_.Name)"
        . $_.FullName
    }
}

# PKI (AD Certificate Services) functions
$pkiPath = Join-Path $ModuleRoot "Private\PKI\*.ps1"
if (Test-Path $pkiPath) {
    Get-ChildItem $pkiPath | ForEach-Object {
        Write-Verbose "  Loading $($_.Name)"
        . $_.FullName
    }
}

#endregion

#region Load Classes (order matters due to dependencies)

Write-Verbose "Loading ADInventory classes..."

# Load classes in dependency order AFTER PSSQLite is loaded and all functions exist
# Classes depend on:
#   - [SQLiteConnection] type from PSSQLite (must be loaded first!)
#   - Write-ADInventoryLog and other utility functions

# SQLite collection classes
. (Join-Path $ModuleRoot "Classes\ADQueryConfig.ps1")
. (Join-Path $ModuleRoot "Classes\SQLiteInventoryWriter.ps1")
. (Join-Path $ModuleRoot "Classes\ADInventorySession.ps1")

#endregion

#region Load Public Functions

Write-Verbose "Loading public functions..."

Get-ChildItem (Join-Path $ModuleRoot "Public\*.ps1") | ForEach-Object {
    Write-Verbose "  Loading $($_.Name)"
    . $_.FullName
}

#endregion

#region Export Module Members

Write-Verbose "SSNC.ADInventory module loaded successfully"

# Export public functions
# Classes are automatically available once loaded
# Private functions are not exported

Export-ModuleMember -Function @(
    'Start-ADInventoryCollection',
    'Test-ADDomainConnectivity'
)

#endregion
