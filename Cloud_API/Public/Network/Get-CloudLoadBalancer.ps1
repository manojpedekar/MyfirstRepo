function Get-CloudLoadBalancer {
    <#
    .SYNOPSIS
        Retrieves load balancer information.
    
    .DESCRIPTION
        Gets information about load balancers. Can retrieve a specific load balancer
        by ID or list all load balancers within a sub-project or project.
        Returns load balancer details including FQDN, pools, health checks, and configuration.
        
        NOTES: Requesting single load balancer information will return more detailed 
        results including pool configurations and health check settings.
    
    .PARAMETER Id
        The unique identifier of the load balancer.
    
    .PARAMETER SubprojectId
        The sub-project ID to list load balancers from.
    
    .PARAMETER ProjectId
        The project ID to list load balancers from.
    
    .EXAMPLE
        PS> Get-CloudLoadBalancer -Id "lb-00000000-0000-0000-0000-000000000000"
        
        Retrieves details for a specific load balancer.
    
    .EXAMPLE
        PS> Get-CloudLoadBalancer -SubprojectId "subproject-..."
        
        Lists all load balancers in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('LoadBalancerId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/loadbalancers/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            elseif ($ProjectId) { $queryParams['projectId'] = $ProjectId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/loadbalancers' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve load balancer(s): $($_.Exception.Message)"
        return $null
    }
}
