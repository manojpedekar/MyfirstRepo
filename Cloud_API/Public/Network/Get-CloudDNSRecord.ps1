function Get-CloudDNSRecord {
    <#
    .SYNOPSIS
        Retrieves DNS records.
    
    .DESCRIPTION
        Gets DNS records for a domain.
        Can retrieve a specific record by ID or list all records, optionally filtered by type.
    
    .PARAMETER DomainId
        The domain ID to list records from (mandatory for listing).
    
    .PARAMETER RecordId
        The unique identifier of a specific DNS record.
    
    .PARAMETER Type
        Filter records by type (A, AAAA, CNAME, MX, TXT, NS, SOA).
    
    .EXAMPLE
        PS> Get-CloudDNSRecord -DomainId "domain-..."
        
        Lists all DNS records for the specified domain.
    
    .EXAMPLE
        PS> Get-CloudDNSRecord -DomainId "domain-..." -Type "A"
        
        Lists all A records for the specified domain.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainId,
        
        [Parameter(Mandatory=$false)]
        [Alias('Id')]
        [string]$RecordId,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS', 'SOA')]
        [string]$Type
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($RecordId) {
            $path = "network/dns/domains/$DomainId/records/$RecordId"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($Type) { $queryParams['type'] = $Type }
            
            $response = Invoke-CloudAPIRequest -Path "network/dns/domains/$DomainId/records" -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve DNS record(s): $($_.Exception.Message)"
        return $null
    }
}
