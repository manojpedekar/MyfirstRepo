function Get-CloudResourceTag {
    <#
    .SYNOPSIS
        Retrieves all tags for a specific resource.
    
    .DESCRIPTION
        Gets all tags that are applied to a specific resource, identified by
        its type and ID.
    
    .PARAMETER ResourceType
        The type of the resource. Required.
    
    .PARAMETER ResourceId
        The unique identifier of the resource. Required.
    
    .EXAMPLE
        PS> Get-CloudResourceTag -ResourceType "Instance" -ResourceId "i-12345"
        
        Retrieves all tags for the specified instance.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceType,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('Id')]
        [string]$ResourceId
    )
    
    try {
        # Make API request
        $headers = New-CloudAPIHeaders
        $response = Invoke-CloudAPIRequest -Path "resources/$ResourceType/$ResourceId/tags" -Method 'GET' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve resource tags: $($_.Exception.Message)"
        return $null
    }
}
