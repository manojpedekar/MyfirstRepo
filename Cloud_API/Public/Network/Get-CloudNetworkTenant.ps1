function Get-CloudNetworkTenant {
    <#
    .SYNOPSIS
        Retrieves network tenants.
    
    .DESCRIPTION
        Gets network tenant information.
        Can retrieve a specific tenant by ID or list all tenants, optionally filtered by name.
    
    .PARAMETER Id
        The unique identifier of the network tenant.
    
    .PARAMETER Name
        The name of the network tenant to search for.
    
    .EXAMPLE
        PS> Get-CloudNetworkTenant -Id "tenant-..."
        
        Retrieves details for a specific network tenant.
    
    .EXAMPLE
        PS> Get-CloudNetworkTenant -Name "Production"
        
        Lists network tenants matching the name.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('NetworkTenantId', 'TenantId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/tenants/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($Name) { $queryParams['name'] = $Name }
            
            $response = Invoke-CloudAPIRequest -Path 'network/tenants' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve network tenant(s): $($_.Exception.Message)"
        return $null
    }
}
