function Set-CloudScheduledTask {
    <#
    .SYNOPSIS
        Updates an existing scheduled task.
    
    .DESCRIPTION
        Updates the configuration of an existing scheduled task, including
        name, schedule, and enabled status.
    
    .PARAMETER Id
        The unique identifier of the scheduled task to update. Required.
    
    .PARAMETER Name
        The new name for the task.
    
    .PARAMETER Schedule
        The new cron expression schedule.
    
    .PARAMETER Enabled
        Whether the task is enabled ($true) or disabled ($false).
    
    .EXAMPLE
        PS> Set-CloudScheduledTask -Id "task-123" -Schedule "0 3 * * *"
        
        Updates the task to run at 3 AM instead.
    
    .EXAMPLE
        PS> Set-CloudScheduledTask -Id "task-123" -Enabled $false
        
        Disables the scheduled task.
    
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
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$Schedule,
        
        [Parameter(Mandatory=$false)]
        [bool]$Enabled
    )
    
    process {
        try {
            # Build request body with only specified parameters
            $body = @{}
            
            if ($PSBoundParameters.ContainsKey('Name')) { $body['name'] = $Name }
            if ($PSBoundParameters.ContainsKey('Schedule')) { $body['schedule'] = $Schedule }
            if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = $Enabled }
            
            # Check if any parameters were provided
            if ($body.Count -eq 0) {
                Write-Warning "No parameters specified for update. Task remains unchanged."
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType
            $response = Invoke-CloudAPIRequest -Path "tasks/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            return $response
        }
        catch {
            Write-Error "Failed to update scheduled task: $($_.Exception.Message)"
            return $null
        }
    }
}
