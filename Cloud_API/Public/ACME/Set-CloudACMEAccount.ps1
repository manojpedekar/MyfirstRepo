function Set-CloudACMEAccount {
    <#
    .SYNOPSIS
        Updates an ACME account.
    
    .DESCRIPTION
        Updates the configuration of an existing ACME account. Currently supports
        updating the contact email address.
    
    .PARAMETER Id
        The unique identifier of the account to update. Required.
    
    .PARAMETER Email
        The new contact email address.
    
    .EXAMPLE
        PS> Set-CloudACMEAccount -Id "acme-acc-55c319eb-5944-4d00-a927-02e2eff4430a" -Email "newadmin@example.com"
        
        Updates the account's email address.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('AccountId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[\w\.-]+@[\w\.-]+\.\w+$')]
        [string]$Email
    )
    
    process {
        try {
            # Build request body with only provided parameters
            $body = @{}
            
            if ($Email) {
                $body['email'] = $Email
            }
            
            # Check if any updates were specified
            if ($body.Count -eq 0) {
                Write-Warning "No updates specified. Nothing to change."
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType
            $response = Invoke-CloudAPIRequest -Path "acme/accounts/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            return $response
        }
        catch {
            Write-Error "Failed to update ACME account: $($_.Exception.Message)"
            return $null
        }
    }
}
