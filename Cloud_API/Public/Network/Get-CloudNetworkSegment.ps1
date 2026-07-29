function Get-CloudNetworkSegment {
    <#
    .SYNOPSIS
        Retrieves network segments/VLANs.
    
    .DESCRIPTION
        Gets information about network segments or VLANs.
        Can retrieve a specific segment by ID or list all segments for a deployment zone or sub-project.
    
    .PARAMETER Id
        The unique identifier of the network segment.
    
    .PARAMETER DeploymentZoneId
        The deployment zone ID to list network segments from.
    
    .PARAMETER SubprojectId
        The sub-project ID to list network segments from.
    
    .EXAMPLE
        PS> Get-CloudNetworkSegment -Id "segment-..."
        
        Retrieves details for a specific network segment.
    
    .EXAMPLE
        PS> Get-CloudNetworkSegment -DeploymentZoneId "zone-..."
        
        Lists all network segments in the specified deployment zone.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('NetworkSegmentId', 'SegmentId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$DeploymentZoneId,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/segments/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($DeploymentZoneId) { $queryParams['deploymentZoneId'] = $DeploymentZoneId }
            elseif ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/segments' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve network segment(s): $($_.Exception.Message)"
        return $null
    }
}
