function Get-CloudUser {
    <#
    .SYNOPSIS
        Retrieves information about cloud users.
    
    .DESCRIPTION
        Gets details about one or more cloud users. Can retrieve a specific user
        by ID or email, or list all users with optional filtering by project
        and sub-project.
    
    .PARAMETER Id
        The unique identifier of the user to retrieve.
    
    .PARAMETER Email
        The email address of the user to retrieve.
    
    .PARAMETER ProjectId
        The project ID to filter users by.
    
    .PARAMETER SubprojectId
        The sub-project ID to filter users by.
    
    .PARAMETER CheckOnly
        If specified, tests if the user exists and returns $true or $false.
    
    .EXAMPLE
        PS> Get-CloudUser -Id "user-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves details for a specific user.
    
    .EXAMPLE
        PS> Get-CloudUser -Email "user@example.com"
        
        Retrieves details for a user by email address.
    
    .EXAMPLE
        PS> Get-CloudUser -ProjectId "project-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        
        Lists all users in the specified project.
    
    .EXAMPLE
        PS> Get-CloudUser -Id "user-55c319eb-5944-4d00-a927-02e2eff4430a" -CheckOnly
        
        Tests if the specified user exists. Returns $true or $false.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('UserId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Email,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [switch]$CheckOnly
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # CheckOnly mode
            if ($CheckOnly) {
                if (-not $Id) {
                    Write-Error "CheckOnly parameter requires an Id to be specified"
                    return $null
                }
                return Test-CloudAPIResource -ResourceType 'iam/users' -ResourceId $Id
            }
            
            # Build query parameters
            $queryParams = @{
                sort = 'email,asc'
            }
            
            if ($Email) { $queryParams['email'] = $Email }
            if ($ProjectId) { $queryParams['projectId'] = $ProjectId }
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            
            # Determine path
            if ($Id) {
                $path = "iam/users/$Id"
            } else {
                $path = "iam/users"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve user(s): $($_.Exception.Message)"
            return $null
        }
    }
}
