function Get-CloudBackup {
    <#
    .SYNOPSIS
        Retrieves backup information for instances.
    
    .DESCRIPTION
        Gets information about backups. Can retrieve a specific backup by ID,
        or list all backups for an instance or sub-project.
    
    .PARAMETER Id
        The unique identifier of the backup.
    
    .PARAMETER InstanceId
        The instance ID to list backups for.
    
    .PARAMETER SubprojectId
        The sub-project ID to list backups from.
    
    .EXAMPLE
        PS> Get-CloudBackup -Id "bkp-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for a specific backup.
    
    .EXAMPLE
        PS> Get-CloudBackup -InstanceId "i-..."
        
        Lists all backups for the specified instance.
    
    .EXAMPLE
        PS> Get-CloudBackup -SubprojectId "subproject-..."
        
        Lists all backups in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('BackupId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$InstanceId,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "storage/backups/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{
                sort = 'createdDate%2Cdesc'
            }
            if ($InstanceId) { $queryParams['instanceId'] = $InstanceId }
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            
            $response = Invoke-CloudAPIRequest -Path 'storage/backups' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve backup(s): $($_.Exception.Message)"
        return $null
    }
}
