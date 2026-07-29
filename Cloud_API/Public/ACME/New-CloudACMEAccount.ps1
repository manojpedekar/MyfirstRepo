function New-CloudACMEAccount {
    <#
    .SYNOPSIS
        Creates a new ACME account.
    
    .DESCRIPTION
        Registers a new account with an ACME certificate authority. This account
        can then be used to request and manage certificates.
        
        The email address is used for important notifications about certificate
        expirations and account issues.
    
    .PARAMETER Email
        The contact email address for the account. Required.
    
    .PARAMETER AcceptTerms
        Indicates acceptance of the ACME provider's terms of service. Required.
    
    .PARAMETER Provider
        The ACME provider to use. Defaults to 'letsencrypt'.
    
    .EXAMPLE
        PS> New-CloudACMEAccount -Email "admin@example.com" -AcceptTerms
        
        Creates a new ACME account with the specified email.
    
    .EXAMPLE
        PS> New-CloudACMEAccount -Email "admin@example.com" -AcceptTerms -Provider "letsencrypt-staging"
        
        Creates an account with the Let's Encrypt staging environment.
    
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
        [ValidatePattern('^[\w\.-]+@[\w\.-]+\.\w+$')]
        [string]$Email,
        
        [Parameter(Mandatory=$true)]
        [switch]$AcceptTerms,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('letsencrypt', 'letsencrypt-staging')]
        [string]$Provider = 'letsencrypt'
    )
    
    try {
        # Build request body
        $body = @{
            email = $Email
            acceptTerms = $true
            provider = $Provider
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path 'acme/accounts' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create ACME account: $($_.Exception.Message)"
        return $null
    }
}
