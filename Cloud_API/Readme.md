# SS&C Cloud API PowerShell Module

## DESCRIPTION
This module is a comprehensive set of functions to interact with the SS&C Cloud API. Version 2.0.0 introduces a new modular architecture with improved maintainability, centralized error handling, and backward compatibility.

The goal of this module is to create an API 'provider' to be used in future scripting for the Windows team. This module can be used standalone or as part of larger automation workflows.

### Module Structure (Version 2.0.0)

The module has been restructured into a modular architecture:

```
Cloud-API/
├── Cloud-API.psd1              # Module manifest
├── Cloud-API.psm1              # Root module loader
├── Private/                    # Internal helper functions
│   ├── Initialize-CloudAPIConnection.ps1
│   ├── New-CloudAPIHeaders.ps1
│   ├── Invoke-CloudAPIRequest.ps1
│   ├── Format-CloudAPIError.ps1
│   ├── Test-CloudAPIResource.ps1
│   ├── Protect-String.ps1
│   └── Unprotect-String.ps1
└── Public/                     # Exported functions
    ├── Compute/                # Instance management
    ├── Network/                # Security groups, net access, IPs
    ├── Storage/                # Volumes and disks
    ├── Management/             # Projects, sub-projects, jobs
    ├── IAM/                    # Identity and access management
    ├── Admin/                  # Administrative functions
    ├── ACME/                   # Certificate management
    ├── Kubernetes/             # K8s cluster management
    └── Support/                # Support tickets
```

### Key Features

- **Centralized API Handling**: All API requests go through `Invoke-CloudAPIRequest` with built-in retry logic and pagination
- **Automatic Pagination**: Large result sets are automatically retrieved across multiple pages
- **Error Handling**: Consistent error handling with user-friendly messages
- **Backward Compatibility**: All existing function names work as aliases to new functions
- **Pipeline Support**: Functions support PowerShell pipeline operations
- **ShouldProcess Support**: Destructive operations support `-WhatIf` and `-Confirm`

**Note**: This module is actively maintained. Version 2.0.0 is a significant rewrite while maintaining full backward compatibility.

### Getting Function information

Functions in the module are documented to provide needed information when using Get-Help. These functions also try to stay within the [approved verbs](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands?view=powershell-7.5) available.

To list all available commands within this module, run the below after loading: 
```
get-command -Module Cloud-API
```

If you need further information regarding a command, run 'Get-Help' like the below example: 

```powershell
Get-Help Get-CloudInstance
Get-Help Get-CloudInstance -Examples
Get-Help Get-CloudInstance -Full
```

### Function Naming Convention

All functions use the `Verb-CloudNoun` naming pattern to avoid conflicts with other modules:

- `Get-CloudInstance` (new name)
- `New-CloudSecurityGroup` (new name)
- `Remove-CloudVolume` (new name)

### Backward Compatibility

All original function names are maintained as **aliases** for backward compatibility:

- `Get-Instance` → `Get-CloudInstance`
- `New-Instance` → `New-CloudInstance`
- `Get-NetAccess` → `Get-CloudNetAccess`
- `Get-SecurityGroup` → `Get-CloudSecurityGroup`
- `Get-CloudDisk` → `Get-CloudVolume`
- And many more...

Your existing scripts will continue to work without modification.
```

NAME
    Get-Instance

SYNOPSIS
    This module is used to get instance information from the SS&C Cloud locations. You can get all instances for an entire 'deployment-zone' or just a single instance. See SYNTAX for all options.

        NOTES: Requesting single instance information will return more detailed results than getting them at the sub-project level or higher. Recommended to get at sub-project level as a set $variable, then Get-Instance -instanceId $variable.id, for example to get deeper details.


SYNTAX
    Get-Instance [[-instanceId] <String>] [[-projectId] <String>] [[-accountId] <String>] [[-subprojectId] <String>] [[-deploymentZoneId] <String>] [<CommonParameters>]


DESCRIPTION


RELATED LINKS

REMARKS
    To see the examples, type: "Get-Help Get-Instance -Examples"
    For more information, type: "Get-Help Get-Instance -Detailed"
    For technical information, type: "Get-Help Get-Instance -Full"
```


