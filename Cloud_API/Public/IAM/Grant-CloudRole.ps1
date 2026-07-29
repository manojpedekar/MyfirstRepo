function Grant-CloudRole {
    <#
    .SYNOPSIS
        Assigns a role to a user.
    
    .DESCRIPTION
        Grants a cloud IAM role to a user, optionally scoped to a specific
        project or sub-project. This allows fine-grained access control.
    
    .PARAMETER UserId
        The unique identifier of the user to assign the role to. Required.
    
    .PARAMETER RoleId
        The unique identifier of the role to assign. Required.
    
    .PARAMETER ProjectId
        The project ID to scope the role assignment to.
    
    .PARAMETER SubprojectId
        The sub-project ID to scope the role assignment to.
    
    .EXAMPLE
        PS> Grant-CloudRole -UserId "user-55c319eb-5944-4d00-a927-02e2eff4430a" `
            -RoleId "role-12345678-1234-1234-1234-123456789012"
        
        Assigns a role to a user globally.
    
    .EXAMPLE
        PS> Grant-CloudRole -UserId "user-55c319eb-5944-4d00-a927-02e2eff4430a" `
            -RoleId "role-12345678-1234-1234-1234-123456789012" `
            -ProjectId "project-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        
        Assigns a role to a user scoped to a specific project.
    
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
        [string]$ProjectId,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId
    )
    
    try {
        # Build request body
        $body = @{
            roleId = $RoleId
        }
        
        if ($ProjectId) {
            $body['projectId'] = $ProjectId
        }
        
        if ($SubprojectId) {
            $body['subprojectId'] = $SubprojectId
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "iam/users/$UserId/roles" -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to grant role '$RoleId' to user '$UserId': $($_.Exception.Message)"
        return $null
    }
}
