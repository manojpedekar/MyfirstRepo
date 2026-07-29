function Remove-CloudSupportTicket {
    <#
    .SYNOPSIS
        Deletes a support ticket.

    .DESCRIPTION
        Permanently deletes a support ticket from the system.
        Note: This action may not be allowed for all tickets depending on
        system configuration and permissions.

    .PARAMETER Id
        The unique identifier of the support ticket to delete (mandatory).

    .PARAMETER Force
        Bypass confirmation prompts.

    .EXAMPLE
        PS> Remove-CloudSupportTicket -Id "ticket-12345" -Force

        Deletes the support ticket without confirmation.

    .OUTPUTS
        PSCustomObject or $null.

    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('TicketId')]
        [string]$Id,

        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    process {
        try {
            # Get ticket details for better confirmation message
            $ticket = Get-CloudSupportTicket -Id $Id
            $ticketSubject = if ($ticket) { $ticket.subject } else { $Id }

            if (-not $Force -and -not $PSCmdlet.ShouldProcess("support ticket '$ticketSubject' ($Id)", 'Remove')) {
                return $null
            }

            $headers = New-CloudAPIHeaders -IncludeContentType

            Write-Verbose "Removing support ticket: $Id"

            $response = Invoke-CloudAPIRequest -Path "support/tickets/$Id" -Method 'DELETE' -Headers $headers

            return $response
        }
        catch {
            Write-Error "Failed to remove support ticket: $($_.Exception.Message)"
            return $null
        }
    }
}
