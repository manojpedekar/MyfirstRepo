function Start-CloudVPNConnection {
    <#
    .SYNOPSIS
        Brings up a VPN connection.
    
    .DESCRIPTION
        Initiates a VPN connection by sending the 'up' command to the VPN gateway.
    
    .PARAMETER Id
        The unique identifier of the VPN connection (mandatory).
    
    .EXAMPLE
        PS> Start-CloudVPNConnection -Id "vpn-..."
        
        Brings up the specified VPN connection.
    
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
        [Alias('VPNConnectionId')]
        [string]$Id
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("VPN connection '$Id'", 'Start')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $response = Invoke-CloudAPIRequest -Path "network/vpn-connections/$Id/up" -Method 'POST' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to start VPN connection: $($_.Exception.Message)"
        return $null
    }
}
