# Running AD Inventory Collections

This guide explains how to run AD Inventory collections using the `Start-ADInventoryCollection` cmdlet.

## Basic Collection

### Current Domain Only

Collect from the domain your computer is joined to:

```powershell
Import-Module "C:\Tools\ADInventory\SSNC.ADInventory.psd1"

$result = Start-ADInventoryCollection -CurrentDomain -OutputPath "C:\Output"
```

### Walk Trust Relationships

Collect from current domain plus all trusted domains (inbound and bidirectional):

```powershell
$result = Start-ADInventoryCollection -WalkTrust -OutputPath "C:\Output"
```

### Specific Domains

Collect from an explicit list of domains:

```powershell
$result = Start-ADInventoryCollection -Domains "contoso.com","fabrikam.com" -OutputPath "C:\Output"
```

## Domain Selection (Parameter Sets)

The cmdlet has three mutually exclusive parameter sets:

| Parameter Set | Usage | Description |
|--------------|-------|-------------|
| `CurrentDomain` | `-CurrentDomain` | Process only the current computer's domain |
| `WalkTrust` | `-WalkTrust` | Current domain + all trusted domains |
| `Domains` | `-Domains @(...)` | Explicit list of domain names |

You must use exactly one of these parameters.

## Filtering Object Types

By default, all object types are collected. Use `-ObjectTypes` to collect specific types only:

```powershell
# Collect only users and groups
$result = Start-ADInventoryCollection -CurrentDomain -ObjectTypes Users,Groups -OutputPath "C:\Output"

# Collect only computers
$result = Start-ADInventoryCollection -CurrentDomain -ObjectTypes Computers -OutputPath "C:\Output"
```

Valid object types:
- `Users` - User accounts
- `Groups` - Security and distribution groups
- `Computers` - Computer accounts
- `Contacts` - Mail-enabled contacts
- `All` - All object types (default)

## Using Alternate Credentials

For cross-domain collection or when running as a different user:

```powershell
# Prompt for credentials
$cred = Get-Credential

# Use credentials for collection
$result = Start-ADInventoryCollection -Domains "partner.com" -Credential $cred -OutputPath "C:\Output"
```

## Parallel Processing

For multi-domain collections, enable parallel processing for faster completion:

```powershell
# Enable parallel with default throttle (4 concurrent domains)
$result = Start-ADInventoryCollection -WalkTrust -EnableParallel -OutputPath "C:\Output"

# Increase parallelism for many domains
$result = Start-ADInventoryCollection -WalkTrust -EnableParallel -ParallelThrottleLimit 8 -OutputPath "C:\Output"
```

Parallel processing is recommended when collecting from 3+ domains.

## Resume Capability

For long-running collections, enable checkpointing to resume if interrupted:

```powershell
$result = Start-ADInventoryCollection -WalkTrust -EnableResume -OutputPath "C:\Output"
```

If collection is interrupted:
- Run the same command again
- Module detects existing checkpoint
- Resumes from last completed domain

## Foreign Security Principal Resolution

Resolve FSPs to their source domain objects:

```powershell
$result = Start-ADInventoryCollection -WalkTrust -ResolveForeignSecurityPrincipals -OutputPath "C:\Output"
```

This requires network connectivity to trusted domains.

## Verbose Logging

Enable detailed logging for troubleshooting:

```powershell
$result = Start-ADInventoryCollection -CurrentDomain -EnableVerboseLogging -OutputPath "C:\Output"
```

## Output Results

The cmdlet returns an object with collection statistics:

```powershell
$result = Start-ADInventoryCollection -CurrentDomain -OutputPath "C:\Output"

# View key results
Write-Host "Database: $($result.DatabasePath)"
Write-Host "Log file: $($result.LogFilePath)"
Write-Host "Total objects: $($result.TotalObjects)"
Write-Host "Duration: $($result.DurationSeconds) seconds"

# Detailed counts
Write-Host "Users: $($result.UsersCollected)"
Write-Host "Groups: $($result.GroupsCollected)"
Write-Host "Computers: $($result.ComputersCollected)"
Write-Host "Contacts: $($result.ContactsCollected)"
Write-Host "Sites: $($result.SitesCollected)"
Write-Host "Subnets: $($result.SubnetsCollected)"

# Check for skipped domains
if ($result.DomainsSkipped -gt 0) {
    Write-Host "Skipped domains:"
    $result.SkippedDomains | ForEach-Object {
        Write-Host "  $($_.Domain): $($_.Reason)"
    }
}
```

## Pre-Flight Connectivity Test

Before running a large collection, test connectivity:

```powershell
# Test current domain
Test-ADDomainConnectivity -CurrentDomain

# Test with trust walking
Test-ADDomainConnectivity -WalkTrust -Port @(636, 389)

# Export results for analysis
Test-ADDomainConnectivity -WalkTrust -Port @(636, 389, 3268) `
    -LogFile "C:\temp\connectivity.log" `
    -OutCliXml "C:\temp\connectivity.xml"
```

## Complete Examples

### Basic Current Domain Collection

```powershell
Import-Module "C:\Tools\ADInventory\SSNC.ADInventory.psd1"

$result = Start-ADInventoryCollection -CurrentDomain -OutputPath "C:\Output"

Write-Host "Collection complete!"
Write-Host "Database: $($result.DatabasePath)"
Write-Host "Objects: $($result.TotalObjects)"
```

### Multi-Domain with Parallel Processing

```powershell
$result = Start-ADInventoryCollection `
    -WalkTrust `
    -EnableParallel `
    -ParallelThrottleLimit 6 `
    -OutputPath "C:\Output" `
    -EnableVerboseLogging

Write-Host "Domains processed: $($result.DomainsProcessed)"
Write-Host "Domains skipped: $($result.DomainsSkipped)"
```

### Specific Domains with Credentials

```powershell
$cred = Get-Credential -Message "Enter credentials for AD access"

$result = Start-ADInventoryCollection `
    -Domains "contoso.com","fabrikam.com","partner.com" `
    -Credential $cred `
    -ResolveForeignSecurityPrincipals `
    -OutputPath "C:\Output"
```

### Scheduled Task Collection

```powershell
# Script for Task Scheduler: C:\Scripts\ADCollection.ps1

$ErrorActionPreference = "Stop"
$logFile = "C:\Logs\ADInventory_$(Get-Date -Format 'yyyyMMdd').log"

Start-Transcript -Path $logFile

try {
    Import-Module "C:\Tools\ADInventory\SSNC.ADInventory.psd1"

    $result = Start-ADInventoryCollection `
        -WalkTrust `
        -EnableParallel `
        -EnableResume `
        -OutputPath "C:\Output"

    Write-Host "Collection completed successfully"
    Write-Host "Total objects: $($result.TotalObjects)"
}
catch {
    Write-Error "Collection failed: $_"
    exit 1
}
finally {
    Stop-Transcript
}
```

## Performance Considerations

| Setting | Recommendation |
|---------|----------------|
| PageSize | Default (1000) works well; increase to 2500 for fast DCs |
| ParallelThrottleLimit | 4 for balanced; up to 8 for many domains |
| EnableResume | Enable for collections taking >30 minutes |

Typical performance: 10,000-50,000 objects per minute.

## After Collection

1. **Upload** the resulting .zip file to the web application
2. **Review** the collection log for any warnings or errors
3. **Verify** object counts match expectations

## Next Steps

- [Parameters Reference](parameters.md) - All available parameters
- [Sites & Services](sites-services.md) - Topology collection details
- [Uploading](../uploading/index) - Upload your collection

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
