function New-CloudScheduledTask {
    <#
    .SYNOPSIS
        Creates a new scheduled task.
    
    .DESCRIPTION
        Creates a new scheduled task that performs actions on resources at
        specified intervals using cron expressions.
    
    .PARAMETER Name
        The name for the scheduled task. Required.
    
    .PARAMETER ResourceType
        The type of resource the task operates on. Required.
    
    .PARAMETER ResourceId
        The ID of the specific resource to operate on. Required.
    
    .PARAMETER Action
        The action to perform (e.g., 'backup', 'snapshot', 'restart').
    
    .PARAMETER Schedule
        The cron expression defining when the task runs (e.g., '0 0 * * *' for daily at midnight).
    
    .PARAMETER Wait
        If specified, waits for the task creation to complete.
    
    .EXAMPLE
        PS> New-CloudScheduledTask -Name "Daily Backup" -ResourceType "Instance" `
             -ResourceId "i-12345" -Action "backup" -Schedule "0 2 * * *"
        
        Creates a daily backup task at 2 AM.
    
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
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceType,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceId,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('backup', 'snapshot', 'restart', 'stop', 'start', 'patch', 'script')]
        [string]$Action,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Schedule,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    try {
        # Build request body
        $body = @{
            name = $Name
            resourceType = $ResourceType
            resourceId = $ResourceId
        }
        
        if ($Action) { $body['action'] = $Action }
        if ($Schedule) { $body['schedule'] = $Schedule }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path 'tasks' -Method 'POST' -Headers $headers -Body $body -Wait:$Wait
        
        return $response
    }
    catch {
        Write-Error "Failed to create scheduled task: $($_.Exception.Message)"
        return $null
    }
}
