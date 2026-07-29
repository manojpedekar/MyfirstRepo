function New-CloudKubernetesServiceAccount {
    <#
    .SYNOPSIS
        Creates a service account in a Kubernetes cluster.
    
    .DESCRIPTION
        Creates a new service account in the specified namespace of a
        Kubernetes cluster. Returns the service account details including token.
    
    .PARAMETER ClusterId
        The unique identifier of the Kubernetes cluster. Required.
    
    .PARAMETER Name
        The name for the new service account. Required.
    
    .PARAMETER Namespace
        The namespace to create the service account in. Defaults to 'default'.
    
    .PARAMETER Wait
        If specified, waits for the service account creation to complete.
    
    .PARAMETER Async
        If specified, returns immediately with the job object for async tracking.
    
    .EXAMPLE
        PS> New-CloudKubernetesServiceAccount -ClusterId "k8s-..." -Name "my-service-account"
        
        Creates a service account named "my-service-account" in the default namespace.
    
    .EXAMPLE
        PS> New-CloudKubernetesServiceAccount -ClusterId "k8s-..." -Name "ci-cd-sa" -Namespace "ci-cd"
        
        Creates a service account in the "ci-cd" namespace.
    
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
        [string]$Namespace = 'default',
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    try {
        # Build request body
        $body = @{
            name = $Name
            namespace = $Namespace
        }
        
        # Confirm action
        if (-not $PSCmdlet.ShouldProcess("service account '$Name' in namespace '$Namespace' of cluster '$ClusterId'", 'Create')) {
            return $null
        }
        
        # Build invoke parameters
        $invokeParams = @{
            Path = "kubernetes/clusters/$ClusterId/serviceaccounts"
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
        Write-Error "Failed to create service account: $($_.Exception.Message)"
        return $null
    }
}
