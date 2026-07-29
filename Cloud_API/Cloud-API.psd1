@{
    # Script module or binary module file associated with this manifest
    RootModule = 'Cloud-API.psm1'
    
    # Version number of this module
    ModuleVersion = '2.0.0'
    
    # Supported PSEditions
    # CompatiblePSEditions = @()
    
    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    
    # Author of this module
    Author = 'SS&C Cloud Team'
    
    # Company or vendor of this module
    CompanyName = 'SS&C Technologies'
    
    # Copyright statement for this module
    Copyright = '(c) 2026 SS&C Technologies. All rights reserved.'
    
    # Description of the functionality provided by this module
    Description = 'PowerShell module for managing SS&C Private Cloud resources via REST API. Provides functions for compute, network, storage, IAM, monitoring, tags, scheduled tasks, webhooks, notifications, and administrative operations.'
    
    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'
    
    # Name of the PowerShell host required by this module
    # PowerShellHostName = ''
    
    # Minimum version of the PowerShell host required by this module
    # PowerShellHostVersion = ''
    
    # Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # DotNetFrameworkVersion = ''
    
    # Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # ClrVersion = ''
    
    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''
    
    # Modules that must be imported into the global environment prior to importing this module
    # RequiredModules = @()
    
    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()
    
    # Script files (.ps1) that are run in the caller's environment prior to importing this module
    # ScriptsToProcess = @()
    
    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()
    
    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()
    
    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @()
    
    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        # Compute
        'Get-CloudInstance',
        'New-CloudInstance',
        'Set-CloudInstance',
        'Remove-CloudInstance',
        'Start-CloudInstance',
        'Stop-CloudInstance',
        'Restart-CloudInstance',
        'Reset-CloudInstance',
        'Get-CloudInstanceMetadata',
        'Invoke-CloudInstancePower',
        'Get-CloudImageGroup',
        'Get-CloudImage',
        'Get-CloudImageGroupDetail',
        # Compute - Snapshots
        'Get-CloudSnapshot',
        'New-CloudSnapshot',
        'Remove-CloudSnapshot',
        'Restore-CloudSnapshot',
        'Get-CloudSnapshotSchedule',
        'Set-CloudSnapshotSchedule',
        # Compute - Patching
        'Get-CloudPatchGroup',
        'Get-CloudPatchGroupDetail',
        'Get-CloudInstancePatchStatus',
        'Start-CloudInstancePatching',
        'Add-CloudInstanceToPatchGroup',
        'Remove-CloudInstanceFromPatchGroup',
        # Compute - Advanced Operations
        'Copy-CloudInstance',
        'Move-CloudInstance',
        'Resize-CloudInstance',
        'Export-CloudInstance',
        'Get-CloudInstanceConsole',
        'Get-CloudInstanceVNC',
        # Compute - Affinity Rules
        'Get-CloudAffinityRule',
        'New-CloudAffinityRule',
        'Remove-CloudAffinityRule',
        # Network
        'Get-CloudNetAccess',
        'New-CloudNetAccess',
        'Set-CloudNetAccess',
        'Remove-CloudNetAccess',
        'Get-CloudSecurityGroup',
        'New-CloudSecurityGroup',
        'Add-CloudSecurityGroupMember',
        'Remove-CloudSecurityGroupMember',
        'Remove-CloudSecurityGroup',
        'Get-CloudSecondaryIP',
        'New-CloudSecondaryIP',
        'Add-CloudSecondaryIP',
        'Get-CloudDNSAlias',
        'New-CloudDNSAlias',
        'Test-CloudDNSAliasAvailable',
        'Get-CloudDeploymentZone',
        # Network - Phase 3: Load Balancers
        'Get-CloudLoadBalancer',
        'New-CloudLoadBalancer',
        'Set-CloudLoadBalancer',
        'Remove-CloudLoadBalancer',
        'Get-CloudLoadBalancerPool',
        'Add-CloudLoadBalancerPoolMember',
        'Remove-CloudLoadBalancerPoolMember',
        'Get-CloudLoadBalancerHealthCheck',
        'Set-CloudLoadBalancerHealthCheck',
        # Network - Phase 3: Firewall & NAT
        'Get-CloudFirewallRule',
        'New-CloudFirewallRule',
        'Set-CloudFirewallRule',
        'Remove-CloudFirewallRule',
        'Get-CloudNATRule',
        'New-CloudNATRule',
        'Remove-CloudNATRule',
        # Network - Phase 3: VPN
        'Get-CloudVPNConnection',
        'New-CloudVPNConnection',
        'Set-CloudVPNConnection',
        'Remove-CloudVPNConnection',
        'Get-CloudVPNStatus',
        'Start-CloudVPNConnection',
        'Stop-CloudVPNConnection',
        'Get-CloudDirectConnect',
        'Get-CloudNetworkSegment',
        # Network - Phase 3: DNS
        'Get-CloudDNSDomain',
        'New-CloudDNSDomain',
        'Remove-CloudDNSDomain',
        'Get-CloudDNSRecord',
        'New-CloudDNSRecord',
        'Set-CloudDNSRecord',
        'Remove-CloudDNSRecord',
        # Network - Phase 3: Advanced Networking
        'Get-CloudVLAN',
        'Get-CloudIPPool',
        'New-CloudIPPool',
        'Remove-CloudIPPool',
        'Get-CloudVPC',
        'New-CloudVPC',
        'Remove-CloudVPC',
        'Get-CloudNetworkTenant',
        'Get-CloudTier',
        # Network - Phase 3: Global Load Balancers
        'Get-CloudGlobalLoadBalancer',
        'New-CloudGlobalLoadBalancer',
        'Set-CloudGlobalLoadBalancer',
        'Remove-CloudGlobalLoadBalancer',
        # Storage
        'Get-CloudVolume',
        'New-CloudVolume',
        'Set-CloudVolume',
        'Remove-CloudVolume',
        # Storage - Phase 4: Backup Management
        'Get-CloudBackupPolicy',
        'Set-CloudBackupPolicy',
        'Get-CloudBackup',
        'Start-CloudBackup',
        'Restore-CloudBackup',
        'Remove-CloudBackup',
        # Storage - Phase 4: Storage Pools & Tiers
        'Get-CloudStoragePool',
        'Get-CloudStorageTier',
        'Set-CloudVolumeTier',
        'Copy-CloudVolume',
        'Get-CloudVolumeAttachment',
        'Add-CloudVolumeAttachment',
        'Remove-CloudVolumeAttachment',
        # Storage - Phase 4: File Shares
        'Get-CloudFileShare',
        'New-CloudFileShare',
        'Set-CloudFileShare',
        'Remove-CloudFileShare',
        'Get-CloudFileSharePermission',
        'Add-CloudFileSharePermission',
        'Remove-CloudFileSharePermission',
        # Management
        'Get-CloudSubproject',
        'Get-CloudProject',
        'Get-CloudAccount',
        'Get-CloudJob',
        'Resume-CloudJob',
        # Admin
        'Get-CloudCMDB',
        'Sync-CloudPOSIXGroup',
        # Phase 9: Monitoring & Alerts
        'Get-CloudAlert',
        'New-CloudAlert',
        'Set-CloudAlert',
        'Remove-CloudAlert',
        'Get-CloudMetric',
        'Get-CloudAlertHistory',
        # Phase 9: Tags
        'Get-CloudTag',
        'New-CloudTag',
        'Set-CloudTag',
        'Remove-CloudTag',
        'Get-CloudResourceTag',
        # Phase 9: Scheduled Tasks
        'Get-CloudScheduledTask',
        'New-CloudScheduledTask',
        'Set-CloudScheduledTask',
        'Remove-CloudScheduledTask',
        'Start-CloudScheduledTask',
        'Get-CloudScheduledTaskRun',
        # Phase 9: Webhooks
        'Get-CloudWebhook',
        'New-CloudWebhook',
        'Set-CloudWebhook',
        'Remove-CloudWebhook',
        'Test-CloudWebhook',
        # Phase 9: Notifications
        'Get-CloudNotificationChannel',
        'New-CloudNotificationChannel',
        'Set-CloudNotificationChannel',
        'Remove-CloudNotificationChannel',
        # Phase 2: Kubernetes Cluster Management
        'Get-CloudKubernetesCluster',
        'New-CloudKubernetesCluster',
        'Set-CloudKubernetesCluster',
        'Remove-CloudKubernetesCluster',
        'Start-CloudKubernetesCluster',
        'Stop-CloudKubernetesCluster',
        'Get-CloudKubernetesClusterStatus',
        # Phase 2: Kubernetes Node Pool Functions
        'Get-CloudKubernetesNodePool',
        'New-CloudKubernetesNodePool',
        'Set-CloudKubernetesNodePool',
        'Remove-CloudKubernetesNodePool',
        'Scale-CloudKubernetesNodePool',
        # Phase 2: Kubernetes Kubeconfig & Access Functions
        'Get-CloudKubernetesKubeconfig',
        'New-CloudKubernetesServiceAccount',
        # Phase 2: Kubernetes Workload Functions
        'Get-CloudKubernetesWorkload',
        'Get-CloudKubernetesNamespace',
        # Phase 6: ACME Certificate Management
        # ACME Certificates
        'Get-CloudACMECertificate',
        'New-CloudACMECertificate',
        'Remove-CloudACMECertificate',
        'Export-CloudACMECertificate',
        'Renew-CloudACMECertificate',
        'Revoke-CloudACMECertificate',
        # ACME Domains
        'Get-CloudACMEDomain',
        'New-CloudACMEDomain',
        'Test-CloudACMEDomain',
        'Remove-CloudACMEDomain',
        # ACME Accounts
        'Get-CloudACMEAccount',
        'New-CloudACMEAccount',
        'Set-CloudACMEAccount',
        # Certificate Installation
        'Install-CloudACMECertificate',
        'Get-CloudCertificateInstallation',
        # IAM & Access Management
        'Disable-CloudUser',
        'Enable-CloudUser',
        'Get-CloudAccessPolicy',
        'Get-CloudAPIToken',
        'Get-CloudPermission',
        'Get-CloudRole',
        'Get-CloudServiceAccount',
        'Get-CloudUser',
        'Get-CloudUserPreference',
        'Grant-CloudRole',
        'New-CloudAccessPolicy',
        'New-CloudAPIToken',
        'New-CloudRole',
        'New-CloudServiceAccount',
        'New-CloudUser',
        'Remove-CloudAccessPolicy',
        'Remove-CloudAPIToken',
        'Remove-CloudRole',
        'Remove-CloudServiceAccount',
        'Remove-CloudUser',
        'Revoke-CloudRole',
        'Set-CloudAccessPolicy',
        'Set-CloudRole',
        'Set-CloudServiceAccount',
        'Set-CloudUser',
        'Set-CloudUserPreference',
        # Support & Admin
        'Close-CloudSupportTicket',
        'Get-CloudSupportTicket',
        'New-CloudSupportTicket',
        'Remove-CloudSupportTicket',
        'Set-CloudSupportTicket',
        'Update-CloudSupportTicket',
        'Get-CloudTenant',
        'Get-CloudOrganization',
        'Get-CloudQuota',
        'Set-CloudQuota',
        # Audit, Billing & CMDB
        'Export-CloudAuditLog',
        'Get-CloudActivityLog',
        'Get-CloudAuditLog',
        'Get-CloudBillingSummary',
        'Get-CloudCostReport',
        'Get-CloudResourceUsage',
        'Search-CloudCMDB',
        'Update-CloudCMDB',
        # Security - Access Pre-Authorization
        'Get-CloudAccessPreAuth',
        'New-CloudAccessPreAuth',
        'Set-CloudAccessPreAuth',
        'Remove-CloudAccessPreAuth'
    )
    
    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()
    
    # Variables to export from this module
    VariablesToExport = @()
    
    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @(
        # Compute aliases
        'Get-Instance',
        'New-Instance',
        'Set-Instance',
        'Remove-Instance',
        'Start-Instance',
        'Stop-Instance',
        'Restart-Instance',
        'Reset-Instance',
        'Get-InstanceMetadata',
        'Invoke-InstancePower',
        'Get-ImageGroup',
        'Get-PatchGroups',
        # Compute - Images
        'Get-Image',
        'Get-ImageGroupDetail',
        # Compute - Snapshots
        'Get-Snapshot',
        'New-Snapshot',
        'Remove-Snapshot',
        'Restore-Snapshot',
        'Get-SnapshotSchedule',
        'Set-SnapshotSchedule',
        # Compute - Patching
        'Get-InstancePatchStatus',
        'Start-InstancePatching',
        'Get-PatchGroupDetail',
        'Add-InstanceToPatchGroup',
        'Remove-InstanceFromPatchGroup',
        # Compute - Advanced Operations
        'Copy-Instance',
        'Move-Instance',
        'Resize-Instance',
        'Export-Instance',
        'Get-InstanceConsole',
        'Get-InstanceVNC',
        # Compute - Affinity Rules
        'Get-AffinityRule',
        'New-AffinityRule',
        'Remove-AffinityRule',
        # Network aliases
        'Get-NetAccess',
        'New-NetAccess',
        'Set-NetAccess',
        'Remove-NetAccess',
        'Get-SecurityGroup',
        'New-SecurityGroup',
        'Add-SecurityGroupMember',
        'Remove-SecurityGroupMember',
        'Remove-SecurityGroup',
        'Get-SecondaryIP',
        'New-SecondaryIP',
        'Add-SecondaryIP',
        'Get-DNSAliases',
        'New-DNSAlias',
        'Confirm-DNSAliasAvailable',
        'Get-DeploymentZones',
        # Network - Phase 3 aliases
        'Get-LoadBalancer',
        'New-LoadBalancer',
        'Set-LoadBalancer',
        'Remove-LoadBalancer',
        'Get-LoadBalancerPool',
        'Add-LoadBalancerPoolMember',
        'Remove-LoadBalancerPoolMember',
        'Get-LoadBalancerHealthCheck',
        'Set-LoadBalancerHealthCheck',
        'Get-FirewallRule',
        'New-FirewallRule',
        'Set-FirewallRule',
        'Remove-FirewallRule',
        'Get-NATRule',
        'New-NATRule',
        'Remove-NATRule',
        'Get-VPNConnection',
        'New-VPNConnection',
        'Set-VPNConnection',
        'Remove-VPNConnection',
        'Get-VPNStatus',
        'Start-VPNConnection',
        'Stop-VPNConnection',
        'Get-DirectConnect',
        'Get-NetworkSegment',
        'Get-DNSDomain',
        'New-DNSDomain',
        'Remove-DNSDomain',
        'Get-DNSRecord',
        'New-DNSRecord',
        'Set-DNSRecord',
        'Remove-DNSRecord',
        'Get-VLAN',
        'Get-IPPool',
        'New-IPPool',
        'Remove-IPPool',
        'Get-VPC',
        'New-VPC',
        'Remove-VPC',
        'Get-NetworkTenant',
        'Get-Tier',
        'Get-GlobalLoadBalancer',
        'New-GlobalLoadBalancer',
        'Set-GlobalLoadBalancer',
        'Remove-GlobalLoadBalancer',
        # Storage aliases
        'Get-CloudDisk',
        'New-CloudDisk',
        'Set-CloudDisk',
        'Remove-CloudDisk',
        # Storage - Phase 4 aliases
        'Get-BackupPolicy',
        'Set-BackupPolicy',
        'Get-Backup',
        'Start-Backup',
        'Restore-Backup',
        'Remove-Backup',
        'Get-StoragePool',
        'Get-StorageTier',
        'Set-VolumeTier',
        'Copy-Volume',
        'Get-VolumeAttachment',
        'Add-VolumeAttachment',
        'Remove-VolumeAttachment',
        'Get-FileShare',
        'New-FileShare',
        'Set-FileShare',
        'Remove-FileShare',
        'Get-FileSharePermission',
        'Add-FileSharePermission',
        'Remove-FileSharePermission',
        # Management aliases
        'Get-SubProject',
        'Get-Project',
        'Get-Account',
        'Resume-StuckJob',
        # Admin aliases
        'Get-CloudCMDB',
        'Sync-POSIXGroups',
        # Phase 9: Monitoring aliases
        'Get-Alert',
        'New-Alert',
        'Set-Alert',
        'Remove-Alert',
        'Get-Metric',
        'Get-AlertHistory',
        # Phase 9: Tag aliases
        'Get-Tag',
        'New-Tag',
        'Set-Tag',
        'Remove-Tag',
        'Get-ResourceTag',
        # Phase 9: Task aliases
        'Get-ScheduledTask',
        'New-ScheduledTask',
        'Set-ScheduledTask',
        'Remove-ScheduledTask',
        'Start-ScheduledTask',
        'Get-ScheduledTaskRun',
        # Phase 9: Webhook aliases
        'Get-Webhook',
        'New-Webhook',
        'Set-Webhook',
        'Remove-Webhook',
        'Test-Webhook',
        # Phase 9: Notification aliases
        'Get-NotificationChannel',
        'New-NotificationChannel',
        'Set-NotificationChannel',
        'Remove-NotificationChannel',
        # Phase 8: Support aliases
        'Get-SupportTicket',
        'New-SupportTicket',
        'Set-SupportTicket',
        'Update-SupportTicket',
        'Close-SupportTicket',
        'Remove-SupportTicket',
        # Phase 8: Audit & Admin aliases
        'Get-AuditLog',
        'Get-ActivityLog',
        'Export-AuditLog',
        'Get-Tenant',
        'Get-Organization',
        'Get-Quota',
        'Set-Quota',
        'Get-CostReport',
        'Get-BillingSummary',
        'Get-ResourceUsage',
        # Phase 8: CMDB aliases
        'Search-CMDB',
        'Update-CMDB',
        # Phase 7: Kubernetes aliases
        'Get-KubernetesCluster',
        'New-KubernetesCluster',
        'Set-KubernetesCluster',
        'Remove-KubernetesCluster',
        'Start-KubernetesCluster',
        'Stop-KubernetesCluster',
        'Get-KubernetesClusterStatus',
        'Get-KubernetesNodePool',
        'New-KubernetesNodePool',
        'Set-KubernetesNodePool',
        'Remove-KubernetesNodePool',
        'Scale-KubernetesNodePool',
        'Get-KubernetesKubeconfig',
        'New-KubernetesServiceAccount',
        'Get-KubernetesWorkload',
        'Get-KubernetesNamespace',
        # Phase 6: ACME aliases
        'Get-ACMECertificate',
        'New-ACMECertificate',
        'Remove-ACMECertificate',
        'Export-ACMECertificate',
        'Renew-ACMECertificate',
        'Revoke-ACMECertificate',
        'Get-ACMEDomain',
        'New-ACMEDomain',
        'Test-ACMEDomain',
        'Remove-ACMEDomain',
        'Get-ACMEAccount',
        'New-ACMEAccount',
        'Set-ACMEAccount',
        'Install-ACMECertificate',
        'Get-CertificateInstallation',
        # Security - Access Pre-Authorization
        'Get-AccessPreAuth',
        'New-AccessPreAuth',
        'Set-AccessPreAuth',
        'Remove-AccessPreAuth'
    )
    
    # DSC resources to export from this module
    # DscResourcesToExport = @()
    
    # List of all modules packaged with this module
    # ModuleList = @()
    
    # List of all files packaged with this module
    # FileList = @()
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('SS&C', 'Cloud', 'API', 'REST', 'Automation', 'SSNC')
            
            # A URL to the license for this module
            # LicenseUri = ''
            
            # A URL to the main website for this project
            # ProjectUri = ''
            
            # A URL to an icon representing this module
            # IconUri = ''
            
            # ReleaseNotes of this module
            ReleaseNotes = @'
Version 2.0.0
- Complete module rewrite with modular architecture and full API functionality.
- New helper functions for centralized API handling
- Automatic pagination support
- Retry logic with exponential backoff
- Async operation support
- Backward compatibility maintained via aliases
- All 40 existing functions refactored to use new patterns
'@
            
            # Prerelease string of this module
            # Prerelease = ''
            
            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false
            
            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        } # End of PSData hashtable
    } # End of PrivateData hashtable
    
    # HelpInfo URI of this module
    # HelpInfoURI = ''
    
    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
}
