function Add-CloudVolumeAttachment {
    <#
    .SYNOPSIS
        Attaches a volume to an instance.
    
    .DESCRIPTION
        Attaches a specified volume to a specified instance.
        The volume must be in an available state and not already attached.
    
    .PARAMETER VolumeId
        The unique identifier of the volume to attach. Required.
    
    .PARAMETER InstanceId
        The instance ID to attach the volume to. Required.
    
    .EXAMPLE
        PS> Add-CloudVolumeAttachment -VolumeId "v-..." -InstanceId "i-..."
        
        Attaches the volume to the specified instance.
    
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
        [string]$VolumeId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$InstanceId
    )
    
    try {
        $body = @{
            volumeId = $VolumeId
            instanceId = $InstanceId
        }
        
        if (-not $PSCmdlet.ShouldProcess("volume '$VolumeId' to instance '$InstanceId'", 'Attach')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path 'storage/volume-attachments' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to attach volume: $($_.Exception.Message)"
        return $null
    }
}
