function Test-CloudACMEDomain {
    <#
    .SYNOPSIS
        Tests domain validation for ACME.
    
    .DESCRIPTION
        Tests whether a domain can be validated for ACME certificate issuance.
        This checks DNS records, HTTP accessibility, or other validation requirements
        depending on the configured validation method.
    
    .PARAMETER Domain
        The domain to test. Required.
    
    .PARAMETER Id
        The domain ID to test (alternative to -Domain).
    
    .EXAMPLE
        PS> Test-CloudACMEDomain -Domain "example.com"
        
        Tests validation for example.com.
    
    .EXAMPLE
        PS> Test-CloudACMEDomain -Id "domain-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Tests validation using the domain ID.
    
    .OUTPUTS
        PSCustomObject with test results. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='ByDomain')]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,
        
        [Parameter(Mandatory=$true, ParameterSetName='ById')]
        [ValidateNotNullOrEmpty()]
        [Alias('DomainId')]
        [string]$Id
    )
    
    try {
        # Determine path
        if ($PSCmdlet.ParameterSetName -eq 'ByDomain') {
            # First get the domain ID
            $domainInfo = Get-CloudACMEDomain -Domain $Domain | Select-Object -First 1
            if (-not $domainInfo) {
                Write-Error "Domain '$Domain' not found"
                return $null
            }
            $Id = $domainInfo.id
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders
        $response = Invoke-CloudAPIRequest -Path "acme/domains/$Id/test" -Method 'POST' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to test ACME domain validation: $($_.Exception.Message)"
        return $null
    }
}
