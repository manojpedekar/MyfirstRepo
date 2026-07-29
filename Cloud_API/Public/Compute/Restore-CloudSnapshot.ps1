function Restore-CloudSnapshot {
    <#
    .SYNOPSIS
        Restores an instance from a snapshot.
    
    .DESCRIPTION
        Restores an instance to the state captured in the specified snapshot.
        This operation typically overwrites the current instance state.
    
    .PARAMETER Id
        The unique identifier of the snapshot to restore from. This parameter is mandatory.
    
    .PARAMETER InstanceId
        The unique identifier of the instance to restore. If not specified, attempts
        to restore to the original instance.
    
    .PARAMETER Wait
        If specified, waits for the restore operation to complete before returning.
    
    .PARAMETER Async
        If specified, returns immediately after starting the restore operation.
        Returns the operation/job object for tracking.
    
    .EXAMPLE
        PS> Restore-CloudSnapshot -Id "snap-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Restores from the specified snapshot.
    
    .EXAMPLE
        PS> Restore-CloudSnapshot -Id "snap-55c319eb-5944-4d00-a927-02e2eff4430a" -Wait
        
        Restores and waits for the operation to complete.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('SnapshotId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$InstanceId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            
            # Validate snapshot exists
            $snapshot = Get-CloudSnapshot -Id $Id
            if (-not $snapshot) {
                Write-Error "Snapshot '$Id' not found"
                return $null
            }
            
            # Build request body
            $body = @{}
            if ($InstanceId) { $body['instanceId'] = $InstanceId }
            
            # Build invoke parameters
            $invokeParams = @{
                Path = "compute/snapshots/$Id/restore"
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
            Write-Error "Failed to restore snapshot: $($_.Exception.Message)"
            return $null
        }
    }
}
