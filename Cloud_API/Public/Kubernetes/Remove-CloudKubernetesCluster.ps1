function Remove-CloudKubernetesCluster {
    <#
    .SYNOPSIS
        Deletes a Kubernetes cluster.
    
    .DESCRIPTION
        Permanently deletes a Kubernetes cluster and all associated resources
        including node pools and workloads. Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the Kubernetes cluster to delete. Required.
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudKubernetesCluster -Id "k8s-..." -Force
        
        Deletes the cluster without confirmation.
    
    .OUTPUTS
        PSCustomObject or $null. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [Alias('ClusterId', 'KubernetesClusterId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Get cluster name for better confirmation message
            $cluster = Get-CloudKubernetesCluster -Id $Id
            $clusterName = if ($cluster) { $cluster.name } else { $Id }
            
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("Kubernetes cluster '$clusterName' ($Id)", 'Remove')) {
                return $null
            }
            
            $headers = New-CloudAPIHeaders -IncludeContentType
            
            $response = Invoke-CloudAPIRequest -Path "kubernetes/clusters/$Id" -Method 'DELETE' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error -Message "Failed to remove Kubernetes cluster: $($_.Exception.Message)" -ErrorId 'RemoveCloudKubernetesClusterFailed'
            return $null
        }
    }
}
