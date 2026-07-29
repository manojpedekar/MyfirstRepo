function Move-CloudInstance {
    <#
    .SYNOPSIS
        Moves an instance to a different location.
    
    .DESCRIPTION
        Moves a cloud instance to a different sub-project or deployment zone.
        This operation may require the instance to be powered off.
    
    .PARAMETER Id
        The unique identifier of the instance to move. This parameter is mandatory.
    
    .PARAMETER TargetSubprojectId
        The target sub-project ID where the instance will be moved.
    
    .PARAMETER TargetDeploymentZoneId
        The target deployment zone ID where the instance will be moved.
    
    .PARAMETER Wait
        If specified, waits for the move operation to complete before returning.
    
    .PARAMETER Async
        If specified, returns immediately after starting the move operation.
        Returns the operation/job object for tracking.
    
    .EXAMPLE
        PS> Move-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -TargetSubprojectId "subproject-..."
        
        Moves the instance to a different sub-project.
    
    .EXAMPLE
        PS> Move-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -TargetDeploymentZoneId "deploymentzone-..." -Wait
        
        Moves the instance to a different deployment zone and waits for completion.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('InstanceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$TargetSubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$TargetDeploymentZoneId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            
            # Validate instance exists
            $instance = Get-CloudInstance -Id $Id
            if (-not $instance) {
                Write-Error "Instance '$Id' not found"
                return $null
            }
            
            # Validate at least one target is specified
            if (-not $TargetSubprojectId -and -not $TargetDeploymentZoneId) {
                Write-Error "Either TargetSubprojectId or TargetDeploymentZoneId must be specified"
                return $null
            }
            
            # Build request body
            $body = @{}
            if ($TargetSubprojectId) { $body['targetSubprojectId'] = $TargetSubprojectId }
            if ($TargetDeploymentZoneId) { $body['targetDeploymentZoneId'] = $TargetDeploymentZoneId }
            
            # Build invoke parameters
            $invokeParams = @{
                Path = "compute/instances/$Id/move"
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
            Write-Error "Failed to move instance: $($_.Exception.Message)"
            return $null
        }
    }
}
