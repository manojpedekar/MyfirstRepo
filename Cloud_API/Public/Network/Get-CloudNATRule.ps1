function Get-CloudNATRule {
    <#
    .SYNOPSIS
        Retrieves NAT rules.
    
    .DESCRIPTION
        Gets NAT (Network Address Translation) rules.
        Can retrieve a specific rule by ID or list all rules for a sub-project or project.
    
    .PARAMETER Id
        The unique identifier of the NAT rule.
    
    .PARAMETER SubprojectId
        The sub-project ID to list NAT rules from.
    
    .PARAMETER ProjectId
        The project ID to list NAT rules from.
    
    .EXAMPLE
        PS> Get-CloudNATRule -Id "natrule-..."
        
        Retrieves details for a specific NAT rule.
    
    .EXAMPLE
        PS> Get-CloudNATRule -SubprojectId "subproject-..."
        
        Lists all NAT rules in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('NATRuleId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "network/nat-rules/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{}
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            elseif ($ProjectId) { $queryParams['projectId'] = $ProjectId }
            
            $response = Invoke-CloudAPIRequest -Path 'network/nat-rules' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve NAT rule(s): $($_.Exception.Message)"
        return $null
    }
}
