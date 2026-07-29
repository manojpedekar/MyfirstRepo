function Get-CloudUserPreference {
    <#
    .SYNOPSIS
        Retrieves user preferences for a specific user.
    
    .DESCRIPTION
        Gets the preferences and settings stored for a cloud user,
        including UI preferences, notification settings, etc.
    
    .PARAMETER UserId
        The unique identifier of the user whose preferences to retrieve. Required.
    
    .EXAMPLE
        PS> Get-CloudUserPreference -UserId "user-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves preferences for the specified user.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$UserId
    )
    
    process {
        try {
            # Make API request
            $headers = New-CloudAPIHeaders
            $response = Invoke-CloudAPIRequest -Path "iam/users/$UserId/preferences" -Method 'GET' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve preferences for user '$UserId': $($_.Exception.Message)"
            return $null
        }
    }
}
