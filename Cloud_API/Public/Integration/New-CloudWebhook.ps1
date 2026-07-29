function New-CloudWebhook {
    <#
    .SYNOPSIS
        Creates a new webhook.
    
    .DESCRIPTION
        Creates a new webhook that sends HTTP POST requests to the specified
        URL when subscribed events occur.
    
    .PARAMETER Name
        The name for the webhook. Required.
    
    .PARAMETER Url
        The URL to send webhook notifications to. Required.
    
    .PARAMETER EventTypes
        The event types to subscribe to (e.g., 'CREATED', 'UPDATED', 'DELETED').
    
    .PARAMETER Secret
        An optional secret key for webhook signature verification.
    
    .EXAMPLE
        PS> New-CloudWebhook -Name "Instance Monitor" `
             -Url "https://example.com/webhook" `
             -EventTypes @('CREATED', 'DELETED')
        
        Creates a webhook that notifies on instance creation and deletion.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^https?://')]
        [string]$Url,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('CREATED', 'UPDATED', 'DELETED', 'STATUS_CHANGED', 'ALERT_TRIGGERED')]
        [string[]]$EventTypes,
        
        [Parameter(Mandatory=$false)]
        [string]$Secret
    )
    
    try {
        # Build request body
        $body = @{
            name = $Name
            url = $Url
        }
        
        if ($EventTypes) { $body['eventTypes'] = $EventTypes }
        if ($Secret) { $body['secret'] = $Secret }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path 'webhooks' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create webhook: $($_.Exception.Message)"
        return $null
    }
}
