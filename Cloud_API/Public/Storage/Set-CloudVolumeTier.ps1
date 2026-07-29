function Set-CloudVolumeTier {
    <#
    .SYNOPSIS
        Moves a volume to a different storage tier.
    
    .DESCRIPTION
        Changes the storage tier of a specified volume.
        This operation may take time depending on the volume size.
        Supports waiting for the operation to complete via the -Wait switch.
    
    .PARAMETER VolumeId
        The unique identifier of the volume to move. Required.
    
    .PARAMETER TierId
        The unique identifier of the target storage tier. Required.
    
    .PARAMETER Wait
        If specified, waits for the tier change operation to complete.
    
    .EXAMPLE
        PS> Set-CloudVolumeTier -VolumeId "v-..." -TierId "tier-..."
        
        Moves the volume to the specified tier.
    
    .EXAMPLE
        PS> Set-CloudVolumeTier -VolumeId "v-..." -TierId "tier-..." -Wait
        
        Moves the volume to the specified tier and waits for completion.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [Alias('Id')]
        [string]$VolumeId,
        
        [Parameter(Mandatory=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [string]$TierId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    begin {
        $headers = $null
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType
        }
        catch {
            Write-Error -Message "Failed to initialize API headers: $($_.Exception.Message)" -ErrorId 'InitializeCloudAPIHeadersFailed'
            return
        }
        $results = @()
    }
    
    process {
        try {
            $body = @{
                tierId = $TierId
            }
            
            if (-not $PSCmdlet.ShouldProcess("volume '$VolumeId' to tier '$TierId'", 'Move')) {
                return $null
            }
            
            $response = Invoke-CloudAPIRequest -Path "storage/volumes/$VolumeId/tier" -Method 'POST' -Headers $headers -Body $body -Wait:$Wait
            
            $results += $response
        }
        catch {
            Write-Error -Message "Failed to move volume '$VolumeId' to tier '$TierId': $($_.Exception.Message)" -ErrorId 'SetCloudVolumeTierFailed'
        }
    }
    
    end {
        return $results
    }
}
