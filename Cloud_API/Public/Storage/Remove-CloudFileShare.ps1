function Remove-CloudFileShare {
    <#
    .SYNOPSIS
        Deletes a file share.
    
    .DESCRIPTION
        Removes a specified file share from the system.
        This operation cannot be undone. Ensure no systems are actively using the share.
    
    .PARAMETER Id
        The unique identifier of the file share to remove. Required.
    
    .PARAMETER Force
        If specified, bypasses the confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudFileShare -Id "fs-00000000-0000-0000-0000-0000000000000"
        
        Prompts for confirmation before removing the file share.
    
    .EXAMPLE
        PS> Remove-CloudFileShare -Id "fs-..." -Force
        
        Removes the file share without prompting.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('FileShareId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("file share '$Id'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "storage/file-shares/$Id" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove file share: $($_.Exception.Message)"
        return $null
    }
}
