function Get-CloudImageGroup {
    <#
    .SYNOPSIS
        Retrieves image group information.
    
    .DESCRIPTION
        Gets information about image groups and their associated images in the cloud.
        Can retrieve all image groups for a project or detailed images for a specific group.
    
    .PARAMETER ProjectId
        The project ID to list image groups for.
    
    .PARAMETER ImageGroupId
        The image group ID to get detailed images for.
    
    .EXAMPLE
        PS> Get-CloudImageGroup -ProjectId "project-84193807-a81d-4b9b-895b-6c8d8292b55a"
        
        Lists all image groups in the specified project.
    
    .EXAMPLE
        PS> Get-CloudImageGroup -ImageGroupId "imagegroup-00000000-0000-0000-0000-0000000000000"
        
        Gets detailed images for the specified image group.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ProjectId,
        
        [Parameter(Mandatory=$false)]
        [string]$ImageGroupId
    )
    
    try {
        $headers = New-CloudAPIHeaders
        
        if ($ImageGroupId) {
            $path = "compute/imagegroups/$ImageGroupId/images"
        } elseif ($ProjectId) {
            $queryParams = @{
                projectId = $ProjectId
                sort = 'asc'
            }
            $response = Invoke-CloudAPIRequest -Path 'compute/imagegroups' -Method 'GET' -Headers $headers -QueryParameters $queryParams
            return $response
        } else {
            $response = Invoke-CloudAPIRequest -Path 'compute/imagegroups' -Method 'GET' -Headers $headers
            return $response
        }
        
        $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        return $response
    }
    catch {
        Write-Error "Failed to retrieve image group(s): $($_.Exception.Message)"
        return $null
    }
}
