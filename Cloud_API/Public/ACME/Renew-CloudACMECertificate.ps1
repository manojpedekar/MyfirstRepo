function Renew-CloudACMECertificate {
    <#
    .SYNOPSIS
        Renews an ACME certificate.
    
    .DESCRIPTION
        Initiates the renewal process for an existing ACME certificate. The certificate
        will be renewed with the same domain(s) and configuration as the original.
        
        By default, this function returns immediately after submitting the renewal request.
        Use the -Wait switch to wait for the renewal to complete.
    
    .PARAMETER Id
        The unique identifier of the certificate to renew. Required.
    
    .PARAMETER Wait
        If specified, waits for the renewal to complete before returning.
    
    .PARAMETER Async
        If specified, returns immediately with the operation/job object for tracking.
    
    .EXAMPLE
        PS> Renew-CloudACMECertificate -Id "cert-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Initiates renewal of the specified certificate.
    
    .EXAMPLE
        PS> Renew-CloudACMECertificate -Id "cert-55c319eb-5944-4d00-a927-02e2eff4430a" -Wait
        
        Renews the certificate and waits for completion.
    
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
        [Alias('CertificateId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    process {
        try {
            # Make API request
            $headers = New-CloudAPIHeaders
            
            # Build invoke parameters
            $invokeParams = @{
                Path = "acme/certificates/$Id/renew"
                Method = 'POST'
                Headers = $headers
            }
            
            if ($Wait) { $invokeParams['Wait'] = $true }
            if ($Async) { $invokeParams['Async'] = $true }
            
            # Request certificate renewal
            $response = Invoke-CloudAPIRequest @invokeParams
            
            return $response
        }
        catch {
            Write-Error "Failed to renew ACME certificate: $($_.Exception.Message)"
            return $null
        }
    }
}
