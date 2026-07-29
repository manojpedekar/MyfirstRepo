function Get-CloudCostReport {
    <#
    .SYNOPSIS
        Retrieves cost reports for accounts or projects.

    .DESCRIPTION
        Gets cost and usage reports with optional grouping and filtering.
        Reports can be generated for specific date ranges and grouped by
        various dimensions.

    .PARAMETER AccountId
        Filter by account ID.

    .PARAMETER ProjectId
        Filter by project ID.

    .PARAMETER StartDate
        The start date for the report period.

    .PARAMETER EndDate
        The end date for the report period.

    .PARAMETER GroupBy
        Group results by: 'Resource', 'Project', 'Service', 'Day', 'Month'.

    .PARAMETER Format
        Report format: 'Summary' or 'Detailed'. Default is 'Summary'.

    .EXAMPLE
        PS> Get-CloudCostReport -StartDate (Get-Date).AddDays(-30) -EndDate (Get-Date) -GroupBy 'Project'

        Gets a cost report for the last 30 days grouped by project.

    .EXAMPLE
        PS> Get-CloudCostReport -AccountId "account-12345" -GroupBy 'Service' -Format 'Detailed'

        Gets a detailed cost report for an account grouped by service.

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
        [datetime]$StartDate = (Get-Date).AddDays(-30),

        [Parameter(Mandatory=$false)]
        [datetime]$EndDate = (Get-Date),

        [Parameter(Mandatory=$false)]
        [ValidateSet('Resource', 'Project', 'Service', 'Day', 'Month', 'Region')]
        [string]$GroupBy = 'Service',

        [Parameter(Mandatory=$false)]
        [ValidateSet('Summary', 'Detailed')]
        [string]$Format = 'Summary'
    )

    try {
        # Validate date range
        if ($StartDate -gt $EndDate) {
            Write-Error "StartDate must be before EndDate"
            return $null
        }

        $headers = New-CloudAPIHeaders

        # Build query parameters
        $queryParams = @{
            startDate = $StartDate.ToUniversalTime().ToString('yyyy-MM-dd')
            endDate = $EndDate.ToUniversalTime().ToString('yyyy-MM-dd')
            groupBy = $GroupBy.ToLower()
            format = $Format.ToLower()
        }

        if ($AccountId) { $queryParams['accountId'] = $AccountId }
        if ($ProjectId) { $queryParams['projectId'] = $ProjectId }

        Write-Verbose "Retrieving cost report from $StartDate to $EndDate grouped by $GroupBy"

        $response = Invoke-CloudAPIRequest -Path 'admin/cost-reports' -Method 'GET' -Headers $headers -QueryParameters $queryParams

        return $response
    }
    catch {
        Write-Error "Failed to retrieve cost report: $($_.Exception.Message)"
        return $null
    }
}
