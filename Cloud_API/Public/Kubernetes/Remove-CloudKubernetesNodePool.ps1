function Remove-CloudKubernetesNodePool {
    <#
    .SYNOPSIS
        Deletes a node pool from a Kubernetes cluster.
    
    .DESCRIPTION
        Permanently deletes a node pool and all associated nodes from a
        Kubernetes cluster. Use -Force to bypass confirmation prompts.
    
    .PARAMETER ClusterId
        The unique identifier of the Kubernetes cluster. Required.
    
    .PARAMETER PoolId
        The unique identifier of the node pool to delete. Required.
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudKubernetesNodePool -ClusterId "k8s-..." -PoolId "pool-..." -Force
        
        Deletes the node pool without confirmation.
    
    .OUTPUTS
        PSCustomObject or $null. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('ClusterId', 'KubernetesClusterId')]
        [string]$ClusterId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('NodePoolId', 'Id')]
        [string]$PoolId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Get pool name for better confirmation message
            $pool = Get-CloudKubernetesNodePool -ClusterId $ClusterId -PoolId $PoolId
            $poolName = if ($pool) { $pool.name } else { $PoolId }
            
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("node pool '$poolName' ($PoolId) in cluster '$ClusterId'", 'Remove')) {
                return $null
            }
            
            $headers = New-CloudAPIHeaders -IncludeContentType
            
            $response = Invoke-CloudAPIRequest -Path "kubernetes/clusters/$ClusterId/nodepools/$PoolId" -Method 'DELETE' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to remove node pool: $($_.Exception.Message)"
            return $null
        }
    }
}
