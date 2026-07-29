function Install-CloudACMECertificate {
    <#
    .SYNOPSIS
        Installs an ACME certificate to a cloud resource.
    
    .DESCRIPTION
        Installs a specified ACME certificate to a cloud resource such as a load
        balancer, instance, or application gateway. The certificate will be
        configured for use by the specified resource.
        
        By default, this function returns immediately after submitting the request.
        Use the -Wait switch to wait for the installation to complete.
    
    .PARAMETER CertificateId
        The unique identifier of the certificate to install. Required.
    
    .PARAMETER ResourceType
        The type of resource to install the certificate on (e.g., 'loadbalancer', 'instance', 'applicationgateway').
    
    .PARAMETER ResourceId
        The unique identifier of the target resource.
    
    .PARAMETER Port
        The port to configure with the certificate (for load balancers).
    
    .PARAMETER Wait
        If specified, waits for the installation to complete before returning.
    
    .PARAMETER Async
        If specified, returns immediately with the operation/job object for tracking.
    
    .EXAMPLE
        PS> Install-CloudACMECertificate -CertificateId "cert-55c319eb-5944-4d00-a927-02e2eff4430a" -ResourceType "loadbalancer" -ResourceId "lb-abc123"
        
        Installs the certificate to the specified load balancer.
    
    .EXAMPLE
        PS> Install-CloudACMECertificate -CertificateId "cert-55c319eb-5944-4d00-a927-02e2eff4430a" -ResourceType "loadbalancer" -ResourceId "lb-abc123" -Port 443 -Wait
        
        Installs the certificate on port 443 and waits for completion.
    
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
        [Alias('Id')]
        [string]$CertificateId,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('loadbalancer', 'instance', 'applicationgateway', 'cdn')]
        [string]$ResourceType,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceId,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 65535)]
        [int]$Port,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    try {
        # Validate port is only used with appropriate resource types
        if ($Port -and $ResourceType -notin @('loadbalancer', 'applicationgateway')) {
            Write-Warning "Port parameter is typically only used with loadbalancer or applicationgateway resource types. It may be ignored for $ResourceType."
        }
        
        # Build request body
        $body = @{
            certificateId = $CertificateId
            resourceType = $ResourceType
            resourceId = $ResourceId
        }
        
        if ($Port) {
            $body['port'] = $Port
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        # Build invoke parameters
        $invokeParams = @{
            Path = 'acme/certificates/install'
            Method = 'POST'
            Headers = $headers
            Body = $body
        }
        
        if ($Wait) { $invokeParams['Wait'] = $true }
        if ($Async) { $invokeParams['Async'] = $true }
        
        # Request certificate installation
        $response = Invoke-CloudAPIRequest @invokeParams
        
        return $response
    }
    catch {
        Write-Error "Failed to install ACME certificate: $($_.Exception.Message)"
        return $null
    }
}
