<#
.SYNOPSIS
    SS&C Cloud API PowerShell Module

.DESCRIPTION
    A comprehensive PowerShell module for interacting with the SS&C Private Cloud API.
    Provides functions for managing compute, network, storage, IAM, and administrative resources.

    This module uses a modular architecture with:
    - Private helper functions for common operations
    - Public functions organized by category (Compute, Network, Storage, etc.)
    - Centralized error handling and retry logic
    - Automatic pagination support
    - Backward compatibility aliases

.NOTES
    Version: 2.0.0
    Author: SS&C Cloud Team
    Requires: PowerShell 5.1 or later
    
    API Documentation: https://portal.ssnc-corp.cloud/api/docs

.EXAMPLE
    Import-Module Cloud-API
    
    Imports the module and initializes the API connection.

.EXAMPLE
    Get-CloudInstance -SubprojectId "subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
    
    Lists all instances in the specified sub-project.
#>

#Requires -Version 5.1

# Ensure TLS 1.2 is available for secure connections
# This addresses compatibility issues with modern systems that require TLS 1.2+
if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Write-Verbose "TLS 1.2 has been added to the security protocol settings"
}

#region Module Configuration

$script:ModuleConfig = @{
    # API Configuration
    BaseUri = 'https://portal.ssnc-corp.cloud'
    ApiVersion = 'v2'
    AdminApiVersion = 'v1'
    
    # Default Headers
    DefaultContentType = 'application/json'
    DefaultAccept = 'application/json'
    
    # Authentication
    KeyFilePath = (Join-Path $env:USERPROFILE 'cloudapi.key')
    
    # Retry Configuration
    MaxRetries = 3
    RetryDelaySeconds = 5
    
    # Pagination
    DefaultPageSize = 100
    MaxPageSize = 1000
}

$script:CloudAPIKey = $null

#endregion

#region Load Private Functions

$PrivateFunctions = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue
foreach ($Function in $PrivateFunctions) {
    try {
        . $Function.FullName
        Write-Verbose "Loaded private function: $($Function.BaseName)"
    }
    catch {
        Write-Error "Failed to import private function $($Function.FullName): $($_.Exception.Message)"
    }
}

#endregion

#region Load Public Functions

$PublicFunctions = Get-ChildItem -Path "$PSScriptRoot\Public\*\*.ps1" -ErrorAction SilentlyContinue
foreach ($Function in $PublicFunctions) {
    try {
        . $Function.FullName
        Write-Verbose "Loaded public function: $($Function.BaseName)"
    }
    catch {
        Write-Error "Failed to import public function $($Function.FullName): $($_.Exception.Message)"
    }
}

#endregion

#region Initialize Connection

try {
    Initialize-CloudAPIConnection
}
catch {
    Write-Warning "Failed to initialize Cloud API connection: $($_.Exception.Message)"
    Write-Warning "You may need to provide your API key when running commands."
}

#endregion

#region Backward Compatibility Aliases

# Compute aliases
Set-Alias -Name 'Get-Instance' -Value 'Get-CloudInstance' -Scope Global
Set-Alias -Name 'New-Instance' -Value 'New-CloudInstance' -Scope Global
Set-Alias -Name 'Set-Instance' -Value 'Set-CloudInstance' -Scope Global
Set-Alias -Name 'Remove-Instance' -Value 'Remove-CloudInstance' -Scope Global
Set-Alias -Name 'Start-Instance' -Value 'Start-CloudInstance' -Scope Global
Set-Alias -Name 'Stop-Instance' -Value 'Stop-CloudInstance' -Scope Global
Set-Alias -Name 'Restart-Instance' -Value 'Restart-CloudInstance' -Scope Global
Set-Alias -Name 'Reset-Instance' -Value 'Reset-CloudInstance' -Scope Global
Set-Alias -Name 'Get-InstanceMetadata' -Value 'Get-CloudInstanceMetadata' -Scope Global
Set-Alias -Name 'Invoke-InstancePower' -Value 'Invoke-CloudInstancePower' -Scope Global
Set-Alias -Name 'Get-ImageGroup' -Value 'Get-CloudImageGroup' -Scope Global
Set-Alias -Name 'Get-PatchGroups' -Value 'Get-CloudPatchGroup' -Scope Global

