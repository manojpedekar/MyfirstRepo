function Get-CloudBillingSummary {
    <#
    .SYNOPSIS
        Retrieves billing summary information.

    .DESCRIPTION
        Gets billing summary for a specified account and time period.
        Includes total costs, breakdown by service, and comparison
        with previous periods.

    .PARAMETER AccountId
        The account ID to get billing summary for (mandatory).

    .PARAMETER Month
        The month number (1-12). Defaults to current month.

    .PARAMETER Year
        The year. Defaults to current year.

    .PARAMETER IncludeProjectBreakdown
        Include breakdown by project in the summary.

    .EXAMPLE
        PS> Get-CloudBillingSummary -AccountId "account-12345"

        Gets the billing summary for the current month.

    .EXAMPLE
        PS> Get-CloudBillingSummary -AccountId "account-12345" -Month 1 -Year 2024

        Gets the billing summary for January 2024.

    .EXAMPLE
        PS> Get-CloudBillingSummary -AccountId "account-12345" -IncludeProjectBreakdown

        Gets billing summary with project-level breakdown.

    .OUTPUTS
        PSCustomObject. Returns $null on error.

    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccountId,

        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 12)]
        [int]$Month = (Get-Date).Month,

        [Parameter(Mandatory=$false)]
        [ValidateRange(2000, 2100)]
        [int]$Year = (Get-Date).Year,

        [Parameter(Mandatory=$false)]
        [switch]$IncludeProjectBreakdown
    )

    try {
        $headers = New-CloudAPIHeaders

        # Build query parameters
        $queryParams = @{
            accountId = $AccountId
            month = $Month
            year = $Year
        }

        if ($IncludeProjectBreakdown) {
            $queryParams['includeProjectBreakdown'] = 'true'
        }

        Write-Verbose "Retrieving billing summary for $Month/$Year"

        $response = Invoke-CloudAPIRequest -Path 'admin/billing-summary' -Method 'GET' -Headers $headers -QueryParameters $queryParams

        return $response
    }
    catch {
        Write-Error "Failed to retrieve billing summary: $($_.Exception.Message)"
        return $null
    }
}
