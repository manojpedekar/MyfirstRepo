function Get-CloudACMEAccount {
    <#
    .SYNOPSIS
        Retrieves ACME account information.
    
    .DESCRIPTION
        Gets details about one or more ACME accounts configured in the system.
        ACME accounts are used to manage certificates with external certificate
        authorities like Let's Encrypt.
    
    .PARAMETER Id
        The unique identifier of the account to retrieve.
    
    .EXAMPLE
        PS> Get-CloudACMEAccount
        
        Lists all ACME accounts.
    
    .EXAMPLE
        PS> Get-CloudACMEAccount -Id "acme-acc-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves details for a specific account.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('AccountId')]
        [string]$Id
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # Determine path
            if ($Id) {
                $path = "acme/accounts/$Id"
            } else {
                $path = "acme/accounts"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve ACME account(s): $($_.Exception.Message)"
            return $null
        }
    }
}