# Compute - Images
Set-Alias -Name 'Get-Image' -Value 'Get-CloudImage' -Scope Global
Set-Alias -Name 'Get-ImageGroupDetail' -Value 'Get-CloudImageGroupDetail' -Scope Global

# Compute - Snapshots
Set-Alias -Name 'Get-Snapshot' -Value 'Get-CloudSnapshot' -Scope Global
Set-Alias -Name 'New-Snapshot' -Value 'New-CloudSnapshot' -Scope Global
Set-Alias -Name 'Remove-Snapshot' -Value 'Remove-CloudSnapshot' -Scope Global
Set-Alias -Name 'Restore-Snapshot' -Value 'Restore-CloudSnapshot' -Scope Global
Set-Alias -Name 'Get-SnapshotSchedule' -Value 'Get-CloudSnapshotSchedule' -Scope Global
Set-Alias -Name 'Set-SnapshotSchedule' -Value 'Set-CloudSnapshotSchedule' -Scope Global

# Compute - Patching
Set-Alias -Name 'Get-PatchGroupDetail' -Value 'Get-CloudPatchGroupDetail' -Scope Global
Set-Alias -Name 'Get-InstancePatchStatus' -Value 'Get-CloudInstancePatchStatus' -Scope Global
Set-Alias -Name 'Start-InstancePatching' -Value 'Start-CloudInstancePatching' -Scope Global
Set-Alias -Name 'Add-InstanceToPatchGroup' -Value 'Add-CloudInstanceToPatchGroup' -Scope Global
Set-Alias -Name 'Remove-InstanceFromPatchGroup' -Value 'Remove-CloudInstanceFromPatchGroup' -Scope Global

# Compute - Advanced Operations
Set-Alias -Name 'Copy-Instance' -Value 'Copy-CloudInstance' -Scope Global
Set-Alias -Name 'Move-Instance' -Value 'Move-CloudInstance' -Scope Global
Set-Alias -Name 'Resize-Instance' -Value 'Resize-CloudInstance' -Scope Global
Set-Alias -Name 'Export-Instance' -Value 'Export-CloudInstance' -Scope Global
Set-Alias -Name 'Get-InstanceConsole' -Value 'Get-CloudInstanceConsole' -Scope Global
Set-Alias -Name 'Get-InstanceVNC' -Value 'Get-CloudInstanceVNC' -Scope Global

# Compute - Affinity Rules
Set-Alias -Name 'Get-AffinityRule' -Value 'Get-CloudAffinityRule' -Scope Global
Set-Alias -Name 'New-AffinityRule' -Value 'New-CloudAffinityRule' -Scope Global
Set-Alias -Name 'Remove-AffinityRule' -Value 'Remove-CloudAffinityRule' -Scope Global

# Network aliases
Set-Alias -Name 'Get-NetAccess' -Value 'Get-CloudNetAccess' -Scope Global
Set-Alias -Name 'New-NetAccess' -Value 'New-CloudNetAccess' -Scope Global
Set-Alias -Name 'Set-NetAccess' -Value 'Set-CloudNetAccess' -Scope Global
Set-Alias -Name 'Remove-NetAccess' -Value 'Remove-CloudNetAccess' -Scope Global
Set-Alias -Name 'Get-SecurityGroup' -Value 'Get-CloudSecurityGroup' -Scope Global
Set-Alias -Name 'New-SecurityGroup' -Value 'New-CloudSecurityGroup' -Scope Global
Set-Alias -Name 'Add-SecurityGroupMember' -Value 'Add-CloudSecurityGroupMember' -Scope Global
Set-Alias -Name 'Remove-SecurityGroupMember' -Value 'Remove-CloudSecurityGroupMember' -Scope Global
Set-Alias -Name 'Remove-SecurityGroup' -Value 'Remove-CloudSecurityGroup' -Scope Global
Set-Alias -Name 'Get-SecondaryIP' -Value 'Get-CloudSecondaryIP' -Scope Global
Set-Alias -Name 'New-SecondaryIP' -Value 'New-CloudSecondaryIP' -Scope Global
Set-Alias -Name 'Add-SecondaryIP' -Value 'Add-CloudSecondaryIP' -Scope Global
Set-Alias -Name 'Get-DNSAliases' -Value 'Get-CloudDNSAlias' -Scope Global
Set-Alias -Name 'New-DNSAlias' -Value 'New-CloudDNSAlias' -Scope Global
Set-Alias -Name 'Confirm-DNSAliasAvailable' -Value 'Test-CloudDNSAliasAvailable' -Scope Global
Set-Alias -Name 'Get-DeploymentZones' -Value 'Get-CloudDeploymentZone' -Scope Global

