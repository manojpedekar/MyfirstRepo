function Get-CloudScheduledTask {
    <#
    .SYNOPSIS
        Retrieves scheduled tasks from the cloud platform.
    
    .DESCRIPTION
        Gets scheduled tasks from the SS&C Cloud platform. Can retrieve a specific
        task by ID or list all tasks with optional filtering by resource type,
        resource ID, and status.
    
    .PARAMETER Id
        The unique identifier of the scheduled task to retrieve.
    
    .PARAMETER ResourceType
        Filter tasks by the type of resource they operate on.
    
    .PARAMETER ResourceId
        Filter tasks by the specific resource ID.
    
    .PARAMETER Status
        Filter tasks by status (e.g., 'ACTIVE', 'PAUSED', 'DISABLED').
    
    .EXAMPLE
        PS> Get-CloudScheduledTask
        
        Retrieves all scheduled tasks.
    
    .EXAMPLE
        PS> Get-CloudScheduledTask -Id "task-12345"
        
        Retrieves details for a specific scheduled task.
    
    .EXAMPLE
        PS> Get-CloudScheduledTask -ResourceType "Instance" -Status "ACTIVE"
        
        Retrieves all active tasks for instances.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('TaskId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceType,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceId,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('ACTIVE', 'PAUSED', 'DISABLED', 'ERROR')]
        [string]$Status
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # Build query parameters
            $queryParams = @{
                sort = 'name,asc'
            }
            
            if ($ResourceType) { $queryParams['resourceType'] = $ResourceType }
            if ($ResourceId) { $queryParams['resourceId'] = $ResourceId }
            if ($Status) { $queryParams['status'] = $Status }
            
            # Determine path
            if ($Id) {
                $path = "tasks/$Id"
            } else {
                $path = 'tasks'
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve scheduled task(s): $($_.Exception.Message)"
            return $null
        }
    }
}
