function Get-CloudVPC {
    <#
    .SYNOPSIS
        Retrieves VPCs (Virtual Private Clouds).
    
    .DESCRIPTION
        Gets VPC information.
        Can retrieve a specific VPC by ID or list all VPCs for a sub-project or project.
    
    .PARAMETER Id
        The unique identifier of the VPC.
    
    .PARAMETER SubprojectId
        The sub-project ID to list VPCs from.
    
    .PARAMETER ProjectId
        The project ID to list VPCs from.
    
    .EXAMPLE
        PS> Get-CloudVPC -Id "vpc-..."
        
        Retrieves details for a specific VPC.
    
    .EXAMPLE
        PS> Get-CloudVPC -SubprojectId "subproject-..."
        
        Lists all VPCs in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('VPCId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/vpcs/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            elseif ($ProjectId) { $queryParams['projectId'] = $ProjectId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/vpcs' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve VPC(s): $($_.Exception.Message)"
        return $null
    }
}
