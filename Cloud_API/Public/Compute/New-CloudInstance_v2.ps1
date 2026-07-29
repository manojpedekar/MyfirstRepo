function New-CloudInstance_v2 {
    <#
    .SYNOPSIS
        Creates a new instance in the cloud (v2 - corrected security group handling).

    .DESCRIPTION
        Creates a new cloud instance with specified CPU, memory, image, security group(s),
        site, and domain delegation.

        This is version 2 of New-CloudInstance. It exists to correct a defect in the
        original function that prevented security groups from being attached at build time.

        CHANGES FROM v1:
        - The JSON body field is now 'securityGroupIds' (capital 'G'), which is what the
          SS&C Cloud API (case-sensitive) actually expects. v1 sent 'securitygroupIds'
          (lowercase 'g'), which the API silently ignored, so no security group was attached.
        - 'securityGroupIds' is sent as an ARRAY ([string[]]), matching the API contract,
          so one OR multiple security groups can be attached.

        v1 (New-CloudInstance.ps1) is left unchanged to preserve rollback capability.

    .PARAMETER SubprojectId
        The sub-project ID where the instance will be created. Required.

    .PARAMETER Name
        The name for the new instance. Required.

    .PARAMETER Cpu
        Number of CPU cores. Required. Valid range 1-64.

    .PARAMETER Memory
        Amount of memory in GB. Required. Valid range 1-512.

    .PARAMETER SecurityGroupIds
        One or more security group ID(s) to assign to the instance. Required.
        Accepts a single value or an array, e.g. -SecurityGroupIds 'tier-...','vtier-...'.

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
        The network configuration (CIDR) for the instance.

    .PARAMETER Wait
        If specified, waits for the instance creation to complete.

    .EXAMPLE
        PS> $param = @{
            SubprojectId     = "subproject-43be98b7-6eed-4dbe-a056-fbbfca1e4b49"
            Name             = "KCPeerPMC"
            Cpu              = 4
            Memory           = 8
            SecurityGroupIds = "tier-f40267c6-2263-46e2-935f-14c757d92cb9"
            Site             = "na-central-kc"
            DomainDelegation = "globeop.com"
        }
        PS> New-CloudInstance_v2 @param -Verbose

        Creates an instance and attaches the "Application" security group.

    .EXAMPLE
        PS> New-CloudInstance_v2 -SubprojectId $sub -Name "web01" -Cpu 2 -Memory 8 `
                -SecurityGroupIds 'tier-aaaa','vtier-bbbb' -Site 'na-central-kc'

        Creates an instance attached to two security groups.

    .OUTPUTS
        PSCustomObject. Returns $null on error.

    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0 (function v2)
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
        [string[]]$SecurityGroupIds,

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

        # Build request body.
        # NOTE: 'securityGroupIds' (capital 'G') and an array value are required by the API.
        $body = @{
            subprojectId     = $SubprojectId
            name             = $Name
            domainDelegation = $DomainDelegation
            cpu              = $Cpu
            memory           = $Memory
            imageId          = $ImageId
            securityGroupIds = @($SecurityGroupIds)
            site             = $Site
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
        Write-Error -Message "Failed to create instance: $($_.Exception.Message)" -ErrorId 'NewCloudInstanceV2Failed'
        return $null
    }
}
