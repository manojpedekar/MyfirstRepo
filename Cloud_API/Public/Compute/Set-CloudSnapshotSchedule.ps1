function Set-CloudSnapshotSchedule {
    <#
    .SYNOPSIS
        Configures automatic snapshot schedules for an instance.
    
    .DESCRIPTION
        Sets up automatic snapshot creation schedules for a cloud instance.
        Supports multiple schedules with different frequencies and retention policies.
    
    .PARAMETER InstanceId
        The unique identifier of the instance. This parameter is mandatory.
        Accepts pipeline input.
    
    .PARAMETER Schedule
        A hashtable or array of hashtables defining the schedule(s).
        Each schedule should include:
        - frequency: The snapshot frequency (e.g., "DAILY", "WEEKLY", "HOURLY")
        - retention: Number of snapshots to retain
        - hour (optional): Hour of day for the snapshot (0-23)
        - dayOfWeek (optional): Day of week for weekly snapshots (0-6, where 0 is Sunday)
    
    .PARAMETER Enabled
        Enable or disable the snapshot schedule.
    
    .PARAMETER Wait
        If specified, waits for the configuration to be applied.
    
    .EXAMPLE
        PS> Set-CloudSnapshotSchedule -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Schedule @{
            frequency = "DAILY"
            retention = 7
            hour = 2
        }
        
        Configures a daily snapshot at 2 AM with 7-day retention.
    
    .EXAMPLE
        PS> Set-CloudSnapshotSchedule -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Enabled $false
        
        Disables automatic snapshots for the instance.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('InstanceId', 'Id')]
        [string]$InstanceId,
        
        [Parameter(Mandatory=$false)]
        [object]$Schedule,
        
        [Parameter(Mandatory=$false)]
        [bool]$Enabled = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            
            # Validate instance exists
            $instanceExists = Test-CloudAPIResource -ResourceType 'compute/instances' -ResourceId $InstanceId
            if (-not $instanceExists) {
                Write-Error "Instance '$InstanceId' not found"
                return $null
            }
            
            # Build request body
            $body = @{
                enabled = $Enabled
            }
            
            if ($Schedule) {
                $body['schedules'] = $Schedule
            }
            
            # Build invoke parameters
            $invokeParams = @{
                Path = "compute/instances/$InstanceId/snapshot-schedules"
                Method = 'PUT'
                Headers = $headers
                Body = $body
            }
            
            if ($Wait) { $invokeParams['Wait'] = $true }
            
            # Make API request
            $response = Invoke-CloudAPIRequest @invokeParams
            
            return $response
        }
        catch {
            Write-Error "Failed to configure snapshot schedule: $($_.Exception.Message)"
            return $null
        }
    }
}
