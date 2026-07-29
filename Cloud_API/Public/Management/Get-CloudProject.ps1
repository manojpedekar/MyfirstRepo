function Get-CloudProject {
    <#
    .SYNOPSIS
        Retrieves project information.
    
    .DESCRIPTION
        Gets information about a specific project.
    
    .PARAMETER Id
        The unique identifier of the project. Required.
    
    .EXAMPLE
        PS> Get-CloudProject -Id "project-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for the specified project.
    
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
        [Alias('ProjectId')]
        [string]$Id
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "management/projects/$Id" -Method 'GET' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve project: $($_.Exception.Message)"
        return $null
    }
}
