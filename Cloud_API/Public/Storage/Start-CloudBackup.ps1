function Start-CloudBackup {
    <#
    .SYNOPSIS
        Triggers a backup for an instance.
    
    .DESCRIPTION
        Initiates an on-demand backup of a specified instance.
        Supports waiting for the backup to complete via the -Wait switch.
    
    .PARAMETER InstanceId
        The instance ID to backup. Required.
    
    .PARAMETER Name
        The name for the backup. If not specified, a default name will be generated.
    
    .PARAMETER Description
        An optional description for the backup.
    
    .PARAMETER Wait
        If specified, waits for the backup operation to complete.
    
    .EXAMPLE
        PS> Start-CloudBackup -InstanceId "i-..." -Name "Pre-Update-Backup"
        
        Triggers a backup with the specified name.
    
    .EXAMPLE
        PS> Start-CloudBackup -InstanceId "i-..." -Name "Full-Backup" -Wait
        
        Triggers a backup and waits for completion.
    
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
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$Description,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    try {
        # Generate default name if not provided
        if (-not $Name) {
            $timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
            $Name = "manual-backup-$timestamp"
        }
        
        $body = @{
            name = $Name
        }
        
        if ($Description) { $body['description'] = $Description }
        
        if (-not $PSCmdlet.ShouldProcess("instance '$InstanceId' with backup '$Name'", 'Start Backup')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "storage/instances/$InstanceId/backups" -Method 'POST' -Headers $headers -Body $body -Wait:$Wait
        
        return $response
    }
    catch {
        Write-Error "Failed to start backup: $($_.Exception.Message)"
        return $null
    }
}
