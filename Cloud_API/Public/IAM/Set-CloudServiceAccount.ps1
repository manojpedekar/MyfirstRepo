function Set-CloudServiceAccount {
    <#
    .SYNOPSIS
        Updates an existing cloud service account.
    
    .DESCRIPTION
        Updates the properties of an existing service account, including name
        and role assignments.
    
    .PARAMETER Id
        The unique identifier of the service account to update. Required.
    
    .PARAMETER Name
        The updated name for the service account.
    
    .PARAMETER RoleIds
        Array of role IDs to assign to the service account. Replaces existing roles.
    
    .EXAMPLE
        PS> Set-CloudServiceAccount -Id "sa-55c319eb-5944-4d00-a927-02e2eff4430a" -Name "Updated-Name"
        
        Updates the name of the specified service account.
    
    .EXAMPLE
        PS> Set-CloudServiceAccount -Id "sa-55c319eb-5944-4d00-a927-02e2eff4430a" `
            -RoleIds @("role-1", "role-2", "role-3")
        
        Updates the roles assigned to the service account.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('ServiceAccountId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string[]]$RoleIds
    )
    
    process {
        try {
            # Build request body with only provided parameters
            $body = @{}
            
            if ($PSBoundParameters.ContainsKey('Name')) {
                $body['name'] = $Name
            }
            
            if ($PSBoundParameters.ContainsKey('RoleIds')) {
                $body['roleIds'] = $RoleIds
            }
            
            # Ensure we have at least one property to update
            if ($body.Count -eq 0) {
                Write-Error "At least one property (Name or RoleIds) must be specified for update"
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            $response = Invoke-CloudAPIRequest -Path "iam/service-accounts/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            return $response
        }
        catch {
            Write-Error "Failed to update service account '$Id': $($_.Exception.Message)"
            return $null
        }
    }
}
