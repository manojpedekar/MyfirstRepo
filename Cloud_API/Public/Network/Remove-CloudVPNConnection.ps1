function Remove-CloudVPNConnection {
    <#
    .SYNOPSIS
        Deletes a VPN connection.
    
    .DESCRIPTION
        Permanently deletes a VPN connection.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the VPN connection (mandatory).
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudVPNConnection -Id "vpn-..." -Force
        
        Deletes the VPN connection without confirmation.
    
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
        [Alias('VPNConnectionId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("VPN connection '$Id'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $response = Invoke-CloudAPIRequest -Path "network/vpn-connections/$Id" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove VPN connection: $($_.Exception.Message)"
        return $null
    }
}
