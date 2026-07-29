function Get-CloudSnapshot {
    <#
    .SYNOPSIS
        Retrieves information about cloud snapshots.
    
    .DESCRIPTION
        Gets details about one or more snapshots. Can retrieve a specific snapshot
        by ID, or list all snapshots for an instance or sub-project.
    
    .PARAMETER Id
        The unique identifier of the snapshot to retrieve.
    
    .PARAMETER InstanceId
        Filter snapshots by instance ID.
    
    .PARAMETER SubprojectId
        Filter snapshots by sub-project ID.
    
    .PARAMETER CheckOnly
        If specified, tests if the snapshot exists and returns $true or $false.
    
    .EXAMPLE
        PS> Get-CloudSnapshot
        
        Lists all snapshots.
    
    .EXAMPLE
        PS> Get-CloudSnapshot -Id "snap-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Gets details for a specific snapshot.
    
    .EXAMPLE
        PS> Get-CloudSnapshot -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Lists all snapshots for the specified instance.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('SnapshotId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$InstanceId,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [switch]$CheckOnly
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # CheckOnly mode
            if ($CheckOnly) {
                if (-not $Id) {
                    Write-Error "CheckOnly parameter requires an Id to be specified"
                    return $null
                }
                return Test-CloudAPIResource -ResourceType 'compute/snapshots' -ResourceId $Id
            }
            
            # If instance ID is specified, use that endpoint
            if ($InstanceId -and -not $Id) {
                $path = "compute/instances/$InstanceId/snapshots"
                $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
                return $response
            }
            
            # Build query parameters for general snapshot query
            $queryParams = @{
                sort = 'createdDate,desc'
            }
            
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            
            # Determine path
            if ($Id) {
                $path = "compute/snapshots/$Id"
            } else {
                $path = "compute/snapshots"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve snapshot(s): $($_.Exception.Message)"
            return $null
        }
    }
}