## API Key Requirements

This module, when loaded, will attempt to import your API key from an encrypted file located at the root of your user directory. **If this file does not exist, the module will prompt you to input your API Key.** 

To setup an encrypted API key file: 

1. Open a Powershell window and load the below function.
    ```   
    function Protect-String {
        param (
            [string]$StringtoEncrypt,
            [switch]$Computer
        )

        if ($Computer) {
            $key = "LocalMachine"
        } else {
            $key = "CurrentUser"
        }
        $data = [System.Text.Encoding]::UTF8.GetBytes($StringtoEncrypt)
        $data = [System.Security.Cryptography.ProtectedData]::Protect($data, $null, [System.Security.Cryptography.DataProtectionScope]::$key)
        [Convert]::ToBase64String($data)
    }
    ```

2. Next, modify then run the below command to create your encrypted file. 
    ```powershell
    Protect-String "YOUR_API_KEY" | Out-File -FilePath (Join-Path $env:USERPROFILE 'cloudapi.key')
    ```

3. Finally, import the module 
    ```
    Import-Module C:\path\to\Cloud-API.psm1'
    ```


## Basic Usage/Tutorial

Below gives a brief introduction to some of my common uses for this module. Please view the actual functions in the module to all functionality. 

#### Get-Instance

Grabs instance information. Either a single instance or all within a sub-project, account, or deployment-zone.
   
   * Single Instance 
        ```
        Get-Instance -instanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        ```

        ```
        id                   : i-55c319eb-5944-4d00-a927-02e2eff4430a
        createdDate          : 9/18/2025 4:09:23 PM
        createdBy            : tnewnham@innovestsystems.com
        projectId            : project-84193807-a81d-4b9b-895b-6c8d8292b55a
        subprojectId         : subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73
        deploymentZoneId     : deploymentzone-na-central-kc
        imageId              : ssnc-cloud-w2k25-base
        name                 : demo
        ip                   : 10.222.14.205
        dns                  : 10-222-14-205.ssnc-corp.cloud
        site                 : na-central-kc
        state                : available
        migrated             : False
        tasksStatus          : COMPLETED
        storageConfiguration : DEFAULT
        workloadType         : CLOUD_WINDOWS
        osType               : Windows
        osVersion            : Windows Server 2025
        hostname             : 10-222-14-205
        gateway              : 10.222.14.1
        powerState           : poweredOn
        cpu                  : 2
        memory               : 4
        baseDisk             : 100
        guestFullName        : Microsoft Windows Server 2016 (64-bit)
        guestState           : running
        toolsStatus          : toolsOk
        toolsRunningStatus   : guestToolsRunning
        mask                 : 255.255.255.0
        vlan                 : 285
        patchingGroup        : 1st-mon-2am-6am
        scheduledForPatching : True
        lastPatchedDate      : 9/18/2025 4:09:23 PM
        lastOsPatchedDate    : 9/18/2025 4:09:23 PM
        domainDelegation     : cloudad.ssncad.global
        ownerId              : user-7e75ddcb-3ec8-4aaa-8d6b-6575678d562e
        imageName            : Windows Server 2025
        deploymentZoneName   : na-central-kc
        securityGroups       : {@{id=securitygroup-ab1620d4-6e5b-44e0-adec-1f8a33aa3d2d; name=Secondary IP ip-f7b076d9-3c40-4710-8da3-b126e3ffc6ca Group; type=SecondaryIP; ip=; fqdn=; cmdb=31320; networkingTenantId=ssnc}, @{id=securitygroup-6da71de1-87be-467f-ac65-f151c5f88277; name=test5;
                            type=SecurityGroup; ip=; fqdn=; cmdb=31320; networkingTenantId=ssnc}, @{id=securitygroup-773e6409-249f-4965-b4ec-8de7cf6908f3; name=Secondary IP ip-89ef8db8-cb50-43d1-8187-0f83ccbcca65 Group; type=SecondaryIP; ip=; fqdn=; cmdb=31320; networkingTenantId=ssnc}}
        tags                 : {}
        enterpriseDatabase   : False
        enterpriseCluster    : False
        ```


   * Sub-Project
  
        ```
        Get-Instance -subprojectId "subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        ```

        ```
        id                   : i-55c319eb-5944-4d00-a927-02e2eff4430a
        createdDate          : 9/18/2025 4:09:23 PM
        createdBy            : tnewnham@innovestsystems.com
        projectId            : project-84193807-a81d-4b9b-895b-6c8d8292b55a
        subprojectId         : subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73
        deploymentZoneId     : deploymentzone-na-central-kc
        imageId              : ssnc-cloud-w2k25-base
        name                 : demo
        ip                   : 10.222.14.205
        dns                  : 10-222-14-205.ssnc-corp.cloud
        site                 : na-central-kc
        state                : available
        migrated             : False
        tasksStatus          : COMPLETED
        storageConfiguration : DEFAULT
        workloadType         : CLOUD_WINDOWS
        osType               : Windows
        osVersion            : Windows Server 2025

        id                   : i-de3a497c-a96b-408b-83fc-857a5963f677
        createdDate          : 9/18/2025 8:19:01 AM
        createdBy            : tnewnham@innovestsystems.com
        projectId            : project-84193807-a81d-4b9b-895b-6c8d8292b55a
        subprojectId         : subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73
        deploymentZoneId     : deploymentzone-na-central-kc
        imageId              : ssnc-cloud-w2k25-base
        name                 : server1
        ip                   : 10.173.18.167
        dns                  : 10-173-18-167.ssnc-corp.cloud
        site                 : na-central-kc
        state                : available
        migrated             : False
        tasksStatus          : COMPLETED
        storageConfiguration : DEFAULT
        workloadType         : CLOUD_WINDOWS
        osType               : Windows
        osVersion            : Windows Server 2025
        ```

