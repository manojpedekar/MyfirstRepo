function Set-CloudLoadBalancerHealthCheck {
    <#
    .SYNOPSIS
        Configures load balancer health checks.
    
    .DESCRIPTION
        Sets or updates the health check configuration for a load balancer.
        Defines how the load balancer checks the health of pool members.
    
    .PARAMETER LoadBalancerId
        The unique identifier of the load balancer (mandatory).
    
    .PARAMETER Protocol
        The health check protocol (e.g., 'TCP', 'HTTP', 'HTTPS').
    
    .PARAMETER Port
        The port to use for health checks.
    
    .PARAMETER Interval
        The interval between health checks in seconds.
    
    .PARAMETER Timeout
        The timeout for health check responses in seconds.
    
    .PARAMETER Threshold
        The number of consecutive failures before marking a member as unhealthy.
    
    .PARAMETER Path
        The URL path for HTTP/HTTPS health checks (e.g., '/health').
    
    .EXAMPLE
        PS> Set-CloudLoadBalancerHealthCheck -LoadBalancerId "lb-..." -Protocol "HTTP" -Port 80 -Interval 30 -Timeout 5 -Threshold 3 -Path "/health"
        
        Configures HTTP health checks on port 80.
    
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
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('TCP', 'HTTP', 'HTTPS')]
        [string]$Protocol,
        
        [Parameter(Mandatory=$false)]
        [int]$Port,
        
        [Parameter(Mandatory=$false)]
        [int]$Interval,
        
        [Parameter(Mandatory=$false)]
        [int]$Timeout,
        
        [Parameter(Mandatory=$false)]
        [int]$Threshold,
        
        [Parameter(Mandatory=$false)]
        [string]$Path
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("health check for load balancer '$LoadBalancerId'", 'Configure')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $body = @{}
        if ($Protocol) { $body['protocol'] = $Protocol }
        if ($Port) { $body['port'] = $Port }
        if ($Interval) { $body['interval'] = $Interval }
        if ($Timeout) { $body['timeout'] = $Timeout }
        if ($Threshold) { $body['threshold'] = $Threshold }
        if ($Path) { $body['path'] = $Path }
        
        if ($body.Count -eq 0) {
            Write-Warning "No health check parameters specified."
            return $null
        }
        
        $response = Invoke-CloudAPIRequest -Path "network/loadbalancers/$LoadBalancerId/healthcheck" -Method 'PUT' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to configure health check: $($_.Exception.Message)"
        return $null
    }
}
