# AD Inventory Parameters Reference

Complete reference for all parameters in the SSNC.ADInventory module.

## Start-ADInventoryCollection

Main function for collecting AD inventory data.

### Syntax

```powershell
# Parameter Set: CurrentDomain
Start-ADInventoryCollection
    -CurrentDomain
    [-OutputPath <String>]
    [-ObjectTypes <String[]>]
    [-PageSize <Int32>]
    [-Credential <PSCredential>]
    [-EnableVerboseLogging]
    [-EnableParallel]
    [-ParallelThrottleLimit <Int32>]
    [-EnableResume]
    [-ResolveForeignSecurityPrincipals]

# Parameter Set: WalkTrust
Start-ADInventoryCollection
    -WalkTrust
    [-OutputPath <String>]
    [-ObjectTypes <String[]>]
    [-PageSize <Int32>]
    [-Credential <PSCredential>]
    [-EnableVerboseLogging]
    [-EnableParallel]
    [-ParallelThrottleLimit <Int32>]
    [-EnableResume]
    [-ResolveForeignSecurityPrincipals]

# Parameter Set: Domains
Start-ADInventoryCollection
    -Domains <String[]>
    [-WalkTrust]
    [-OutputPath <String>]
    [-ObjectTypes <String[]>]
    [-PageSize <Int32>]
    [-Credential <PSCredential>]
    [-EnableVerboseLogging]
    [-EnableParallel]
    [-ParallelThrottleLimit <Int32>]
    [-EnableResume]
    [-ResolveForeignSecurityPrincipals]
```

### Domain Selection Parameters

#### -CurrentDomain

Collect from the current computer's domain only.

| Property | Value |
|----------|-------|
| Type | Switch |
| Required | Yes (in CurrentDomain set) |
| Position | Named |

```powershell
Start-ADInventoryCollection -CurrentDomain -OutputPath "C:\Output"
```

#### -WalkTrust

Walk trust relationships to discover and collect from trusted domains.

| Property | Value |
|----------|-------|
| Type | Switch |
| Required | Yes (in WalkTrust set) |
| Position | Named |

```powershell
# Collect from current domain + all inbound/bidirectional trusts
Start-ADInventoryCollection -WalkTrust -OutputPath "C:\Output"
```

#### -Domains

Explicit list of domain names to collect from.

| Property | Value |
|----------|-------|
| Type | String[] |
| Required | Yes (in Domains set) |
| Position | Named |

```powershell
Start-ADInventoryCollection -Domains "contoso.com","fabrikam.com" -OutputPath "C:\Output"

# Can combine with -WalkTrust to also walk trusts from specified domains
Start-ADInventoryCollection -Domains "contoso.com" -WalkTrust -OutputPath "C:\Output"
```

### Output Parameters

#### -OutputPath

Directory where output files will be created.

| Property | Value |
|----------|-------|
| Type | String |
| Required | No |
| Default | Current directory |
| Validation | Must be existing directory |

```powershell
Start-ADInventoryCollection -CurrentDomain -OutputPath "C:\ADInventory\Output"
```

### Filtering Parameters

#### -ObjectTypes

Types of AD objects to collect.

| Property | Value |
|----------|-------|
| Type | String[] |
| Required | No |
| Default | @('All') |
| Valid Values | 'Users', 'Groups', 'Computers', 'Contacts', 'All' |

```powershell
# Collect only users and groups
Start-ADInventoryCollection -CurrentDomain -ObjectTypes Users,Groups

# Collect only computers
Start-ADInventoryCollection -CurrentDomain -ObjectTypes Computers
```

### Performance Parameters

#### -PageSize

LDAP query page size for batch processing.

| Property | Value |
|----------|-------|
| Type | Int32 |
| Required | No |
| Default | 1000 |
| Valid Range | 100-5000 |

```powershell
# Increase for faster DCs
Start-ADInventoryCollection -CurrentDomain -PageSize 2500
```

#### -EnableParallel

Enable parallel domain processing using runspaces.

| Property | Value |
|----------|-------|
| Type | Switch |
| Required | No |
| Default | False |

```powershell
Start-ADInventoryCollection -WalkTrust -EnableParallel
```

#### -ParallelThrottleLimit

Maximum number of concurrent domain collections.

| Property | Value |
|----------|-------|
| Type | Int32 |
| Required | No |
| Default | 4 |
| Valid Range | 1-32 |
| Requires | -EnableParallel |

```powershell
Start-ADInventoryCollection -WalkTrust -EnableParallel -ParallelThrottleLimit 8
```

### Authentication Parameters

#### -Credential

Credentials for AD authentication.

| Property | Value |
|----------|-------|
| Type | PSCredential |
| Required | No |
| Default | Current user |

```powershell
$cred = Get-Credential
Start-ADInventoryCollection -Domains "partner.com" -Credential $cred
```

### Advanced Parameters

#### -EnableResume

Enable checkpoint-based resume for interrupted collections.

| Property | Value |
|----------|-------|
| Type | Switch |
| Required | No |
| Default | False |

```powershell
# Enable checkpointing for long collections
Start-ADInventoryCollection -WalkTrust -EnableResume -OutputPath "C:\Output"

# If interrupted, run the same command to resume
```

