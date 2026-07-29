function Get-CloudDirectConnect {
    <#
    .SYNOPSIS
        Retrieves direct connect/dedicated connections.
    
    .DESCRIPTION
        Gets information about direct connect or dedicated network connections.
        Can retrieve a specific connection by ID or list all connections for an account.
    
    .PARAMETER Id
        The unique identifier of the direct connect connection.
    
    .PARAMETER AccountId
        The account ID to list direct connect connections from.
    
    .EXAMPLE
        PS> Get-CloudDirectConnect -Id "dx-..."
        
        Retrieves details for a specific direct connect connection.
    
    .EXAMPLE
        PS> Get-CloudDirectConnect -AccountId "account-..."
        
        Lists all direct connect connections for the specified account.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('DirectConnectId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$AccountId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/direct-connects/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($AccountId) { $queryParams['accountId'] = $AccountId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/direct-connects' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve direct connect connection(s): $($_.Exception.Message)"
        return $null
    }
}
