function Get-CloudDNSAlias {
    <#
    .SYNOPSIS
        Retrieves DNS alias information.
    
    .DESCRIPTION
        Gets information about DNS aliases in a sub-project.
    
    .PARAMETER SubprojectId
        The sub-project ID to list DNS aliases from.
    
    .EXAMPLE
        PS> Get-CloudDNSAlias -SubprojectId "subproject-..."
        
        Lists all DNS aliases in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SubprojectId
    )
    
    try {
        $headers = New-CloudAPIHeaders
        $queryParams = @{
            subprojectId = $SubprojectId
        }
        
        $response = Invoke-CloudAPIRequest -Path 'network/secondary-ips' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve DNS aliases: $($_.Exception.Message)"
        return $null
    }
}
