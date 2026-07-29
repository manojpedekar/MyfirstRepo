function Get-CloudVolumeAttachment {
    <#
    .SYNOPSIS
        Retrieves volume attachment information.
    
    .DESCRIPTION
        Gets information about volume attachments. Can retrieve attachments
        for a specific volume or all volumes attached to an instance.
    
    .PARAMETER VolumeId
        The unique identifier of the volume to get attachment information for.
    
    .PARAMETER InstanceId
        The instance ID to list all attached volumes for.
    
    .EXAMPLE
        PS> Get-CloudVolumeAttachment -VolumeId "v-..."
        
        Retrieves attachment information for a specific volume.
    
    .EXAMPLE
        PS> Get-CloudVolumeAttachment -InstanceId "i-..."
        
        Lists all volumes attached to the specified instance.
    
    .EXAMPLE
        PS> Get-CloudVolumeAttachment
        
        Lists all volume attachments in the system.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$VolumeId,
        
        [Parameter(Mandatory=$false)]
        [string]$InstanceId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $queryParams = @{
            sort = 'createdDate%2Cdesc'
        }
        
        if ($VolumeId) { $queryParams['volumeId'] = $VolumeId }
        if ($InstanceId) { $queryParams['instanceId'] = $InstanceId }
        
        $response = Invoke-CloudAPIRequest -Path 'storage/volume-attachments' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve volume attachment(s): $($_.Exception.Message)"
        return $null
    }
}
