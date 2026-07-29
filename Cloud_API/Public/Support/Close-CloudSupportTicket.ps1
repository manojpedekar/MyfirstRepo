function Close-CloudSupportTicket {
    <#
    .SYNOPSIS
        Closes a support ticket.

    .DESCRIPTION
        Closes an existing support ticket with an optional resolution note.
        This action changes the ticket status to 'Closed'.

    .PARAMETER Id
        The unique identifier of the support ticket to close (mandatory).

    .PARAMETER Resolution
        An optional resolution note explaining how the issue was resolved.

    .EXAMPLE
        PS> Close-CloudSupportTicket -Id "ticket-12345"

        Closes the support ticket.

    .EXAMPLE
        PS> Close-CloudSupportTicket -Id "ticket-12345" -Resolution "Issue resolved by restarting the service."

        Closes the ticket with a resolution note.

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
        [string]$Resolution
    )

    process {
        try {
            if (-not $PSCmdlet.ShouldProcess("support ticket '$Id'", 'Close')) {
                return $null
            }

            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept

            # Build request body
            $body = @{}
            if ($Resolution) {
                $body['resolution'] = $Resolution
            }

            Write-Verbose "Closing support ticket: $Id"

            $response = Invoke-CloudAPIRequest -Path "support/tickets/$Id/close" -Method 'POST' -Headers $headers -Body $body

            return $response
        }
        catch {
            Write-Error "Failed to close support ticket: $($_.Exception.Message)"
            return $null
        }
    }
}
