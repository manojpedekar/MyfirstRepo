function Get-CloudKubernetesKubeconfig {
    <#
    .SYNOPSIS
        Retrieves the kubeconfig for a Kubernetes cluster.
    
    .DESCRIPTION
        Gets the kubeconfig YAML content for accessing a Kubernetes cluster.
        This can be saved to a file and used with kubectl or other Kubernetes tools.
    
    .PARAMETER ClusterId
        The unique identifier of the Kubernetes cluster. Required.
    
    .PARAMETER ExpirationHours
        The number of hours until the kubeconfig expires. Defaults to 24 hours.
    
    .PARAMETER OutFile
        If specified, saves the kubeconfig to the specified file path.
    
    .EXAMPLE
        PS> Get-CloudKubernetesKubeconfig -ClusterId "k8s-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves the kubeconfig YAML for the specified cluster.
    
    .EXAMPLE
        PS> Get-CloudKubernetesKubeconfig -ClusterId "k8s-..." -ExpirationHours 72 -OutFile "~/.kube/config"
        
        Gets a kubeconfig valid for 72 hours and saves it to the default kubectl config location.
    
    .OUTPUTS
        [string]. Returns the kubeconfig YAML content. Returns $null on error.
    
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
        [ValidateRange(1, 720)]
        [int]$ExpirationHours = 24,
        
        [Parameter(Mandatory=$false)]
        [ValidateScript({
            $parent = Split-Path -Parent $_
            if ($parent -and -not (Test-Path $parent)) {
                throw "Parent directory does not exist: $parent"
            }
            return $true
        })]
        [string]$OutFile
    )
    
    process {
        try {
            # Check for required ConvertTo-Yaml cmdlet
            if (-not (Get-Command -Name 'ConvertTo-Yaml' -ErrorAction SilentlyContinue)) {
                Write-Error "The 'ConvertTo-Yaml' cmdlet is required but not available. Please install the PowerShell-Yaml module: Install-Module -Name PowerShell-Yaml"
                return $null
            }

            $headers = New-CloudAPIHeaders
            
            # Build query parameters
            $queryParams = @{
                expirationHours = $ExpirationHours
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path "kubernetes/clusters/$ClusterId/kubeconfig" -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            # If response is an object, extract the kubeconfig content
            $kubeconfig = if ($response -is [string]) {
                $response
            } elseif ($response.kubeconfig) {
                $response.kubeconfig
            } elseif ($response.content) {
                $response.content
            } else {
                # Assume the response itself is the content
                $response | ConvertTo-Yaml -ErrorAction SilentlyContinue | Out-String
            }
            
            # Save to file if specified
            if ($OutFile) {
                try {
                    $kubeconfig | Out-File -FilePath $OutFile -Encoding UTF8 -Force
                    Write-Verbose "Kubeconfig saved to: $OutFile"
                }
                catch {
                    Write-Error "Failed to save kubeconfig to file: $($_.Exception.Message)"
                }
            }
            
            # Return object with success status
            return [PSCustomObject]@{
                Path = $OutFile
                Success = $true
                Content = $kubeconfig
            }
        }
        catch {
            Write-Error "Failed to retrieve kubeconfig: $($_.Exception.Message)"
            return $null
        }
    }
}
