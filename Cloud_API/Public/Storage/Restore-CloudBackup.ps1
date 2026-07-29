function Restore-CloudBackup {
    <#
    .SYNOPSIS
        Restores an instance from a backup.
    
    .DESCRIPTION
        Restores an instance from a specified backup.
        Can restore to the original instance or a different target instance.
        Supports waiting for the restore operation to complete via the -Wait switch.
    
    .PARAMETER Id
        The unique identifier of the backup to restore from. Required.
    
    .PARAMETER TargetInstanceId
        The instance ID to restore to. If not specified, restores to the original instance.
    
    .PARAMETER Wait
        If specified, waits for the restore operation to complete.
    
    .EXAMPLE
        PS> Restore-CloudBackup -Id "bkp-..."
        
        Restores the backup to the original instance.
    
    .EXAMPLE
        PS> Restore-CloudBackup -Id "bkp-..." -TargetInstanceId "i-..." -Wait
        
        Restores the backup to a different instance and waits for completion.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    
    .WARNING
        This operation may overwrite data on the target instance. Use with caution.
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('BackupId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$TargetInstanceId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    try {
        $body = @{}
        
        if ($TargetInstanceId) {
            $body['targetInstanceId'] = $TargetInstanceId
        }
        
        $targetDescription = if ($TargetInstanceId) { "instance '$TargetInstanceId'" } else { "original instance" }
        
        if (-not $PSCmdlet.ShouldProcess("backup '$Id' to $targetDescription", 'Restore')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "storage/backups/$Id/restore" -Method 'POST' -Headers $headers -Body $body -Wait:$Wait
        
        return $response
    }
    catch {
        Write-Error "Failed to restore backup: $($_.Exception.Message)"
        return $null
    }
}
