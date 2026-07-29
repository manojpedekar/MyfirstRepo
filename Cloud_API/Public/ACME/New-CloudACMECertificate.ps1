function New-CloudACMECertificate {
    <#
    .SYNOPSIS
        Requests a new ACME certificate.
    
    .DESCRIPTION
        Creates a new ACME certificate request for the specified domain. The certificate
        will be automatically provisioned and can include Subject Alternative Names (SANs).
        
        By default, this function returns immediately after submitting the request. Use the
        -Wait switch to wait for the certificate to be issued.
    
    .PARAMETER Domain
        The primary domain for the certificate. Required.
    
    .PARAMETER SubjectAlternativeNames
        Additional domains or subdomains to include in the certificate (SANs).
    
    .PARAMETER KeyType
        The type of key to use for the certificate. Defaults to 'RSA'.
    
    .PARAMETER KeySize
        The key size in bits. Defaults to 2048.
    
    .PARAMETER Wait
        If specified, waits for the certificate to be issued before returning.
    
    .PARAMETER Async
        If specified, returns immediately with the operation/job object for tracking.
    
    .EXAMPLE
        PS> New-CloudACMECertificate -Domain "www.example.com"
        
        Requests a new certificate for www.example.com.
    
    .EXAMPLE
        PS> New-CloudACMECertificate -Domain "example.com" -SubjectAlternativeNames @("www.example.com", "api.example.com") -Wait
        
        Requests a certificate with SANs and waits for completion.
    
    .EXAMPLE
        PS> New-CloudACMECertificate -Domain "secure.example.com" -KeyType "ECDSA" -KeySize 256
        
        Requests a certificate using ECDSA P-256 key.
    
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
        
        [Parameter(Mandatory=$false)]
        [string[]]$SubjectAlternativeNames,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('RSA', 'ECDSA')]
        [string]$KeyType = 'RSA',
        
        [Parameter(Mandatory=$false)]
        [ValidateSet(2048, 3072, 4096, 256, 384, 521)]
        [int]$KeySize = 2048,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    try {
        # Build request body
        $body = @{
            domain = $Domain
            keyType = $KeyType
            keySize = $KeySize
        }
        
        if ($SubjectAlternativeNames) {
            $body['subjectAlternativeNames'] = $SubjectAlternativeNames
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        # Build invoke parameters
        $invokeParams = @{
            Path = 'acme/certificates'
            Method = 'POST'
            Headers = $headers
            Body = $body
        }
        
        if ($Wait) { $invokeParams['Wait'] = $true }
        if ($Async) { $invokeParams['Async'] = $true }
        
        # Request certificate
        $response = Invoke-CloudAPIRequest @invokeParams
        
        return $response
    }
    catch {
        Write-Error "Failed to request ACME certificate: $($_.Exception.Message)"
        return $null
    }
}
