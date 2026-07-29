function Test-CloudAPIResource {
    <#
    .SYNOPSIS
        Tests if a resource exists by making a HEAD/GET request.
    
    .DESCRIPTION
        Makes a lightweight API request to check if a resource exists.
        Returns $true if the resource exists, $false otherwise.
        This function suppresses errors to avoid cluttering the error stream.
    
    .PARAMETER ResourceType
        The type of resource (e.g., 'compute/instances', 'network/securitygroups').
    
    .PARAMETER ResourceId
        The unique identifier of the resource to test.
    
    .EXAMPLE
        PS> Test-CloudAPIResource -ResourceType 'compute/instances' -ResourceId 'i-55c319eb-5944-4d00-a927-02e2eff4430a'
        True
        
        Tests if the specified instance exists.
    
    .OUTPUTS
        Boolean
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceType,
        
        [Parameter(Mandatory=$true)]
        [string]$ResourceId
    )
    
    try {
        $headers = New-CloudAPIHeaders
        $null = Invoke-CloudAPIRequest -Path "$ResourceType/$ResourceId" -Method 'GET' -Headers $headers -ErrorAction Stop
        return $true
    }
    catch {
        # Check if it's a 404 (not found) vs other errors
        $statusCode = $_.Exception.Response?.StatusCode.value__
        if ($statusCode -eq 404) {
            return $false
        }
        
        # For other errors, we can't determine existence
        Write-Verbose "Error testing resource existence: $($_.Exception.Message)"
        return $false
    }
}
