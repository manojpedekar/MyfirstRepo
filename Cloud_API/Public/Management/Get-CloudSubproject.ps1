function Get-CloudSubproject {
    <#
    .SYNOPSIS
        Retrieves sub-project information.
    
    .DESCRIPTION
        Gets information about sub-projects. Can retrieve a specific sub-project
        by ID or list all sub-projects within a project.
    
    .PARAMETER Id
        The unique identifier of the sub-project.
    
    .PARAMETER ProjectId
        The project ID to list sub-projects from.
    
    .EXAMPLE
        PS> Get-CloudSubproject -Id "subproject-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for a specific sub-project.
    
    .EXAMPLE
        PS> Get-CloudSubproject -ProjectId "project-..."
        
        Lists all sub-projects in the specified project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('SubprojectId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeAccept
        
        if ($ProjectId) {
            $queryParams = @{
                projectId = $ProjectId
            }
            $response = Invoke-CloudAPIRequest -Path 'management/subprojects' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        } elseif ($Id) {
            $response = Invoke-CloudAPIRequest -Path "management/subprojects/$Id" -Method 'GET' -Headers $headers
        } else {
            $response = Invoke-CloudAPIRequest -Path 'management/subprojects' -Method 'GET' -Headers $headers
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve sub-project(s): $($_.Exception.Message)"
        return $null
    }
}
