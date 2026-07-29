function Enable-CloudUser {
    <#
    .SYNOPSIS
        Enables a disabled user account.
    
    .DESCRIPTION
        Activates a previously disabled user account, allowing the user to
        access the cloud platform again.
    
    .PARAMETER Id
        The unique identifier of the user to enable. Required.
    
    .EXAMPLE
        PS> Enable-CloudUser -Id "user-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Enables the specified user account.
    
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
            $response = Invoke-CloudAPIRequest -Path "iam/users/$Id/enable" -Method 'POST' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to enable user '$Id': $($_.Exception.Message)"
            return $null
        }
    }
}
