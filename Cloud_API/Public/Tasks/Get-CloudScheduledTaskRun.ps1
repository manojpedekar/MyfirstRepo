function Get-CloudScheduledTaskRun {
    <#
    .SYNOPSIS
        Retrieves task run history.
    
    .DESCRIPTION
        Gets the execution history of scheduled tasks, including status,
        start/end times, and output.
    
    .PARAMETER TaskId
        The ID of the scheduled task to get run history for.
    
    .PARAMETER RunId
        The ID of a specific run to retrieve.
    
    .EXAMPLE
        PS> Get-CloudScheduledTaskRun -TaskId "task-123"
        
        Retrieves all run history for the task.
    
    .EXAMPLE
        PS> Get-CloudScheduledTaskRun -TaskId "task-123" -RunId "run-456"
        
        Retrieves details for a specific task run.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$TaskId,
        
        [Parameter(Mandatory=$false)]
        [string]$RunId
    )
    
    try {
        # Build query parameters
        $queryParams = @{
            sort = 'startTime,desc'
        }
        
        # Determine path
        if ($TaskId -and $RunId) {
            $path = "tasks/$TaskId/runs/$RunId"
        } elseif ($TaskId) {
            $path = "tasks/$TaskId/runs"
        } else {
            $path = 'tasks/runs'
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders
        $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve task run history: $($_.Exception.Message)"
        return $null
    }
}
