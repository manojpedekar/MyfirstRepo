function Add-CloudInstanceToPatchGroup {
    <#
    .SYNOPSIS
        Adds an instance to a patch group.
    
    .DESCRIPTION
        Adds a cloud instance to a specific patch group, enabling it to receive
        patches according to the group's schedule and maintenance window.
    
    .PARAMETER InstanceId
        The unique identifier of the instance. This parameter is mandatory.
        Accepts pipeline input.
    
    .PARAMETER PatchGroupId
        The unique identifier of the patch group. This parameter is mandatory.
    
    .PARAMETER Wait
        If specified, waits for the operation to complete.
    
    .EXAMPLE
        PS> Add-CloudInstanceToPatchGroup -InstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a" -PatchGroupId "pg-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        
        Adds the instance to the specified patch group.
    
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
        [Alias('InstanceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('PatchGroupId')]
        [string]$PatchGroupId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            
            # Validate instance exists
            $instanceExists = Test-CloudAPIResource -ResourceType 'compute/instances' -ResourceId $Id
            if (-not $instanceExists) {
                Write-Error "Instance '$Id' not found"
                return $null
            }
            
            # Build request body
            $body = @{
                patchGroupId = $PatchGroupId
            }
            
            # Build invoke parameters
            $invokeParams = @{
                Path = "compute/instances/$Id/patch-group"
                Method = 'POST'
                Headers = $headers
                Body = $body
            }
            
            if ($Wait) { $invokeParams['Wait'] = $true }
            
            # Make API request
            $response = Invoke-CloudAPIRequest @invokeParams
            
            return $response
        }
        catch {
            Write-Error "Failed to add instance to patch group: $($_.Exception.Message)"
            return $null
        }
    }
}
