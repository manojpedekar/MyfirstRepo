function Remove-CloudDNSDomain {
    <#
    .SYNOPSIS
        Deletes a DNS domain.
    
    .DESCRIPTION
        Permanently deletes a DNS domain and all its records.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the DNS domain (mandatory).
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudDNSDomain -Id "domain-..." -Force
        
        Deletes the DNS domain without confirmation.
    
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
        [Alias('DNSDomainId', 'DomainId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("DNS domain '$Id'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $response = Invoke-CloudAPIRequest -Path "network/dns/domains/$Id" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove DNS domain: $($_.Exception.Message)"
        return $null
    }
}
