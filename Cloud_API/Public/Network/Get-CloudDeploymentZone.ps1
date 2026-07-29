function Get-CloudDeploymentZone {
    <#
    .SYNOPSIS
        Retrieves deployment zone information.
    
    .DESCRIPTION
        Gets information about deployment zones. Can retrieve all publicly available
        deployment zones, or zones available in a specific account.
    
    .PARAMETER Id
        The unique identifier of a specific deployment zone.
    
    .PARAMETER AccountId
        The account ID to list deployment zones for.
    
    .EXAMPLE
        PS> Get-CloudDeploymentZone
        
        Lists all publicly available deployment zones.
    
    .EXAMPLE
        PS> Get-CloudDeploymentZone -AccountId "account-..."
        
        Lists deployment zones available in the specified account.
    
    .EXAMPLE
        PS> Get-CloudDeploymentZone -Id "deploymentzone-na-central-kc"
        
        Retrieves details for a specific deployment zone.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$AccountId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "management/deploymentzones/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } elseif ($AccountId) {
            $queryParams = @{
                accountId = $AccountId
            }
            $response = Invoke-CloudAPIRequest -Path 'management/deploymentzones' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        } else {
            $response = Invoke-CloudAPIRequest -Path 'management/deploymentzones' -Method 'GET' -Headers $headers
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve deployment zone(s): $($_.Exception.Message)"
        return $null
    }
}
