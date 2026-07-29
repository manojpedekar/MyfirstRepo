function Remove-CloudScheduledTask {
    <#
    .SYNOPSIS
        Deletes a scheduled task.
    
    .DESCRIPTION
        Permanently deletes a scheduled task from the cloud platform.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the scheduled task to delete. Required.
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudScheduledTask -Id "task-123" -Force
        
        Deletes the scheduled task without confirmation.
    
    .OUTPUTS
        PSCustomObject or $null. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('TaskId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Confirm action
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("scheduled task '$Id'", 'Remove')) {
                return $null
            }
            
            $headers = New-CloudAPIHeaders -IncludeContentType
            
            $response = Invoke-CloudAPIRequest -Path "tasks/$Id" -Method 'DELETE' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to remove scheduled task: $($_.Exception.Message)"
            return $null
        }
    }
}
