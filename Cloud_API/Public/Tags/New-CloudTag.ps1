function New-CloudTag {
    <#
    .SYNOPSIS
        Creates a new tag or applies an existing tag to resources.
    
    .DESCRIPTION
        Creates a new tag with the specified key and value, and optionally
        applies it to one or more resources. Can be used to tag multiple
        resources at once.
    
    .PARAMETER Key
        The tag key. Required.
    
    .PARAMETER Value
        The tag value.
    
    .PARAMETER ResourceType
        The type of resource to tag.
    
    .PARAMETER ResourceId
        The ID of the resource to tag. Can accept multiple IDs via pipeline.
    
    .EXAMPLE
        PS> New-CloudTag -Key "Environment" -Value "Production"
        
        Creates a new tag without applying it to any resource.
    
    .EXAMPLE
        PS> New-CloudTag -Key "Environment" -Value "Production" `
             -ResourceType "Instance" -ResourceId "i-12345"
        
        Creates a tag and applies it to a specific instance.
    
    .EXAMPLE
        PS> Get-CloudInstance -ProjectId "proj-123" | New-CloudTag `
             -Key "Project" -Value "Alpha"
        
        Tags all instances in a project.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,
        
        [Parameter(Mandatory=$false)]
        [string]$Value,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceType,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('Id')]
        [string]$ResourceId
    )
    
    begin {
        $headers = New-CloudAPIHeaders -IncludeContentType
        $results = @()
    }
    
    process {
        try {
            # Build request body
            $body = @{
                key = $Key
            }
            
            if ($PSBoundParameters.ContainsKey('Value')) { $body['value'] = $Value }
            if ($ResourceType) { $body['resourceType'] = $ResourceType }
            if ($ResourceId) { $body['resourceId'] = $ResourceId }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path 'tags' -Method 'POST' -Headers $headers -Body $body
            
            if ($response) {
                $results += $response
            }
        }
        catch {
            Write-Error -Message "Failed to create tag: $($_.Exception.Message)" -ErrorId 'NewCloudTagFailed'
        }
    }
    
    end {
        if ($results.Count -eq 1) {
            return $results[0]
        } elseif ($results.Count -gt 1) {
            return $results
        } else {
            return $null
        }
    }
}
