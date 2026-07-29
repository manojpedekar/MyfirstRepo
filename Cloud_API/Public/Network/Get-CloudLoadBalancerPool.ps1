function Get-CloudLoadBalancerPool {
    <#
    .SYNOPSIS
        Retrieves load balancer pool information.
    
    .DESCRIPTION
        Gets information about pools and their members for a specific load balancer.
        Can retrieve a specific pool or list all pools for the load balancer.
    
    .PARAMETER LoadBalancerId
        The unique identifier of the load balancer (mandatory).
    
    .PARAMETER PoolId
        The unique identifier of a specific pool (optional).
    
    .EXAMPLE
        PS> Get-CloudLoadBalancerPool -LoadBalancerId "lb-..."
        
        Lists all pools for the specified load balancer.
    
    .EXAMPLE
        PS> Get-CloudLoadBalancerPool -LoadBalancerId "lb-..." -PoolId "pool-..."
        
        Retrieves details for a specific pool.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('lbId')]
        [string]$LoadBalancerId,
        
        [Parameter(Mandatory=$false)]
        [Alias('id')]
        [string]$PoolId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($PoolId) {
            $path = "network/loadbalancers/$LoadBalancerId/pools/$PoolId"
        } else {
            $path = "network/loadbalancers/$LoadBalancerId/pools"
        }
        
        $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve load balancer pool(s): $($_.Exception.Message)"
        return $null
    }
}
