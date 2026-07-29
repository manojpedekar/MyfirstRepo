function Remove-CloudNotificationChannel {
    <#
    .SYNOPSIS
        Deletes a notification channel.
    
    .DESCRIPTION
        Permanently deletes a notification channel from the cloud platform.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the notification channel to delete. Required.
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudNotificationChannel -Id "channel-123" -Force
        
        Deletes the notification channel without confirmation.
    
    .OUTPUTS
        PSCustomObject or $null. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('ChannelId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Confirm action
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("notification channel '$Id'", 'Remove')) {
                return $null
            }
            
            $headers = New-CloudAPIHeaders -IncludeContentType
            
            $response = Invoke-CloudAPIRequest -Path "notifications/channels/$Id" -Method 'DELETE' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to remove notification channel: $($_.Exception.Message)"
            return $null
        }
    }
}
