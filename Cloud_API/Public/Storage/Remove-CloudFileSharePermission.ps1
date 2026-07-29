function Remove-CloudFileSharePermission {
    <#
    .SYNOPSIS
        Removes a permission from a file share.
    
    .DESCRIPTION
        Removes a specific permission from a file share, revoking access
        for the IP range or client associated with that permission.
    
    .PARAMETER FileShareId
        The unique identifier of the file share to remove permission from. Required.
    
    .PARAMETER PermissionId
        The unique identifier of the permission to remove. Required.
    
    .PARAMETER Force
        If specified, bypasses the confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudFileSharePermission -FileShareId "fs-..." -PermissionId "perm-..."
        
        Prompts for confirmation before removing the permission.
    
    .EXAMPLE
        PS> Remove-CloudFileSharePermission -FileShareId "fs-..." -PermissionId "perm-..." -Force
        
        Removes the permission without prompting.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileShareId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$PermissionId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("permission '$PermissionId' from file share '$FileShareId'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "storage/file-shares/$FileShareId/permissions/$PermissionId" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove file share permission: $($_.Exception.Message)"
        return $null
    }
}
