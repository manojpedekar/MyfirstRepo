function Get-CloudGlobalLoadBalancer {
    <#
    .SYNOPSIS
        Retrieves global/multi-region load balancers.
    
    .DESCRIPTION
        Gets global load balancer information.
        Can retrieve a specific global load balancer by ID or list all global load balancers for a project.
    
    .PARAMETER Id
        The unique identifier of the global load balancer.
    
    .PARAMETER ProjectId
        The project ID to list global load balancers from.
    
    .EXAMPLE
        PS> Get-CloudGlobalLoadBalancer -Id "glb-..."
        
        Retrieves details for a specific global load balancer.
    
    .EXAMPLE
        PS> Get-CloudGlobalLoadBalancer -ProjectId "project-..."
        
        Lists all global load balancers in the specified project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('GlobalLoadBalancerId', 'GLBId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/global-loadbalancers/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($ProjectId) { $queryParams['projectId'] = $ProjectId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/global-loadbalancers' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve global load balancer(s): $($_.Exception.Message)"
        return $null
    }
}
