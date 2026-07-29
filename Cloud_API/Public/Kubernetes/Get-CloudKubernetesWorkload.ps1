function Get-CloudKubernetesWorkload {
    <#
    .SYNOPSIS
        Retrieves workloads from a Kubernetes cluster.
    
    .DESCRIPTION
        Gets information about workloads (deployments, statefulsets, daemonsets, etc.)
        running in a Kubernetes cluster. Can filter by namespace and workload name.
    
    .PARAMETER ClusterId
        The unique identifier of the Kubernetes cluster. Required.
    
    .PARAMETER Namespace
        The namespace to filter workloads by.
    
    .PARAMETER Name
        The name of a specific workload to retrieve.
    
    .PARAMETER Type
        The type of workload to filter by (deployment, statefulset, daemonset, etc.).
    
    .EXAMPLE
        PS> Get-CloudKubernetesWorkload -ClusterId "k8s-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Lists all workloads across all namespaces in the cluster.
    
    .EXAMPLE
        PS> Get-CloudKubernetesWorkload -ClusterId "k8s-..." -Namespace "production" -Name "my-app"
        
        Retrieves a specific workload named "my-app" in the "production" namespace.
    
    .EXAMPLE
        PS> Get-CloudKubernetesWorkload -ClusterId "k8s-..." -Namespace "default" -Type "deployment"
        
        Lists all deployments in the "default" namespace.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('ClusterId', 'KubernetesClusterId')]
        [string]$ClusterId,
        
        [Parameter(Mandatory=$false)]
        [string]$Namespace,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('deployment', 'statefulset', 'daemonset', 'job', 'cronjob', 'replicaset', 'pod')]
        [string]$Type
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeAccept
            
            # Build query parameters
            $queryParams = @{}
            
            if ($Namespace) { $queryParams['namespace'] = $Namespace }
            if ($Name) { $queryParams['name'] = $Name }
            if ($Type) { $queryParams['type'] = $Type }
            
            # Determine path
            if ($Name) {
                $path = "kubernetes/clusters/$ClusterId/workloads/$Name"
            } else {
                $path = "kubernetes/clusters/$ClusterId/workloads"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve workload(s): $($_.Exception.Message)"
            return $null
        }
    }
}