#### Get-CloudImage

Retrieves information about cloud images available for creating instances.

```powershell
# List all available images
Get-CloudImage

# Get a specific image
Get-CloudImage -Id "img-55c319eb-5944-4d00-a927-02e2eff4430a"

# Filter by image group
Get-CloudImage -ImageGroupId "ig-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
```

#### Get-CloudSnapshot / New-CloudSnapshot / Remove-CloudSnapshot

Manage instance snapshots for backup and recovery.

```powershell
# List all snapshots for an instance
Get-CloudSnapshot -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a"

# Create a new snapshot
New-CloudSnapshot -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Name "Pre-Update-Backup" -Wait

# Restore from snapshot
Restore-CloudSnapshot -Id "snap-..." -Wait

# Remove a snapshot
Remove-CloudSnapshot -Id "snap-..." -Force
```

#### Get-CloudSnapshotSchedule / Set-CloudSnapshotSchedule

Configure automatic snapshot schedules.

```powershell
# Get current schedule
Get-CloudSnapshotSchedule -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a"

# Set daily snapshots with 7-day retention
Set-CloudSnapshotSchedule -InstanceId "i-..." -Schedule @{
    frequency = "DAILY"
    retention = 7
    hour = 2
} -Wait
```

#### Get-CloudInstancePatchStatus / Start-CloudInstancePatching

Manage instance patching operations.

```powershell
# Get patching status
Get-CloudInstancePatchStatus -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a"

# Start patching immediately
Start-CloudInstancePatching -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Wait

# Add instance to a patch group
Add-CloudInstanceToPatchGroup -InstanceId "i-..." -PatchGroupId "pg-..."
```

#### Copy-CloudInstance / Move-CloudInstance / Resize-CloudInstance

Advanced instance operations.

```powershell
# Clone an instance
Copy-CloudInstance -SourceInstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Name "Clone-01" -Wait

# Move to different sub-project
Move-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -TargetSubprojectId "subproject-..." -Wait

# Resize instance resources
Resize-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Cpu 4 -Memory 8 -Wait
```

#### Get-CloudInstanceConsole / Get-CloudInstanceVNC

