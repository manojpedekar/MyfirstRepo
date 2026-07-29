function Set-CloudSupportTicket {
    <#
    .SYNOPSIS
        Updates an existing support ticket.

    .DESCRIPTION
        Updates the status and/or priority of an existing support ticket.
        At least one update parameter must be specified.

    .PARAMETER Id
        The unique identifier of the support ticket to update (mandatory).

    .PARAMETER Status
        The new status of the ticket. Valid values: 'Open', 'In Progress', 'Pending', 'Resolved', 'Closed'.

    .PARAMETER Priority
        The new priority of the ticket. Valid values: 'Low', 'Medium', 'High', 'Critical'.

    .EXAMPLE
        PS> Set-CloudSupportTicket -Id "ticket-12345" -Status 'In Progress'

        Updates the ticket status to 'In Progress'.

    .EXAMPLE
        PS> Set-CloudSupportTicket -Id "ticket-12345" -Priority 'High' -Status 'Pending'

        Updates both priority and status.

    .OUTPUTS
        PSCustomObject. Returns $null on error.

    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('TicketId')]
        [string]$Id,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Open', 'In Progress', 'Pending', 'Resolved', 'Closed')]
        [string]$Status,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$Priority
    )

    process {
        try {
            # Validate at least one update parameter is provided
            if (-not $Status -and -not $Priority) {
                Write-Warning "No update parameters specified. Please provide Status and/or Priority."
                return $null
            }

            if (-not $PSCmdlet.ShouldProcess("support ticket '$Id'", 'Update')) {
                return $null
            }

            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept

            # Build body dynamically
            $body = @{}
            if ($Status) { $body['status'] = $Status }
            if ($Priority) { $body['priority'] = $Priority }

            Write-Verbose "Updating support ticket: $Id"

            $response = Invoke-CloudAPIRequest -Path "support/tickets/$Id" -Method 'PUT' -Headers $headers -Body $body

            return $response
        }
        catch {
            Write-Error "Failed to update support ticket: $($_.Exception.Message)"
            return $null
        }
    }
}
