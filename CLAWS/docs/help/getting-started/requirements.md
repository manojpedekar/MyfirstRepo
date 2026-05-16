# System Requirements

This page lists the hardware and software requirements for running the collection tools.

## NTFS Permissions Collector

### Minimum Requirements

| Component | Requirement |
|-----------|-------------|
| Operating System | Windows Server 2016+ or Windows 10/11 |
| PowerShell | 5.1 or 7.x |
| Memory | 4 GB RAM minimum (8 GB recommended for large collections) |
| Disk Space | 10 GB free for output files |
| Permissions | Local Administrator on the target server |

### Network Requirements

- Network access to file shares being collected (if remote)
- Outbound HTTPS (443) to this web application for uploads

### Supported File Systems

- NTFS (primary)
- ReFS (limited support)

> **Note:** FAT32 and exFAT do not support ACLs and cannot be collected.

## AD Inventory Collector

### Minimum Requirements

| Component | Requirement |
|-----------|-------------|
| Operating System | Windows Server 2016+ or Windows 10/11 |
| PowerShell | 5.1 or 7.x |
| Memory | 4 GB RAM minimum |
| Disk Space | 5 GB free for output files |
| .NET Framework | 4.7.2+ (usually pre-installed) |

### Active Directory Requirements

| Requirement | Description |
|-------------|-------------|
| Domain Membership | Collector must run from a domain-joined machine |
| Read Access | Read access to AD objects (Domain Users is typically sufficient) |
| LDAP Connectivity | Port 389 (LDAP) or 636 (LDAPS) to domain controllers |
| Global Catalog | Port 3268/3269 for cross-domain queries |

### For Sites & Services Collection

Additional requirements for collecting site topology:

- Read access to Configuration partition
- Access to all domain controllers for site assignment data

See [AD Inventory Permissions](../ad-inventory/permissions.md) for detailed permission requirements.

## Web Application (Upload)

### Browser Support

| Browser | Minimum Version |
|---------|-----------------|
| Microsoft Edge | 88+ |
| Google Chrome | 88+ |
| Mozilla Firefox | 85+ |
| Safari | 14+ |

### Upload Limits

| Limit | Default Value |
|-------|---------------|
| Maximum file size | 3 GB |
| Maximum extracted size | 50 GB |
| Supported format | .zip only |

> **Note:** These limits are configurable by administrators. Contact support if you need to upload larger files.

## Performance Considerations

### NTFS Collection

Collection time depends on:

- Number of folders and files
- Depth of folder hierarchy
- Number of unique ACL entries
- Disk I/O speed

**Estimate:** ~10,000-50,000 folders per minute on typical hardware.

### AD Collection

Collection time depends on:

- Number of objects in the domain
- Number of group memberships
- Network latency to domain controllers
- Whether collecting cross-domain data

**Estimate:** ~50,000-100,000 objects per minute on typical hardware.

## Virtualization Support

Both collectors are fully supported on:

- VMware vSphere
- Microsoft Hyper-V
- Azure Virtual Machines
- AWS EC2

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
