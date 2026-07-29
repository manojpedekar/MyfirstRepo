function Remove-CloudLoadBalancerPoolMember {
    <#
    .SYNOPSIS
        Removes a member from a load balancer pool.
    
    .DESCRIPTION
        Removes a member from an existing load balancer pool.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER LoadBalancerId
        The unique identifier of the load balancer (mandatory).
    
    .PARAMETER PoolId
        The unique identifier of the pool (mandatory).
    
    .PARAMETER MemberId
        The unique identifier of the member to remove (mandatory).
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudLoadBalancerPoolMember -LoadBalancerId "lb-..." -PoolId "pool-..." -MemberId "member-..." -Force
        
        Removes the member without confirmation.
    
    .OUTPUTS
        PSCustomObject or $null. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('lbId')]
        [string]$LoadBalancerId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('id')]
        [string]$PoolId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$MemberId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("member '$MemberId' from pool '$PoolId'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $response = Invoke-CloudAPIRequest -Path "network/loadbalancers/$LoadBalancerId/pools/$PoolId/members/$MemberId" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove pool member: $($_.Exception.Message)"
        return $null
    }
}
