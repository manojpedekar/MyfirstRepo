function Stop-CloudVPNConnection {
    <#
    .SYNOPSIS
        Brings down a VPN connection.
    
    .DESCRIPTION
        Terminates a VPN connection by sending the 'down' command to the VPN gateway.
    
    .PARAMETER Id
        The unique identifier of the VPN connection (mandatory).
    
    .EXAMPLE
        PS> Stop-CloudVPNConnection -Id "vpn-..."
        
        Brings down the specified VPN connection.
    
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
        if (-not $PSCmdlet.ShouldProcess("VPN connection '$Id'", 'Stop')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $response = Invoke-CloudAPIRequest -Path "network/vpn-connections/$Id/down" -Method 'POST' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to stop VPN connection: $($_.Exception.Message)"
        return $null
    }
}
