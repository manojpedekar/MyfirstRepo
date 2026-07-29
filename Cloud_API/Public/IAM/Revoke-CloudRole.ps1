function Revoke-CloudRole {
    <#
    .SYNOPSIS
        Removes a role assignment from a user.
    
    .DESCRIPTION
        Revokes a cloud IAM role from a user, optionally scoped to a specific
        project. This removes the user's permissions associated with that role.
    
    .PARAMETER UserId
        The unique identifier of the user to remove the role from. Required.
    
    .PARAMETER RoleId
        The unique identifier of the role to remove. Required.
    
    .PARAMETER ProjectId
        The project ID scope of the role assignment to remove.
    
    .EXAMPLE
        PS> Revoke-CloudRole -UserId "user-55c319eb-5944-4d00-a927-02e2eff4430a" `
            -RoleId "role-12345678-1234-1234-1234-123456789012"
        
        Removes a role assignment from a user.
    
    .EXAMPLE
        PS> Revoke-CloudRole -UserId "user-55c319eb-5944-4d00-a927-02e2eff4430a" `
            -RoleId "role-12345678-1234-1234-1234-123456789012" `
            -ProjectId "project-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        
        Removes a role assignment scoped to a specific project.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$UserId,
        
        [Parameter(Mandatory=$true)]
        [string]$RoleId,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectId
    )
    
    try {
        # Build query parameters
        $queryParams = @{}
        
        if ($ProjectId) {
            $queryParams['projectId'] = $ProjectId
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders
        $response = Invoke-CloudAPIRequest -Path "iam/users/$UserId/roles/$RoleId" -Method 'DELETE' -Headers $headers -QueryParameters $queryParams
        
        return $response
    }
    catch {
        Write-Error "Failed to revoke role '$RoleId' from user '$UserId': $($_.Exception.Message)"
        return $null
    }
}
