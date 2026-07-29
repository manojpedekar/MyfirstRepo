function Get-CloudTier {
    <#
    .SYNOPSIS
        Retrieves network tiers.
    
    .DESCRIPTION
        Gets network tier information.
        Can retrieve a specific tier by ID or list all tiers for a deployment zone.
    
    .PARAMETER Id
        The unique identifier of the network tier.
    
    .PARAMETER DeploymentZoneId
        The deployment zone ID to list tiers from.
    
    .EXAMPLE
        PS> Get-CloudTier -Id "tier-..."
        
        Retrieves details for a specific network tier.
    
    .EXAMPLE
        PS> Get-CloudTier -DeploymentZoneId "zone-..."
        
        Lists all network tiers in the specified deployment zone.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('TierId', 'NetworkTierId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$DeploymentZoneId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/tiers/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($DeploymentZoneId) { $queryParams['deploymentZoneId'] = $DeploymentZoneId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/tiers' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve network tier(s): $($_.Exception.Message)"
        return $null
    }
}
