function Get-CloudLoadBalancerHealthCheck {
    <#
    .SYNOPSIS
        Retrieves load balancer health check configuration.
    
    .DESCRIPTION
        Gets the health check configuration for a specific load balancer.
        Returns details about the health check protocol, port, interval, timeout, and thresholds.
    
    .PARAMETER LoadBalancerId
        The unique identifier of the load balancer (mandatory).
    
    .EXAMPLE
        PS> Get-CloudLoadBalancerHealthCheck -LoadBalancerId "lb-..."
        
        Retrieves health check configuration for the specified load balancer.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('lbId')]
        [string]$LoadBalancerId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $path = "network/loadbalancers/$LoadBalancerId/healthcheck"
        
        $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve health check configuration: $($_.Exception.Message)"
        return $null
    }
}
