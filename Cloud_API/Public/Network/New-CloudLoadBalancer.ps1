function New-CloudLoadBalancer {
    <#
    .SYNOPSIS
        Creates a new load balancer.
    
    .DESCRIPTION
        Creates a new load balancer within a specified sub-project.
        Supports -Wait switch to wait for the load balancer to be fully provisioned.
    
    .PARAMETER Name
        The name of the load balancer (mandatory).
    
    .PARAMETER SubprojectId
        The sub-project ID where the load balancer will be created (mandatory).
    
    .PARAMETER Type
        The type of load balancer (e.g., 'layer4', 'layer7').
    
    .PARAMETER Ports
        The ports to listen on (e.g., 80, 443).
    
    .PARAMETER Protocol
        The protocol to use (e.g., 'TCP', 'UDP', 'HTTP', 'HTTPS').
    
    .PARAMETER Wait
        Wait for the load balancer to be fully provisioned before returning.
    
    .EXAMPLE
        PS> New-CloudLoadBalancer -Name "web-lb" -SubprojectId "subproject-..." -Ports 80,443 -Protocol "HTTP"
        
        Creates a new layer 7 load balancer.
    
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
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('layer4', 'layer7')]
        [string]$Type = 'layer7',
        
        [Parameter(Mandatory=$false)]
        [int[]]$Ports = @(80),
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('TCP', 'UDP', 'HTTP', 'HTTPS')]
        [string]$Protocol = 'HTTP',
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("load balancer '$Name' in subproject '$SubprojectId'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $body = @{
            name = $Name
            subprojectId = $SubprojectId
            type = $Type
            ports = $Ports
            protocol = $Protocol
        }
        
        $response = Invoke-CloudAPIRequest -Path 'network/loadbalancers' -Method 'POST' -Headers $headers -Body $body -Wait:$Wait
        
        return $response
    }
    catch {
        Write-Error "Failed to create load balancer: $($_.Exception.Message)"
        return $null
    }
}
