function Get-CloudServiceAccount {
    <#
    .SYNOPSIS
        Retrieves information about cloud service accounts.
    
    .DESCRIPTION
        Gets details about one or more cloud service accounts. Can retrieve a specific
        service account by ID or list all accounts with optional filtering by project.
    
    .PARAMETER Id
        The unique identifier of the service account to retrieve.
    
    .PARAMETER ProjectId
        The project ID to filter service accounts by.
    
    .PARAMETER CheckOnly
        If specified, tests if the service account exists and returns $true or $false.
    
    .EXAMPLE
        PS> Get-CloudServiceAccount -Id "sa-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves details for a specific service account.
    
    .EXAMPLE
        PS> Get-CloudServiceAccount -ProjectId "project-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        
        Lists all service accounts in the specified project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('ServiceAccountId')]
        [string]$Id,
        
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
                return Test-CloudAPIResource -ResourceType 'iam/service-accounts' -ResourceId $Id
            }
            
            # Build query parameters
            $queryParams = @{
                sort = 'name,asc'
            }
            
            if ($ProjectId) { $queryParams['projectId'] = $ProjectId }
            
            # Determine path
            if ($Id) {
                $path = "iam/service-accounts/$Id"
            } else {
                $path = "iam/service-accounts"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve service account(s): $($_.Exception.Message)"
            return $null
        }
    }
}
