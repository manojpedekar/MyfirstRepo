function Get-CloudSupportTicket {
    <#
    .SYNOPSIS
        Retrieves support tickets from the SS&C Cloud API.

    .DESCRIPTION
        Gets one or more support tickets with optional filtering by status, priority,
        account, or project. Returns ticket details including subject, description,
        status, priority, and comments.

    .PARAMETER Id
        The unique identifier of the support ticket to retrieve.

    .PARAMETER Status
        Filter tickets by status (e.g., 'Open', 'In Progress', 'Closed').

    .PARAMETER Priority
        Filter tickets by priority (e.g., 'Low', 'Medium', 'High', 'Critical').

    .PARAMETER AccountId
        Filter tickets by account ID.

    .PARAMETER ProjectId
        Filter tickets by project ID.

    .EXAMPLE
        PS> Get-CloudSupportTicket

        Retrieves all support tickets accessible to the current user.

    .EXAMPLE
        PS> Get-CloudSupportTicket -Id "ticket-12345"

        Retrieves a specific support ticket by ID.

    .EXAMPLE
        PS> Get-CloudSupportTicket -Status 'Open' -Priority 'High'

        Retrieves all open tickets with high priority.

    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.

    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('TicketId')]
        [string]$Id,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Open', 'In Progress', 'Pending', 'Resolved', 'Closed')]
        [string]$Status,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$Priority,

        [Parameter(Mandatory=$false)]
        [string]$AccountId,

        [Parameter(Mandatory=$false)]
        [string]$ProjectId
    )

    begin {
        $headers = New-CloudAPIHeaders
    }

    process {
        try {
            # Build query parameters
            $queryParams = @{
                sort = 'createdAt,desc'
            }

            if ($Status) { $queryParams['status'] = $Status }
            if ($Priority) { $queryParams['priority'] = $Priority }
            if ($AccountId) { $queryParams['accountId'] = $AccountId }
            if ($ProjectId) { $queryParams['projectId'] = $ProjectId }

            # Determine path based on whether Id is provided
            $path = if ($Id) { "support/tickets/$Id" } else { 'support/tickets' }

            Write-Verbose "Retrieving support ticket(s) from path: $path"

            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams

            return $response
        }
        catch {
            Write-Error "Failed to retrieve support ticket(s): $($_.Exception.Message)"
            return $null
        }
    }
}
