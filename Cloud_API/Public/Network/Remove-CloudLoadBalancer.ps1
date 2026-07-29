function Remove-CloudLoadBalancer {
    <#
    .SYNOPSIS
        Deletes a load balancer.
    
    .DESCRIPTION
        Permanently deletes a load balancer and all associated configuration.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the load balancer (mandatory).
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudLoadBalancer -Id "lb-..." -Force
        
        Deletes the load balancer without confirmation.
    
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
        [Alias('LoadBalancerId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        # Get resource name for better confirmation message
        $resource = Get-CloudLoadBalancer -Id $Id
        $resourceName = if ($resource) { $resource.name } else { $Id }
        
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("load balancer '$resourceName' ($Id)", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $response = Invoke-CloudAPIRequest -Path "network/loadbalancers/$Id" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove load balancer: $($_.Exception.Message)"
        return $null
    }
}
