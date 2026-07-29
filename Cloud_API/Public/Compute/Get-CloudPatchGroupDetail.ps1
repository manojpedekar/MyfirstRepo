function Get-CloudPatchGroupDetail {
    <#
    .SYNOPSIS
        Retrieves detailed information about a specific patch group.
    
    .DESCRIPTION
        Gets comprehensive details about a patch group including its schedule,
        timezone, maintenance window, and list of affected instances.
    
    .PARAMETER Id
        The unique identifier of the patch group.
    
    .PARAMETER IncludeInstances
        If specified, includes all instances that are members of this patch group.
    
    .EXAMPLE
        PS> Get-CloudPatchGroupDetail -Id "pg-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        
        Gets detailed information about the specified patch group.
    
    .EXAMPLE
        PS> Get-CloudPatchGroupDetail -Id "pg-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73" -IncludeInstances
        
        Gets patch group details including all member instances.
    
    .OUTPUTS
        PSCustomObject with properties:
        - id: Patch group ID
        - name: Patch group name
        - schedule: Patching schedule configuration
        - timezone: Timezone for the schedule
        - maintenanceWindow: Start and end times
        - affectedInstances: List of instances (if IncludeInstances specified)
        Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('PatchGroupId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$IncludeInstances
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders
            
            # Get patch group details
            $path = "compute/patch-groups/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
            
            if (-not $response) {
                return $null
            }
            
            # Include instances if requested
            if ($IncludeInstances) {
                $instances = Get-CloudInstance | Where-Object { $_.patchingGroup -eq $response.name -or $_.patchingGroup -eq $Id }
                if ($instances) {
                    $response | Add-Member -NotePropertyName 'affectedInstances' -NotePropertyValue $instances -Force
                }
            }
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve patch group details: $($_.Exception.Message)"
            return $null
        }
    }
}
