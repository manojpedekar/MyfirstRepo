function Set-CloudVPNConnection {
    <#
    .SYNOPSIS
        Updates a VPN connection.
    
    .DESCRIPTION
        Updates an existing VPN connection's configuration including name, remote gateway, and pre-shared key.
    
    .PARAMETER Id
        The unique identifier of the VPN connection (mandatory).
    
    .PARAMETER Name
        The new name for the VPN connection.
    
    .PARAMETER RemoteGateway
        The new IP address of the remote VPN gateway.
    
    .PARAMETER PreSharedKey
        The new pre-shared key for authentication.
    
    .EXAMPLE
        PS> Set-CloudVPNConnection -Id "vpn-..." -Name "updated-vpn" -RemoteGateway "198.51.100.2"
        
        Updates the VPN connection name and remote gateway.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [Alias('VPNConnectionId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$RemoteGateway,
        
        [Parameter(Mandatory=$false)]
        [string]$PreSharedKey
    )
    
    begin {
        $headers = $null
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType
        }
        catch {
            Write-Error -Message "Failed to initialize API headers: $($_.Exception.Message)" -ErrorId 'InitializeCloudAPIHeadersFailed'
            return
        }
        $results = @()
    }
    
    process {
        try {
            if (-not $PSCmdlet.ShouldProcess("VPN connection '$Id'", 'Update')) {
                return $null
            }
            
            $body = @{}
            if ($Name) { $body['name'] = $Name }
            if ($RemoteGateway) { $body['remoteGateway'] = $RemoteGateway }
            if ($PreSharedKey) { $body['preSharedKey'] = $PreSharedKey }
            
            if ($body.Count -eq 0) {
                Write-Warning "No parameters to update specified."
                return $null
            }
            
            $response = Invoke-CloudAPIRequest -Path "network/vpn-connections/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            $results += $response
        }
        catch {
            Write-Error -Message "Failed to update VPN connection '$Id': $($_.Exception.Message)" -ErrorId 'SetCloudVPNConnectionFailed'
        }
    }
    
    end {
        return $results
    }
}
