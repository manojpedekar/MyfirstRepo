# Cloud-API PowerShell Module - Agent Guidelines

## Project Overview

**SS&C Cloud API PowerShell Module v2.0.0** - A comprehensive PowerShell module for managing SS&C Private Cloud resources via REST API.

- **Language**: PowerShell 5.1+
- **Type**: Binary PowerShell module
- **API**: RESTful API at `https://portal.ssnc-corp.cloud`
- **Architecture**: Modular with Public/Private function separation

## Quick Start Commands

### Import the Module
```powershell
# Import from repo root
Import-Module C:\Users\tnewnham\git\CloudShell\Cloud-API.psd1 -Force

# List all available commands
Get-Command -Module Cloud-API

# Get help for a function
Get-Help Get-CloudInstance -Full
```

### Verify Module State
```powershell
# Check if module loaded correctly
Get-Module Cloud-API

# Count exported functions
(Get-Command -Module Cloud-API).Count

# Test API connectivity (requires valid API key)
Get-CloudInstance -SubprojectId "your-subproject-id" -Verbose
```

## Project Structure

```
Cloud-API/
├── Cloud-API.psd1          # Module manifest - exports & metadata
├── Cloud-API.psm1          # Root module - loader & configuration
├── Private/                # Internal helper functions (7 files)
│   ├── Initialize-CloudAPIConnection.ps1   # API key loading
│   ├── New-CloudAPIHeaders.ps1             # Request headers
│   ├── Invoke-CloudAPIRequest.ps1          # Centralized API handler
│   ├── Format-CloudAPIError.ps1            # Error formatting
│   ├── Test-CloudAPIResource.ps1           # Resource validation
│   ├── Protect-String.ps1                  # String encryption
│   └── Unprotect-String.ps1                # String decryption
└── Public/                 # Exported functions by category
    ├── Compute/            # 35+ functions - instances, snapshots, patching
    ├── Network/            # NetAccess, security groups, DNS, load balancers
    ├── Storage/            # Volumes, backups, file shares
    ├── Management/         # Projects, jobs
    ├── IAM/                # Users, roles, permissions
    ├── Admin/              # CMDB, POSIX sync
    ├── ACME/               # Certificate management
    ├── Kubernetes/         # K8s clusters, node pools
    ├── Integration/        # External integrations
    ├── Monitoring/         # Alerts, metrics
    ├── Notification/       # Channels, webhooks
    ├── Support/            # Support tickets
    ├── Tags/               # Resource tagging
    ├── Tasks/              # Scheduled tasks
    └── Security/           # Access pre-authorization management
```

## Critical Architecture Patterns

### Function Naming Convention
- **New Functions**: `Verb-CloudNoun` (e.g., `Get-CloudInstance`)
- **Backward Compatibility**: Aliases without "Cloud" (e.g., `Get-Instance`)
- **All functions must be added to three locations:**
  1. `Cloud-API.psd1` → `FunctionsToExport` array
  2. `Cloud-API.psm1` → `Export-ModuleMember -Function` array
  3. `Cloud-API.psm1` → Set-Alias call (if alias needed) + `Export-ModuleMember -Alias`

### API Request Pattern (ALWAYS USE)
All API calls must go through the centralized handler:

```powershell
function Get-CloudExample {
    [CmdletBinding()]
    param([string]$Id)
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        $path = "compute/instances/$Id"
        $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        return $response
    }
}
```

**DO NOT** use `Invoke-RestMethod` directly in public functions.

### Key Centralized Features
- **Automatic pagination**: `Invoke-CloudAPIRequest` handles multi-page responses
- **Retry logic**: Built-in exponential backoff for 429/5xx errors
- **Async operations**: Use `-Wait` switch for long-running operations
- **Error handling**: Consistent formatting via `Format-CloudAPIError`

### Security Functions Pattern
Access Pre-Authorization functions follow the standard Verb-CloudNoun pattern:
- `Get-CloudAccessPreAuth` - List/get pre-authorizations
- `New-CloudAccessPreAuth` - Create firewall rule pre-authorization
- `Set-CloudAccessPreAuth` - Update pre-authorization
- `Remove-CloudAccessPreAuth` - Delete pre-authorization

## Module Configuration

Configuration is stored in `$script:ModuleConfig` in `Cloud-API.psm1`:

```powershell
$script:ModuleConfig = @{
    BaseUri = 'https://portal.ssnc-corp.cloud'
    ApiVersion = 'v2'
    AdminApiVersion = 'v1'
    MaxRetries = 3
    RetryDelaySeconds = 5
    DefaultPageSize = 100
}
```

## API Authentication

The module expects an encrypted API key file:

```powershell
# Default location: ~\cloudapi.key
$script:ModuleConfig.KeyFilePath = (Join-Path $env:USERPROFILE 'cloudapi.key')
```

If the key file doesn't exist, the module prompts for API key on first use.

## Critical Gotchas

### Export Synchronization (CRITICAL)
The module has **three sources of truth** that must stay synchronized:

