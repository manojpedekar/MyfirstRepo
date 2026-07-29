function Remove-CloudVolumeAttachment {
    <#
    .SYNOPSIS
        Detaches a volume from an instance.
    
    .DESCRIPTION
        Detaches a specified volume from a specified instance.
        Ensure the volume is not in use before detaching.
    
    .PARAMETER VolumeId
        The unique identifier of the volume to detach. Required.
    
    .PARAMETER InstanceId
        The instance ID to detach the volume from. Required.
    
    .PARAMETER Force
        If specified, bypasses the confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudVolumeAttachment -VolumeId "v-..." -InstanceId "i-..."
        
        Prompts for confirmation before detaching the volume.
    
    .EXAMPLE
        PS> Remove-CloudVolumeAttachment -VolumeId "v-..." -InstanceId "i-..." -Force
        
        Detaches the volume without prompting.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$VolumeId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$InstanceId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("volume '$VolumeId' from instance '$InstanceId'", 'Detach')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        # Find the attachment ID first
        $attachments = Get-CloudVolumeAttachment -VolumeId $VolumeId -InstanceId $InstanceId
        if (-not $attachments) {
            Write-Error "No attachment found for volume '$VolumeId' on instance '$InstanceId'"
            return $null
        }
        
        # Handle both single object and array responses
        $attachment = if ($attachments -is [array]) { $attachments[0] } else { $attachments }
        $attachmentId = $attachment.id
        
        $response = Invoke-CloudAPIRequest -Path "storage/volume-attachments/$attachmentId" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to detach volume: $($_.Exception.Message)"
        return $null
    }
}
