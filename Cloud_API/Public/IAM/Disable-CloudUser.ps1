function Disable-CloudUser {
    <#
    .SYNOPSIS
        Disables a user account.
    
    .DESCRIPTION
        Deactivates a user account, preventing the user from accessing the
        cloud platform. The user account is not deleted.
    
    .PARAMETER Id
        The unique identifier of the user to disable. Required.
    
    .EXAMPLE
        PS> Disable-CloudUser -Id "user-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Disables the specified user account.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('UserId')]
        [string]$Id
    )
    
    process {
        try {
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType
            $response = Invoke-CloudAPIRequest -Path "iam/users/$Id/disable" -Method 'POST' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to disable user '$Id': $($_.Exception.Message)"
            return $null
        }
    }
}
