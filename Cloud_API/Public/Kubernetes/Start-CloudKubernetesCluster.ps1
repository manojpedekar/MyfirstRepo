function Start-CloudKubernetesCluster {
    <#
    .SYNOPSIS
        Starts a stopped Kubernetes cluster.
    
    .DESCRIPTION
        Powers on a Kubernetes cluster that is currently in a stopped state.
        This starts all control plane and worker node components.
    
    .PARAMETER Id
        The unique identifier of the Kubernetes cluster to start. Required.
    
    .PARAMETER Wait
        If specified, waits for the cluster to reach the 'running' state.
    
    .EXAMPLE
        PS> Start-CloudKubernetesCluster -Id "k8s-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Starts the specified cluster.
    
    .EXAMPLE
        PS> Start-CloudKubernetesCluster -Id "k8s-..." -Wait
        
        Starts the cluster and waits for it to become running.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [Alias('ClusterId', 'KubernetesClusterId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    process {
        try {
            # Get cluster for confirmation message
            $cluster = Get-CloudKubernetesCluster -Id $Id
            $clusterName = if ($cluster) { $cluster.name } else { $Id }
            
            if (-not $PSCmdlet.ShouldProcess("Kubernetes cluster '$clusterName' ($Id)", 'Start')) {
                return $null
            }
            
            $headers = New-CloudAPIHeaders -IncludeContentType
            $response = Invoke-CloudAPIRequest -Path "kubernetes/clusters/$Id/start" -Method 'POST' -Headers $headers
            
            if ($Wait) {
                Write-Verbose "Waiting for cluster to become running..."
                $startTime = Get-Date
                do {
                    Start-Sleep -Seconds 10
                    $cluster = Get-CloudKubernetesCluster -Id $Id
                    $status = Get-CloudKubernetesClusterStatus -Id $Id
                    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                    Write-Verbose "Current state: $($status.state) (elapsed: ${elapsed}s)"
                } while ($status.state -ne 'running' -and $status.state -ne 'available')
                $totalElapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                Write-Verbose "Kubernetes cluster '$Id' is now running after $totalElapsed seconds"
            }
            
            return $response
        }
        catch {
            Write-Error -Message "Failed to start Kubernetes cluster '$Id': $($_.Exception.Message)" -ErrorId 'StartCloudKubernetesClusterFailed'
            return $null
        }
    }
}
