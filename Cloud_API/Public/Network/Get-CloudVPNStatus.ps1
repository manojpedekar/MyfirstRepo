function Get-CloudVPNStatus {
    <#
    .SYNOPSIS
        Retrieves VPN connection status.
    
    .DESCRIPTION
        Gets the current status of a VPN connection including connection state, uptime, and bytes transferred.
    
    .PARAMETER Id
        The unique identifier of the VPN connection (mandatory).
    
    .EXAMPLE
        PS> Get-CloudVPNStatus -Id "vpn-..."
        
        Retrieves status for the specified VPN connection.
    
    .OUTPUTS
        PSCustomObject containing status information. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('VPNConnectionId')]
        [string]$Id
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $path = "network/vpn-connections/$Id/status"
        
        $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve VPN status: $($_.Exception.Message)"
        return $null
    }
}
