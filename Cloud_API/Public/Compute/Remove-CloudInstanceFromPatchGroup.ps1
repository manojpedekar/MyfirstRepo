function Remove-CloudInstanceFromPatchGroup {
    <#
    .SYNOPSIS
        Removes an instance from its patch group.
    
    .DESCRIPTION
        Removes a cloud instance from its current patch group, stopping automatic
        patching for that instance. Supports ShouldProcess for safety.
    
    .PARAMETER InstanceId
        The unique identifier of the instance. This parameter is mandatory.
    
    .PARAMETER Force
        If specified, suppresses the confirmation prompt.
    
    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.
    
    .EXAMPLE
        PS> Remove-CloudInstanceFromPatchGroup -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Removes the instance from its patch group after confirmation.
    
    .EXAMPLE
        PS> Remove-CloudInstanceFromPatchGroup -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Force
        
        Removes the instance without confirmation.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$InstanceId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
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
            
            # Get current patch group for confirmation message
            $instance = Get-CloudInstance -Id $InstanceId
            $patchGroup = if ($instance.patchingGroup) { $instance.patchingGroup } else { "assigned patch group" }
            
            # Build confirmation message
            $target = "Instance: $($instance.name) from $patchGroup"
            $action = "Remove from Patch Group"
            
            if ($Force -or $PSCmdlet.ShouldProcess($target, $action)) {
                # Make API request
                $response = Invoke-CloudAPIRequest -Path "compute/instances/$InstanceId/patch-group" -Method 'DELETE' -Headers $headers
                
                Write-Verbose "Successfully removed instance $InstanceId from patch group"
                return $response
            }
        }
        catch {
            Write-Error "Failed to remove instance from patch group: $($_.Exception.Message)"
            return $null
        }
    }
}
