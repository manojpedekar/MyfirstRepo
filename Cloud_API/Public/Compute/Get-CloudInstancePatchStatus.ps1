function Get-CloudInstancePatchStatus {
    <#
    .SYNOPSIS
        Retrieves patching status for a cloud instance.
    
    .DESCRIPTION
        Gets the current patching status and schedule information for a cloud instance,
        including last patched date, next scheduled patch, and patching group membership.
    
    .PARAMETER InstanceId
        The unique identifier of the instance. This parameter is mandatory.
    
    .EXAMPLE
        PS> Get-CloudInstancePatchStatus -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Gets patching status for the specified instance.
    
    .OUTPUTS
        PSCustomObject with properties:
        - lastPatchedDate: Date/time of last patching
        - scheduledForPatching: Boolean indicating if patching is scheduled
        - patchingGroup: The patching group name/ID
        - nextPatchDate: Next scheduled patch date
        - patchStatus: Current patching status
        Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
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
            
            # Get patch status
            $path = "compute/instances/$InstanceId/patch-status"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve patch status: $($_.Exception.Message)"
            return $null
        }
    }
}
