function Set-CloudKubernetesCluster {
    <#
    .SYNOPSIS
        Updates an existing Kubernetes cluster.
    
    .DESCRIPTION
        Updates the configuration of an existing Kubernetes cluster including
        name and version. The cluster must be in a state that allows updates.
    
    .PARAMETER Id
        The unique identifier of the Kubernetes cluster to update. Required.
    
    .PARAMETER Name
        The new name for the cluster.
    
    .PARAMETER Version
        The Kubernetes version to upgrade to.
    
    .EXAMPLE
        PS> Set-CloudKubernetesCluster -Id "k8s-..." -Name "new-name"
        
        Renames the cluster to "new-name".
    
    .EXAMPLE
        PS> Set-CloudKubernetesCluster -Id "k8s-..." -Version "1.29"
        
        Upgrades the cluster to Kubernetes version 1.29.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [Alias('ClusterId', 'KubernetesClusterId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$Version
    )
    
    process {
        try {
            # Validate at least one update parameter is provided
            if (-not $Name -and -not $Version) {
                Write-Error "At least one of Name or Version must be specified to update the cluster"
                return $null
            }
            
            # Get cluster for name in confirmation message
            $cluster = Get-CloudKubernetesCluster -Id $Id
            if (-not $cluster) {
                Write-Error "Kubernetes cluster '$Id' not found"
                return $null
            }
            
            # Build request body
            $body = @{}
            
            if ($Name) {
                $body['name'] = $Name
            }
            
            if ($Version) {
                $body['version'] = $Version
            }
            
            # Confirm action
            $action = if ($Version) { 'Update/Upgrade' } else { 'Update' }
            if (-not $PSCmdlet.ShouldProcess("Kubernetes cluster '$($cluster.name)' ($Id)", $action)) {
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            $response = Invoke-CloudAPIRequest -Path "kubernetes/clusters/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            return $response
        }
        catch {
            Write-Error -Message "Failed to update Kubernetes cluster '$Id': $($_.Exception.Message)" -ErrorId 'SetCloudKubernetesClusterFailed'
            return $null
        }
    }
}
