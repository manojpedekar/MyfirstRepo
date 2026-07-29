function Get-CloudJob {
    <#
    .SYNOPSIS
        Retrieves job information.
    
    .DESCRIPTION
        Gets information about cloud jobs. Can retrieve a specific job by ID
        or list all incomplete jobs within a sub-project.
    
    .PARAMETER Id
        The unique identifier of the job.
    
    .PARAMETER SubprojectId
        The sub-project ID to list jobs from.
    
    .PARAMETER IncludeComplete
        If specified, includes completed jobs when listing by sub-project.
    
    .EXAMPLE
        PS> Get-CloudJob -Id "job-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for a specific job.
    
    .EXAMPLE
        PS> Get-CloudJob -SubprojectId "subproject-..."
        
        Lists all incomplete jobs in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('JobId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [switch]$IncludeComplete
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeAccept
        
        if ($Id) {
            $response = Invoke-CloudAPIRequest -Path "management/jobs/$Id" -Method 'GET' -Headers $headers
        } elseif ($SubprojectId) {
            $queryParams = @{
                subprojectId = $SubprojectId
                sort = 'createdDate'
            }
            if (-not $IncludeComplete) {
                $queryParams['isComplete'] = 'false'
            }
            
            $response = Invoke-CloudAPIRequest -Path 'management/jobs' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        } else {
            $response = Invoke-CloudAPIRequest -Path 'management/jobs' -Method 'GET' -Headers $headers
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve job(s): $($_.Exception.Message)"
        return $null
    }
}
