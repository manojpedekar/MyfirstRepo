function Remove-CloudACMEDomain {
    <#
    .SYNOPSIS
        Removes a domain from ACME management.
    
    .DESCRIPTION
        Unregisters a domain from ACME management. This does not affect existing
        certificates but prevents new certificates from being issued for this domain.
        
        By default, prompts for confirmation unless the -Force switch is used.
    
    .PARAMETER Id
        The unique identifier of the domain to remove. Required.
    
    .PARAMETER Force
        If specified, bypasses the confirmation prompt.
    
    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.
    
    .EXAMPLE
        PS> Remove-CloudACMEDomain -Id "domain-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Prompts for confirmation before removing the domain.
    
    .EXAMPLE
        PS> Remove-CloudACMEDomain -Id "domain-55c319eb-5944-4d00-a927-02e2eff4430a" -Force
        
        Removes the domain without prompting.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('DomainId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Get domain details for the confirmation message
            $domain = Get-CloudACMEDomain -Id $Id
            $domainName = if ($domain) { $domain.domain } else { $Id }
            
            # Use ShouldProcess for confirmation
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("domain '$domainName' ($Id)", 'Remove')) {
                return $null
            }
            
            $headers = New-CloudAPIHeaders
            $response = Invoke-CloudAPIRequest -Path "acme/domains/$Id" -Method 'DELETE' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to remove ACME domain: $($_.Exception.Message)"
            return $null
        }
    }
}
