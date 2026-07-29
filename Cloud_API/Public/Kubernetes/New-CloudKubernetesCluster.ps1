function New-CloudKubernetesCluster {
    <#
    .SYNOPSIS
        Creates a new Kubernetes cluster.
    
    .DESCRIPTION
        Creates a new Kubernetes cluster with specified configuration including
        version and optional node pools. Supports waiting for cluster creation to complete.
    
    .PARAMETER Name
        The name for the new Kubernetes cluster. Required.
    
    .PARAMETER SubprojectId
        The sub-project ID where the cluster will be created. Required.
    
    .PARAMETER Version
        The Kubernetes version to use for the cluster.
    
    .PARAMETER NodePools
        Array of node pool configurations to create with the cluster.
    
    .PARAMETER Wait
        If specified, waits for the cluster creation to complete.
    
    .PARAMETER Async
        If specified, returns immediately with the job object for async tracking.
    
    .EXAMPLE
        PS> New-CloudKubernetesCluster -Name "prod-cluster" -SubprojectId "subproject-..." -Version "1.28"
        
        Creates a new Kubernetes cluster with version 1.28.
    
    .EXAMPLE
        PS> $nodePools = @(
        >>     @{name="default"; size="medium"; count=3; minCount=1; maxCount=5}
        >> )
        PS> New-CloudKubernetesCluster -Name "dev-cluster" -SubprojectId "subproject-..." -NodePools $nodePools -Wait
        
        Creates a cluster with a node pool and waits for completion.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$Version,
        
        [Parameter(Mandatory=$false)]
        [array]$NodePools,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    try {
        # Build request body
        $body = @{
            name = $Name
            subprojectId = $SubprojectId
        }
        
        if ($Version) {
            $body['version'] = $Version
        }
        
        if ($NodePools) {
            $body['nodePools'] = $NodePools
        }
        
        # Confirm action
        if (-not $PSCmdlet.ShouldProcess("Kubernetes cluster '$Name' in sub-project '$SubprojectId'", 'Create')) {
            return $null
        }
        
        # Build invoke parameters
        $invokeParams = @{
            Path = 'kubernetes/clusters'
            Method = 'POST'
            Headers = (New-CloudAPIHeaders -IncludeContentType -IncludeAccept)
            Body = $body
        }
        
        if ($Wait) { $invokeParams['Wait'] = $true }
        if ($Async) { $invokeParams['Async'] = $true }
        
        # Make API request
        $response = Invoke-CloudAPIRequest @invokeParams
        
        return $response
    }
    catch {
        Write-Error "Failed to create Kubernetes cluster: $($_.Exception.Message)"
        return $null
    }
}
