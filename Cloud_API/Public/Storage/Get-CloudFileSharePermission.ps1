function Get-CloudFileSharePermission {
    <#
    .SYNOPSIS
        Retrieves file share permissions.
    
    .DESCRIPTION
        Gets all permissions for a specified file share.
        Permissions control which clients can access the share and with what access level.
    
    .PARAMETER FileShareId
        The unique identifier of the file share to get permissions for. Required.
    
    .EXAMPLE
        PS> Get-CloudFileSharePermission -FileShareId "fs-..."
        
        Lists all permissions for the specified file share.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileShareId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $response = Invoke-CloudAPIRequest -Path "storage/file-shares/$FileShareId/permissions" -Method 'GET' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve file share permissions: $($_.Exception.Message)"
        return $null
    }
}
