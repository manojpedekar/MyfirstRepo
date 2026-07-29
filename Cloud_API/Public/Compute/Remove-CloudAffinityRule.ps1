function Remove-CloudAffinityRule {
    <#
    .SYNOPSIS
        Removes an affinity or anti-affinity rule.
    
    .DESCRIPTION
        Deletes an affinity rule, removing the placement constraints on the
        associated instances. Supports ShouldProcess for safety.
    
    .PARAMETER Id
        The unique identifier of the affinity rule to remove. This parameter is mandatory.
    
    .PARAMETER Force
        If specified, suppresses the confirmation prompt.
    
    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.
    
    .EXAMPLE
        PS> Remove-CloudAffinityRule -Id "ar-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Removes the specified affinity rule after confirmation.
    
    .EXAMPLE
        PS> Remove-CloudAffinityRule -Id "ar-55c319eb-5944-4d00-a927-02e2eff4430a" -Force
        
        Removes the rule without confirmation.
    
    .EXAMPLE
        PS> Remove-CloudAffinityRule -Id "ar-55c319eb-5944-4d00-a927-02e2eff4430a" -WhatIf
        
        Shows what would happen without actually removing the rule.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('AffinityRuleId', 'RuleId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders
            
            # Get rule info for confirmation message
            $rule = Get-CloudAffinityRule -Id $Id
            if (-not $rule) {
                Write-Error "Affinity rule '$Id' not found"
                return $null
            }
            
            # Build confirmation message
            $ruleName = if ($rule.name) { $rule.name } else { "Unnamed Rule" }
            $ruleType = if ($rule.type) { $rule.type } else { "Unknown Type" }
            $target = "$ruleType Rule: $ruleName ($Id)"
            $action = "Remove"
            
            if ($Force -or $PSCmdlet.ShouldProcess($target, $action)) {
                # Make API request
                $response = Invoke-CloudAPIRequest -Path "compute/affinity-rules/$Id" -Method 'DELETE' -Headers $headers
                
                Write-Verbose "Successfully removed affinity rule $Id"
                return $response
            }
        }
        catch {
            Write-Error "Failed to remove affinity rule: $($_.Exception.Message)"
            return $null
        }
    }
}
