function Set-CloudAccessPolicy {
    <#
    .SYNOPSIS
        Updates an existing cloud access policy.
    
    .DESCRIPTION
        Updates the rules of an existing access policy. This allows modifying
        the access controls without creating a new policy.
    
    .PARAMETER Id
        The unique identifier of the access policy to update. Required.
    
    .PARAMETER Rules
        Array of access rules to replace the existing rules.
    
    .EXAMPLE
        PS> $rules = @(
            @{ action = "compute.instances:*"; resource = "*"; condition = "time:DayTime" }
        )
        PS> Set-CloudAccessPolicy -Id "policy-55c319eb-5944-4d00-a927-02e2eff4430a" -Rules $rules
        
        Updates the rules of an access policy.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('PolicyId')]
        [string]$Id,
        
        [Parameter(Mandatory=$true)]
        [array]$Rules
    )
    
    process {
        try {
            # Validate rules is not empty
            if ($Rules.Count -eq 0) {
                Write-Error "Rules array cannot be empty"
                return $null
            }
            
            # Build request body
            $body = @{
                rules = $Rules
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            $response = Invoke-CloudAPIRequest -Path "iam/access-policies/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            return $response
        }
        catch {
            Write-Error "Failed to update access policy '$Id': $($_.Exception.Message)"
            return $null
        }
    }
}
