function Get-CloudQuota {
    <#
    .SYNOPSIS
        Retrieves quota information for accounts or projects.

    .DESCRIPTION
        Gets resource quota limits and current usage for specified accounts
        or projects. Quotas control resource allocation limits.

    .PARAMETER AccountId
        The account ID to retrieve quotas for.

    .PARAMETER ProjectId
        The project ID to retrieve quotas for.

    .PARAMETER ResourceType
        Filter by specific resource type (e.g., 'instances', 'volumes', 'networks').

    .EXAMPLE
        PS> Get-CloudQuota -AccountId "account-12345"

        Retrieves all quotas for a specific account.

    .EXAMPLE
        PS> Get-CloudQuota -ProjectId "project-12345" -ResourceType 'instances'

        Retrieves instance quotas for a specific project.

    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.

    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$AccountId,

        [Parameter(Mandatory=$false)]
        [string]$ProjectId,

        [Parameter(Mandatory=$false)]
        [string]$ResourceType
    )

    try {
        # Validate at least one filter is provided
        if (-not $AccountId -and -not $ProjectId) {
            Write-Warning "Please specify either AccountId or ProjectId."
            return $null
        }

        $headers = New-CloudAPIHeaders

        # Build query parameters
        $queryParams = @{}

        if ($AccountId) { $queryParams['accountId'] = $AccountId }
        if ($ProjectId) { $queryParams['projectId'] = $ProjectId }
        if ($ResourceType) { $queryParams['resourceType'] = $ResourceType }

        Write-Verbose "Retrieving quotas for account '$AccountId' project '$ProjectId'"

        $response = Invoke-CloudAPIRequest -Path 'admin/quotas' -Method 'GET' -Headers $headers -QueryParameters $queryParams

        return $response
    }
    catch {
        Write-Error "Failed to retrieve quotas: $($_.Exception.Message)"
        return $null
    }
}
