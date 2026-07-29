function Get-CloudACMEDomain {
    <#
    .SYNOPSIS
        Retrieves ACME-managed domains.
    
    .DESCRIPTION
        Gets details about one or more domains managed by ACME. Can retrieve a specific
        domain by ID or list all domains with optional filtering.
        
        These domains have been registered with the ACME provider and can have
        certificates issued for them.
    
    .PARAMETER Id
        The unique identifier of the domain to retrieve.
    
    .PARAMETER Domain
        Filter by domain name (supports wildcards).
    
    .PARAMETER Status
        Filter by status (e.g., 'active', 'pending', 'failed', 'suspended').
    
    .EXAMPLE
        PS> Get-CloudACMEDomain
        
        Lists all ACME-managed domains.
    
    .EXAMPLE
        PS> Get-CloudACMEDomain -Id "domain-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves details for a specific domain.
    
    .EXAMPLE
        PS> Get-CloudACMEDomain -Domain "*.example.com"
        
        Lists all domains matching the pattern.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('DomainId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Domain,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('active', 'pending', 'failed', 'suspended', 'validating')]
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
                $path = "acme/domains/$Id"
            } else {
                $path = "acme/domains"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve ACME domain(s): $($_.Exception.Message)"
            return $null
        }
    }
}
