function Remove-CloudNATRule {
    <#
    .SYNOPSIS
        Deletes a NAT rule.
    
    .DESCRIPTION
        Permanently deletes a NAT (Network Address Translation) rule.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the NAT rule (mandatory).
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudNATRule -Id "natrule-..." -Force
        
        Deletes the NAT rule without confirmation.
    
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
        [Alias('NATRuleId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("NAT rule '$Id'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $response = Invoke-CloudAPIRequest -Path "network/nat-rules/$Id" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove NAT rule: $($_.Exception.Message)"
        return $null
    }
}
