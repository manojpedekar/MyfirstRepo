function New-CloudNotificationChannel {
    <#
    .SYNOPSIS
        Creates a new notification channel.
    
    .DESCRIPTION
        Creates a new notification channel for sending alerts and notifications
        via Email, Slack, or PagerDuty.
    
    .PARAMETER Name
        The name for the notification channel. Required.
    
    .PARAMETER Type
        The type of channel: 'Email', 'Slack', or 'PagerDuty'. Required.
    
    .PARAMETER Configuration
        A hashtable containing channel-specific configuration:
        - Email: @{ recipients = @('user@example.com'); smtpServer = '...' }
        - Slack: @{ webhookUrl = 'https://hooks.slack.com/...'; channel = '#alerts' }
        - PagerDuty: @{ integrationKey = '...'; serviceId = '...' }
    
    .EXAMPLE
        PS> $config = @{ recipients = @('admin@example.com') }
        PS> New-CloudNotificationChannel -Name "Admin Email" -Type "Email" -Configuration $config
        
        Creates an email notification channel.
    
    .EXAMPLE
        PS> $config = @{ webhookUrl = 'https://hooks.slack.com/services/...'; channel = '#ops' }
        PS> New-CloudNotificationChannel -Name "Ops Slack" -Type "Slack" -Configuration $config
        
        Creates a Slack notification channel.
    
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
        [ValidateSet('Email', 'Slack', 'PagerDuty')]
        [string]$Type,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Configuration
    )
    
    try {
        # Build request body
        $body = @{
            name = $Name
            type = $Type
        }
        
        if ($Configuration) { $body['configuration'] = $Configuration }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path 'notifications/channels' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create notification channel: $($_.Exception.Message)"
        return $null
    }
}