# Network - Phase 3: Load Balancer aliases
Set-Alias -Name 'Get-LoadBalancer' -Value 'Get-CloudLoadBalancer' -Scope Global
Set-Alias -Name 'New-LoadBalancer' -Value 'New-CloudLoadBalancer' -Scope Global
Set-Alias -Name 'Set-LoadBalancer' -Value 'Set-CloudLoadBalancer' -Scope Global
Set-Alias -Name 'Remove-LoadBalancer' -Value 'Remove-CloudLoadBalancer' -Scope Global
Set-Alias -Name 'Get-LoadBalancerPool' -Value 'Get-CloudLoadBalancerPool' -Scope Global
Set-Alias -Name 'Add-LoadBalancerPoolMember' -Value 'Add-CloudLoadBalancerPoolMember' -Scope Global
Set-Alias -Name 'Remove-LoadBalancerPoolMember' -Value 'Remove-CloudLoadBalancerPoolMember' -Scope Global
Set-Alias -Name 'Get-LoadBalancerHealthCheck' -Value 'Get-CloudLoadBalancerHealthCheck' -Scope Global
Set-Alias -Name 'Set-LoadBalancerHealthCheck' -Value 'Set-CloudLoadBalancerHealthCheck' -Scope Global

# Network - Phase 3: Firewall & NAT aliases
Set-Alias -Name 'Get-FirewallRule' -Value 'Get-CloudFirewallRule' -Scope Global
Set-Alias -Name 'New-FirewallRule' -Value 'New-CloudFirewallRule' -Scope Global
Set-Alias -Name 'Set-FirewallRule' -Value 'Set-CloudFirewallRule' -Scope Global
Set-Alias -Name 'Remove-FirewallRule' -Value 'Remove-CloudFirewallRule' -Scope Global
Set-Alias -Name 'Get-NATRule' -Value 'Get-CloudNATRule' -Scope Global
Set-Alias -Name 'New-NATRule' -Value 'New-CloudNATRule' -Scope Global
Set-Alias -Name 'Remove-NATRule' -Value 'Remove-CloudNATRule' -Scope Global

# Network - Phase 3: VPN aliases
Set-Alias -Name 'Get-VPNConnection' -Value 'Get-CloudVPNConnection' -Scope Global
Set-Alias -Name 'New-VPNConnection' -Value 'New-CloudVPNConnection' -Scope Global
Set-Alias -Name 'Set-VPNConnection' -Value 'Set-CloudVPNConnection' -Scope Global
Set-Alias -Name 'Remove-VPNConnection' -Value 'Remove-CloudVPNConnection' -Scope Global
Set-Alias -Name 'Get-VPNStatus' -Value 'Get-CloudVPNStatus' -Scope Global
Set-Alias -Name 'Start-VPNConnection' -Value 'Start-CloudVPNConnection' -Scope Global
Set-Alias -Name 'Stop-VPNConnection' -Value 'Stop-CloudVPNConnection' -Scope Global
Set-Alias -Name 'Get-DirectConnect' -Value 'Get-CloudDirectConnect' -Scope Global
Set-Alias -Name 'Get-NetworkSegment' -Value 'Get-CloudNetworkSegment' -Scope Global

