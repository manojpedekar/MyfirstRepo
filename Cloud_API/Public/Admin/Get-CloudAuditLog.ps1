function Get-CloudAuditLog {
    <#
    .SYNOPSIS
        Retrieves audit logs from the SS&C Cloud API.

    .DESCRIPTION
        Gets audit log entries with optional filtering by date range, resource type,
        resource ID, or user ID. Supports pagination for large result sets.

    .PARAMETER StartDate
        The start date for the audit log query. Defaults to 7 days ago.

    .PARAMETER EndDate
        The end date for the audit log query. Defaults to current date.

    .PARAMETER ResourceType
        Filter by resource type (e.g., 'instance', 'network', 'volume').

    .PARAMETER ResourceId
        Filter by specific resource ID.

    .PARAMETER UserId
        Filter by user ID who performed the action.

    .PARAMETER Action
        Filter by action type (e.g., 'CREATE', 'UPDATE', 'DELETE').

    .PARAMETER Limit
        Maximum number of results to return. Default is 100.

    .EXAMPLE
        PS> Get-CloudAuditLog

        Retrieves audit logs from the last 7 days.

    .EXAMPLE
        PS> Get-CloudAuditLog -StartDate (Get-Date).AddDays(-30) -ResourceType 'instance'

        Retrieves instance-related audit logs from the last 30 days.

    .EXAMPLE
        PS> Get-CloudAuditLog -UserId "user@example.com" -Action 'DELETE'

        Retrieves delete actions performed by a specific user.

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
        [string]$ResourceType,

        [Parameter(Mandatory=$false)]
        [string]$ResourceId,

        [Parameter(Mandatory=$false)]
        [string]$UserId,

        [Parameter(Mandatory=$false)]
        [ValidateSet('CREATE', 'READ', 'UPDATE', 'DELETE', 'LOGIN', 'LOGOUT')]
        [string]$Action,

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

        if ($ResourceType) { $queryParams['resourceType'] = $ResourceType }
        if ($ResourceId) { $queryParams['resourceId'] = $ResourceId }
        if ($UserId) { $queryParams['userId'] = $UserId }
        if ($Action) { $queryParams['action'] = $Action }

        Write-Verbose "Retrieving audit logs from $StartDate to $EndDate"

        $response = Invoke-CloudAPIRequest -Path 'admin/audit-logs' -Method 'GET' -Headers $headers -QueryParameters $queryParams

        return $response
    }
    catch {
        Write-Error "Failed to retrieve audit logs: $($_.Exception.Message)"
        return $null
    }
}
