function Test-CloudWebhook {
    <#
    .SYNOPSIS
        Tests a webhook configuration.
    
    .DESCRIPTION
        Sends a test event to the webhook URL to verify it is configured
        correctly and can receive notifications.
    
    .PARAMETER Id
        The unique identifier of the webhook to test. Required.
    
    .EXAMPLE
        PS> Test-CloudWebhook -Id "webhook-123"
        
        Sends a test event to the webhook.
    
    .OUTPUTS
        PSCustomObject containing test results. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('WebhookId')]
        [string]$Id
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType
            
            $response = Invoke-CloudAPIRequest -Path "webhooks/$Id/test" -Method 'POST' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to test webhook: $($_.Exception.Message)"
            return $null
        }
    }
}
