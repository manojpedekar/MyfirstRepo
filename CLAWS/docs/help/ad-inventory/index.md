# AD Inventory Collector

The **SSNC.ADInventory** PowerShell module collects comprehensive Active Directory data including objects, group memberships, trust relationships, Sites & Services topology, and domain health information.

**Current Version:** 1.9.1

## What It Collects

### Per-Domain Data

| Data Type | Description |
|-----------|-------------|
| **Users** | All user accounts with attributes (department, title, manager, etc.) |
| **Groups** | Security and distribution groups with type and scope |
| **Computers** | Computer accounts with OS info, DNS hostname |
| **Contacts** | Mail-enabled contacts (non-security principals) |
| **Group Memberships** | Direct group-to-member relationships |
| **Foreign Security Principals** | FSPs from trusted domains (with optional resolution) |
| **Trust Relationships** | Inbound, outbound, and bidirectional trusts |
| **Domain Configuration** | FSMO roles, functional level, SYSVOL replication |

### Per-Forest Data

| Data Type | Description |
|-----------|-------------|
| **Forest Configuration** | Schema version, forest mode, FSMO roles |
| **Sites** | AD sites with description and location |
| **Subnets** | IP subnets and site assignments |
| **Site Links** | Replication links with cost and interval |
| **Domain Controllers** | DC placement, GC status, RODC status |
| **Site Settings** | ISTG, topology options per site |
| **Optional Features** | Recycle Bin, PAM feature status |
| **Domain Health** | SYSVOL replication, GPO health assessment |

## Key Features

- **Multi-domain collection** - Current domain, trust walking, or explicit list
- **Parallel processing** - Collect from multiple domains simultaneously
- **Resume capability** - Checkpoint-based recovery for interrupted collections
- **FSP resolution** - Resolve Foreign Security Principals to source objects
- **Object filtering** - Collect only specific object types
- **SQLite output** - Self-contained database for reliable transport

## Exported Functions

| Function | Purpose |
|----------|---------|
| `Start-ADInventoryCollection` | Main collection function |
| `Test-ADDomainConnectivity` | Pre-flight connectivity validation |

## In This Section

| Article | Description |
|---------|-------------|
| [Installation](installation) | Download and install the module |
| [Required Permissions](permissions.md) | What permissions you need |
| [Running Collections](collection.md) | How to run AD collections |
| [Parameters Reference](parameters.md) | Complete parameter documentation |
| [Sites & Services](sites-services.md) | Topology data collection |

## Quick Example

```powershell
# Import the module
Import-Module "C:\Tools\ADInventory\SSNC.ADInventory.psd1"

# Collect from current domain
$result = Start-ADInventoryCollection -CurrentDomain -OutputPath "C:\Output"

# View results
Write-Host "Collected $($result.TotalObjects) objects"
Write-Host "Database: $($result.DatabasePath)"
```

## Output Contents

The collector produces a ZIP file containing:

```
ADInventory_<GUID>.zip
├── ADInventory_<GUID>.db3    # SQLite database with all collected data
└── ADInventory_<DateTime>.log # Detailed collection log
```

## Collection Statistics

After completion, you'll see statistics including:

- Total objects collected (users, groups, computers, contacts)
- Direct and recursive group memberships
- Sites, subnets, and site links
- Trusts and Foreign Security Principals
- Domain and forest records
- Collection duration
- Any skipped domains with reasons

## Next Steps

1. [Check required permissions](permissions.md)
2. [Install the module](installation.md)
3. [Review parameters](parameters.md)
4. [Run your first collection](collection.md)

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
