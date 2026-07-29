function Get-CloudTag {
    <#
    .SYNOPSIS
        Retrieves tags from the cloud platform.
    
    .DESCRIPTION
        Gets tags from the SS&C Cloud platform. Can retrieve a specific tag
        by ID or list all tags with optional filtering by key, resource type,
        and resource ID.
    
    .PARAMETER Id
        The unique identifier of the tag to retrieve.
    
    .PARAMETER Key
        Filter tags by key name (e.g., 'Environment', 'Owner').
    
    .PARAMETER ResourceType
        Filter tags by the type of resource they are applied to.
    
    .PARAMETER ResourceId
        Filter tags by the specific resource ID they are applied to.
    
    .EXAMPLE
        PS> Get-CloudTag
        
        Retrieves all tags.
    
    .EXAMPLE
        PS> Get-CloudTag -Id "tag-12345"
        
        Retrieves details for a specific tag.
    
    .EXAMPLE
        PS> Get-CloudTag -Key 'Environment' -ResourceType 'Instance'
        
        Retrieves all Environment tags applied to instances.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('TagId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Key,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceType,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceId
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # Build query parameters
            $queryParams = @{
                sort = 'key,asc'
            }
            
            if ($Key) { $queryParams['key'] = $Key }
            if ($ResourceType) { $queryParams['resourceType'] = $ResourceType }
            if ($ResourceId) { $queryParams['resourceId'] = $ResourceId }
            
            # Determine path
            if ($Id) {
                $path = "tags/$Id"
            } else {
                $path = 'tags'
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve tag(s): $($_.Exception.Message)"
            return $null
        }
    }
}
