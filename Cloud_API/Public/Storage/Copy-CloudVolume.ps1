function Copy-CloudVolume {
    <#
    .SYNOPSIS
        Copies or clones a volume.
    
    .DESCRIPTION
        Creates a copy/clone of a specified volume.
        Can optionally attach the copy to a different instance.
        Supports waiting for the operation to complete via the -Wait switch.
    
    .PARAMETER VolumeId
        The unique identifier of the volume to copy. Required.
    
    .PARAMETER Name
        The name for the new volume copy. If not specified, a default name will be generated.
    
    .PARAMETER TargetInstanceId
        The instance ID to attach the copied volume to. Optional.
    
    .PARAMETER Wait
        If specified, waits for the copy operation to complete.
    
    .EXAMPLE
        PS> Copy-CloudVolume -VolumeId "v-..." -Name "Volume-Copy-01"
        
        Creates a copy of the volume with the specified name.
    
    .EXAMPLE
        PS> Copy-CloudVolume -VolumeId "v-..." -TargetInstanceId "i-..." -Wait
        
        Copies the volume and attaches it to the specified instance.
    
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
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$TargetInstanceId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    try {
        # Generate default name if not provided
        if (-not $Name) {
            $timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
            $Name = "volume-copy-$timestamp"
        }
        
        $body = @{
            name = $Name
        }
        
        if ($TargetInstanceId) { $body['targetInstanceId'] = $TargetInstanceId }
        
        if (-not $PSCmdlet.ShouldProcess("volume '$VolumeId' to create '$Name'", 'Copy')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "storage/volumes/$VolumeId/copy" -Method 'POST' -Headers $headers -Body $body -Wait:$Wait
        
        return $response
    }
    catch {
        Write-Error "Failed to copy volume: $($_.Exception.Message)"
        return $null
    }
}
