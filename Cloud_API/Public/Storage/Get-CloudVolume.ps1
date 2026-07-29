function Get-CloudVolume {
    <#
    .SYNOPSIS
        Retrieves cloud volume (disk) information.
    
    .DESCRIPTION
        Gets information about cloud volumes. Can retrieve a specific volume by ID
        or list all volumes within a sub-project.
        
        NOTES: Requesting single volume information will return more detailed results
        than getting them at the sub-project level or higher.
    
    .PARAMETER Id
        The unique identifier of the volume.
    
    .PARAMETER SubprojectId
        The sub-project ID to list volumes from.
    
    .EXAMPLE
        PS> Get-CloudVolume -Id "v-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for a specific volume.
    
    .EXAMPLE
        PS> Get-CloudVolume -SubprojectId "subproject-..."
        
        Lists all volumes in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('VolumeId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "storage/volumes/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{
                sort = 'name%2Casc'
            }
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            
            $response = Invoke-CloudAPIRequest -Path 'storage/volumes' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve volume(s): $($_.Exception.Message)"
        return $null
    }
}
