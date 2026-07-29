function Get-CloudSnapshotSchedule {
    <#
    .SYNOPSIS
        Retrieves snapshot schedules for an instance.
    
    .DESCRIPTION
        Gets the configured automatic snapshot schedules for a cloud instance.
        Schedules define when snapshots are automatically created and how long
        they are retained.
    
    .PARAMETER InstanceId
        The unique identifier of the instance. This parameter is mandatory.
    
    .EXAMPLE
        PS> Get-CloudSnapshotSchedule -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Gets snapshot schedules for the specified instance.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('InstanceId', 'Id')]
        [string]$InstanceId
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders
            
            # Validate instance exists
            $instanceExists = Test-CloudAPIResource -ResourceType 'compute/instances' -ResourceId $InstanceId
            if (-not $instanceExists) {
                Write-Error "Instance '$InstanceId' not found"
                return $null
            }
            
            # Get snapshot schedules
            $path = "compute/instances/$InstanceId/snapshot-schedules"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve snapshot schedule: $($_.Exception.Message)"
            return $null
        }
    }
}
