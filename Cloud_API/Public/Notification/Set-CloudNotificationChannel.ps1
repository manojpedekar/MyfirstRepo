function Set-CloudNotificationChannel {
    <#
    .SYNOPSIS
        Updates an existing notification channel.
    
    .DESCRIPTION
        Updates the configuration of an existing notification channel.
        The type cannot be changed; to change types, create a new channel.
    
    .PARAMETER Id
        The unique identifier of the notification channel to update. Required.
    
    .PARAMETER Configuration
        The updated configuration hashtable for the channel.
    
    .EXAMPLE
        PS> $config = @{ recipients = @('newadmin@example.com') }
        PS> Set-CloudNotificationChannel -Id "channel-123" -Configuration $config
        
        Updates the email recipients.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('ChannelId')]
        [string]$Id,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Configuration
    )
    
    process {
        try {
            # Build request body
            $body = @{
                configuration = $Configuration
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType
            $response = Invoke-CloudAPIRequest -Path "notifications/channels/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            return $response
        }
        catch {
            Write-Error "Failed to update notification channel: $($_.Exception.Message)"
            return $null
        }
    }
}
