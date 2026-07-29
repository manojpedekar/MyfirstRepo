function Get-CloudVPNConnection {
    <#
    .SYNOPSIS
        Retrieves VPN connections.
    
    .DESCRIPTION
        Gets VPN (Virtual Private Network) connections.
        Can retrieve a specific connection by ID or list all connections for a sub-project or project.
    
    .PARAMETER Id
        The unique identifier of the VPN connection.
    
    .PARAMETER SubprojectId
        The sub-project ID to list VPN connections from.
    
    .PARAMETER ProjectId
        The project ID to list VPN connections from.
    
    .EXAMPLE
        PS> Get-CloudVPNConnection -Id "vpn-..."
        
        Retrieves details for a specific VPN connection.
    
    .EXAMPLE
        PS> Get-CloudVPNConnection -SubprojectId "subproject-..."
        
        Lists all VPN connections in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('VPNConnectionId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/vpn-connections/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            elseif ($ProjectId) { $queryParams['projectId'] = $ProjectId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/vpn-connections' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve VPN connection(s): $($_.Exception.Message)"
        return $null
    }
}