Access instance consoles.

```powershell
# Get web console URL
Get-CloudInstanceConsole -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a"

# Get VNC connection details
Get-CloudInstanceVNC -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a"
```

#### Get-CloudAffinityRule / New-CloudAffinityRule / Remove-CloudAffinityRule

Manage affinity and anti-affinity rules for instance placement.

```powershell
# List all affinity rules
Get-CloudAffinityRule

# Create anti-affinity rule (keep instances on different hosts)
New-CloudAffinityRule -Name "WebServers-HA" -Type "AntiAffinity" `
    -InstanceIds @("i-1...", "i-2...", "i-3...") -Wait

# Create affinity rule (keep instances on same host)
New-CloudAffinityRule -Name "Database-Cluster" -Type "Affinity" `
    -InstanceIds @("i-db1...", "i-db2...") -Wait

# Remove an affinity rule
Remove-CloudAffinityRule -Id "ar-..." -Force
```

### New Functions in Version 2.0.0 (Phase 2)

The following compute functions have been added in Phase 2:

**Image Management:**
- `Get-CloudImage` - Get available images
- `Get-CloudImageGroupDetail` - Get detailed image group information

**Snapshot Management:**
- `Get-CloudSnapshot` - List snapshots
- `New-CloudSnapshot` - Create snapshots
- `Remove-CloudSnapshot` - Delete snapshots
- `Restore-CloudSnapshot` - Restore from snapshot
- `Get-CloudSnapshotSchedule` - View snapshot schedules
- `Set-CloudSnapshotSchedule` - Configure automatic snapshots

**Patching Management:**
- `Get-CloudInstancePatchStatus` - Get patching status
- `Start-CloudInstancePatching` - Trigger patching
- `Get-CloudPatchGroupDetail` - Get patch group details
- `Add-CloudInstanceToPatchGroup` - Add instance to patch group
- `Remove-CloudInstanceFromPatchGroup` - Remove from patch group

**Advanced Operations:**
- `Copy-CloudInstance` - Clone instances
- `Move-CloudInstance` - Move to different location
- `Resize-CloudInstance` - Change CPU/memory
- `Export-CloudInstance` - Export as template
- `Get-CloudInstanceConsole` - Get console access
- `Get-CloudInstanceVNC` - Get VNC details

**Affinity Rules:**
- `Get-CloudAffinityRule` - List affinity rules
- `New-CloudAffinityRule` - Create affinity/anti-affinity rules
- `Remove-CloudAffinityRule` - Remove affinity rules

### New Functions in Version 2.0.0 (Phase 3 - Network Expansion)

The following network functions have been added in Phase 3, expanding the Network section to cover all network-related API endpoints:

**Load Balancers:**
- `Get-CloudLoadBalancer` - List and retrieve load balancers
- `New-CloudLoadBalancer` - Create new load balancers
- `Set-CloudLoadBalancer` - Update load balancer configuration
- `Remove-CloudLoadBalancer` - Delete load balancers
- `Get-CloudLoadBalancerPool` - Get pool/member information
- `Add-CloudLoadBalancerPoolMember` - Add members to pools
- `Remove-CloudLoadBalancerPoolMember` - Remove members from pools
- `Get-CloudLoadBalancerHealthCheck` - Get health check configuration
- `Set-CloudLoadBalancerHealthCheck` - Configure health checks

**Firewall & NAT:**
- `Get-CloudFirewallRule` - Get firewall rules
- `New-CloudFirewallRule` - Create firewall rules
- `Set-CloudFirewallRule` - Update firewall rules
- `Remove-CloudFirewallRule` - Delete firewall rules
- `Get-CloudNATRule` - Get NAT rules
- `New-CloudNATRule` - Create NAT rules
- `Remove-CloudNATRule` - Delete NAT rules

