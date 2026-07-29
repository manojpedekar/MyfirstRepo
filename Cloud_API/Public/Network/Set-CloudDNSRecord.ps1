function Set-CloudDNSRecord {
    <#
    .SYNOPSIS
        Updates a DNS record.
    
    .DESCRIPTION
        Updates an existing DNS record's value or TTL.
    
    .PARAMETER DomainId
        The domain ID containing the record (mandatory).
    
    .PARAMETER RecordId
        The unique identifier of the DNS record (mandatory).
    
    .PARAMETER Value
        The new record value.
    
    .PARAMETER TTL
        The new time-to-live in seconds.
    
    .EXAMPLE
        PS> Set-CloudDNSRecord -DomainId "domain-..." -RecordId "record-..." -Value "203.0.113.20" -TTL 7200
        
        Updates the DNS record value and TTL.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [string]$DomainId,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [Alias('Id')]
        [string]$RecordId,
        
        [Parameter(Mandatory=$false)]
        [string]$Value,
        
        [Parameter(Mandatory=$false)]
        [int]$TTL
    )
    
    begin {
        $headers = $null
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType
        }
        catch {
            Write-Error -Message "Failed to initialize API headers: $($_.Exception.Message)" -ErrorId 'InitializeCloudAPIHeadersFailed'
            return
        }
        $results = @()
    }
    
    process {
        try {
            if (-not $PSCmdlet.ShouldProcess("DNS record '$RecordId' in domain '$DomainId'", 'Update')) {
                return $null
            }
            
            $body = @{}
            if ($Value) { $body['value'] = $Value }
            if ($TTL) { $body['ttl'] = $TTL }
            
            if ($body.Count -eq 0) {
                Write-Warning "No parameters to update specified."
                return $null
            }
            
            $response = Invoke-CloudAPIRequest -Path "network/dns/domains/$DomainId/records/$RecordId" -Method 'PUT' -Headers $headers -Body $body
            
            $results += $response
        }
        catch {
            Write-Error -Message "Failed to update DNS record '$RecordId' in domain '$DomainId': $($_.Exception.Message)" -ErrorId 'SetCloudDNSRecordFailed'
        }
    }
    
    end {
        return $results
    }
}
