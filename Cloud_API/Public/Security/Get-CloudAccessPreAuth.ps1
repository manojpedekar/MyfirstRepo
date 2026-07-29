function Get-CloudAccessPreAuth {
    <#
    .SYNOPSIS
        Gets access pre-authorizations from the Cloud API.
    
    .DESCRIPTION
        Retrieves access pre-authorization records that define firewall rule pre-approvals.
        Can retrieve all pre-authorizations or a specific one by ID.
    
    .PARAMETER Id
        The unique identifier of a specific pre-authorization to retrieve.
    
    .PARAMETER ResourceId
        Filter pre-authorizations by the target resource ID.
    
    .EXAMPLE
        PS> Get-CloudAccessPreAuth
        Lists all access pre-authorizations.
    
    .EXAMPLE
        PS> Get-CloudAccessPreAuth -Id "preauth-abc123"
        Gets the specific pre-authorization with ID "preauth-abc123".
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [Alias('PreAuthId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceId
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders
            
            if ($Id) {
                $path = "security/access/pre-authorizations/$Id"
            } else {
                $path = "security/access/pre-authorizations"
                $queryParams = @{}
                if ($ResourceId) { $queryParams['resourceId'] = $ResourceId }
                if ($queryParams.Count -gt 0) {
                    $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
                    return $response
                }
            }
            
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
            return $response
        }
        catch {
            Write-Error "Failed to get access pre-authorization: $($_.Exception.Message)"
            return $null
        }
    }
}
