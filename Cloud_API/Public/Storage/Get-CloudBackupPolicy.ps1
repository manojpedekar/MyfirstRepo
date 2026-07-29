function Get-CloudBackupPolicy {
    <#
    .SYNOPSIS
        Retrieves backup policies for instances or sub-projects.
    
    .DESCRIPTION
        Gets backup policies. Can retrieve a specific policy by ID, or list all policies
        for an instance or sub-project.
    
    .PARAMETER Id
        The unique identifier of the backup policy.
    
    .PARAMETER InstanceId
        The instance ID to retrieve backup policies for.
    
    .PARAMETER SubprojectId
        The sub-project ID to list backup policies from.
    
    .EXAMPLE
        PS> Get-CloudBackupPolicy -Id "bp-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for a specific backup policy.
    
    .EXAMPLE
        PS> Get-CloudBackupPolicy -InstanceId "i-..."
        
        Gets the backup policy for the specified instance.
    
    .EXAMPLE
        PS> Get-CloudBackupPolicy -SubprojectId "subproject-..."
        
        Lists all backup policies in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('BackupPolicyId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$InstanceId,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "storage/backup-policies/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } elseif ($InstanceId) {
            $queryParams = @{
                sort = 'name%2Casc'
                instanceId = $InstanceId
            }
            $response = Invoke-CloudAPIRequest -Path 'storage/backup-policies' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        } else {
            $queryParams = @{
                sort = 'name%2Casc'
            }
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            
            $response = Invoke-CloudAPIRequest -Path 'storage/backup-policies' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve backup policy(ies): $($_.Exception.Message)"
        return $null
    }
}
