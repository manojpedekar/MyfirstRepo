function Test-CloudDNSAliasAvailable {
    <#
    .SYNOPSIS
        Tests if a DNS alias is available.
    
    .DESCRIPTION
        Checks the availability of a DNS alias name.
    
    .PARAMETER Name
        The DNS alias name to check.
    
    .EXAMPLE
        PS> Test-CloudDNSAliasAvailable -Name "myalias"
        
        Tests if the DNS alias name is available.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    try {
        $headers = New-CloudAPIHeaders
        $response = Invoke-CloudAPIRequest -Path 'network/dns/availability' -Method 'GET' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to check DNS alias availability: $($_.Exception.Message)"
        return $null
    }
}
