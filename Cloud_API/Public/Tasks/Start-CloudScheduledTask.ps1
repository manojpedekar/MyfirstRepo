function Start-CloudScheduledTask {
    <#
    .SYNOPSIS
        Runs a scheduled task immediately.
    
    .DESCRIPTION
        Triggers a scheduled task to run immediately, regardless of its
        configured schedule. Useful for on-demand execution.
    
    .PARAMETER Id
        The unique identifier of the scheduled task to run. Required.
    
    .EXAMPLE
        PS> Start-CloudScheduledTask -Id "task-123"
        
        Runs the scheduled task immediately.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('TaskId')]
        [string]$Id
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType
            
            $response = Invoke-CloudAPIRequest -Path "tasks/$Id/run" -Method 'POST' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to start scheduled task: $($_.Exception.Message)"
            return $null
        }
    }
}
