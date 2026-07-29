function Set-CloudVolume {
    <#
    .SYNOPSIS
        Modifies a cloud volume.
    
    .DESCRIPTION
        Updates the properties of an existing cloud volume.
    
    .PARAMETER Id
        The unique identifier of the volume. Required.
    
    .PARAMETER InstanceId
        The instance ID to attach the volume to.
    
    .PARAMETER Name
        The new name for the volume.
    
    .PARAMETER IsDatabase
        Whether this volume is for a database.
    
    .PARAMETER Size
        The new size of the volume in GB.
    
    .PARAMETER Detach
        If specified, detaches the volume from any instance.
    
    .EXAMPLE
        PS> Set-CloudVolume -Id "v-..." -Size 100
        
        Updates the volume size to 100GB.
    
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
        [Alias('VolumeId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$InstanceId,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [bool]$IsDatabase,
        
        [Parameter(Mandatory=$false)]
        [string]$Size,
        
        [Parameter(Mandatory=$false)]
        [switch]$Detach
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
            # Get current volume details
            $current = Get-CloudVolume -Id $Id
            if (-not $current) {
                Write-Error -Message "Volume '$Id' not found" -ErrorId 'SetCloudVolumeNotFound'
                return $null
            }
            
            # Use current values if not specified
            if (-not $PSBoundParameters.ContainsKey('InstanceId')) { $InstanceId = $current.instanceId }
            if (-not $PSBoundParameters.ContainsKey('Name')) { $Name = $current.name }
            if (-not $PSBoundParameters.ContainsKey('IsDatabase')) { $IsDatabase = $current.isDatabase }
            if (-not $PSBoundParameters.ContainsKey('Size')) { $Size = $current.size }
            
            # Build request body
            $body = @{
                volumeId = $Id
                instanceId = $InstanceId
                name = $Name
                isDatabase = $IsDatabase
                size = $Size
            }
            
            if ($Detach) {
                $body['detach'] = $true
            }
            
            if (-not $PSCmdlet.ShouldProcess("volume '$Name' ($Id)", 'Update')) {
                return $null
            }
            
            $response = Invoke-CloudAPIRequest -Path "storage/volumes/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            $results += $response
        }
        catch {
            Write-Error -Message "Failed to update volume '$Id': $($_.Exception.Message)" -ErrorId 'SetCloudVolumeFailed'
        }
    }
    
    end {
        return $results
    }
}
