function New-CloudDNSRecord {
    <#
    .SYNOPSIS
        Creates a new DNS record.
    
    .DESCRIPTION
        Creates a new DNS record (A, AAAA, CNAME, MX, TXT, etc.) for a domain.
    
    .PARAMETER DomainId
        The domain ID where the record will be created (mandatory).
    
    .PARAMETER Name
        The record name (e.g., 'www' for www.example.com).
    
    .PARAMETER Type
        The record type: A, AAAA, CNAME, MX, TXT (mandatory).
    
    .PARAMETER Value
        The record value (mandatory).
    
    .PARAMETER TTL
        The time-to-live in seconds (default: 3600).
    
    .PARAMETER Priority
        The priority for MX records.
    
    .EXAMPLE
        PS> New-CloudDNSRecord -DomainId "domain-..." -Name "www" -Type "A" -Value "203.0.113.10" -TTL 3600
        
        Creates an A record.
    
    .EXAMPLE
        PS> New-CloudDNSRecord -DomainId "domain-..." -Name "@" -Type "MX" -Value "mail.example.com" -Priority 10
        
        Creates an MX record.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainId,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS')]
        [string]$Type,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Value,
        
        [Parameter(Mandatory=$false)]
        [int]$TTL = 3600,
        
        [Parameter(Mandatory=$false)]
        [int]$Priority
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("DNS record '$Name' of type '$Type' in domain '$DomainId'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $body = @{
            type = $Type
            value = $Value
            ttl = $TTL
        }
        
        if ($Name) { $body['name'] = $Name }
        if ($Priority -and $Type -eq 'MX') { $body['priority'] = $Priority }
        
        $response = Invoke-CloudAPIRequest -Path "network/dns/domains/$DomainId/records" -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create DNS record: $($_.Exception.Message)"
        return $null
    }
}