1. **Public/*.ps1 files** - actual function implementations
2. **Cloud-API.psd1** → `FunctionsToExport` and `AliasesToExport`
3. **Cloud-API.psm1** → `Export-ModuleMember` and `Set-Alias`

**Common Issue**: Adding a function to Public/ but not updating psd1/psm1 will make it unavailable to users.

**Verification**: Run `Get-Command -Module Cloud-API` after any changes.

### Async Operations
Functions that create/modify resources often support async:
- `-Wait` switch: Blocks until operation completes
- Default: Returns job object immediately
- Use `-Timeout` to control wait duration (default: 300 seconds)

### Error Handling
- Functions should return `$null` on failure, not throw
- Use `Write-Error` for non-terminating errors
- Use `Write-Verbose` for diagnostic info
- Never use `Write-Host` in module functions

### Function Requirements
Every public function must include:
1. Comprehensive comment-based help (SYNOPSIS, DESCRIPTION, EXAMPLES)
2. `[CmdletBinding()]` attribute
3. Proper parameter validation
4. Pipeline support where applicable (`ValueFromPipeline`, `ValueFromPipelineByPropertyName`)
5. ShouldProcess support for destructive operations (`[CmdletBinding(SupportsShouldProcess=$true)]`)

## Development Workflow

### Adding a New Function

1. Create file: `Public/<Category>/Verb-CloudNoun.ps1`
2. Follow existing function template structure
3. Add to `Cloud-API.psd1` → `FunctionsToExport`
4. Add to `Cloud-API.psm1` → `Export-ModuleMember -Function`
5. Add alias to `Cloud-API.psm1` → `Set-Alias` (if backward compat needed)
6. Add alias to `Cloud-API.psm1` → `Export-ModuleMember -Alias`
7. Test: `Import-Module .\Cloud-API.psd1 -Force`
8. Verify: `Get-Command -Module Cloud-API | Where-Object {$_.Name -like "*YourNoun*"}`

### Testing Changes

```powershell
# Force reimport after changes
Import-Module C:\Users\tnewnham\git\CloudShell\Cloud-API.psd1 -Force

# Verify specific function
Get-Command Get-CloudInstance -Module Cloud-API

# Check help documentation
Get-Help Get-CloudInstance -Examples

# Test with verbose output
Get-CloudInstance -SubprojectId "test" -Verbose
```

### Validation Checklist

Before committing changes:
- [ ] Function added to `FunctionsToExport` in psd1
- [ ] Function added to `Export-ModuleMember` in psm1
- [ ] Aliases added (if applicable) to both psd1 and psm1
- [ ] Module imports without errors: `Import-Module .\Cloud-API.psd1 -Force`
- [ ] Function appears in `Get-Command -Module Cloud-API`
- [ ] Help is accessible: `Get-Help FunctionName`
- [ ] No `Write-Host` calls in code
- [ ] All API calls use `Invoke-CloudAPIRequest`

## Important Files

| File | Purpose |
|------|---------|
| `Cloud-API.psd1` | Module manifest - metadata and exports |
| `Cloud-API.psm1` | Root module - loader, config, aliases |
| `Private/Invoke-CloudAPIRequest.ps1` | Central API handler (critical) |
| `Private/Initialize-CloudAPIConnection.ps1` | API key management |
| `Readme.md` | Full documentation with examples |

## Related Documentation

- **Readme.md**: Comprehensive usage examples and API reference
- **plans/synchronize-module-exports.md**: Export synchronization plan
- **plans/module-export-validation-plan.md**: Validation and CI/CD planning
- **API Docs**: https://portal.ssnc-corp.cloud/api/docs

## No Build/Test Infrastructure

**Important**: This project has no CI/CD, automated tests, or build pipeline:
- No `.github/workflows/` directory
- No `package.json`, `Makefile`, or similar
- No Pester tests (though planned)
- No linting or formatting tools configured

**Manual verification is required** for all changes using the commands in the Testing Changes section above.

## Key Design Principles

1. **Backward Compatibility**: Always maintain aliases for old function names
2. **Pipeline Support**: Functions should work in pipelines where logical
3. **Consistent Error Handling**: Return `$null` on failure, use `Write-Error`
4. **Centralized API Logic**: All requests go through `Invoke-CloudAPIRequest`
5. **Verb-Noun Compliance**: Use [approved verbs](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands)
6. **ShouldProcess**: Destructive operations must support `-WhatIf` and `-Confirm`

## How to Investigate

Read these files first (in order):
1. `Readme.md` - high-level overview and usage examples
2. `Cloud-API.psd1` - see what's exported and module metadata
3. `Cloud-API.psm1` - understand loading logic and configuration
4. `Private/Invoke-CloudAPIRequest.ps1` - understand API handling
5. Sample public functions (e.g., `Public/Compute/Get-CloudInstance.ps1`)

For specific categories, explore the relevant `Public/<Category>/` directory.
