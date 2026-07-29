function Get-CloudImage {
    <#
    .SYNOPSIS
        Retrieves information about cloud images.
    
    .DESCRIPTION
        Gets details about available images for creating instances. Can retrieve all images
        or filter by image group or project. When retrieving a specific image by ID, more
        detailed information is returned.
    
    .PARAMETER Id
        The unique identifier of the image to retrieve.
    
    .PARAMETER ImageGroupId
        Filter images by image group ID.
    
    .PARAMETER ProjectId
        Filter images available to a specific project.
    
    .PARAMETER CheckOnly
        If specified, tests if the image exists and returns $true or $false.
    
    .EXAMPLE
        PS> Get-CloudImage
        
        Lists all available images.
    
    .EXAMPLE
        PS> Get-CloudImage -Id "img-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Gets details for a specific image.
    
    .EXAMPLE
        PS> Get-CloudImage -ImageGroupId "ig-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        
        Lists all images in the specified image group.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('ImageId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$ImageGroupId,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId,
        
        [Parameter(Mandatory=$false)]
        [switch]$CheckOnly
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # CheckOnly mode
            if ($CheckOnly) {
                if (-not $Id) {
                    Write-Error "CheckOnly parameter requires an Id to be specified"
                    return $null
                }
                return Test-CloudAPIResource -ResourceType 'compute/images' -ResourceId $Id
            }
            
            # Build query parameters
            $queryParams = @{
                sort = 'name,asc'
            }
            
            if ($ImageGroupId) { $queryParams['imageGroupId'] = $ImageGroupId }
            if ($ProjectId) { $queryParams['projectId'] = $ProjectId }
            
            # Determine path
            if ($Id) {
                $path = "compute/images/$Id"
            } else {
                $path = "compute/images"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve image(s): $($_.Exception.Message)"
            return $null
        }
    }
}
