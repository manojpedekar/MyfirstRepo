function Get-CloudActivityLog {
    <#
    .SYNOPSIS
        Retrieves activity logs from the SS&C Cloud API.

    .DESCRIPTION
        Gets activity log entries with optional filtering by date range, project,
        or subproject. Activity logs track user activities and system events.

    .PARAMETER StartDate
        The start date for the activity log query. Defaults to 7 days ago.

    .PARAMETER EndDate
        The end date for the activity log query. Defaults to current date.

    .PARAMETER ProjectId
        Filter by project ID.

    .PARAMETER SubprojectId
        Filter by subproject ID.

    .PARAMETER EventType
        Filter by event type (e.g., 'USER_ACTION', 'SYSTEM_EVENT').

    .PARAMETER Limit
        Maximum number of results to return. Default is 100.

    .EXAMPLE
        PS> Get-CloudActivityLog

        Retrieves activity logs from the last 7 days.

    .EXAMPLE
        PS> Get-CloudActivityLog -ProjectId "project-123" -StartDate (Get-Date).AddDays(-1)

        Retrieves activity logs for a specific project from the last 24 hours.

    .EXAMPLE
        PS> Get-CloudActivityLog -SubprojectId "subproject-456" -EventType 'USER_ACTION'

        Retrieves user action logs for a specific subproject.

    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.

    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [datetime]$StartDate = (Get-Date).AddDays(-7),

        [Parameter(Mandatory=$false)]
        [datetime]$EndDate = (Get-Date),

        [Parameter(Mandatory=$false)]
        [string]$ProjectId,

        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,

        [Parameter(Mandatory=$false)]
        [ValidateSet('USER_ACTION', 'SYSTEM_EVENT', 'API_CALL', 'ERROR')]
        [string]$EventType,

        [Parameter(Mandatory=$false)]
        [int]$Limit = 100
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
            startDate = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            endDate = $EndDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            size = $Limit
            sort = 'timestamp,desc'
        }

        if ($ProjectId) { $queryParams['projectId'] = $ProjectId }
        if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
        if ($EventType) { $queryParams['eventType'] = $EventType }

        Write-Verbose "Retrieving activity logs from $StartDate to $EndDate"

        $response = Invoke-CloudAPIRequest -Path 'admin/activity-logs' -Method 'GET' -Headers $headers -QueryParameters $queryParams

        return $response
    }
    catch {
        Write-Error "Failed to retrieve activity logs: $($_.Exception.Message)"
        return $null
    }
}
