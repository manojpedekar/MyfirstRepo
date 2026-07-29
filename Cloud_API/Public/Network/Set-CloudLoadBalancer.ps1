function Set-CloudLoadBalancer {
    <#
    .SYNOPSIS
        Updates a load balancer configuration.
    
    .DESCRIPTION
        Updates an existing load balancer's configuration including name, ports, and protocol.
    
    .PARAMETER Id
        The unique identifier of the load balancer (mandatory).
    
    .PARAMETER Name
        The new name for the load balancer.
    
    .PARAMETER Ports
        The ports to listen on.
    
    .PARAMETER Protocol
        The protocol to use.
    
    .EXAMPLE
        PS> Set-CloudLoadBalancer -Id "lb-..." -Name "updated-lb" -Ports 80,443,8080
        
        Updates the load balancer name and ports.
    
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
        [Alias('LoadBalancerId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [int[]]$Ports,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('TCP', 'UDP', 'HTTP', 'HTTPS')]
        [string]$Protocol
    )
    
    begin {
        $headers = $null
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType
        }
        catch {
            Write-Error -Message "Failed to initialize API headers: $($_.Exception.Message)" -ErrorId 'InitializeCloudAPIHeadersFailed'
            return
        }
        $results = @()
    }
    
    process {
        try {
            if (-not $PSCmdlet.ShouldProcess("load balancer '$Id'", 'Update')) {
                return $null
            }
            
            $body = @{}
            if ($Name) { $body['name'] = $Name }
            if ($Ports) { $body['ports'] = $Ports }
            if ($Protocol) { $body['protocol'] = $Protocol }
            
            if ($body.Count -eq 0) {
                Write-Warning "No parameters to update specified."
                return $null
            }
            
            $response = Invoke-CloudAPIRequest -Path "network/loadbalancers/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            $results += $response
        }
        catch {
            Write-Error -Message "Failed to update load balancer '$Id': $($_.Exception.Message)" -ErrorId 'SetCloudLoadBalancerFailed'
        }
    }
    
    end {
        return $results
    }
}
