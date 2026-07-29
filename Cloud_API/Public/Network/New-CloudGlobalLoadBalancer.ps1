function New-CloudGlobalLoadBalancer {
    <#
    .SYNOPSIS
        Creates a new global load balancer.
    
    .DESCRIPTION
        Creates a new global/multi-region load balancer for distributing traffic across multiple regions.
    
    .PARAMETER Name
        The name of the global load balancer (mandatory).
    
    .PARAMETER ProjectId
        The project ID where the global load balancer will be created (mandatory).
    
    .PARAMETER FQDN
        The fully qualified domain name for the global load balancer (mandatory).
    
    .EXAMPLE
        PS> New-CloudGlobalLoadBalancer -Name "global-web-lb" -ProjectId "project-..." -FQDN "global.example.com"
        
        Creates a new global load balancer.
    
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
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$FQDN
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("global load balancer '$Name' in project '$ProjectId'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $body = @{
            name = $Name
            projectId = $ProjectId
            fqdn = $FQDN
        }
        
        $response = Invoke-CloudAPIRequest -Path 'network/global-loadbalancers' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create global load balancer: $($_.Exception.Message)"
        return $null
    }
}