# Network - Phase 3: DNS aliases
Set-Alias -Name 'Get-DNSDomain' -Value 'Get-CloudDNSDomain' -Scope Global
Set-Alias -Name 'New-DNSDomain' -Value 'New-CloudDNSDomain' -Scope Global
Set-Alias -Name 'Remove-DNSDomain' -Value 'Remove-CloudDNSDomain' -Scope Global
Set-Alias -Name 'Get-DNSRecord' -Value 'Get-CloudDNSRecord' -Scope Global
Set-Alias -Name 'New-DNSRecord' -Value 'New-CloudDNSRecord' -Scope Global
Set-Alias -Name 'Set-DNSRecord' -Value 'Set-CloudDNSRecord' -Scope Global
Set-Alias -Name 'Remove-DNSRecord' -Value 'Remove-CloudDNSRecord' -Scope Global

# Network - Phase 3: Advanced Networking aliases
Set-Alias -Name 'Get-VLAN' -Value 'Get-CloudVLAN' -Scope Global
Set-Alias -Name 'Get-IPPool' -Value 'Get-CloudIPPool' -Scope Global
Set-Alias -Name 'New-IPPool' -Value 'New-CloudIPPool' -Scope Global
Set-Alias -Name 'Remove-IPPool' -Value 'Remove-CloudIPPool' -Scope Global
Set-Alias -Name 'Get-VPC' -Value 'Get-CloudVPC' -Scope Global
Set-Alias -Name 'New-VPC' -Value 'New-CloudVPC' -Scope Global
Set-Alias -Name 'Remove-VPC' -Value 'Remove-CloudVPC' -Scope Global
Set-Alias -Name 'Get-NetworkTenant' -Value 'Get-CloudNetworkTenant' -Scope Global
Set-Alias -Name 'Get-Tier' -Value 'Get-CloudTier' -Scope Global

# Network - Phase 3: Global Load Balancer aliases
Set-Alias -Name 'Get-GlobalLoadBalancer' -Value 'Get-CloudGlobalLoadBalancer' -Scope Global
Set-Alias -Name 'New-GlobalLoadBalancer' -Value 'New-CloudGlobalLoadBalancer' -Scope Global
Set-Alias -Name 'Set-GlobalLoadBalancer' -Value 'Set-CloudGlobalLoadBalancer' -Scope Global
Set-Alias -Name 'Remove-GlobalLoadBalancer' -Value 'Remove-CloudGlobalLoadBalancer' -Scope Global

# Storage aliases
Set-Alias -Name 'Get-CloudDisk' -Value 'Get-CloudVolume' -Scope Global
Set-Alias -Name 'New-CloudDisk' -Value 'New-CloudVolume' -Scope Global
Set-Alias -Name 'Set-CloudDisk' -Value 'Set-CloudVolume' -Scope Global
Set-Alias -Name 'Remove-CloudDisk' -Value 'Remove-CloudVolume' -Scope Global

