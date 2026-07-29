function Get-CloudNotificationChannel {
    <#
    .SYNOPSIS
        Retrieves notification channels from the cloud platform.
    
    .DESCRIPTION
        Gets notification channels from the SS&C Cloud platform. Can retrieve
        a specific channel by ID or list all channels with optional filtering
        by type (Email, Slack, PagerDuty).
    
    .PARAMETER Id
        The unique identifier of the notification channel to retrieve.
    
    .PARAMETER Type
        Filter channels by type: 'Email', 'Slack', or 'PagerDuty'.
    
    .EXAMPLE
        PS> Get-CloudNotificationChannel
        
        Retrieves all notification channels.
    
    .EXAMPLE
        PS> Get-CloudNotificationChannel -Type 'Slack'
        
        Retrieves all Slack notification channels.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('ChannelId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Email', 'Slack', 'PagerDuty')]
        [string]$Type
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
            
            if ($Type) { $queryParams['type'] = $Type }
            
            # Determine path
            if ($Id) {
                $path = "notifications/channels/$Id"
            } else {
                $path = 'notifications/channels'
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve notification channel(s): $($_.Exception.Message)"
            return $null
        }
    }
}
