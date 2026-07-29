function Get-CloudAccount {
    <#
    .SYNOPSIS
        Retrieves account information.
    
    .DESCRIPTION
        Gets information about a specific account.
    
    .PARAMETER Id
        The unique identifier of the account. Required.
    
    .EXAMPLE
        PS> Get-CloudAccount -Id "account-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for the specified account.
    
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
        [Alias('AccountId')]
        [string]$Id
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "management/accounts/$Id" -Method 'GET' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve account: $($_.Exception.Message)"
        return $null
    }
}