# Storage - Phase 4 aliases
Set-Alias -Name 'Get-BackupPolicy' -Value 'Get-CloudBackupPolicy' -Scope Global
Set-Alias -Name 'Set-BackupPolicy' -Value 'Set-CloudBackupPolicy' -Scope Global
Set-Alias -Name 'Get-Backup' -Value 'Get-CloudBackup' -Scope Global
Set-Alias -Name 'Start-Backup' -Value 'Start-CloudBackup' -Scope Global
Set-Alias -Name 'Restore-Backup' -Value 'Restore-CloudBackup' -Scope Global
Set-Alias -Name 'Remove-Backup' -Value 'Remove-CloudBackup' -Scope Global
Set-Alias -Name 'Get-StoragePool' -Value 'Get-CloudStoragePool' -Scope Global
Set-Alias -Name 'Get-StorageTier' -Value 'Get-CloudStorageTier' -Scope Global
Set-Alias -Name 'Set-VolumeTier' -Value 'Set-CloudVolumeTier' -Scope Global
Set-Alias -Name 'Copy-Volume' -Value 'Copy-CloudVolume' -Scope Global
Set-Alias -Name 'Get-VolumeAttachment' -Value 'Get-CloudVolumeAttachment' -Scope Global
Set-Alias -Name 'Add-VolumeAttachment' -Value 'Add-CloudVolumeAttachment' -Scope Global
Set-Alias -Name 'Remove-VolumeAttachment' -Value 'Remove-CloudVolumeAttachment' -Scope Global
Set-Alias -Name 'Get-FileShare' -Value 'Get-CloudFileShare' -Scope Global
Set-Alias -Name 'New-FileShare' -Value 'New-CloudFileShare' -Scope Global
Set-Alias -Name 'Set-FileShare' -Value 'Set-CloudFileShare' -Scope Global
Set-Alias -Name 'Remove-FileShare' -Value 'Remove-CloudFileShare' -Scope Global
Set-Alias -Name 'Get-FileSharePermission' -Value 'Get-CloudFileSharePermission' -Scope Global
Set-Alias -Name 'Add-FileSharePermission' -Value 'Add-CloudFileSharePermission' -Scope Global
Set-Alias -Name 'Remove-FileSharePermission' -Value 'Remove-CloudFileSharePermission' -Scope Global

# IAM - Phase 5: User Management aliases
Set-Alias -Name 'Get-User' -Value 'Get-CloudUser' -Scope Global
Set-Alias -Name 'New-User' -Value 'New-CloudUser' -Scope Global
Set-Alias -Name 'Set-User' -Value 'Set-CloudUser' -Scope Global
Set-Alias -Name 'Remove-User' -Value 'Remove-CloudUser' -Scope Global
Set-Alias -Name 'Enable-User' -Value 'Enable-CloudUser' -Scope Global
Set-Alias -Name 'Disable-User' -Value 'Disable-CloudUser' -Scope Global
Set-Alias -Name 'Get-UserPreference' -Value 'Get-CloudUserPreference' -Scope Global
Set-Alias -Name 'Set-UserPreference' -Value 'Set-CloudUserPreference' -Scope Global

# IAM - Phase 5: Role Management aliases
Set-Alias -Name 'Get-Role' -Value 'Get-CloudRole' -Scope Global
Set-Alias -Name 'New-Role' -Value 'New-CloudRole' -Scope Global
Set-Alias -Name 'Set-Role' -Value 'Set-CloudRole' -Scope Global
Set-Alias -Name 'Remove-Role' -Value 'Remove-CloudRole' -Scope Global
Set-Alias -Name 'Grant-Role' -Value 'Grant-CloudRole' -Scope Global
Set-Alias -Name 'Revoke-Role' -Value 'Revoke-CloudRole' -Scope Global

# IAM - Phase 5: Permission & Access Policy aliases
Set-Alias -Name 'Get-Permission' -Value 'Get-CloudPermission' -Scope Global
Set-Alias -Name 'Get-AccessPolicy' -Value 'Get-CloudAccessPolicy' -Scope Global
Set-Alias -Name 'New-AccessPolicy' -Value 'New-CloudAccessPolicy' -Scope Global
Set-Alias -Name 'Set-AccessPolicy' -Value 'Set-CloudAccessPolicy' -Scope Global
Set-Alias -Name 'Remove-AccessPolicy' -Value 'Remove-CloudAccessPolicy' -Scope Global

# IAM - Phase 5: API Token Management aliases
Set-Alias -Name 'Get-APIToken' -Value 'Get-CloudAPIToken' -Scope Global
Set-Alias -Name 'New-APIToken' -Value 'New-CloudAPIToken' -Scope Global
Set-Alias -Name 'Remove-APIToken' -Value 'Remove-CloudAPIToken' -Scope Global

