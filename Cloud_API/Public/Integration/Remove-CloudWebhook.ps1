function Remove-CloudWebhook {
    <#
    .SYNOPSIS
        Deletes a webhook.
    
    .DESCRIPTION
        Permanently deletes a webhook from the cloud platform.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the webhook to delete. Required.
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudWebhook -Id "webhook-123" -Force
        
        Deletes the webhook without confirmation.
    
    .OUTPUTS
        PSCustomObject or $null. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('WebhookId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Confirm action
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("webhook '$Id'", 'Remove')) {
                return $null
            }
            
            $headers = New-CloudAPIHeaders -IncludeContentType
            
            $response = Invoke-CloudAPIRequest -Path "webhooks/$Id" -Method 'DELETE' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to remove webhook: $($_.Exception.Message)"
            return $null
        }
    }
}
