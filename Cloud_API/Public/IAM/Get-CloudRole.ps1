function Get-CloudRole {
    <#
    .SYNOPSIS
        Retrieves information about cloud IAM roles.
    
    .DESCRIPTION
        Gets details about one or more cloud IAM roles. Can retrieve a specific role
        by ID or name, or list all roles with optional filtering by project.
    
    .PARAMETER Id
        The unique identifier of the role to retrieve.
    
    .PARAMETER Name
        The name of the role to retrieve.
    
    .PARAMETER ProjectId
        The project ID to filter roles by.
    
    .PARAMETER CheckOnly
        If specified, tests if the role exists and returns $true or $false.
    
    .EXAMPLE
        PS> Get-CloudRole -Id "role-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves details for a specific role.
    
    .EXAMPLE
        PS> Get-CloudRole -Name "Admin"
        
        Retrieves details for a role by name.
    
    .EXAMPLE
        PS> Get-CloudRole -ProjectId "project-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        
        Lists all roles in the specified project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('RoleId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId,
        
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
                return Test-CloudAPIResource -ResourceType 'iam/roles' -ResourceId $Id
            }
            
            # Build query parameters
            $queryParams = @{
                sort = 'name,asc'
            }
            
            if ($Name) { $queryParams['name'] = $Name }
            if ($ProjectId) { $queryParams['projectId'] = $ProjectId }
            
            # Determine path
            if ($Id) {
                $path = "iam/roles/$Id"
            } else {
                $path = "iam/roles"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve role(s): $($_.Exception.Message)"
            return $null
        }
    }
}
