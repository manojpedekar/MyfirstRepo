function Get-CloudNetAccess {
    <#
    .SYNOPSIS
        Retrieves network access rule information.
    
    .DESCRIPTION
        Gets information about a specific network access rule (firewall rule) by ID.
    
    .PARAMETER Id
        The unique identifier of the network access rule. Required.
    
    .EXAMPLE
        PS> Get-CloudNetAccess -Id "networkaccess-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for the specified network access rule.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('NetAccessId')]
        [string]$Id
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path "network/accesses/$Id" -Method 'GET' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve network access rule: $($_.Exception.Message)"
        return $null
    }
}