# IAM - Phase 5: Service Account Management aliases
Set-Alias -Name 'Get-ServiceAccount' -Value 'Get-CloudServiceAccount' -Scope Global
Set-Alias -Name 'New-ServiceAccount' -Value 'New-CloudServiceAccount' -Scope Global
Set-Alias -Name 'Set-ServiceAccount' -Value 'Set-CloudServiceAccount' -Scope Global
Set-Alias -Name 'Remove-ServiceAccount' -Value 'Remove-CloudServiceAccount' -Scope Global

# Management aliases
Set-Alias -Name 'Get-SubProject' -Value 'Get-CloudSubproject' -Scope Global
Set-Alias -Name 'Get-Project' -Value 'Get-CloudProject' -Scope Global
Set-Alias -Name 'Get-Account' -Value 'Get-CloudAccount' -Scope Global
Set-Alias -Name 'Get-CloudJob' -Value 'Get-CloudJob' -Scope Global
Set-Alias -Name 'Resume-StuckJob' -Value 'Resume-CloudJob' -Scope Global

# Admin aliases
Set-Alias -Name 'Get-CloudCMDB' -Value 'Get-CloudCMDB' -Scope Global
Set-Alias -Name 'Sync-POSIXGroups' -Value 'Sync-CloudPOSIXGroup' -Scope Global

# Phase 8: Support aliases
Set-Alias -Name 'Get-SupportTicket' -Value 'Get-CloudSupportTicket' -Scope Global
Set-Alias -Name 'New-SupportTicket' -Value 'New-CloudSupportTicket' -Scope Global
Set-Alias -Name 'Set-SupportTicket' -Value 'Set-CloudSupportTicket' -Scope Global
Set-Alias -Name 'Update-SupportTicket' -Value 'Update-CloudSupportTicket' -Scope Global
Set-Alias -Name 'Close-SupportTicket' -Value 'Close-CloudSupportTicket' -Scope Global
Set-Alias -Name 'Remove-SupportTicket' -Value 'Remove-CloudSupportTicket' -Scope Global

# Phase 8: Audit & Admin aliases
Set-Alias -Name 'Get-AuditLog' -Value 'Get-CloudAuditLog' -Scope Global
Set-Alias -Name 'Get-ActivityLog' -Value 'Get-CloudActivityLog' -Scope Global
Set-Alias -Name 'Export-AuditLog' -Value 'Export-CloudAuditLog' -Scope Global
Set-Alias -Name 'Get-Tenant' -Value 'Get-CloudTenant' -Scope Global
Set-Alias -Name 'Get-Organization' -Value 'Get-CloudOrganization' -Scope Global
Set-Alias -Name 'Get-Quota' -Value 'Get-CloudQuota' -Scope Global
Set-Alias -Name 'Set-Quota' -Value 'Set-CloudQuota' -Scope Global
Set-Alias -Name 'Get-CostReport' -Value 'Get-CloudCostReport' -Scope Global
Set-Alias -Name 'Get-BillingSummary' -Value 'Get-CloudBillingSummary' -Scope Global
Set-Alias -Name 'Get-ResourceUsage' -Value 'Get-CloudResourceUsage' -Scope Global

# Phase 8: CMDB aliases
Set-Alias -Name 'Search-CMDB' -Value 'Search-CloudCMDB' -Scope Global
Set-Alias -Name 'Update-CMDB' -Value 'Update-CloudCMDB' -Scope Global

# Phase 6: ACME Certificate aliases
Set-Alias -Name 'Get-ACMECertificate' -Value 'Get-CloudACMECertificate' -Scope Global
Set-Alias -Name 'New-ACMECertificate' -Value 'New-CloudACMECertificate' -Scope Global
Set-Alias -Name 'Remove-ACMECertificate' -Value 'Remove-CloudACMECertificate' -Scope Global
Set-Alias -Name 'Export-ACMECertificate' -Value 'Export-CloudACMECertificate' -Scope Global
Set-Alias -Name 'Renew-ACMECertificate' -Value 'Renew-CloudACMECertificate' -Scope Global
Set-Alias -Name 'Revoke-ACMECertificate' -Value 'Revoke-CloudACMECertificate' -Scope Global

