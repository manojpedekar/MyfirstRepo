function Scale-CloudKubernetesNodePool {
    <#
    .SYNOPSIS
        Scales a node pool in a Kubernetes cluster.
    
    .DESCRIPTION
        Scales a node pool to a specified number of nodes. This is a convenience
        function that wraps Set-CloudKubernetesNodePool for scaling operations.
        Supports waiting for the scaling operation to complete.
    
    .PARAMETER ClusterId
        The unique identifier of the Kubernetes cluster. Required.
    
    .PARAMETER PoolId
        The unique identifier of the node pool to scale. Required.
    
    .PARAMETER Count
        The target number of nodes. Required.
    
    .PARAMETER Wait
        If specified, waits for the scaling operation to complete.
    
    .PARAMETER Async
        If specified, returns immediately with the job object for async tracking.
    
    .EXAMPLE
        PS> Scale-CloudKubernetesNodePool -ClusterId "k8s-..." -PoolId "pool-..." -Count 5
        
        Scales the node pool to 5 nodes.
    
    .EXAMPLE
        PS> Scale-CloudKubernetesNodePool -ClusterId "k8s-..." -PoolId "pool-..." -Count 10 -Wait
        
        Scales the node pool to 10 nodes and waits for completion.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('ClusterId', 'KubernetesClusterId')]
        [string]$ClusterId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('NodePoolId', 'Id')]
        [string]$PoolId,
        
        [Parameter(Mandatory=$true)]
        [ValidateRange(0, 100)]
        [int]$Count,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    process {
        try {
            # Get pool for confirmation message
            $pool = Get-CloudKubernetesNodePool -ClusterId $ClusterId -PoolId $PoolId
            $poolName = if ($pool) { $pool.name } else { $PoolId }
            
            if (-not $PSCmdlet.ShouldProcess("node pool '$poolName' ($PoolId) in cluster '$ClusterId' to $Count nodes", 'Scale')) {
                return $null
            }
            
            # Build request body
            $body = @{
                count = $Count
            }
            
            # Build invoke parameters
            $invokeParams = @{
                Path = "kubernetes/clusters/$ClusterId/nodepools/$PoolId/scale"
                Method = 'POST'
                Headers = (New-CloudAPIHeaders -IncludeContentType -IncludeAccept)
                Body = $body
            }
            
            if ($Wait) { $invokeParams['Wait'] = $true }
            if ($Async) { $invokeParams['Async'] = $true }
            
            # Make API request
            $response = Invoke-CloudAPIRequest @invokeParams
            
            return $response
        }
        catch {
            Write-Error "Failed to scale node pool: $($_.Exception.Message)"
            return $null
        }
    }
}
