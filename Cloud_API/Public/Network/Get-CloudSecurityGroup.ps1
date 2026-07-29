function Get-CloudSecurityGroup {
    <#
    .SYNOPSIS
        Retrieves security group information.
    
    .DESCRIPTION
        Gets information about security groups. Can retrieve a specific security group
        by ID or list all security groups within a sub-project or project.
        
        NOTES: Requesting single security group information will return more detailed 
        results than getting them at the sub-project level or higher. Recommended to 
        get at sub-project level as a set $variable, then get details by ID.
    
    .PARAMETER Id
        The unique identifier of the security group.
    
    .PARAMETER SubprojectId
        The sub-project ID to list security groups from.
    
    .PARAMETER ProjectId
        The project ID to list security groups from.
    
    .EXAMPLE
        PS> Get-CloudSecurityGroup -Id "securitygroup-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for a specific security group.
    
    .EXAMPLE
        PS> Get-CloudSecurityGroup -SubprojectId "subproject-..."
        
        Lists all security groups in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('SecuritygroupId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/securitygroups/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($SubprojectId) { $queryParams['resourceId'] = $SubprojectId }
            elseif ($ProjectId) { $queryParams['resourceId'] = $ProjectId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/securitygroups' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve security group(s): $($_.Exception.Message)"
        return $null
    }
}
