function Get-CloudStoragePool {
    <#
    .SYNOPSIS
        Retrieves storage pool information.
    
    .DESCRIPTION
        Gets information about storage pools. Can retrieve a specific pool by ID,
        or list all pools in a deployment zone or sub-project.
    
    .PARAMETER Id
        The unique identifier of the storage pool.
    
    .PARAMETER DeploymentZoneId
        The deployment zone ID to filter pools by.
    
    .PARAMETER SubprojectId
        The sub-project ID to filter pools by.
    
    .EXAMPLE
        PS> Get-CloudStoragePool -Id "pool-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for a specific storage pool.
    
    .EXAMPLE
        PS> Get-CloudStoragePool -DeploymentZoneId "deploymentzone-..."
        
        Lists all storage pools in the specified deployment zone.
    
    .EXAMPLE
        PS> Get-CloudStoragePool -SubprojectId "subproject-..."
        
        Lists all storage pools available to the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('StoragePoolId', 'PoolId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$DeploymentZoneId,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "storage/pools/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{
                sort = 'name%2Casc'
            }
            if ($DeploymentZoneId) { $queryParams['deploymentZoneId'] = $DeploymentZoneId }
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            
            $response = Invoke-CloudAPIRequest -Path 'storage/pools' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve storage pool(s): $($_.Exception.Message)"
        return $null
    }
}
