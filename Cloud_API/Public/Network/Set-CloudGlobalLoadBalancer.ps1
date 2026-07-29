function Set-CloudGlobalLoadBalancer {
    <#
    .SYNOPSIS
        Updates a global load balancer.
    
    .DESCRIPTION
        Updates an existing global load balancer's configuration.
    
    .PARAMETER Id
        The unique identifier of the global load balancer (mandatory).
    
    .PARAMETER Name
        The new name for the global load balancer.
    
    .PARAMETER FQDN
        The new fully qualified domain name.
    
    .EXAMPLE
        PS> Set-CloudGlobalLoadBalancer -Id "glb-..." -Name "updated-glb" -FQDN "new.example.com"
        
        Updates the global load balancer name and FQDN.
    
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
        [Alias('GlobalLoadBalancerId', 'GLBId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$FQDN
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("global load balancer '$Id'", 'Update')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $body = @{}
        if ($Name) { $body['name'] = $Name }
        if ($FQDN) { $body['fqdn'] = $FQDN }
        
        if ($body.Count -eq 0) {
            Write-Warning "No parameters to update specified."
            return $null
        }
        
        $response = Invoke-CloudAPIRequest -Path "network/global-loadbalancers/$Id" -Method 'PUT' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to update global load balancer: $($_.Exception.Message)"
        return $null
    }
}