**VPN & Connectivity:**
- `Get-CloudVPNConnection` - Get VPN connections
- `New-CloudVPNConnection` - Create VPN connections
- `Set-CloudVPNConnection` - Update VPN connections
- `Remove-CloudVPNConnection` - Delete VPN connections
- `Get-CloudVPNStatus` - Get VPN connection status
- `Start-CloudVPNConnection` - Bring up VPN connection
- `Stop-CloudVPNConnection` - Bring down VPN connection
- `Get-CloudDirectConnect` - Get dedicated connections
- `Get-CloudNetworkSegment` - Get network segments/VLANs

**DNS Management:**
- `Get-CloudDNSDomain` - Get DNS domains
- `New-CloudDNSDomain` - Create DNS domains
- `Remove-CloudDNSDomain` - Delete DNS domains
- `Get-CloudDNSRecord` - Get DNS records
- `New-CloudDNSRecord` - Create DNS records (A, AAAA, CNAME, MX, TXT)
- `Set-CloudDNSRecord` - Update DNS records
- `Remove-CloudDNSRecord` - Delete DNS records

**Advanced Networking:**
- `Get-CloudVLAN` - Get VLAN information
- `Get-CloudIPPool` - Get IP pools
- `New-CloudIPPool` - Create IP pools
- `Remove-CloudIPPool` - Delete IP pools
- `Get-CloudVPC` - Get VPCs (Virtual Private Clouds)
- `New-CloudVPC` - Create VPCs
- `Remove-CloudVPC` - Delete VPCs
- `Get-CloudNetworkTenant` - Get network tenants
- `Get-CloudTier` - Get network tiers

**Global Load Balancers:**
- `Get-CloudGlobalLoadBalancer` - Get global/multi-region load balancers
- `New-CloudGlobalLoadBalancer` - Create global load balancers
- `Set-CloudGlobalLoadBalancer` - Update global load balancers
- `Remove-CloudGlobalLoadBalancer` - Delete global load balancers

### New Functions in Version 2.0.0 (Phase 5 - IAM & Security)

The following IAM and Security functions have been added in Phase 5, providing comprehensive identity and access management capabilities:

**User Management:**
- `Get-CloudUser` - Get users with filtering by email, project, or sub-project
- `New-CloudUser` - Create new users with optional project assignments
- `Set-CloudUser` - Update user properties and project assignments
- `Remove-CloudUser` - Delete users (with ShouldProcess support)
- `Enable-CloudUser` - Enable disabled user accounts
- `Disable-CloudUser` - Disable user accounts
- `Get-CloudUserPreference` - Get user preferences and settings
- `Set-CloudUserPreference` - Set user preferences

**Role Management:**
- `Get-CloudRole` - Get roles with filtering by name or project
- `New-CloudRole` - Create custom roles with permissions
- `Set-CloudRole` - Update role properties and permissions
- `Remove-CloudRole` - Delete roles (with ShouldProcess support)
- `Grant-CloudRole` - Assign roles to users with project scope
- `Revoke-CloudRole` - Remove role assignments from users

**Permission & Access Policy:**
- `Get-CloudPermission` - List available permissions by resource type
- `Get-CloudAccessPolicy` - Get access policies with project filtering
- `New-CloudAccessPolicy` - Create access policies with rules
- `Set-CloudAccessPolicy` - Update access policy rules
- `Remove-CloudAccessPolicy` - Delete access policies (with ShouldProcess support)

**API Token Management:**
- `Get-CloudAPIToken` - List API tokens for current user
- `New-CloudAPIToken` - Create new API tokens with expiration
- `Remove-CloudAPIToken` - Revoke API tokens (with ShouldProcess support)

**Service Account Management:**
- `Get-CloudServiceAccount` - Get service accounts with project filtering
- `New-CloudServiceAccount` - Create service accounts with roles
- `Set-CloudServiceAccount` - Update service account properties
- `Remove-CloudServiceAccount` - Delete service accounts (with ShouldProcess support)

### New Functions in Version 2.0.0 (Phase 4 - Storage Expansion)

The following storage functions have been added in Phase 4, completing the Storage section with backup management, storage pools/tiers, and file share support:

