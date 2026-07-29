function Get-CloudWebhook {
    <#
    .SYNOPSIS
        Retrieves webhooks from the cloud platform.
    
    .DESCRIPTION
        Gets webhooks from the SS&C Cloud platform. Can retrieve a specific
        webhook by ID or list all webhooks with optional filtering.
    
    .PARAMETER Id
        The unique identifier of the webhook to retrieve.
    
    .PARAMETER ResourceType
        Filter webhooks by resource type.
    
    .PARAMETER EventType
        Filter webhooks by event type (e.g., 'CREATED', 'UPDATED', 'DELETED').
    
    .EXAMPLE
        PS> Get-CloudWebhook
        
        Retrieves all webhooks.
    
    .EXAMPLE
        PS> Get-CloudWebhook -Id "webhook-12345"
        
        Retrieves details for a specific webhook.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('WebhookId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceType,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('CREATED', 'UPDATED', 'DELETED', 'STATUS_CHANGED', 'ALERT_TRIGGERED')]
        [string]$EventType
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # Build query parameters
            $queryParams = @{
                sort = 'name,asc'
            }
            
            if ($ResourceType) { $queryParams['resourceType'] = $ResourceType }
            if ($EventType) { $queryParams['eventType'] = $EventType }
            
            # Determine path
            if ($Id) {
                $path = "webhooks/$Id"
            } else {
                $path = 'webhooks'
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve webhook(s): $($_.Exception.Message)"
            return $null
        }
    }
}
