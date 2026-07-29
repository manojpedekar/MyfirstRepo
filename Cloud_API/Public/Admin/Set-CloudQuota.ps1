function Set-CloudQuota {
    <#
    .SYNOPSIS
        Sets resource quota limits.

    .DESCRIPTION
        Updates the quota limit for a specific resource type on an account
        or project. This controls the maximum number of resources that can
        be created.

    .PARAMETER AccountId
        The account ID to set quota for (mandatory).

    .PARAMETER ProjectId
        The project ID to set quota for (optional, uses account default if not specified).

    .PARAMETER ResourceType
        The type of resource (mandatory). Examples: 'instances', 'volumes', 'networks'.

    .PARAMETER Limit
        The quota limit value (mandatory). Use -1 for unlimited.

    .EXAMPLE
        PS> Set-CloudQuota -AccountId "account-12345" -ResourceType 'instances' -Limit 50

        Sets the instance quota to 50 for the account.

    .EXAMPLE
        PS> Set-CloudQuota -AccountId "account-12345" -ProjectId "project-67890" -ResourceType 'volumes' -Limit 100

        Sets the volume quota to 100 for a specific project.

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
        [string]$AccountId,

        [Parameter(Mandatory=$false)]
        [string]$ProjectId,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceType,

        [Parameter(Mandatory=$true)]
        [int]$Limit
    )

    try {
        if (-not $PSCmdlet.ShouldProcess("quota for resource '$ResourceType' on account '$AccountId'", 'Set')) {
            return $null
        }

        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept

        # Build request body
        $body = @{
            accountId = $AccountId
            resourceType = $ResourceType
            limit = $Limit
        }

        if ($ProjectId) { $body['projectId'] = $ProjectId }

        Write-Verbose "Setting quota: $ResourceType = $Limit for account $AccountId"

        $response = Invoke-CloudAPIRequest -Path 'admin/quotas' -Method 'PUT' -Headers $headers -Body $body

        return $response
    }
    catch {
        Write-Error "Failed to set quota: $($_.Exception.Message)"
        return $null
    }
}
