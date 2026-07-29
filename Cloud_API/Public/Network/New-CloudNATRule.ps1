function New-CloudNATRule {
    <#
    .SYNOPSIS
        Creates a new NAT rule.
    
    .DESCRIPTION
        Creates a new NAT (Network Address Translation) rule to map internal IPs to external IPs.
    
    .PARAMETER Name
        The name of the NAT rule (mandatory).
    
    .PARAMETER SubprojectId
        The sub-project ID where the NAT rule will be created (mandatory).
    
    .PARAMETER InternalIP
        The internal IP address to translate from.
    
    .PARAMETER ExternalIP
        The external IP address to translate to.
    
    .PARAMETER Protocol
        The protocol (e.g., 'TCP', 'UDP', 'ANY').
    
    .PARAMETER Port
        The port number for the NAT rule.
    
    .PARAMETER Wait
        Wait for the NAT rule to be fully provisioned before returning.
    
    .EXAMPLE
        PS> New-CloudNATRule -Name "web-nat" -SubprojectId "subproject-..." -InternalIP "10.0.0.5" -ExternalIP "203.0.113.10" -Protocol "TCP" -Port 80
        
        Creates a NAT rule mapping internal IP to external IP.
    
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
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$InternalIP,
        
        [Parameter(Mandatory=$false)]
        [string]$ExternalIP,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('TCP', 'UDP', 'ANY')]
        [string]$Protocol = 'TCP',
        
        [Parameter(Mandatory=$false)]
        [int]$Port,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("NAT rule '$Name' in subproject '$SubprojectId'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $body = @{
            name = $Name
            subprojectId = $SubprojectId
            protocol = $Protocol
        }
        
        if ($InternalIP) { $body['internalIp'] = $InternalIP }
        if ($ExternalIP) { $body['externalIp'] = $ExternalIP }
        if ($Port) { $body['port'] = $Port }
        
        $response = Invoke-CloudAPIRequest -Path 'network/nat-rules' -Method 'POST' -Headers $headers -Body $body -Wait:$Wait
        
        return $response
    }
    catch {
        Write-Error "Failed to create NAT rule: $($_.Exception.Message)"
        return $null
    }
}
