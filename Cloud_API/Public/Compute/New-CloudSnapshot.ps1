function New-CloudSnapshot {
    <#
    .SYNOPSIS
        Creates a new snapshot of an instance.
    
    .DESCRIPTION
        Creates a point-in-time snapshot of a cloud instance. The instance can be
        running or stopped when the snapshot is created.
    
    .PARAMETER InstanceId
        The unique identifier of the instance to snapshot. This parameter is mandatory.
    
    .PARAMETER Name
        A descriptive name for the snapshot.
    
    .PARAMETER Description
        A description of the snapshot.
    
    .PARAMETER Wait
        If specified, waits for the snapshot creation to complete before returning.
    
    .PARAMETER Async
        If specified, returns immediately after starting the snapshot creation.
        Returns the operation/job object for tracking.
    
    .EXAMPLE
        PS> New-CloudSnapshot -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Name "Pre-Update-Backup"
        
        Creates a new snapshot of the specified instance.
    
    .EXAMPLE
        PS> New-CloudSnapshot -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Name "Backup" -Description "Weekly backup" -Wait
        
        Creates a snapshot and waits for it to complete.
    
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
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$Description,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
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
                instanceId = $InstanceId
            }
            
            if ($Name) { $body['name'] = $Name }
            if ($Description) { $body['description'] = $Description }
            
            # Build invoke parameters
            $invokeParams = @{
                Path = "compute/instances/$InstanceId/snapshots"
                Method = 'POST'
                Headers = $headers
                Body = $body
            }
            
            if ($Wait) { $invokeParams['Wait'] = $true }
            if ($Async) { $invokeParams['Async'] = $true }
            
            # Make API request
            $response = Invoke-CloudAPIRequest @invokeParams
            
            return $response
        }
        catch {
            Write-Error "Failed to create snapshot: $($_.Exception.Message)"
            return $null
        }
    }
}
