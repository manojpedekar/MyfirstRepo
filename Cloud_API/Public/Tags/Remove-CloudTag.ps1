function Remove-CloudTag {
    <#
    .SYNOPSIS
        Removes a tag from resources.
    
    .DESCRIPTION
        Removes a tag from specified resources or deletes the tag entirely
        if no resources are specified. Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the tag to remove. Required.
    
    .PARAMETER ResourceType
        The type of resource to remove the tag from.
    
    .PARAMETER ResourceId
        The ID of the resource to remove the tag from.
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudTag -Id "tag-123" -Force
        
        Deletes the tag entirely without confirmation.
    
    .EXAMPLE
        PS> Remove-CloudTag -Id "tag-123" -ResourceType "Instance" `
             -ResourceId "i-12345" -Force
        
        Removes the tag from a specific instance.
    
    .OUTPUTS
        PSCustomObject or $null. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('TagId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceType,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Build confirmation message
            $target = "tag '$Id'"
            if ($ResourceType -and $ResourceId) {
                $target = "tag '$Id' from $ResourceType '$ResourceId'"
            }
            
            # Confirm action
            if (-not $Force -and -not $PSCmdlet.ShouldProcess($target, 'Remove')) {
                return $null
            }
            
            # Build query parameters if removing from specific resource
            $queryParams = @{}
            if ($ResourceType) { $queryParams['resourceType'] = $ResourceType }
            if ($ResourceId) { $queryParams['resourceId'] = $ResourceId }
            
            $headers = New-CloudAPIHeaders -IncludeContentType
            
            $response = Invoke-CloudAPIRequest -Path "tags/$Id" -Method 'DELETE' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error -Message "Failed to remove tag: $($_.Exception.Message)" -ErrorId 'RemoveCloudTagFailed'
            return $null
        }
    }
}
