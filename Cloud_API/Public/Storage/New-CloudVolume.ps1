function New-CloudVolume {
    <#
    .SYNOPSIS
        Creates a new cloud volume (disk).
    
    .DESCRIPTION
        Creates a new storage volume with specified settings and optionally attaches
        it to an instance. If instanceId is specified, the function will auto-populate
        subprojectId, site, and deploymentZoneId from the instance details.
    
    .PARAMETER InstanceId
        The instance ID to attach the volume to. If specified, will auto-populate
        other parameters from the instance.
    
    .PARAMETER SubprojectId
        The sub-project ID. Required if InstanceId is not specified.
    
    .PARAMETER Name
        The name for the volume. If not specified, will use instance name plus timestamp.
    
    .PARAMETER Site
        The site for the volume. Required if InstanceId is not specified.
    
    .PARAMETER DeploymentZoneId
        The deployment zone ID. Required if InstanceId is not specified.
    
    .PARAMETER Size
        The size of the volume in GB. Required.
    
    .PARAMETER IsDatabase
        Whether this volume is for a database. Defaults to $false.
    
    .PARAMETER Wait
        If specified, waits for the volume creation to complete.
    
    .EXAMPLE
        PS> New-CloudVolume -InstanceId "i-..." -Size 50
        
        Creates a 50GB volume attached to the specified instance.
    
    .EXAMPLE
        PS> New-CloudVolume -SubprojectId "subproject-..." -Name "MyVolume" -Site "na-central-kc" -DeploymentZoneId "deploymentzone-..." -Size 100
        
        Creates a 100GB volume in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$false)]
        [string]$InstanceId,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$Site,
        
        [Parameter(Mandatory=$false)]
        [string]$DeploymentZoneId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateRange(10,16384)]
        [int]$Size,
        
        [Parameter(Mandatory=$false)]
        [bool]$IsDatabase = $false,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    try {
        $Date = Get-Date -Format "dd-MM-yyyy-HH-mm-ss"
        
        # Auto-populate from instance if provided
        if ($InstanceId) {
            $instance = Get-CloudInstance -Id $InstanceId
            if (-not $instance) {
                Write-Error "Instance '$InstanceId' not found"
                return $null
            }
            
            if (-not $Name) { $Name = "$($instance.name)-data-$Date" }
            if (-not $SubprojectId) { $SubprojectId = $instance.subprojectId }
            if (-not $Site) { $Site = $instance.site }
            if (-not $DeploymentZoneId) { $DeploymentZoneId = $instance.deploymentZoneId }
        } else {
            if (-not $Name) { $Name = "volume-data-$Date" }
        }
        
        # Validate required parameters
        if (-not $SubprojectId) {
            Write-Error "SubprojectId is required when InstanceId is not specified"
            return $null
        }
        if (-not $Site) {
            Write-Error "Site is required when InstanceId is not specified"
            return $null
        }
        if (-not $DeploymentZoneId) {
            Write-Error "DeploymentZoneId is required when InstanceId is not specified"
            return $null
        }
        
        # Build request body
        $body = @{
            subprojectId = $SubprojectId
            name = $Name
            site = $Site
            deploymentZoneId = $DeploymentZoneId
            isDatabase = $IsDatabase
            size = $Size
        }
        
        if ($InstanceId) {
            $body['instanceId'] = $InstanceId
        }
        
        if (-not $PSCmdlet.ShouldProcess("volume '$Name' ($Size GB)", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path 'storage/volumes' -Method 'POST' -Headers $headers -Body $body -Wait:$Wait
        
        return $response
    }
    catch {
        Write-Error -Message "Failed to create volume: $($_.Exception.Message)" -ErrorId 'NewCloudVolumeFailed'
        return $null
    }
}
