function Set-CloudTag {
    <#
    .SYNOPSIS
        Updates the value of an existing tag.
    
    .DESCRIPTION
        Updates the value of an existing tag. Only the value can be changed;
        to change the key, you must remove and recreate the tag.
    
    .PARAMETER Id
        The unique identifier of the tag to update. Required.
    
    .PARAMETER Value
        The new value for the tag. Required.
    
    .EXAMPLE
        PS> Set-CloudTag -Id "tag-123" -Value "Staging"
        
        Updates the tag value to "Staging".
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('TagId')]
        [string]$Id,
        
        [Parameter(Mandatory=$true)]
        [string]$Value
    )
    
    process {
        try {
            # Build request body
            $body = @{
                value = $Value
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType
            $response = Invoke-CloudAPIRequest -Path "tags/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            return $response
        }
        catch {
            Write-Error -Message "Failed to update tag: $($_.Exception.Message)" -ErrorId 'SetCloudTagFailed'
            return $null
        }
    }
}
