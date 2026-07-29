function Set-CloudRole {
    <#
    .SYNOPSIS
        Updates an existing IAM role.
    
    .DESCRIPTION
        Updates the properties of an existing cloud IAM role, including name,
        description, and associated permissions.
    
    .PARAMETER Id
        The unique identifier of the role to update. Required.
    
    .PARAMETER Name
        The updated name for the role.
    
    .PARAMETER Description
        The updated description of the role.
    
    .PARAMETER Permissions
        Array of permission identifiers to assign to the role. Replaces existing permissions.
    
    .EXAMPLE
        PS> Set-CloudRole -Id "role-55c319eb-5944-4d00-a927-02e2eff4430a" -Description "Updated description"
        
        Updates the description of the specified role.
    
    .EXAMPLE
        PS> Set-CloudRole -Id "role-55c319eb-5944-4d00-a927-02e2eff4430a" `
            -Permissions @("compute.instances.read", "compute.instances.delete")
        
        Updates the permissions assigned to the role.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('RoleId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$Description,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Permissions
    )
    
    process {
        try {
            # Build request body with only provided parameters
            $body = @{}
            
            if ($PSBoundParameters.ContainsKey('Name')) {
                $body['name'] = $Name
            }
            
            if ($PSBoundParameters.ContainsKey('Description')) {
                $body['description'] = $Description
            }
            
            if ($PSBoundParameters.ContainsKey('Permissions')) {
                $body['permissions'] = $Permissions
            }
            
            # Ensure we have at least one property to update
            if ($body.Count -eq 0) {
                Write-Error "At least one property (Name, Description, or Permissions) must be specified for update"
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            $response = Invoke-CloudAPIRequest -Path "iam/roles/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            return $response
        }
        catch {
            Write-Error "Failed to update role '$Id': $($_.Exception.Message)"
            return $null
        }
    }
}
