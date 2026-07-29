function Get-CloudAffinityRule {
    <#
    .SYNOPSIS
        Retrieves affinity and anti-affinity rules.
    
    .DESCRIPTION
        Gets information about affinity and anti-affinity rules that control
        instance placement on physical hosts. Affinity rules keep instances on
        the same host, while anti-affinity rules keep them on different hosts.
    
    .PARAMETER Id
        The unique identifier of the affinity rule to retrieve.
    
    .PARAMETER SubprojectId
        Filter affinity rules by sub-project ID.
    
    .PARAMETER Type
        Filter by rule type: "Affinity" or "AntiAffinity".
    
    .PARAMETER CheckOnly
        If specified, tests if the rule exists and returns $true or $false.
    
    .EXAMPLE
        PS> Get-CloudAffinityRule
        
        Lists all affinity and anti-affinity rules.
    
    .EXAMPLE
        PS> Get-CloudAffinityRule -Id "ar-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Gets details for a specific affinity rule.
    
    .EXAMPLE
        PS> Get-CloudAffinityRule -Type "AntiAffinity" -SubprojectId "subproject-..."
        
        Lists all anti-affinity rules in the specified sub-project.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('AffinityRuleId', 'RuleId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Affinity', 'AntiAffinity')]
        [string]$Type,
        
        [Parameter(Mandatory=$false)]
        [switch]$CheckOnly
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # CheckOnly mode
            if ($CheckOnly) {
                if (-not $Id) {
                    Write-Error "CheckOnly parameter requires an Id to be specified"
                    return $null
                }
                return Test-CloudAPIResource -ResourceType 'compute/affinity-rules' -ResourceId $Id
            }
            
            # Build query parameters
            $queryParams = @{}
            
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            if ($Type) { $queryParams['type'] = $Type }
            
            # Determine path
            if ($Id) {
                $path = "compute/affinity-rules/$Id"
            } else {
                $path = "compute/affinity-rules"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve affinity rule(s): $($_.Exception.Message)"
            return $null
        }
    }
}
