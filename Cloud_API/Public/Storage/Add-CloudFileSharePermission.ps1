function Add-CloudFileSharePermission {
    <#
    .SYNOPSIS
        Adds a permission to a file share.
    
    .DESCRIPTION
        Adds a new permission to a file share, allowing specific IP ranges
        or clients to access the share.
    
    .PARAMETER FileShareId
        The unique identifier of the file share to add permission to. Required.
    
    .PARAMETER IPRange
        The IP range or specific IP address to grant access to (e.g., "10.0.0.0/24" or "10.0.0.5").
    
    .PARAMETER ReadOnly
        If specified, grants read-only access. Otherwise, grants read-write access.
    
    .EXAMPLE
        PS> Add-CloudFileSharePermission -FileShareId "fs-..." -IPRange "10.0.0.0/24"
        
        Grants read-write access to the 10.0.0.0/24 subnet.
    
    .EXAMPLE
        PS> Add-CloudFileSharePermission -FileShareId "fs-..." -IPRange "10.0.0.5" -ReadOnly
        
        Grants read-only access to a specific IP address.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileShareId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$IPRange,
        
        [Parameter(Mandatory=$false)]
        [switch]$ReadOnly
    )
    
    try {
        $body = @{
            ipRange = $IPRange
            readOnly = $ReadOnly.IsPresent
        }
        
        $accessType = if ($ReadOnly) { 'read-only' } else { 'read-write' }
        
        if (-not $PSCmdlet.ShouldProcess("file share '$FileShareId' for IP range '$IPRange' ($accessType)", 'Add Permission')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "storage/file-shares/$FileShareId/permissions" -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to add file share permission: $($_.Exception.Message)"
        return $null
    }
}
