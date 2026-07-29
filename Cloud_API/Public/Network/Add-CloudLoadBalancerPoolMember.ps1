function Add-CloudLoadBalancerPoolMember {
    <#
    .SYNOPSIS
        Adds a member to a load balancer pool.
    
    .DESCRIPTION
        Adds a new member (instance or IP address) to an existing load balancer pool.
        Can specify either an instance ID or IP address with port.
    
    .PARAMETER LoadBalancerId
        The unique identifier of the load balancer (mandatory).
    
    .PARAMETER PoolId
        The unique identifier of the pool (mandatory).
    
    .PARAMETER InstanceId
        The instance ID to add as a member.
    
    .PARAMETER IPAddress
        The IP address to add as a member.
    
    .PARAMETER Port
        The port number for the member (mandatory when using IPAddress).
    
    .PARAMETER Weight
        The weight of the member for load distribution (default: 1).
    
    .EXAMPLE
        PS> Add-CloudLoadBalancerPoolMember -LoadBalancerId "lb-..." -PoolId "pool-..." -InstanceId "instance-..."
        
        Adds an instance as a pool member.
    
    .EXAMPLE
        PS> Add-CloudLoadBalancerPoolMember -LoadBalancerId "lb-..." -PoolId "pool-..." -IPAddress "10.0.0.5" -Port 80 -Weight 2
        
        Adds an IP address as a pool member with weight 2.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('lbId')]
        [string]$LoadBalancerId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('id')]
        [string]$PoolId,
        
        [Parameter(Mandatory=$false)]
        [string]$InstanceId,
        
        [Parameter(Mandatory=$false)]
        [string]$IPAddress,
        
        [Parameter(Mandatory=$false)]
        [int]$Port,
        
        [Parameter(Mandatory=$false)]
        [int]$Weight = 1
    )
    
    try {
        # Validate that either InstanceId or IPAddress is provided
        if (-not $InstanceId -and -not $IPAddress) {
            Write-Error "Either InstanceId or IPAddress must be specified."
            return $null
        }
        
        if ($IPAddress -and -not $Port) {
            Write-Error "Port is required when specifying IPAddress."
            return $null
        }
        
        if (-not $PSCmdlet.ShouldProcess("member to pool '$PoolId' in load balancer '$LoadBalancerId'", 'Add')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $body = @{
            weight = $Weight
        }
        
        if ($InstanceId) {
            $body['instanceId'] = $InstanceId
        }
        
        if ($IPAddress) {
            $body['ipAddress'] = $IPAddress
            $body['port'] = $Port
        }
        
        $response = Invoke-CloudAPIRequest -Path "network/loadbalancers/$LoadBalancerId/pools/$PoolId/members" -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to add pool member: $($_.Exception.Message)"
        return $null
    }
}
