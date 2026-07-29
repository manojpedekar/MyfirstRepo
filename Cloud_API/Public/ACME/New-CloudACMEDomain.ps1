function New-CloudACMEDomain {
    <#
    .SYNOPSIS
        Registers a domain with ACME.
    
    .DESCRIPTION
        Registers a new domain with the ACME provider. The domain must pass validation
        using the specified validation method (DNS or HTTP) before certificates can be
        issued for it.
    
    .PARAMETER Domain
        The domain to register. Required.
    
    .PARAMETER ValidationMethod
        The validation method to use. Options are:
        - DNS: DNS TXT record validation (recommended for wildcard certificates)
        - HTTP: HTTP file validation
    
    .EXAMPLE
        PS> New-CloudACMEDomain -Domain "example.com" -ValidationMethod "DNS"
        
        Registers example.com using DNS validation.
    
    .EXAMPLE
        PS> New-CloudACMEDomain -Domain "www.example.com" -ValidationMethod "HTTP"
        
        Registers www.example.com using HTTP validation.
    
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
        [string]$Domain,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('DNS', 'HTTP')]
        [string]$ValidationMethod
    )
    
    try {
        # Build request body
        $body = @{
            domain = $Domain
            validationMethod = $ValidationMethod
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path 'acme/domains' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to register ACME domain: $($_.Exception.Message)"
        return $null
    }
}
