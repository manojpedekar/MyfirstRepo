function Get-CloudKubernetesClusterStatus {
    <#
    .SYNOPSIS
        Retrieves the status of a Kubernetes cluster.
    
    .DESCRIPTION
        Gets the current status information for a Kubernetes cluster including
        state, health, and any error conditions.
    
    .PARAMETER Id
        The unique identifier of the Kubernetes cluster. Required.
    
    .EXAMPLE
        PS> Get-CloudKubernetesClusterStatus -Id "k8s-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves the status of the specified cluster.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('ClusterId', 'KubernetesClusterId')]
        [string]$Id
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeAccept
            
            $response = Invoke-CloudAPIRequest -Path "kubernetes/clusters/$Id/status" -Method 'GET' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve Kubernetes cluster status: $($_.Exception.Message)"
            return $null
        }
    }
}
