function Get-CloudIPPool {
    <#
    .SYNOPSIS
        Retrieves IP pools.
    
    .DESCRIPTION
        Gets IP pool information.
        Can retrieve a specific IP pool by ID or list all pools for a sub-project or deployment zone.
    
    .PARAMETER Id
        The unique identifier of the IP pool.
    
    .PARAMETER SubprojectId
        The sub-project ID to list IP pools from.
    
    .PARAMETER DeploymentZoneId
        The deployment zone ID to list IP pools from.
    
    .EXAMPLE
        PS> Get-CloudIPPool -Id "ippool-..."
        
        Retrieves details for a specific IP pool.
    
    .EXAMPLE
        PS> Get-CloudIPPool -SubprojectId "subproject-..."
        
        Lists all IP pools in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('IPPoolId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$DeploymentZoneId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/ip-pools/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            elseif ($DeploymentZoneId) { $queryParams['deploymentZoneId'] = $DeploymentZoneId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/ip-pools' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve IP pool(s): $($_.Exception.Message)"
        return $null
    }
}
