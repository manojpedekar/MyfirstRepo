function Get-CloudAccessPolicy {
    <#
    .SYNOPSIS
        Retrieves information about cloud access policies.
    
    .DESCRIPTION
        Gets details about one or more cloud access policies. Can retrieve a specific policy
        by ID or list all policies with optional filtering by project and sub-project.
    
    .PARAMETER Id
        The unique identifier of the access policy to retrieve.
    
    .PARAMETER ProjectId
        The project ID to filter policies by.
    
    .PARAMETER SubprojectId
        The sub-project ID to filter policies by.
    
    .PARAMETER CheckOnly
        If specified, tests if the policy exists and returns $true or $false.
    
    .EXAMPLE
        PS> Get-CloudAccessPolicy -Id "policy-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves details for a specific access policy.
    
    .EXAMPLE
        PS> Get-CloudAccessPolicy -ProjectId "project-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        
        Lists all access policies in the specified project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('PolicyId')]
        [string]$Id,
        
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
                return Test-CloudAPIResource -ResourceType 'iam/access-policies' -ResourceId $Id
            }
            
            # Build query parameters
            $queryParams = @{
                sort = 'name,asc'
            }
            
            if ($ProjectId) { $queryParams['projectId'] = $ProjectId }
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            
            # Determine path
            if ($Id) {
                $path = "iam/access-policies/$Id"
            } else {
                $path = "iam/access-policies"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve access policy(s): $($_.Exception.Message)"
            return $null
        }
    }
}