# Phase 6: ACME Domain aliases
Set-Alias -Name 'Get-ACMEDomain' -Value 'Get-CloudACMEDomain' -Scope Global
Set-Alias -Name 'New-ACMEDomain' -Value 'New-CloudACMEDomain' -Scope Global
Set-Alias -Name 'Test-ACMEDomain' -Value 'Test-CloudACMEDomain' -Scope Global
Set-Alias -Name 'Remove-ACMEDomain' -Value 'Remove-CloudACMEDomain' -Scope Global

# Phase 6: ACME Account aliases
Set-Alias -Name 'Get-ACMEAccount' -Value 'Get-CloudACMEAccount' -Scope Global
Set-Alias -Name 'New-ACMEAccount' -Value 'New-CloudACMEAccount' -Scope Global
Set-Alias -Name 'Set-ACMEAccount' -Value 'Set-CloudACMEAccount' -Scope Global

# Phase 6: Certificate Installation aliases
Set-Alias -Name 'Install-ACMECertificate' -Value 'Install-CloudACMECertificate' -Scope Global
Set-Alias -Name 'Get-CertificateInstallation' -Value 'Get-CloudCertificateInstallation' -Scope Global

# Phase 2: Kubernetes aliases
# Kubernetes Cluster aliases
Set-Alias -Name 'Get-KubernetesCluster' -Value 'Get-CloudKubernetesCluster' -Scope Global
Set-Alias -Name 'New-KubernetesCluster' -Value 'New-CloudKubernetesCluster' -Scope Global
Set-Alias -Name 'Set-KubernetesCluster' -Value 'Set-CloudKubernetesCluster' -Scope Global
Set-Alias -Name 'Remove-KubernetesCluster' -Value 'Remove-CloudKubernetesCluster' -Scope Global
Set-Alias -Name 'Start-KubernetesCluster' -Value 'Start-CloudKubernetesCluster' -Scope Global
Set-Alias -Name 'Stop-KubernetesCluster' -Value 'Stop-CloudKubernetesCluster' -Scope Global
Set-Alias -Name 'Get-KubernetesClusterStatus' -Value 'Get-CloudKubernetesClusterStatus' -Scope Global

# Kubernetes Node Pool aliases
Set-Alias -Name 'Get-KubernetesNodePool' -Value 'Get-CloudKubernetesNodePool' -Scope Global
Set-Alias -Name 'New-KubernetesNodePool' -Value 'New-CloudKubernetesNodePool' -Scope Global
Set-Alias -Name 'Set-KubernetesNodePool' -Value 'Set-CloudKubernetesNodePool' -Scope Global
Set-Alias -Name 'Remove-KubernetesNodePool' -Value 'Remove-CloudKubernetesNodePool' -Scope Global
Set-Alias -Name 'Scale-KubernetesNodePool' -Value 'Scale-CloudKubernetesNodePool' -Scope Global

# Kubernetes Kubeconfig & Access aliases
Set-Alias -Name 'Get-KubernetesKubeconfig' -Value 'Get-CloudKubernetesKubeconfig' -Scope Global
Set-Alias -Name 'New-KubernetesServiceAccount' -Value 'New-CloudKubernetesServiceAccount' -Scope Global

# Kubernetes Workload aliases
Set-Alias -Name 'Get-KubernetesWorkload' -Value 'Get-CloudKubernetesWorkload' -Scope Global
Set-Alias -Name 'Get-KubernetesNamespace' -Value 'Get-CloudKubernetesNamespace' -Scope Global

# Security - Access Pre-Authorization
Set-Alias -Name 'Get-AccessPreAuth' -Value 'Get-CloudAccessPreAuth' -Scope Global
Set-Alias -Name 'New-AccessPreAuth' -Value 'New-CloudAccessPreAuth' -Scope Global
Set-Alias -Name 'Set-AccessPreAuth' -Value 'Set-CloudAccessPreAuth' -Scope Global
Set-Alias -Name 'Remove-AccessPreAuth' -Value 'Remove-CloudAccessPreAuth' -Scope Global

