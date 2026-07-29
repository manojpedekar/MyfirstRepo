function Remove-CloudDNSRecord {
    <#
    .SYNOPSIS
        Deletes a DNS record.
    
    .DESCRIPTION
        Permanently deletes a DNS record from a domain.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER DomainId
        The domain ID containing the record (mandatory).
    
    .PARAMETER RecordId
        The unique identifier of the DNS record (mandatory).
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudDNSRecord -DomainId "domain-..." -RecordId "record-..." -Force
        
        Deletes the DNS record without confirmation.
    
    .OUTPUTS
        PSCustomObject or $null. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('Id')]
        [string]$RecordId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("DNS record '$RecordId' in domain '$DomainId'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $response = Invoke-CloudAPIRequest -Path "network/dns/domains/$DomainId/records/$RecordId" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove DNS record: $($_.Exception.Message)"
        return $null
    }
}
