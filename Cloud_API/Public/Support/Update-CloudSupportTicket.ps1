function Update-CloudSupportTicket {
    <#
    .SYNOPSIS
        Adds a comment or update to a support ticket.

    .DESCRIPTION
        Adds a comment or internal note to an existing support ticket.
        This is used for ongoing communication about the ticket.

    .PARAMETER Id
        The unique identifier of the support ticket to update (mandatory).

    .PARAMETER Comment
        The comment text to add to the ticket (mandatory).

    .PARAMETER Internal
        If specified, marks the comment as internal (not visible to customer).

    .EXAMPLE
        PS> Update-CloudSupportTicket -Id "ticket-12345" -Comment "Working on this issue now."

        Adds a comment to the ticket.

    .EXAMPLE
        PS> Update-CloudSupportTicket -Id "ticket-12345" -Comment "Internal note" -Internal

        Adds an internal note to the ticket.

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

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Comment,

        [Parameter(Mandatory=$false)]
        [switch]$Internal
    )

    process {
        try {
            if (-not $PSCmdlet.ShouldProcess("support ticket '$Id'", 'Add Comment')) {
                return $null
            }

            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept

            # Build request body
            $body = @{
                comment = $Comment
                internal = $Internal.IsPresent
            }

            Write-Verbose "Adding comment to support ticket: $Id"

            $response = Invoke-CloudAPIRequest -Path "support/tickets/$Id/comments" -Method 'POST' -Headers $headers -Body $body

            return $response
        }
        catch {
            Write-Error "Failed to update support ticket: $($_.Exception.Message)"
            return $null
        }
    }
}
