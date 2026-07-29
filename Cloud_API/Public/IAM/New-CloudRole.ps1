function New-CloudRole {
    <#
    .SYNOPSIS
        Creates a new IAM role in the cloud system.
    
    .DESCRIPTION
        Creates a new cloud IAM role with the specified name, description,
        and associated permissions.
    
    .PARAMETER Name
        The name for the new role. Required.
    
    .PARAMETER Description
        A description of the role and its purpose.
    
    .PARAMETER Permissions
        Array of permission identifiers to assign to the role.
    
    .EXAMPLE
        PS> New-CloudRole -Name "Developer" -Description "Development team role"
        
        Creates a new role with basic information.
    
    .EXAMPLE
        PS> New-CloudRole -Name "Developer" -Description "Development team role" `
            -Permissions @("compute.instances.read", "compute.instances.create")
        
        Creates a new role with specific permissions.
    
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
        [string]$Description,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Permissions
    )
    
    try {
        # Build request body
        $body = @{
            name = $Name
        }
        
        if ($Description) {
            $body['description'] = $Description
        }
        
        if ($Permissions -and $Permissions.Count -gt 0) {
            $body['permissions'] = $Permissions
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path 'iam/roles' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create role: $($_.Exception.Message)"
        return $null
    }
}
