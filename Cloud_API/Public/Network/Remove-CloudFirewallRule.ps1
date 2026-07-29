function Remove-CloudFirewallRule {
    <#
    .SYNOPSIS
        Deletes a firewall rule.
    
    .DESCRIPTION
        Permanently deletes a firewall rule from a security group.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the firewall rule (mandatory).
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudFirewallRule -Id "firewallrule-..." -Force
        
        Deletes the firewall rule without confirmation.
    
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
        [Alias('FirewallRuleId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("firewall rule '$Id'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $response = Invoke-CloudAPIRequest -Path "network/firewall-rules/$Id" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove firewall rule: $($_.Exception.Message)"
        return $null
    }
}
