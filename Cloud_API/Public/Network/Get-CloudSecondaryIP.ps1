function Get-CloudSecondaryIP {
    <#
    .SYNOPSIS
        Retrieves secondary IP information.
    
    .DESCRIPTION
        Gets information about secondary IPs. Can retrieve a specific secondary IP
        by ID or list all secondary IPs within a sub-project.
    
    .PARAMETER Id
        The unique identifier of the secondary IP.
    
    .PARAMETER SubprojectId
        The sub-project ID to list secondary IPs from.
    
    .EXAMPLE
        PS> Get-CloudSecondaryIP -Id "ip-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for a specific secondary IP.
    
    .EXAMPLE
        PS> Get-CloudSecondaryIP -SubprojectId "subproject-..."
        
        Lists all secondary IPs in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('SecondaryIpId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId
    )
    
    try {
        $headers = New-CloudAPIHeaders
        
        if ($Id) {
            $path = "network/secondary-ips/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/secondary-ips' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve secondary IP(s): $($_.Exception.Message)"
        return $null
    }
}
