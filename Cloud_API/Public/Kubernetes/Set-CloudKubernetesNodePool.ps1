function Set-CloudKubernetesNodePool {
    <#
    .SYNOPSIS
        Updates an existing node pool in a Kubernetes cluster.
    
    .DESCRIPTION
        Updates the configuration of an existing node pool including count
        and auto-scaling settings.
    
    .PARAMETER ClusterId
        The unique identifier of the Kubernetes cluster. Required.
    
    .PARAMETER PoolId
        The unique identifier of the node pool to update. Required.
    
    .PARAMETER Count
        The new number of nodes in the pool.
    
    .PARAMETER MinCount
        The new minimum number of nodes for auto-scaling.
    
    .PARAMETER MaxCount
        The new maximum number of nodes for auto-scaling.
    
    .EXAMPLE
        PS> Set-CloudKubernetesNodePool -ClusterId "k8s-..." -PoolId "pool-..." -Count 5
        
        Updates the node pool to have 5 nodes.
    
    .EXAMPLE
        PS> Set-CloudKubernetesNodePool -ClusterId "k8s-..." -PoolId "pool-..." -MinCount 2 -MaxCount 20
        
        Updates the auto-scaling configuration of the node pool.
    
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
        [string]$ClusterId,
        
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [Alias('NodePoolId', 'Id')]
        [string]$PoolId,
        
        [Parameter(Mandatory=$false)]
        [int]$Count,
        
        [Parameter(Mandatory=$false)]
        [int]$MinCount,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxCount
    )
    
    process {
        try {
            # Validate at least one update parameter is provided
            if ($Count -eq 0 -and $MinCount -eq 0 -and $MaxCount -eq 0) {
                Write-Error "At least one of Count, MinCount, or MaxCount must be specified to update the node pool"
                return $null
            }
            
            # Get pool for name in confirmation message
            $pool = Get-CloudKubernetesNodePool -ClusterId $ClusterId -PoolId $PoolId
            if (-not $pool) {
                Write-Error "Node pool '$PoolId' not found in cluster '$ClusterId'"
                return $null
            }
            
            # Build request body
            $body = @{}
            
            if ($Count -gt 0) {
                $body['count'] = $Count
            }
            
            if ($MinCount -gt 0) {
                $body['minCount'] = $MinCount
            }
            
            if ($MaxCount -gt 0) {
                $body['maxCount'] = $MaxCount
            }
            
            # Confirm action
            if (-not $PSCmdlet.ShouldProcess("node pool '$($pool.name)' ($PoolId) in cluster '$ClusterId'", 'Update')) {
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            $response = Invoke-CloudAPIRequest -Path "kubernetes/clusters/$ClusterId/nodepools/$PoolId" -Method 'PUT' -Headers $headers -Body $body
            
            return $response
        }
        catch {
            Write-Error -Message "Failed to update node pool '$PoolId' in cluster '$ClusterId': $($_.Exception.Message)" -ErrorId 'SetCloudKubernetesNodePoolFailed'
            return $null
        }
    }
}
