function Get-CloudKubernetesCluster {
    <#
    .SYNOPSIS
        Retrieves Kubernetes clusters.
    
    .DESCRIPTION
        Gets details about one or more Kubernetes clusters. Can retrieve a specific cluster
        by ID or list all clusters in a sub-project or project.
    
    .PARAMETER Id
        The unique identifier of the Kubernetes cluster to retrieve.
    
    .PARAMETER SubprojectId
        The sub-project ID to list clusters from.
    
    .PARAMETER ProjectId
        The project ID to list clusters from.
    
    .PARAMETER CheckOnly
        If specified, tests if the cluster exists and returns $true or $false.
    
    .EXAMPLE
        PS> Get-CloudKubernetesCluster -Id "k8s-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves details for a specific Kubernetes cluster.
    
    .EXAMPLE
        PS> Get-CloudKubernetesCluster -SubprojectId "subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        
        Lists all Kubernetes clusters in the specified sub-project.
    
    .EXAMPLE
        PS> Get-CloudKubernetesCluster -Id "k8s-55c319eb-5944-4d00-a927-02e2eff4430a" -CheckOnly
        
        Tests if the specified cluster exists. Returns $true or $false.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('ClusterId', 'KubernetesClusterId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId,
        
        [Parameter(Mandatory=$false)]
        [switch]$token,        
        
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
                return Test-CloudAPIResource -ResourceType 'kubernetes/clusters' -ResourceId $Id
            }
            
            # Build query parameters
            $queryParams = @{
                sort = 'name,asc'
            }
            
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            if ($ProjectId) { $queryParams['projectId'] = $ProjectId }
            
            # Determine path
            if ($Id) {
                $path = "kubernetes/clusters/$Id"
            } else {
                $path = "kubernetes/clusters"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve Kubernetes cluster(s): $($_.Exception.Message)"
            return $null
        }
    }
}
