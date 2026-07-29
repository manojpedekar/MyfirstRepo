function Get-CloudCertificateInstallation {
    <#
    .SYNOPSIS
        Retrieves certificate installation information.
    
    .DESCRIPTION
        Gets information about where ACME certificates are installed and their
        configuration on various cloud resources.
    
    .PARAMETER CertificateId
        Filter by certificate ID to see installations of a specific certificate.
    
    .PARAMETER ResourceId
        Filter by resource ID to see certificates installed on a specific resource.
    
    .PARAMETER Id
        Get a specific installation by ID.
    
    .EXAMPLE
        PS> Get-CloudCertificateInstallation
        
        Lists all certificate installations.
    
    .EXAMPLE
        PS> Get-CloudCertificateInstallation -CertificateId "cert-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Lists all installations of the specified certificate.
    
    .EXAMPLE
        PS> Get-CloudCertificateInstallation -ResourceId "lb-abc123"
        
        Lists all certificates installed on the specified resource.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$CertificateId,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceId,
        
        [Parameter(Mandatory=$false)]
        [Alias('InstallationId')]
        [string]$Id
    )
    
    try {
        # Build query parameters
        $queryParams = @{}
        
        if ($CertificateId) { $queryParams['certificateId'] = $CertificateId }
        if ($ResourceId) { $queryParams['resourceId'] = $ResourceId }
        
        # Determine path
        if ($Id) {
            $path = "acme/certificates/install/$Id"
        } else {
            $path = "acme/certificates/install"
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders
        $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve certificate installation(s): $($_.Exception.Message)"
        return $null
    }
}
