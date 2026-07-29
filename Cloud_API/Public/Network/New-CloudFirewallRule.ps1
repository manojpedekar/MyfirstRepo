function New-CloudFirewallRule {
    <#
    .SYNOPSIS
        Creates a new firewall rule.
    
    .DESCRIPTION
        Creates a new firewall rule for a security group.
        Defines ingress or egress traffic rules with protocol, port range, and source/destination.
    
    .PARAMETER SecurityGroupId
        The security group ID to create the rule in (mandatory).
    
    .PARAMETER Direction
        The direction of traffic: 'in' for ingress or 'out' for egress (mandatory).
    
    .PARAMETER Protocol
        The protocol (e.g., 'TCP', 'UDP', 'ICMP', 'ANY').
    
    .PARAMETER PortRange
        The port range (e.g., "80", "443", "1-65535").
    
    .PARAMETER Source
        The source CIDR or security group for ingress rules.
    
    .PARAMETER Destination
        The destination CIDR or security group for egress rules.
    
    .PARAMETER Action
        The action to take: 'allow' or 'deny' (default: 'allow').
    
    .EXAMPLE
        PS> New-CloudFirewallRule -SecurityGroupId "sg-..." -Direction "in" -Protocol "TCP" -PortRange "80" -Source "0.0.0.0/0"
        
        Creates an ingress rule allowing HTTP traffic from anywhere.
    
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
        [string]$SecurityGroupId,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('in', 'out')]
        [string]$Direction,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('TCP', 'UDP', 'ICMP', 'ANY')]
        [string]$Protocol = 'TCP',
        
        [Parameter(Mandatory=$false)]
        [string]$PortRange = "1-65535",
        
        [Parameter(Mandatory=$false)]
        [string]$Source,
        
        [Parameter(Mandatory=$false)]
        [string]$Destination,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('allow', 'deny')]
        [string]$Action = 'allow'
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("firewall rule in security group '$SecurityGroupId'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $body = @{
            securityGroupId = $SecurityGroupId
            direction = $Direction
            protocol = $Protocol
            portRange = $PortRange
            action = $Action
        }
        
        if ($Direction -eq 'in' -and $Source) {
            $body['source'] = $Source
        }
        
        if ($Direction -eq 'out' -and $Destination) {
            $body['destination'] = $Destination
        }
        
        $response = Invoke-CloudAPIRequest -Path 'network/firewall-rules' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create firewall rule: $($_.Exception.Message)"
        return $null
    }
}
