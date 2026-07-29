function New-CloudVPNConnection {
    <#
    .SYNOPSIS
        Creates a new VPN connection.
    
    .DESCRIPTION
        Creates a new VPN (Virtual Private Network) connection for secure site-to-site connectivity.
        Supports -Wait switch to wait for the connection to be fully established.
    
    .PARAMETER Name
        The name of the VPN connection (mandatory).
    
    .PARAMETER SubprojectId
        The sub-project ID where the VPN connection will be created (mandatory).
    
    .PARAMETER RemoteGateway
        The IP address of the remote VPN gateway (mandatory).
    
    .PARAMETER PreSharedKey
        The pre-shared key for authentication (mandatory).
    
    .PARAMETER LocalNetwork
        The local network CIDR.
    
    .PARAMETER RemoteNetwork
        The remote network CIDR.
    
    .PARAMETER Wait
        Wait for the VPN connection to be fully established before returning.
    
    .EXAMPLE
        PS> New-CloudVPNConnection -Name "site-to-site-vpn" -SubprojectId "subproject-..." -RemoteGateway "198.51.100.1" -PreSharedKey "secret123" -LocalNetwork "10.0.0.0/16" -RemoteNetwork "192.168.0.0/16"
        
        Creates a new site-to-site VPN connection.
    
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
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$RemoteGateway,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$PreSharedKey,
        
        [Parameter(Mandatory=$false)]
        [string]$LocalNetwork,
        
        [Parameter(Mandatory=$false)]
        [string]$RemoteNetwork,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("VPN connection '$Name' in subproject '$SubprojectId'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $body = @{
            name = $Name
            subprojectId = $SubprojectId
            remoteGateway = $RemoteGateway
            preSharedKey = $PreSharedKey
        }
        
        if ($LocalNetwork) { $body['localNetwork'] = $LocalNetwork }
        if ($RemoteNetwork) { $body['remoteNetwork'] = $RemoteNetwork }
        
        $response = Invoke-CloudAPIRequest -Path 'network/vpn-connections' -Method 'POST' -Headers $headers -Body $body -Wait:$Wait
        
        return $response
    }
    catch {
        Write-Error "Failed to create VPN connection: $($_.Exception.Message)"
        return $null
    }
}
