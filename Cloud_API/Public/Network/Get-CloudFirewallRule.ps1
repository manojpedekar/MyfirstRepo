function Get-CloudFirewallRule {
    <#
    .SYNOPSIS
        Retrieves firewall rules.
    
    .DESCRIPTION
        Gets firewall rules for security groups or tenants.
        Can retrieve a specific rule by ID or list all rules matching the specified criteria.
    
    .PARAMETER Id
        The unique identifier of the firewall rule.
    
    .PARAMETER SecurityGroupId
        The security group ID to list rules from.
    
    .PARAMETER TenantId
        The tenant ID to list rules from.
    
    .PARAMETER SubprojectId
        The sub-project ID to list rules from.
    
    .EXAMPLE
        PS> Get-CloudFirewallRule -Id "firewallrule-..."
        
        Retrieves details for a specific firewall rule.
    
    .EXAMPLE
        PS> Get-CloudFirewallRule -SecurityGroupId "sg-..."
        
        Lists all firewall rules for the specified security group.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('FirewallRuleId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SecurityGroupId,
        
        [Parameter(Mandatory=$false)]
        [string]$TenantId,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/firewall-rules/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($SecurityGroupId) { $queryParams['securityGroupId'] = $SecurityGroupId }
            elseif ($TenantId) { $queryParams['tenantId'] = $TenantId }
            elseif ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/firewall-rules' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve firewall rule(s): $($_.Exception.Message)"
        return $null
    }
}
