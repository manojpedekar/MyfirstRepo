function New-CloudAccessPolicy {
    <#
    .SYNOPSIS
        Creates a new cloud access policy.
    
    .DESCRIPTION
        Creates a new access policy that defines rules for controlling access
        to cloud resources. Policies can be scoped to projects and contain
        multiple rules.
    
    .PARAMETER Name
        The name for the new access policy. Required.
    
    .PARAMETER ProjectId
        The project ID to scope the policy to.
    
    .PARAMETER Rules
        Array of access rules defining the policy. Each rule should be a hashtable
        with properties like action, resource, condition, etc.
    
    .EXAMPLE
        PS> New-CloudAccessPolicy -Name "DeveloperAccess" -ProjectId "project-123"
        
        Creates a basic access policy scoped to a project.
    
    .EXAMPLE
        PS> $rules = @(
            @{ action = "compute.instances:*"; resource = "*" },
            @{ action = "network.securitygroups:read"; resource = "*" }
        )
        PS> New-CloudAccessPolicy -Name "LimitedAccess" -Rules $rules
        
        Creates an access policy with specific rules.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId,
        
        [Parameter(Mandatory=$false)]
        [array]$Rules
    )
    
    try {
        # Build request body
        $body = @{
            name = $Name
        }
        
        if ($ProjectId) {
            $body['projectId'] = $ProjectId
        }
        
        if ($Rules -and $Rules.Count -gt 0) {
            $body['rules'] = $Rules
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path 'iam/access-policies' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create access policy: $($_.Exception.Message)"
        return $null
    }
}
