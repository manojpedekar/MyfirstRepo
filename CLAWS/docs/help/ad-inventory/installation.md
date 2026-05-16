# Installing the AD Inventory Collector

This guide walks you through downloading and installing the SSNC.ADInventory PowerShell module.

## Prerequisites

Before installing, ensure you have:

| Requirement | Details |
|-------------|---------|
| Operating System | Windows Server 2016+ or Windows 10/11 |
| PowerShell | 5.1 (Desktop) or 7.x (Core) |
| .NET Framework | 4.7.2 or later |
| Domain Membership | Computer must be domain-joined |
| Network Access | LDAP/LDAPS connectivity to domain controllers |

The module includes a bundled copy of PSSQLite (1.1.0) with automatic fallback loading.

## Download

1. Log in to the NTFSPermsUploader web application
2. On the Home page, locate the **Downloads** section
3. Click **Download ADInventory**
4. Save the .zip file to your server

## Installation

### Extract to Local Folder

```powershell
# Create tools directory if needed
New-Item -ItemType Directory -Path "C:\Tools" -Force

# Extract the module
Expand-Archive -Path "C:\Downloads\ADInventory.zip" -DestinationPath "C:\Tools\ADInventory"

# Verify extraction
Get-ChildItem "C:\Tools\ADInventory"
```

You should see files including:
- `SSNC.ADInventory.psd1` - Module manifest
- `SSNC.ADInventory.psm1` - Module code
- `PSSQLite/` - Bundled SQLite support

### Import the Module

```powershell
Import-Module "C:\Tools\ADInventory\SSNC.ADInventory.psd1"
```

## Verify Installation

```powershell
# List exported commands
Get-Command -Module SSNC.ADInventory

# Check module version
Get-Module SSNC.ADInventory | Select-Object Name, Version
```

Expected output:
```
CommandType     Name                            Version    Source
-----------     ----                            -------    ------
Function        Start-ADInventoryCollection     1.9.1      SSNC.ADInventory
Function        Test-ADDomainConnectivity       1.9.1      SSNC.ADInventory
```

## Test Connectivity

Before running a full collection, test connectivity to your domain:

```powershell
# Test current domain on LDAPS (port 636)
Test-ADDomainConnectivity -CurrentDomain

# Test with multiple ports
Test-ADDomainConnectivity -CurrentDomain -Port @(636, 389, 3268)

# Test specific domain
Test-ADDomainConnectivity -Domains "contoso.com" -Port @(636, 389)
```

Example output:
```
Domain        : contoso.com
Status        : Success
DCsDiscovered : 4
DCsAccessible : 4
BestDC        : 10.0.1.10
Latency       : 2
Port          : 636
PortDesc      : LDAP over SSL (LDAPS)
```

## Unblocking Downloaded Files

If you receive security warnings:

```powershell
# Unblock all files in the module folder
Get-ChildItem -Path "C:\Tools\ADInventory" -Recurse | Unblock-File
```

## Execution Policy

If scripts are blocked:

```powershell
# Check current policy
Get-ExecutionPolicy

# Set to RemoteSigned if needed
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Updating the Module

```powershell
# Remove old version
Remove-Item -Path "C:\Tools\ADInventory" -Recurse -Force

# Extract new version
Expand-Archive -Path "C:\Downloads\ADInventory-new.zip" -DestinationPath "C:\Tools\ADInventory"

# Reload module
Remove-Module SSNC.ADInventory -ErrorAction SilentlyContinue
Import-Module "C:\Tools\ADInventory\SSNC.ADInventory.psd1"

# Verify version
Get-Module SSNC.ADInventory | Select-Object Version
```

## Troubleshooting Installation

| Problem | Solution |
|---------|----------|
| "Module not found" | Use full path to .psd1 file |
| "Running scripts is disabled" | Set execution policy to RemoteSigned |
| "Could not load PSSQLite" | Ensure all files extracted; run Unblock-File |
| Connectivity test fails | Check firewall rules for LDAP ports |

## Next Steps

- [Required Permissions](permissions.md) - Understand what access you need
- [Parameters Reference](parameters.md) - All available options
- [Running Collections](collection.md) - Start collecting AD data

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
