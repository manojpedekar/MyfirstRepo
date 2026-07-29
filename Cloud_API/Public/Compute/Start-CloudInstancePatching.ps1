function Start-CloudInstancePatching {
    <#
    .SYNOPSIS
        Triggers patching for a cloud instance.
    
    .DESCRIPTION
        Initiates the patching process for a cloud instance. This can be used to
        apply patches outside the normal maintenance window or to force patching
        for instances not in a patching group.
    
    .PARAMETER InstanceId
        The unique identifier of the instance to patch. This parameter is mandatory.
    
    .PARAMETER PatchGroup
        The patching group to use for this patching operation.
    
    .PARAMETER Wait
        If specified, waits for the patching operation to complete before returning.
    
    .PARAMETER Async
        If specified, returns immediately after starting the patching operation.
        Returns the operation/job object for tracking.
    
    .EXAMPLE
        PS> Start-CloudInstancePatching -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Starts patching for the specified instance.
    
    .EXAMPLE
        PS> Start-CloudInstancePatching -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Wait
        
        Starts patching and waits for completion.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$InstanceId,
        
        [Parameter(Mandatory=$false)]
        [string]$PatchGroup,
        
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
            $body = @{}
            if ($PatchGroup) { $body['patchGroup'] = $PatchGroup }
            
            # Build invoke parameters
            $invokeParams = @{
                Path = "compute/instances/$InstanceId/patch"
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
            Write-Error "Failed to start patching: $($_.Exception.Message)"
            return $null
        }
    }
}
