function Get-CloudACMECertificate {
    <#
    .SYNOPSIS
        Retrieves ACME certificates from the cloud platform.
    
    .DESCRIPTION
        Gets details about one or more ACME certificates. Can retrieve a specific certificate
        by ID or list all certificates with optional filtering by domain or status.
        
        ACME (Automated Certificate Management Environment) certificates are automatically
        provisioned and renewed SSL/TLS certificates.
    
    .PARAMETER Id
        The unique identifier of the certificate to retrieve.
    
    .PARAMETER Domain
        Filter certificates by domain name (supports wildcards).
    
    .PARAMETER Status
        Filter certificates by status (e.g., 'active', 'expired', 'pending', 'revoked').
    
    .EXAMPLE
        PS> Get-CloudACMECertificate
        
        Lists all ACME certificates in the account.
    
    .EXAMPLE
        PS> Get-CloudACMECertificate -Id "cert-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves details for a specific certificate.
    
    .EXAMPLE
        PS> Get-CloudACMECertificate -Domain "*.example.com"
        
        Lists all certificates for the example.com domain and subdomains.
    
    .EXAMPLE
        PS> Get-CloudACMECertificate -Status "active"
        
        Lists all active certificates.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('CertificateId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Domain,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('active', 'expired', 'pending', 'revoked', 'renewing')]
        [string]$Status
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # Build query parameters
            $queryParams = @{
                sort = 'domain,asc'
            }
            
            if ($Domain) { $queryParams['domain'] = $Domain }
            if ($Status) { $queryParams['status'] = $Status }
            
            # Determine path
            if ($Id) {
                $path = "acme/certificates/$Id"
            } else {
                $path = "acme/certificates"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve ACME certificate(s): $($_.Exception.Message)"
            return $null
        }
    }
}
