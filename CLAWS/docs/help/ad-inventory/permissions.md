# AD Inventory Required Permissions

This guide explains what permissions are needed to run AD Inventory collections.

## Minimum Permissions

For most collections, you need only:

| Permission | Scope | Purpose |
|------------|-------|---------|
| Read access to AD objects | Domain partition | Query users, groups, computers |
| Read access to Configuration | Configuration partition | Sites, subnets, site links, optional features |

**Good news:** Members of the **Domain Users** group typically have sufficient read access for complete collections.

## Permission Requirements by Feature

### Basic Object Collection

**Required:** Domain Users membership (default)

```powershell
# This works with Domain Users permissions
Start-ADInventoryCollection -CurrentDomain -OutputPath "C:\Output"
```

Collects: Users, Groups, Computers, Contacts, Group Memberships

### Sites & Services Data

**Required:** Read access to Configuration partition

- Domain Users typically have this access by default
- Data collected: Sites, Subnets, Site Links, Site Settings, DC placement

**Verify access:**
```powershell
# Test Configuration partition access
Get-ADObject -Filter * -SearchBase "CN=Sites,CN=Configuration,DC=company,DC=com" -ResultSetSize 1
```

### Trust Relationships

**Required:** Read access to domain trusts

- Domain Users can read trust objects
- For trust walking (`-WalkTrust`), you need read access in each trusted domain

### Foreign Security Principal Resolution

**Required:** Read access in source/trusted domains

When using `-ResolveForeignSecurityPrincipals`:
- Network connectivity to trusted domains
- Read access in those domains to resolve SIDs

### Domain Health Data

**Required:** Read access to:
- DFSR/FRS replication objects
- Group Policy containers
- Domain configuration

Domain Users typically have this access.

### Optional Features (Recycle Bin, PAM)

**Required:** Read access to Configuration partition

- Checks `CN=Optional Features,CN=Directory Service,CN=Windows NT,CN=Services,CN=Configuration`
- Domain Users have this access by default

## Cross-Domain Collection

When collecting from multiple domains:

| Scenario | Requirement |
|----------|-------------|
| `-WalkTrust` | Read access in current domain + all trusted domains |
| `-Domains` (explicit list) | Read access in each specified domain |
| `-Credential` | Provided credential must have read access |

### Using Alternate Credentials

```powershell
# Prompt for credentials with access to target domains
$cred = Get-Credential

Start-ADInventoryCollection -Domains "contoso.com","partner.com" `
    -Credential $cred -OutputPath "C:\Output"
```

## Checking Your Permissions

### Test Basic AD Access

```powershell
# Test if you can read AD objects
Get-ADUser -Filter * -ResultSetSize 1
Get-ADGroup -Filter * -ResultSetSize 1
Get-ADComputer -Filter * -ResultSetSize 1
```

### Test Configuration Access

```powershell
# Test Sites access
Get-ADReplicationSite -Filter * | Select-Object -First 1

# Test Site Links
Get-ADReplicationSiteLink -Filter * | Select-Object -First 1

# Test Subnets
Get-ADReplicationSubnet -Filter * | Select-Object -First 1
```

### Use the Connectivity Test

```powershell
# Comprehensive connectivity test
Test-ADDomainConnectivity -CurrentDomain -Port @(636, 389, 3268)

# Test with trust walking
Test-ADDomainConnectivity -WalkTrust -Port 636
```

## Service Account Recommendations

For scheduled collections, use a dedicated service account:

### Create Service Account

```powershell
# Create service account (requires AD admin)
New-ADUser -Name "svc_adinventory" `
    -UserPrincipalName "svc_adinventory@company.com" `
    -Path "OU=Service Accounts,DC=company,DC=com" `
    -AccountPassword (Read-Host -AsSecureString "Password") `
    -Enabled $true `
    -PasswordNeverExpires $true `
    -CannotChangePassword $true `
    -Description "AD Inventory Collection Service Account"
```

### Minimal Permissions

The service account needs only:

1. **Domain Users** membership (default)
2. **Log on as batch job** right (for scheduled tasks)
3. Network access to domain controllers

No administrative privileges required.

### Cross-Domain Access

For multi-domain collections:
- Add service account to Domain Users in each target domain, OR
- Create matching accounts in each domain, OR
- Use a trust-accessible group

## Required Network Ports

The collector needs access to domain controllers on these ports:

| Port | Protocol | Service | Required |
|------|----------|---------|----------|
| 636 | TCP | LDAPS | Primary (default) |
| 389 | TCP/UDP | LDAP | Alternative |
| 3268 | TCP | Global Catalog | Cross-domain queries |
| 3269 | TCP | Global Catalog SSL | Secure cross-domain |
| 88 | TCP/UDP | Kerberos | Authentication |
| 53 | TCP/UDP | DNS | DC discovery |
| 445 | TCP | SMB | SYSVOL Access |

### Test Port Connectivity

```powershell
# Test multiple ports
Test-ADDomainConnectivity -Domains "contoso.com" -Port @(636, 389, 3268, 88, 53)
```

## Troubleshooting Permission Issues

### "Access Denied" Errors

```
Error: Access to the path 'CN=Configuration,DC=company,DC=com' is denied.
```

**Causes:**
- Account lacks read access to Configuration partition
- Explicit deny ACE on objects
- Group Policy restriction

**Solutions:**
1. Verify Domain Users membership
2. Check for explicit deny ACEs
3. Contact AD administrator

### "Server is not operational"

**Causes:**
- Network connectivity issue
- Firewall blocking LDAP ports
- DNS resolution failure

**Solutions:**
```powershell
# Test DNS
Resolve-DnsName "company.com"

# Test connectivity
Test-NetConnection -ComputerName "dc01.company.com" -Port 636

# Use connectivity test
Test-ADDomainConnectivity -Domains "company.com" -Port @(636, 389)
```

### Missing Objects in Collection

**Causes:**
- Objects in protected OUs
- Explicit deny ACEs on objects
- Replication latency

**Solutions:**
1. Check collection log for access errors
2. Verify permissions on specific OUs
3. Try collecting from a different DC

## Permission Summary

| Collection Scope | Minimum Permission |
|------------------|-------------------|
| Current domain | Domain Users |
| Trust walking | Domain Users in each trusted domain |
| Sites & Services | Domain Users (Configuration access) |
| Domain Health | Domain Users |
| FSP Resolution | Domain Users in source domains |
| All features | Domain Users + network access |

For most environments, **Domain Users membership is sufficient** for complete AD inventory collection.

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