**Backup Management:**
- `Get-CloudBackupPolicy` - Get backup policies for instances/sub-projects
- `Set-CloudBackupPolicy` - Configure backup policy (retention, schedule, enabled)
- `Get-CloudBackup` - List backups for instances/sub-projects
- `Start-CloudBackup` - Trigger on-demand backups with optional wait
- `Restore-CloudBackup` - Restore from backup to original or different instance
- `Remove-CloudBackup` - Delete backups with confirmation

**Storage Pools & Tiers:**
- `Get-CloudStoragePool` - Get storage pools in deployment zones
- `Get-CloudStorageTier` - Get storage tiers (performance levels)
- `Set-CloudVolumeTier` - Move volumes between storage tiers
- `Copy-CloudVolume` - Clone volumes with optional target attachment
- `Get-CloudVolumeAttachment` - Get volume attachment information
- `Add-CloudVolumeAttachment` - Attach volumes to instances
- `Remove-CloudVolumeAttachment` - Detach volumes from instances

**File Shares:**
- `Get-CloudFileShare` - Get NFS/SMB file shares
- `New-CloudFileShare` - Create new file shares (NFS or SMB)
- `Set-CloudFileShare` - Update file share configuration (resize)
- `Remove-CloudFileShare` - Delete file shares with confirmation
- `Get-CloudFileSharePermission` - Get share access permissions
- `Add-CloudFileSharePermission` - Add IP-based access permissions
- `Remove-CloudFileSharePermission` - Remove access permissions

### New Functions in Version 2.0.0 (Phase 6 - ACME Certificate Management)

The following ACME (Automated Certificate Management Environment) functions have been added in Phase 6, providing comprehensive SSL/TLS certificate lifecycle management via Let's Encrypt and other ACME providers:

**ACME Certificate Management:**
- `Get-CloudACMECertificate` - List and retrieve ACME certificates with filtering by domain/status
- `New-CloudACMECertificate` - Request new certificates with SANs support, supports -Wait for async operations
- `Remove-CloudACMECertificate` - Delete certificates with ShouldProcess confirmation
- `Export-CloudACMECertificate` - Export certificates in PEM or PFX format with optional password protection
- `Renew-CloudACMECertificate` - Initiate certificate renewal, supports -Wait for completion
- `Revoke-CloudACMECertificate` - Revoke certificates with reason codes, ShouldProcess support

**ACME Domain Management:**
- `Get-CloudACMEDomain` - List registered domains with filtering
- `New-CloudACMEDomain` - Register domains with DNS or HTTP validation
- `Test-CloudACMEDomain` - Test domain validation configuration
- `Remove-CloudACMEDomain` - Unregister domains with confirmation

**ACME Account Management:**
- `Get-CloudACMEAccount` - List and retrieve ACME account information
- `New-CloudACMEAccount` - Create accounts with email and terms acceptance
- `Set-CloudACMEAccount` - Update account contact information

**Certificate Installation:**
- `Install-CloudACMECertificate` - Install certificates to load balancers, instances, or application gateways, supports -Wait
- `Get-CloudCertificateInstallation` - Track certificate installations across resources

### Security Management

#### Access Pre-Authorization

Manage firewall rule pre-approval workflows:

```powershell
# List all pre-authorizations
Get-CloudAccessPreAuth

# Get specific pre-authorization
Get-CloudAccessPreAuth -Id "preauth-abc123"

# Create a new pre-authorization for web access
New-CloudAccessPreAuth -Name "Web Access" -ResourceId "instance-xyz789" -Ports "80,443" -Protocol "tcp"

# Create with expiration date
New-CloudAccessPreAuth -Name "SSH Access" -ResourceId "instance-xyz789" -Ports "22" -Protocol "tcp" -ExpirationDate "2026-12-31"

# Update a pre-authorization
Set-CloudAccessPreAuth -Id "preauth-abc123" -Ports "80,443,8080"

# Remove a pre-authorization
Remove-CloudAccessPreAuth -Id "preauth-abc123" -Force

# Pipeline example: Remove all pre-auths for a resource
Get-CloudAccessPreAuth -ResourceId "instance-xyz789" | Remove-CloudAccessPreAuth -Force
```