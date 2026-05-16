# Sites & Services Collection

This guide covers the Active Directory Sites and Services data collected by the AD Inventory module.

## Overview

Sites & Services data is collected automatically as part of every AD Inventory collection. This forest-scoped data includes the complete AD replication topology.

## What Gets Collected

### Sites (AD_Site)

| Attribute | Description |
|-----------|-------------|
| SiteName | Name of the AD site |
| Description | Site description |
| Location | Physical location |
| DistinguishedName | Full DN path |
| ObjectGUID | Unique identifier |
| WhenCreated | Creation timestamp |
| WhenChanged | Last modification |

### Subnets (AD_Subnet)

| Attribute | Description |
|-----------|-------------|
| SubnetName | IP subnet in CIDR notation |
| Description | Subnet description |
| Location | Physical location |
| SiteName | Assigned site |
| SiteObjectDN | Site distinguished name |
| DistinguishedName | Subnet DN |
| ObjectGUID | Unique identifier |

### Site Links (AD_SiteLink)

| Attribute | Description |
|-----------|-------------|
| SiteLinkName | Name of the site link |
| Cost | Replication cost (lower = preferred) |
| ReplicationInterval | Minutes between replications |
| Options | Site link options bitmask |
| UseNotification | Change notification enabled |
| TwoWaySync | Bidirectional sync enabled |
| CompressionDisabled | Whether compression is off |
| SiteCount | Number of sites in link |
| SiteList | JSON array of site names |
| Schedule | Replication schedule (Base64) |
| TransportType | IP or SMTP |

### Site Settings (AD_SiteSettings)

| Attribute | Description |
|-----------|-------------|
| SiteName | Site name |
| InterSiteTopologyGenerator | ISTG server DN |
| InterSiteTopologyGeneratorName | ISTG hostname |
| Options | Site settings options |
| IsAutoTopologyDisabled | Auto topology disabled |
| IsTopologyCleanupDisabled | Cleanup disabled |
| IsMinHopsDisabled | Min hops optimization disabled |
| IsDetectStaleDisabled | Stale detection disabled |
| IsInterSiteAutoTopologyDisabled | Inter-site auto topology disabled |
| IsGroupCachingEnabled | Universal group caching |
| Schedule | Site schedule (Base64) |

### Servers in Sites (AD_SiteServer)

| Attribute | Description |
|-----------|-------------|
| ServerName | Server name |
| SiteName | Site assignment |
| DNSHostName | FQDN |
| ServerReference | Server object DN |
| DistinguishedName | NTDS Settings DN |
| ObjectGUID | Unique identifier |

### Domain Controllers (AD_DomainController)

| Attribute | Description |
|-----------|-------------|
| ServerName | DC hostname |
| SiteName | Site assignment |
| Options | NTDS Settings options |
| IsGlobalCatalog | GC server flag |
| DisableInboundReplication | Inbound replication disabled |
| DisableOutboundReplication | Outbound replication disabled |
| DisableNTDSConnTranslation | Connection translation disabled |
| IsRODC | Read-Only DC flag |
| InvocationId | Replication invocation ID |
| MasterNCs | Naming contexts (JSON) |

### Junction Tables

**AD_SiteSubnet** - Site to subnet relationships
**AD_SiteLinkSite** - Site link to site relationships

## Collection Behavior

Sites & Services data is:
- **Always collected** - No parameter to disable
- **Forest-scoped** - Collected once per forest, not per domain
- **Configuration partition** - Read from CN=Sites,CN=Configuration

## Viewing Collected Data

### In the Web Application

After uploading:
1. Navigate to **Domain Master List**
2. Select your domain
3. View the **Sites** tab (when available)

### Query the SQLite Database

```powershell
# Extract the collection
Expand-Archive "C:\Output\ADInventory_*.zip" -DestinationPath "C:\Temp\Review"

# Install SQLite module if needed
# Install-Module -Name PSSQLite

Import-Module PSSQLite

$db = "C:\Temp\Review\ADInventory_*.db3" | Get-Item | Select-Object -First 1

# Query sites
Invoke-SqliteQuery -DataSource $db.FullName -Query "SELECT * FROM AD_Site"

# Query subnets with site assignment
Invoke-SqliteQuery -DataSource $db.FullName -Query @"
SELECT SubnetName, SiteName, Description, Location
FROM AD_Subnet
ORDER BY SiteName, SubnetName
"@

# Query site links
Invoke-SqliteQuery -DataSource $db.FullName -Query @"
SELECT SiteLinkName, Cost, ReplicationInterval, SiteCount, SiteList
FROM AD_SiteLink
ORDER BY Cost
"@

# Query DCs by site
Invoke-SqliteQuery -DataSource $db.FullName -Query @"
SELECT SiteName, ServerName, IsGlobalCatalog, IsRODC
FROM AD_DomainController
ORDER BY SiteName, ServerName
"@

# Query ISTG per site
Invoke-SqliteQuery -DataSource $db.FullName -Query @"
SELECT SiteName, InterSiteTopologyGeneratorName
FROM AD_SiteSettings
WHERE InterSiteTopologyGeneratorName IS NOT NULL
"@
```

## Domain Health Data

In addition to Sites & Services, the collector gathers domain health information:

### SYSVOL Replication (in AD_Domain)

| Attribute | Description |
|-----------|-------------|
| SysvolReplicationMethod | FRS or DFSR |
| SysvolMigrationState | Migration status if in progress |
| DFSRExists | DFSR objects present |
| FRSExists | FRS objects present |
| DFSRFlags | DFSR configuration flags |

### GPO Health (in AD_Domain)

| Attribute | Description |
|-----------|-------------|
| GPOTotalCount | Total GPOs in domain |
| GPOHealthyCount | GPOs with matching GPC/GPT |
| GPOOrphanedGPCCount | GPCs without matching GPT |
| GPOOrphanedGPTCount | GPTs without matching GPC |
| GPOVersionMismatchCount | Version mismatches |
| GPOOverallHealth | Overall health status |
| SYSVOLAccessible | SYSVOL share accessible |
| DefaultDomainPolicyExists | Default policy present |
| DefaultDCPolicyExists | Default DC policy present |

### Optional Features (AD_OptionalFeature)

| Attribute | Description |
|-----------|-------------|
| FeatureName | Feature name |
| FeatureGUID | Feature GUID |
| IsEnabled | Whether enabled (1/0) |
| RequiredForestLevel | Required forest functional level |
| RequiredForestLevelName | Friendly level name |
| Description | Feature description |

Common features:
- **Recycle Bin** - AD object recovery
- **Privileged Access Management (PAM)** - Time-limited group membership

## Use Cases

### Network Documentation

Document your AD topology for network teams:
- Sites and their locations
- Subnet assignments
- Replication links and costs

### Replication Analysis

Review replication configuration:
- Site link costs
- Replication intervals
- ISTG assignments
- DC placement

### DC Placement Review

Analyze domain controller distribution:
- DCs per site
- Global Catalog placement
- RODC locations

### Health Assessment

Check domain health:
- SYSVOL replication method (FRS vs DFSR)
- GPO health status
- Optional features enabled

### Subnet Audit

Verify subnet configuration:
- All subnets assigned to sites
- No orphaned subnets
- Location data current

## Best Practices

| Practice | Benefit |
|----------|---------|
| Collect from forest root | Complete Configuration partition access |
| Regular collections | Track topology changes |
| Review after network changes | Verify subnet updates |
| Check ISTG assignment | Ensure topology generation working |

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
