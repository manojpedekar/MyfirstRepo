function Get-CloudVLAN {
    <#
    .SYNOPSIS
        Retrieves VLAN information.
    
    .DESCRIPTION
        Gets VLAN (Virtual Local Area Network) information.
        Can retrieve a specific VLAN by ID or list all VLANs for a deployment zone.
    
    .PARAMETER Id
        The unique identifier of the VLAN.
    
    .PARAMETER DeploymentZoneId
        The deployment zone ID to list VLANs from.
    
    .EXAMPLE
        PS> Get-CloudVLAN -Id "vlan-..."
        
        Retrieves details for a specific VLAN.
    
    .EXAMPLE
        PS> Get-CloudVLAN -DeploymentZoneId "zone-..."
        
        Lists all VLANs in the specified deployment zone.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('VLANId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$DeploymentZoneId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/vlans/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($DeploymentZoneId) { $queryParams['deploymentZoneId'] = $DeploymentZoneId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/vlans' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve VLAN(s): $($_.Exception.Message)"
        return $null
    }
}
