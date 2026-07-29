function Get-CloudInstance {
    <#
    .SYNOPSIS
        Retrieves information about cloud instances.
    
    .DESCRIPTION
        Gets details about one or more cloud instances. Can retrieve a specific instance
        by ID or list all instances in a sub-project, project, or account.
        
        NOTES: Requesting single instance information will return more detailed results 
        than getting them at the sub-project level or higher. Recommended to get at 
        sub-project level as a set $variable, then Get-CloudInstance -Id $variable.id, 
        for example to get deeper details.
    
    .PARAMETER Id
        The unique identifier of the instance to retrieve.
    
    .PARAMETER SubprojectId
        The sub-project ID to list instances from.
    
    .PARAMETER ProjectId
        The project ID to list instances from.
    
    .PARAMETER AccountId
        The account ID to list instances from.
    
    .PARAMETER DeploymentZoneId
        The deployment zone ID to filter instances by.
    
    .PARAMETER TierId
        The tier ID to filter instances by.
    
    .PARAMETER CheckOnly
        If specified, tests if the instance exists and returns $true or $false.
    
    .EXAMPLE
        PS> Get-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves details for a specific instance.
    
    .EXAMPLE
        PS> Get-CloudInstance -SubprojectId "subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        
        Lists all instances in the specified sub-project.
    
    .EXAMPLE
        PS> Get-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -CheckOnly
        
        Tests if the specified instance exists. Returns $true or $false.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [Alias('InstanceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId,
        
        [Parameter(Mandatory=$false)]
        [string]$AccountId,
        
        [Parameter(Mandatory=$false)]
        [string]$DeploymentZoneId,
        
        [Parameter(Mandatory=$false)]
        [string]$TierId,
        
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
                return Test-CloudAPIResource -ResourceType 'compute/instances' -ResourceId $Id
            }
            
            # Build query parameters
            $queryParams = @{
                sort = 'name,asc'
            }
            
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            if ($ProjectId) { $queryParams['projectId'] = $ProjectId }
            if ($AccountId) { $queryParams['accountId'] = $AccountId }
            if ($DeploymentZoneId) { $queryParams['deploymentZoneId'] = $DeploymentZoneId }
            if ($TierId) { $queryParams['tierId'] = $TierId }
            
            # Determine path
            if ($Id) {
                $path = "compute/instances/$Id"
            } else {
                $path = "compute/instances"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve instance(s): $($_.Exception.Message)"
            return $null
        }
    }
}