#endregion

#region Export Module Members

Export-ModuleMember -Function @(
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
    # IAM - Phase 5: User Management
    'Get-CloudUser',
    'New-CloudUser',
    'Set-CloudUser',
    'Remove-CloudUser',
    'Enable-CloudUser',
    'Disable-CloudUser',
    'Get-CloudUserPreference',
    'Set-CloudUserPreference',
    # IAM - Phase 5: Role Management
    'Get-CloudRole',
    'New-CloudRole',
    'Set-CloudRole',
    'Remove-CloudRole',
    'Grant-CloudRole',
    'Revoke-CloudRole',
    # IAM - Phase 5: Permission & Access Policy
    'Get-CloudPermission',
    'Get-CloudAccessPolicy',
    'New-CloudAccessPolicy',
    'Set-CloudAccessPolicy',
    'Remove-CloudAccessPolicy',
    # IAM - Phase 5: API Token Management
    'Get-CloudAPIToken',
    'New-CloudAPIToken',
    'Remove-CloudAPIToken',
    # IAM - Phase 5: Service Account Management
    'Get-CloudServiceAccount',
    'New-CloudServiceAccount',
    'Set-CloudServiceAccount',
    'Remove-CloudServiceAccount',
    # Phase 8: Support Functions
    'Get-CloudSupportTicket',
    'New-CloudSupportTicket',
    'Set-CloudSupportTicket',
    'Update-CloudSupportTicket',
    'Close-CloudSupportTicket',
    'Remove-CloudSupportTicket',
    # Phase 8: Audit & Logging Functions
    'Get-CloudAuditLog',
    'Get-CloudActivityLog',
    'Export-CloudAuditLog',
    # Phase 8: Administrative Functions
    'Get-CloudTenant',
    'Get-CloudOrganization',
    'Get-CloudQuota',
    'Set-CloudQuota',
    'Get-CloudCostReport',
    'Get-CloudBillingSummary',
    'Get-CloudResourceUsage',
    # Phase 8: CMDB Functions
    'Search-CloudCMDB',
    'Update-CloudCMDB',
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
    # Phase 9: Notification Channels
    'Get-CloudNotificationChannel',
    'New-CloudNotificationChannel',
    'Set-CloudNotificationChannel',
    'Remove-CloudNotificationChannel',
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
    # Security - Access Pre-Authorization
    'Get-CloudAccessPreAuth',
    'New-CloudAccessPreAuth',
    'Set-CloudAccessPreAuth',
    'Remove-CloudAccessPreAuth'
) -Alias @(
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
    'Get-PatchGroupDetail',
    'Get-InstancePatchStatus',
    'Start-InstancePatching',
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
    # IAM - Phase 5: User Management aliases
    'Get-User',
    'New-User',
    'Set-User',
    'Remove-User',
    'Enable-User',
    'Disable-User',
    'Get-UserPreference',
    'Set-UserPreference',
    # IAM - Phase 5: Role Management aliases
    'Get-Role',
    'New-Role',
    'Set-Role',
    'Remove-Role',
    'Grant-Role',
    'Revoke-Role',
    # IAM - Phase 5: Permission & Access Policy aliases
    'Get-Permission',
    'Get-AccessPolicy',
    'New-AccessPolicy',
    'Set-AccessPolicy',
    'Remove-AccessPolicy',
    # IAM - Phase 5: API Token Management aliases
    'Get-APIToken',
    'New-APIToken',
    'Remove-APIToken',
    # IAM - Phase 5: Service Account Management aliases
    'Get-ServiceAccount',
    'New-ServiceAccount',
    'Set-ServiceAccount',
    'Remove-ServiceAccount',
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
    # Phase 2: Kubernetes aliases
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
    # Security - Access Pre-Authorization
    'Get-AccessPreAuth',
    'New-AccessPreAuth',
    'Set-AccessPreAuth',
    'Remove-AccessPreAuth'
)

#endregion
