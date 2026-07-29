function Set-CloudWebhook {
    <#
    .SYNOPSIS
        Updates an existing webhook.
    
    .DESCRIPTION
        Updates the configuration of an existing webhook, including URL,
        event types, and enabled status.
    
    .PARAMETER Id
        The unique identifier of the webhook to update. Required.
    
    .PARAMETER Url
        The new URL for webhook notifications.
    
    .PARAMETER EventTypes
        The new set of event types to subscribe to.
    
    .PARAMETER Enabled
        Whether the webhook is enabled ($true) or disabled ($false).
    
    .EXAMPLE
        PS> Set-CloudWebhook -Id "webhook-123" -Url "https://new.example.com/webhook"
        
        Updates the webhook URL.
    
    .EXAMPLE
        PS> Set-CloudWebhook -Id "webhook-123" -Enabled $false
        
        Disables the webhook.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('WebhookId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [ValidatePattern('^https?://')]
        [string]$Url,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('CREATED', 'UPDATED', 'DELETED', 'STATUS_CHANGED', 'ALERT_TRIGGERED')]
        [string[]]$EventTypes,
        
        [Parameter(Mandatory=$false)]
        [bool]$Enabled
    )
    
    process {
        try {
            # Build request body with only specified parameters
            $body = @{}
            
            if ($PSBoundParameters.ContainsKey('Url')) { $body['url'] = $Url }
            if ($PSBoundParameters.ContainsKey('EventTypes')) { $body['eventTypes'] = $EventTypes }
            if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = $Enabled }
            
            # Check if any parameters were provided
            if ($body.Count -eq 0) {
                Write-Warning "No parameters specified for update. Webhook remains unchanged."
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType
            $response = Invoke-CloudAPIRequest -Path "webhooks/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            return $response
        }
        catch {
            Write-Error "Failed to update webhook: $($_.Exception.Message)"
            return $null
        }
    }
}
