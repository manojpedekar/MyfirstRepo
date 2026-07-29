function Get-CloudImageGroupDetail {
    <#
    .SYNOPSIS
        Retrieves detailed information about a specific image group.
    
    .DESCRIPTION
        Gets comprehensive details about an image group, including all images within
        the group. This provides more detailed information than Get-CloudImageGroup.
    
    .PARAMETER Id
        The unique identifier of the image group.
    
    .PARAMETER IncludeImages
        If specified, includes all images within the group in the response.
    
    .EXAMPLE
        PS> Get-CloudImageGroupDetail -Id "ig-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        
        Gets detailed information about the specified image group.
    
    .EXAMPLE
        PS> Get-CloudImageGroupDetail -Id "ig-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73" -IncludeImages
        
        Gets detailed information including all images in the group.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('ImageGroupId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$IncludeImages
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders
            
            # Get image group details
            $path = "compute/image-groups/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
            
            if (-not $response) {
                return $null
            }
            
            # Include images if requested
            if ($IncludeImages) {
                $images = Get-CloudImage -ImageGroupId $Id
                if ($images) {
                    $response | Add-Member -NotePropertyName 'images' -NotePropertyValue $images -Force
                }
            }
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve image group details: $($_.Exception.Message)"
            return $null
        }
    }
}
