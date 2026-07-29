function New-CloudSupportTicket {
    <#
    .SYNOPSIS
        Creates a new support ticket.

    .DESCRIPTION
        Creates a new support ticket in the SS&C Cloud support system.
        The ticket can be associated with specific accounts or projects
        and assigned a priority and category.

    .PARAMETER Subject
        The subject/title of the support ticket (mandatory).

    .PARAMETER Description
        The detailed description of the issue (mandatory).

    .PARAMETER Priority
        The priority level of the ticket. Valid values: 'Low', 'Medium', 'High', 'Critical'.
        Default is 'Medium'.

    .PARAMETER Category
        The category of the ticket (e.g., 'Technical', 'Billing', 'Access').

    .PARAMETER AccountId
        The account ID to associate with the ticket.

    .PARAMETER ProjectId
        The project ID to associate with the ticket.

    .PARAMETER Wait
        If specified, waits for the ticket to be fully created.

    .EXAMPLE
        PS> New-CloudSupportTicket -Subject "Server Down" -Description "Production server is not responding" -Priority "Critical"

        Creates a critical priority support ticket.

    .EXAMPLE
        PS> New-CloudSupportTicket -Subject "Access Request" -Description "Need access to project X" -Category "Access" -Wait

        Creates a ticket and waits for it to be created.

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
        [string]$Subject,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Description,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$Priority = 'Medium',

        [Parameter(Mandatory=$false)]
        [ValidateSet('Technical', 'Billing', 'Access', 'General')]
        [string]$Category = 'General',

        [Parameter(Mandatory=$false)]
        [string]$AccountId,

        [Parameter(Mandatory=$false)]
        [string]$ProjectId,

        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )

    try {
        if (-not $PSCmdlet.ShouldProcess("support ticket '$Subject'", 'Create')) {
            return $null
        }

        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept

        # Build request body
        $body = @{
            subject = $Subject
            description = $Description
            priority = $Priority
            category = $Category
        }

        if ($AccountId) { $body['accountId'] = $AccountId }
        if ($ProjectId) { $body['projectId'] = $ProjectId }

        Write-Verbose "Creating support ticket with subject: $Subject"

        $response = Invoke-CloudAPIRequest -Path 'support/tickets' -Method 'POST' -Headers $headers -Body $body -Wait:$Wait

        return $response
    }
    catch {
        Write-Error "Failed to create support ticket: $($_.Exception.Message)"
        return $null
    }
}
