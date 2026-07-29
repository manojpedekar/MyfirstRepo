function Get-CloudResourceUsage {
    <#
    .SYNOPSIS
        Retrieves resource usage statistics.

    .DESCRIPTION
        Gets detailed resource usage statistics for accounts or projects
        over a specified time period. Includes CPU, memory, storage, and
        network usage metrics.

    .PARAMETER AccountId
        Filter by account ID.

    .PARAMETER ProjectId
        Filter by project ID.

    .PARAMETER ResourceType
        Filter by resource type (e.g., 'instance', 'volume', 'network').

    .PARAMETER StartDate
        The start date for the usage period. Defaults to 30 days ago.

    .PARAMETER EndDate
        The end date for the usage period. Defaults to current date.

    .PARAMETER Granularity
        Data granularity: 'Hourly', 'Daily', 'Weekly', 'Monthly'. Default is 'Daily'.

    .EXAMPLE
        PS> Get-CloudResourceUsage -AccountId "account-12345" -StartDate (Get-Date).AddDays(-7)

        Gets resource usage for the last 7 days.

    .EXAMPLE
        PS> Get-CloudResourceUsage -ProjectId "project-67890" -ResourceType 'instance' -Granularity 'Hourly'

        Gets hourly instance usage for a project.

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
        [string]$ResourceType,

        [Parameter(Mandatory=$false)]
        [datetime]$StartDate = (Get-Date).AddDays(-30),

        [Parameter(Mandatory=$false)]
        [datetime]$EndDate = (Get-Date),

        [Parameter(Mandatory=$false)]
        [ValidateSet('Hourly', 'Daily', 'Weekly', 'Monthly')]
        [string]$Granularity = 'Daily'
    )

    try {
        # Validate at least one filter is provided
        if (-not $AccountId -and -not $ProjectId) {
            Write-Warning "Please specify either AccountId or ProjectId."
            return $null
        }

        # Validate date range
        if ($StartDate -gt $EndDate) {
            Write-Error "StartDate must be before EndDate"
            return $null
        }

        $headers = New-CloudAPIHeaders

        # Build query parameters
        $queryParams = @{
            startDate = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            endDate = $EndDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            granularity = $Granularity.ToLower()
        }

        if ($AccountId) { $queryParams['accountId'] = $AccountId }
        if ($ProjectId) { $queryParams['projectId'] = $ProjectId }
        if ($ResourceType) { $queryParams['resourceType'] = $ResourceType }

        Write-Verbose "Retrieving resource usage from $StartDate to $EndDate with $Granularity granularity"

        $response = Invoke-CloudAPIRequest -Path 'admin/resource-usage' -Method 'GET' -Headers $headers -QueryParameters $queryParams

        return $response
    }
    catch {
        Write-Error "Failed to retrieve resource usage: $($_.Exception.Message)"
        return $null
    }
}
