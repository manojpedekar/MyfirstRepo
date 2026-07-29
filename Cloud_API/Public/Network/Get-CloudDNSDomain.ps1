function Get-CloudDNSDomain {
    <#
    .SYNOPSIS
        Retrieves DNS domains.
    
    .DESCRIPTION
        Gets DNS domains managed by the cloud platform.
        Can retrieve a specific domain by ID or list all domains for a sub-project.
    
    .PARAMETER Id
        The unique identifier of the DNS domain.
    
    .PARAMETER SubprojectId
        The sub-project ID to list DNS domains from.
    
    .EXAMPLE
        PS> Get-CloudDNSDomain -Id "domain-..."
        
        Retrieves details for a specific DNS domain.
    
    .EXAMPLE
        PS> Get-CloudDNSDomain -SubprojectId "subproject-..."
        
        Lists all DNS domains in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('DNSDomainId', 'DomainId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/dns/domains/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/dns/domains' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve DNS domain(s): $($_.Exception.Message)"
        return $null
    }
}
