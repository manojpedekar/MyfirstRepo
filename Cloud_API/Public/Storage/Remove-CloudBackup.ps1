function Remove-CloudBackup {
    <#
    .SYNOPSIS
        Deletes a backup.
    
    .DESCRIPTION
        Removes a specified backup from the system.
        This operation cannot be undone.
    
    .PARAMETER Id
        The unique identifier of the backup to remove. Required.
    
    .PARAMETER Force
        If specified, bypasses the confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudBackup -Id "bkp-00000000-0000-0000-0000-0000000000000"
        
        Prompts for confirmation before removing the backup.
    
    .EXAMPLE
        PS> Remove-CloudBackup -Id "bkp-..." -Force
        
        Removes the backup without prompting.
    
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
        [Alias('BackupId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("backup '$Id'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "storage/backups/$Id" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove backup: $($_.Exception.Message)"
        return $null
    }
}
