function Remove-CloudGlobalLoadBalancer {
    <#
    .SYNOPSIS
        Deletes a global load balancer.
    
    .DESCRIPTION
        Permanently deletes a global/multi-region load balancer.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the global load balancer (mandatory).
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudGlobalLoadBalancer -Id "glb-..." -Force
        
        Deletes the global load balancer without confirmation.
    
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
        [Alias('GlobalLoadBalancerId', 'GLBId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("global load balancer '$Id'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $response = Invoke-CloudAPIRequest -Path "network/global-loadbalancers/$Id" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove global load balancer: $($_.Exception.Message)"
        return $null
    }
}
