function New-CloudInstance {
    <#
    .SYNOPSIS
        Creates a new instance in the cloud.
    
    .DESCRIPTION
        Creates a new cloud instance with specified CPU, memory, and other settings.
        The instance will be created in the specified sub-project with the given configuration.
    
    .PARAMETER SubprojectId
        The sub-project ID where the instance will be created. Required.
    
    .PARAMETER Name
        The name for the new instance. Required.
    
    .PARAMETER Cpu
        Number of CPU cores. Required.
    
    .PARAMETER Memory
        Amount of memory in GB. Required.
    
    .PARAMETER SecuritygroupIds
        Security group ID(s) to assign to the instance. Required.
    
    .PARAMETER Site
        The site/location for the instance. Required.
    
    .PARAMETER DomainDelegation
        The domain delegation for the instance. Defaults to 'cloudad.ssncad.global'.
    
    .PARAMETER ImageId
        The image ID to use for the instance. Defaults to 'ssnc-cloud-w2k25-base'.
    
    .PARAMETER PatchingGroup
        The patching group for the instance. If not specified, uses the sub-project's default.
    
    .PARAMETER BackupPolicy
        The backup policy for the instance.
    
    .PARAMETER Network
        The network configuration for the instance.
    
    .PARAMETER Wait
        If specified, waits for the instance creation to complete.
    
    .EXAMPLE
        PS> $param = @{
            subprojectId = "subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
            name = "demo"
            cpu = "2"
            memory = "4"
            securitygroupIds = "securitygroup-6bc70d2c-3e1e-4e59-9e1f-bb1a74d5711b"
            site = "na-central-kc"
        }
        PS> New-CloudInstance @Param
        
        Creates a new instance with the specified configuration.
    
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
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateRange(1,64)]
        [int]$Cpu,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateRange(1,512)]
        [int]$Memory,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SecuritygroupIds,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Site,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainDelegation = "cloudad.ssncad.global",
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$ImageId = "ssnc-cloud-w2k25-base",
        
        [Parameter(Mandatory=$false)]
        [string]$PatchingGroup,
        
        [Parameter(Mandatory=$false)]
        [string]$BackupPolicy,
        
        [Parameter(Mandatory=$false)]
        [string]$Network,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    try {
        # Get default patching group if not specified
        if (-not $PatchingGroup) {
            try {
                $subproject = Get-CloudSubproject -Id $SubprojectId
                $PatchingGroup = $subproject.defaultPatchingGroup
            }
            catch {
                Write-Warning "Could not retrieve default patching group from sub-project"
            }
        }
        
        # Build request body
        $body = @{
            subprojectId = $SubprojectId
            name = $Name
            domainDelegation = $DomainDelegation
            cpu = $Cpu
            memory = $Memory
            imageId = $ImageId
            securitygroupIds = $SecuritygroupIds
            site = $Site
        }
        
        if ($Network) {
            $body['network'] = $Network
        }
        
        if ($PatchingGroup) {
            $body['patchingGroup'] = $PatchingGroup
        }
        
        if ($BackupPolicy) {
            $body['backupPolicy'] = $BackupPolicy
        }
        
        # Confirm action
        if (-not $PSCmdlet.ShouldProcess("instance '$Name' in sub-project '$SubprojectId'", 'Create')) {
            return $null
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path 'compute/instances' -Method 'POST' -Headers $headers -Body $body -Wait:$Wait
        
        return $response
    }
    catch {
        Write-Error -Message "Failed to create instance: $($_.Exception.Message)" -ErrorId 'NewCloudInstanceFailed'
        return $null
    }
}
