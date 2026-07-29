function Set-CloudBackupPolicy {
    <#
    .SYNOPSIS
        Configures a backup policy for an instance.
    
    .DESCRIPTION
        Sets or updates the backup policy configuration for a specific instance.
        This includes retention days, schedule, and whether backups are enabled.
    
    .PARAMETER InstanceId
        The instance ID to configure backup policy for. Required.
    
    .PARAMETER RetentionDays
        The number of days to retain backups.
    
    .PARAMETER Schedule
        The backup schedule in cron format or predefined schedule.
    
    .PARAMETER Enabled
        Whether backups are enabled for this instance.
    
    .EXAMPLE
        PS> Set-CloudBackupPolicy -InstanceId "i-..." -RetentionDays 30 -Enabled $true
        
        Configures the instance to retain backups for 30 days.
    
    .EXAMPLE
        PS> Set-CloudBackupPolicy -InstanceId "i-..." -Schedule "0 2 * * *" -Enabled $true
        
        Sets daily backups at 2 AM.
    
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
        [string]$InstanceId,
        
        [Parameter(Mandatory=$false)]
        [int]$RetentionDays,
        
        [Parameter(Mandatory=$false)]
        [string]$Schedule,
        
        [Parameter(Mandatory=$false)]
        [bool]$Enabled
    )
    
    try {
        # Build request body with only provided parameters
        $body = @{
            instanceId = $InstanceId
        }
        
        if ($PSBoundParameters.ContainsKey('RetentionDays')) { $body['retentionDays'] = $RetentionDays }
        if ($Schedule) { $body['schedule'] = $Schedule }
        if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = $Enabled }
        
        if (-not $PSCmdlet.ShouldProcess("instance '$InstanceId'", 'Set Backup Policy')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "storage/instances/$InstanceId/backup-policy" -Method 'PUT' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to set backup policy: $($_.Exception.Message)"
        return $null
    }
}
