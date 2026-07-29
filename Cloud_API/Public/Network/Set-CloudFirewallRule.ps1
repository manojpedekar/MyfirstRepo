function Set-CloudFirewallRule {
    <#
    .SYNOPSIS
        Updates a firewall rule.
    
    .DESCRIPTION
        Updates an existing firewall rule's configuration.
        Can modify protocol, port range, and action.
    
    .PARAMETER Id
        The unique identifier of the firewall rule (mandatory).
    
    .PARAMETER Protocol
        The protocol (e.g., 'TCP', 'UDP', 'ICMP', 'ANY').
    
    .PARAMETER PortRange
        The port range (e.g., "80", "443", "1-65535").
    
    .PARAMETER Action
        The action to take: 'allow' or 'deny'.
    
    .EXAMPLE
        PS> Set-CloudFirewallRule -Id "firewallrule-..." -PortRange "443" -Action "allow"
        
        Updates the firewall rule to allow HTTPS traffic.
    
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
        [Alias('FirewallRuleId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('TCP', 'UDP', 'ICMP', 'ANY')]
        [string]$Protocol,
        
        [Parameter(Mandatory=$false)]
        [string]$PortRange,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('allow', 'deny')]
        [string]$Action
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
            if (-not $PSCmdlet.ShouldProcess("firewall rule '$Id'", 'Update')) {
                return $null
            }
            
            $body = @{}
            if ($Protocol) { $body['protocol'] = $Protocol }
            if ($PortRange) { $body['portRange'] = $PortRange }
            if ($Action) { $body['action'] = $Action }
            
            if ($body.Count -eq 0) {
                Write-Warning "No parameters to update specified."
                return $null
            }
            
            $response = Invoke-CloudAPIRequest -Path "network/firewall-rules/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            $results += $response
        }
        catch {
            Write-Error -Message "Failed to update firewall rule '$Id': $($_.Exception.Message)" -ErrorId 'SetCloudFirewallRuleFailed'
        }
    }
    
    end {
        return $results
    }
}
