function Get-CloudKubernetesNamespace {
    <#
    .SYNOPSIS
        Retrieves namespaces from a Kubernetes cluster.
    
    .DESCRIPTION
        Gets information about namespaces in a Kubernetes cluster.
        Can retrieve a specific namespace by name or list all namespaces.
    
    .PARAMETER ClusterId
        The unique identifier of the Kubernetes cluster. Required.
    
    .PARAMETER Name
        The name of a specific namespace to retrieve.
    
    .EXAMPLE
        PS> Get-CloudKubernetesNamespace -ClusterId "k8s-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Lists all namespaces in the specified cluster.
    
    .EXAMPLE
        PS> Get-CloudKubernetesNamespace -ClusterId "k8s-..." -Name "production"
        
        Retrieves details for the "production" namespace.
    
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
        [string]$Name
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeAccept
            
            # Determine path
            if ($Name) {
                $path = "kubernetes/clusters/$ClusterId/namespaces/$Name"
            } else {
                $path = "kubernetes/clusters/$ClusterId/namespaces"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve namespace(s): $($_.Exception.Message)"
            return $null
        }
    }
}
