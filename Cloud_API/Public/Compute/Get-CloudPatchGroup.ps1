function Get-CloudPatchGroup {
    <#
    .SYNOPSIS
        Retrieves patching group information.
    
    .DESCRIPTION
        Gets information about available patching groups in the cloud.
        Patching groups define maintenance windows for automated patching.
    
    .EXAMPLE
        PS> Get-CloudPatchGroup
        
        Lists all available patching groups.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param()
    
    try {
        $headers = New-CloudAPIHeaders
        $response = Invoke-CloudAPIRequest -Path 'compute/patch-groups' -Method 'GET' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve patching groups: $($_.Exception.Message)"
        return $null
    }
}
