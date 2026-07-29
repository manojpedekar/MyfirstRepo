function Set-CloudAlert {
    <#
    .SYNOPSIS
        Updates an existing alert rule.
    
    .DESCRIPTION
        Updates the configuration of an existing alert rule, including name,
        threshold, and enabled status.
    
    .PARAMETER Id
        The unique identifier of the alert rule to update. Required.
    
    .PARAMETER Name
        The new name for the alert rule.
    
    .PARAMETER Threshold
        The new threshold value.
    
    .PARAMETER Enabled
        Whether the alert rule is enabled ($true) or disabled ($false).
    
    .EXAMPLE
        PS> Set-CloudAlert -Id "alert-123" -Threshold 90
        
        Updates the alert threshold to 90.
    
    .EXAMPLE
        PS> Set-CloudAlert -Id "alert-123" -Enabled $false
        
        Disables the alert rule.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('AlertId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(0, 100)]
        [int]$Threshold,
        
        [Parameter(Mandatory=$false)]
        [bool]$Enabled
    )
    
    process {
        try {
            # Build request body with only specified parameters
            $body = @{}
            
            if ($PSBoundParameters.ContainsKey('Name')) { $body['name'] = $Name }
            if ($PSBoundParameters.ContainsKey('Threshold')) { $body['threshold'] = $Threshold }
            if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = $Enabled }
            
            # Check if any parameters were provided
            if ($body.Count -eq 0) {
                Write-Warning "No parameters specified for update. Alert rule remains unchanged."
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType
            $response = Invoke-CloudAPIRequest -Path "alerts/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            return $response
        }
        catch {
            Write-Error "Failed to update alert rule: $($_.Exception.Message)"
            return $null
        }
    }
}
