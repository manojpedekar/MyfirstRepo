function New-CloudServiceAccount {
    <#
    .SYNOPSIS
        Creates a new cloud service account.
    
    .DESCRIPTION
        Creates a new service account that can be used by applications and
        automated processes to access cloud resources. Service accounts are
        associated with projects and can be assigned roles.
    
    .PARAMETER Name
        The name for the new service account. Required.
    
    .PARAMETER ProjectId
        The project ID where the service account will be created. Required.
    
    .PARAMETER RoleIds
        Array of role IDs to assign to the service account.
    
    .PARAMETER Wait
        If specified, waits for the service account creation to complete.
    
    .PARAMETER Async
        If specified, returns immediately after making the request without waiting.
    
    .EXAMPLE
        PS> New-CloudServiceAccount -Name "CI-Deployment" -ProjectId "project-123"
        
        Creates a basic service account.
    
    .EXAMPLE
        PS> New-CloudServiceAccount -Name "Backup-Service" -ProjectId "project-123" `
            -RoleIds @("role-1", "role-2") -Wait
        
        Creates a service account with roles and waits for completion.
    
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
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectId,
        
        [Parameter(Mandatory=$false)]
        [string[]]$RoleIds,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    try {
        # Build request body
        $body = @{
            name = $Name
            projectId = $ProjectId
        }
        
        if ($RoleIds -and $RoleIds.Count -gt 0) {
            $body['roleIds'] = $RoleIds
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path 'iam/service-accounts' -Method 'POST' -Headers $headers -Body $body -Wait:$Wait -Async:$Async
        
        return $response
    }
    catch {
        Write-Error "Failed to create service account: $($_.Exception.Message)"
        return $null
    }
}
