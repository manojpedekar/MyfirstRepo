function Remove-CloudAlert {
    <#
    .SYNOPSIS
        Deletes an alert rule.
    
    .DESCRIPTION
        Permanently deletes an alert rule from the cloud platform.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the alert rule to delete. Required.
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudAlert -Id "alert-123" -Force
        
        Deletes the alert rule without confirmation.
    
    .OUTPUTS
        PSCustomObject or $null. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('AlertId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Confirm action
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("alert rule '$Id'", 'Remove')) {
                return $null
            }
            
            $headers = New-CloudAPIHeaders -IncludeContentType
            
            $response = Invoke-CloudAPIRequest -Path "alerts/$Id" -Method 'DELETE' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to remove alert rule: $($_.Exception.Message)"
            return $null
        }
    }
}
