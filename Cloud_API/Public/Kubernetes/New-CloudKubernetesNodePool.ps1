function New-CloudKubernetesNodePool {
    <#
    .SYNOPSIS
        Creates a new node pool in a Kubernetes cluster.
    
    .DESCRIPTION
        Creates a new node pool with specified configuration including size,
        count, and auto-scaling settings. Supports waiting for creation to complete.
    
    .PARAMETER ClusterId
        The unique identifier of the Kubernetes cluster. Required.
    
    .PARAMETER Name
        The name for the new node pool. Required.
    
    .PARAMETER Size
        The size/flavor of nodes in the pool (e.g., small, medium, large).
    
    .PARAMETER Count
        The initial number of nodes in the pool.
    
    .PARAMETER MinCount
        The minimum number of nodes for auto-scaling.
    
    .PARAMETER MaxCount
        The maximum number of nodes for auto-scaling.
    
    .PARAMETER Wait
        If specified, waits for the node pool creation to complete.
    
    .PARAMETER Async
        If specified, returns immediately with the job object for async tracking.
    
    .EXAMPLE
        PS> New-CloudKubernetesNodePool -ClusterId "k8s-..." -Name "worker-pool" -Size "medium" -Count 3
        
        Creates a new node pool with 3 medium-sized nodes.
    
    .EXAMPLE
        PS> New-CloudKubernetesNodePool -ClusterId "k8s-..." -Name "auto-scaling-pool" -Size "large" -MinCount 1 -MaxCount 10 -Wait
        
        Creates an auto-scaling node pool and waits for completion.
    
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
        [Alias('ClusterId', 'KubernetesClusterId')]
        [string]$ClusterId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$Size,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1,100)]
        [int]$Count,
        
        [Parameter(Mandatory=$false)]
        [int]$MinCount,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxCount,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    try {
        # Build request body
        $body = @{
            name = $Name
        }
        
        if ($Size) {
            $body['size'] = $Size
        }
        
        if ($Count -gt 0) {
            $body['count'] = $Count
        }
        
        if ($MinCount -gt 0) {
            $body['minCount'] = $MinCount
        }
        
        if ($MaxCount -gt 0) {
            $body['maxCount'] = $MaxCount
        }
        
        # Confirm action
        if (-not $PSCmdlet.ShouldProcess("node pool '$Name' in cluster '$ClusterId'", 'Create')) {
            return $null
        }
        
        # Build invoke parameters
        $invokeParams = @{
            Path = "kubernetes/clusters/$ClusterId/nodepools"
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
        Write-Error "Failed to create node pool: $($_.Exception.Message)"
        return $null
    }
}
