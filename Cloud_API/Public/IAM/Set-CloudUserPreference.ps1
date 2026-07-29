function Set-CloudUserPreference {
    <#
    .SYNOPSIS
        Sets user preferences for a specific user.
    
    .DESCRIPTION
        Updates or creates preferences for a cloud user. Preferences are
        stored as key-value pairs and can include UI settings, notification
        preferences, and other user-specific configurations.
    
    .PARAMETER UserId
        The unique identifier of the user whose preferences to set. Required.
    
    .PARAMETER Preferences
        A hashtable of preference key-value pairs. Required.
    
    .EXAMPLE
        PS> Set-CloudUserPreference -UserId "user-55c319eb-5944-4d00-a927-02e2eff4430a" `
            -Preferences @{ theme = "dark"; notifications = $true }
        
        Sets user preferences for the specified user.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$UserId,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Preferences
    )
    
    process {
        try {
            # Validate preferences is not empty
            if ($Preferences.Count -eq 0) {
                Write-Error "Preferences hashtable cannot be empty"
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            $response = Invoke-CloudAPIRequest -Path "iam/users/$UserId/preferences" -Method 'PUT' -Headers $headers -Body $Preferences
            
            return $response
        }
        catch {
            Write-Error "Failed to set preferences for user '$UserId': $($_.Exception.Message)"
            return $null
        }
    }
}
