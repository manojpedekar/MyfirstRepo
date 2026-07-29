function Get-CloudCMDB {
    <#
    .SYNOPSIS
        Retrieves CMDB record for a server.
    
    .DESCRIPTION
        Returns the CMDB record for a server identified by its primary IPv4 address.
        Useful for reconciling a server's identity against what the CMDB says.
    
    .PARAMETER IPAddress
        The IPv4 address of the server. Required. Must be a valid IP address format.
    
    .EXAMPLE
        PS> Get-CloudCMDB -IPAddress "10.42.117.76"
        
        Retrieves CMDB data for the server with the specified IP.
    
    .EXAMPLE
        PS> Get-CloudCMDB -IPAddress (Resolve-DnsName $env:COMPUTERNAME -Type A).IPAddress
        
        Retrieves CMDB data for the current server.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidatePattern('\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}')]
        [string]$IPAddress
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        $queryParams = @{
            serverIp = $IPAddress
        }
        
        $response = Invoke-CloudAPIRequest -Path 'cmdb/server' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve CMDB data: $($_.Exception.Message)"
        return $null
    }
}
