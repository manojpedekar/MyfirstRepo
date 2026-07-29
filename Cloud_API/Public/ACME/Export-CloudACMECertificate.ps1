function Export-CloudACMECertificate {
    <#
    .SYNOPSIS
        Exports an ACME certificate.
    
    .DESCRIPTION
        Exports an ACME certificate in the specified format (PEM or PFX). The certificate
        can optionally include the full chain and be protected with a password.
    
    .PARAMETER Id
        The unique identifier of the certificate to export. Required.
    
    .PARAMETER Format
        The export format. Options are 'PEM' (default) or 'PFX'.
    
    .PARAMETER IncludeChain
        If specified, includes the certificate chain in the export.
    
    .PARAMETER Password
        Password for PFX export (required when Format is 'PFX').
    
    .EXAMPLE
        PS> Export-CloudACMECertificate -Id "cert-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Exports the certificate in PEM format.
    
    .EXAMPLE
        PS> Export-CloudACMECertificate -Id "cert-55c319eb-5944-4d00-a927-02e2eff4430a" -Format "PFX" -Password (ConvertTo-SecureString "MyPassword" -AsPlainText -Force) -IncludeChain
        
        Exports the certificate as PFX with chain and password protection.
    
    .OUTPUTS
        PSCustomObject with certificate data. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CertificateId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('PEM', 'PFX')]
        [string]$Format = 'PEM',
        
        [Parameter(Mandatory=$false)]
        [switch]$IncludeChain,
        
        [Parameter(Mandatory=$false)]
        [SecureString]$Password
    )
    
    try {
        # Build request body
        $body = @{
            format = $Format
            includeChain = $IncludeChain.IsPresent
        }
        
        # Add password if provided (convert to plain text for API)
        if ($Password) {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            $body['password'] = $plainPassword
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path "acme/certificates/$Id/export" -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to export ACME certificate: $($_.Exception.Message)"
        return $null
    }
}