#### -ResolveForeignSecurityPrincipals

Resolve Foreign Security Principals to their source domain objects.

| Property | Value |
|----------|-------|
| Type | Switch |
| Required | No |
| Default | False |

```powershell
Start-ADInventoryCollection -WalkTrust -ResolveForeignSecurityPrincipals
```

#### -EnableVerboseLogging

Enable verbose logging output.

| Property | Value |
|----------|-------|
| Type | Switch |
| Required | No |
| Default | False |

```powershell
Start-ADInventoryCollection -CurrentDomain -EnableVerboseLogging
```

### Output Object

The cmdlet returns an object with these properties:

| Property | Type | Description |
|----------|------|-------------|
| InventoryID | GUID | Unique identifier for this collection |
| DatabasePath | String | Full path to SQLite database |
| LogFilePath | String | Full path to log file |
| DomainsProcessed | Int | Successfully processed domains |
| DomainsSkipped | Int | Unreachable domains |
| TotalObjects | Int | Total AD objects collected |
| UsersCollected | Int | User object count |
| GroupsCollected | Int | Group object count |
| ComputersCollected | Int | Computer object count |
| ContactsCollected | Int | Contact object count |
| FSPsCollected | Int | Foreign Security Principals |
| TrustsCollected | Int | Trust relationships |
| DirectMemberships | Int | Direct group memberships |
| RecursiveMemberships | Int | Recursive memberships |
| SitesCollected | Int | AD Sites |
| SubnetsCollected | Int | Subnets |
| SiteLinksCollected | Int | Site links |
| DurationSeconds | Int | Collection runtime |
| SkippedDomains | Array | Domains that couldn't be reached |

---

## Test-ADDomainConnectivity

Pre-flight validation of LDAP connectivity to domain controllers.

### Syntax

```powershell
# Parameter Set: CurrentDomain
Test-ADDomainConnectivity
    -CurrentDomain
    [-Port <Int32[]>]
    [-LogFile <String>]
    [-OutCliXml <String>]
    [-Quiet]

# Parameter Set: WalkTrust
Test-ADDomainConnectivity
    -WalkTrust
    [-Port <Int32[]>]
    [-LogFile <String>]
    [-OutCliXml <String>]
    [-Quiet]

# Parameter Set: Domains
Test-ADDomainConnectivity
    -Domains <String[]>
    [-WalkTrust]
    [-Port <Int32[]>]
    [-LogFile <String>]
    [-OutCliXml <String>]
    [-Quiet]
```

### Parameters

#### -CurrentDomain

Test current domain only.

```powershell
Test-ADDomainConnectivity -CurrentDomain
```

#### -WalkTrust

Test current domain and trusted domains.

```powershell
Test-ADDomainConnectivity -WalkTrust
```

#### -Domains

Test specific domains.

```powershell
Test-ADDomainConnectivity -Domains "contoso.com","fabrikam.com"
```

#### -Port

Ports to test connectivity.

| Property | Value |
|----------|-------|
| Type | Int32[] |
| Required | No |
| Default | @(636) |
| Valid Range | 1-65535 |

Common ports:
- 636 - LDAPS (default)
- 389 - LDAP
- 3268 - Global Catalog
- 3269 - Global Catalog SSL
- 88 - Kerberos
- 53 - DNS

```powershell
Test-ADDomainConnectivity -CurrentDomain -Port @(636, 389, 3268)
```

#### -LogFile

Path to write detailed test results.

```powershell
Test-ADDomainConnectivity -WalkTrust -LogFile "C:\temp\connectivity.log"
```

#### -OutCliXml

Export results as CliXml for analysis.

```powershell
Test-ADDomainConnectivity -WalkTrust -OutCliXml "C:\temp\results.xml"
```

#### -Quiet

Suppress console output; return only objects.

```powershell
$results = Test-ADDomainConnectivity -CurrentDomain -Quiet
```

### Output Object

| Property | Description |
|----------|-------------|
| Domain | Domain name tested |
| Status | Success, Failed, DNS Failed, etc. |
| DCsDiscovered | Number of DCs found via DNS |
| DCsAccessible | Number of DCs accessible |
| BestDC | IP of lowest-latency DC |
| Latency | Latency in milliseconds |
| Port | Port number tested |
| PortDesc | Friendly port description |
| Error | Error message if any |
| TestedAt | Timestamp |

---

## Configuration Options

The module uses an internal `ADQueryConfig` class with these defaults:

| Setting | Default | Description |
|---------|---------|-------------|
| PageSize | 1000 | LDAP query page size |
| ServerTimeoutMinutes | 10 | Server-side LDAP timeout |
| ClientTimeoutMinutes | 15 | Client-side query timeout |
| ConnectionTimeoutSeconds | 30 | TCP connection timeout |
| MaxRetries | 3 | Connection retry attempts |
| RetryDelaySeconds | 5 | Delay between retries |
| DCTestPort | 636 | Default DC test port |
| DCTestTimeout | 1000 | DC test timeout (ms) |
| BatchSize | 5000 | Database insert batch size |

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
