function Stop-CloudKubernetesCluster {
    <#
    .SYNOPSIS
        Stops a running Kubernetes cluster.
    
    .DESCRIPTION
        Powers off a Kubernetes cluster that is currently running.
        This stops all control plane and worker node components.
    
    .PARAMETER Id
        The unique identifier of the Kubernetes cluster to stop. Required.
    
    .PARAMETER Wait
        If specified, waits for the cluster to reach the 'stopped' state.
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Stop-CloudKubernetesCluster -Id "k8s-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Stops the specified cluster.
    
    .EXAMPLE
        PS> Stop-CloudKubernetesCluster -Id "k8s-..." -Wait -Force
        
        Stops the cluster without confirmation and waits for it to stop.
    
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
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Get cluster for confirmation message
            $cluster = Get-CloudKubernetesCluster -Id $Id
            $clusterName = if ($cluster) { $cluster.name } else { $Id }
            
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("Kubernetes cluster '$clusterName' ($Id)", 'Stop')) {
                return $null
            }
            
            $headers = New-CloudAPIHeaders -IncludeContentType
            $response = Invoke-CloudAPIRequest -Path "kubernetes/clusters/$Id/stop" -Method 'POST' -Headers $headers
            
            if ($Wait) {
                Write-Verbose "Waiting for cluster to stop..."
                $startTime = Get-Date
                do {
                    Start-Sleep -Seconds 10
                    $status = Get-CloudKubernetesClusterStatus -Id $Id
                    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                    Write-Verbose "Current state: $($status.state) (elapsed: ${elapsed}s)"
                } while ($status.state -ne 'stopped')
                $totalElapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                Write-Verbose "Kubernetes cluster '$Id' is now stopped after $totalElapsed seconds"
            }
            
            return $response
        }
        catch {
            Write-Error -Message "Failed to stop Kubernetes cluster: $($_.Exception.Message)" -ErrorId 'StopCloudKubernetesClusterFailed'
            return $null
        }
    }
}
