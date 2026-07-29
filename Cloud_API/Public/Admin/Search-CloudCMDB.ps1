function Search-CloudCMDB {
    <#
    .SYNOPSIS
        Searches the Configuration Management Database (CMDB).

    .DESCRIPTION
        Performs a search across the CMDB for configuration items matching
        the specified query. Can filter by type and project.

    .PARAMETER Query
        The search query string (mandatory). Supports wildcards and partial matching.

    .PARAMETER Type
        Filter by CI type (e.g., 'Server', 'Network', 'Application', 'Database').

    .PARAMETER ProjectId
        Filter by project ID.

    .PARAMETER SubprojectId
        Filter by subproject ID.

    .PARAMETER Limit
        Maximum number of results to return. Default is 50.

    .EXAMPLE
        PS> Search-CloudCMDB -Query "web-server*"

        Searches for configuration items matching "web-server*".

    .EXAMPLE
        PS> Search-CloudCMDB -Query "production" -Type 'Server' -ProjectId "project-12345"

        Searches for production servers in a specific project.

    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.

    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Server', 'Network', 'Application', 'Database', 'Storage', 'All')]
        [string]$Type = 'All',

        [Parameter(Mandatory=$false)]
        [string]$ProjectId,

        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,

        [Parameter(Mandatory=$false)]
        [int]$Limit = 50
    )

    try {
        $headers = New-CloudAPIHeaders

        # Build query parameters
        $queryParams = @{
            q = $Query
            limit = $Limit
        }

        if ($Type -ne 'All') { $queryParams['type'] = $Type }
        if ($ProjectId) { $queryParams['projectId'] = $ProjectId }
        if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }

        Write-Verbose "Searching CMDB for: $Query"

        $response = Invoke-CloudAPIRequest -Path 'cmdb/search' -Method 'GET' -Headers $headers -QueryParameters $queryParams

        return $response
    }
    catch {
        Write-Error "Failed to search CMDB: $($_.Exception.Message)"
        return $null
    }
}
