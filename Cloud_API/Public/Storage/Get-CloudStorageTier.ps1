function Get-CloudStorageTier {
    <#
    .SYNOPSIS
        Retrieves storage tier information.
    
    .DESCRIPTION
        Gets information about storage tiers. Can retrieve a specific tier by ID,
        or list all tiers in a deployment zone.
    
    .PARAMETER Id
        The unique identifier of the storage tier.
    
    .PARAMETER DeploymentZoneId
        The deployment zone ID to filter tiers by.
    
    .EXAMPLE
        PS> Get-CloudStorageTier -Id "tier-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for a specific storage tier.
    
    .EXAMPLE
        PS> Get-CloudStorageTier -DeploymentZoneId "deploymentzone-..."
        
        Lists all storage tiers in the specified deployment zone.
    
    .EXAMPLE
        PS> Get-CloudStorageTier
        
        Lists all storage tiers available.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('StorageTierId', 'TierId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$DeploymentZoneId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "storage/tiers/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{
                sort = 'name%2Casc'
            }
            if ($DeploymentZoneId) { $queryParams['deploymentZoneId'] = $DeploymentZoneId }
            
            $response = Invoke-CloudAPIRequest -Path 'storage/tiers' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve storage tier(s): $($_.Exception.Message)"
        return $null
    }
}
