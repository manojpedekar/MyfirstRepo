function Get-CloudKubernetesNodePool {
    <#
    .SYNOPSIS
        Retrieves node pools from a Kubernetes cluster.
    
    .DESCRIPTION
        Gets details about node pools in a Kubernetes cluster. Can retrieve a specific
        pool by ID or list all pools in a cluster.
    
    .PARAMETER ClusterId
        The unique identifier of the Kubernetes cluster. Required.
    
    .PARAMETER PoolId
        The unique identifier of the node pool to retrieve.
    
    .EXAMPLE
        PS> Get-CloudKubernetesNodePool -ClusterId "k8s-..." -PoolId "pool-..."
        
        Retrieves details for a specific node pool.
    
    .EXAMPLE
        PS> Get-CloudKubernetesNodePool -ClusterId "k8s-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Lists all node pools in the specified cluster.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('ClusterId', 'KubernetesClusterId')]
        [string]$ClusterId,
        
        [Parameter(Mandatory=$false)]
        [Alias('NodePoolId', 'Id')]
        [string]$PoolId
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeAccept
            
            # Determine path
            if ($PoolId) {
                $path = "kubernetes/clusters/$ClusterId/nodepools/$PoolId"
            } else {
                $path = "kubernetes/clusters/$ClusterId/nodepools"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve node pool(s): $($_.Exception.Message)"
            return $null
        }
    }
}
