function Get-CloudPermission {
    <#
    .SYNOPSIS
        Retrieves information about available cloud permissions.
    
    .DESCRIPTION
        Gets details about available IAM permissions that can be assigned to roles.
        Can filter by resource type or resource ID.
    
    .PARAMETER Id
        The unique identifier of the permission to retrieve.
    
    .PARAMETER ResourceType
        Filter permissions by resource type (e.g., "compute", "network", "storage").
    
    .PARAMETER ResourceId
        Filter permissions by specific resource ID.
    
    .EXAMPLE
        PS> Get-CloudPermission
        
        Lists all available permissions.
    
    .EXAMPLE
        PS> Get-CloudPermission -ResourceType "compute"
        
        Lists all permissions related to compute resources.
    
    .EXAMPLE
        PS> Get-CloudPermission -Id "permission-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves details for a specific permission.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('PermissionId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceType,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceId
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # Build query parameters
            $queryParams = @{
                sort = 'name,asc'
            }
            
            if ($ResourceType) { $queryParams['resourceType'] = $ResourceType }
            if ($ResourceId) { $queryParams['resourceId'] = $ResourceId }
            
            # Determine path
            if ($Id) {
                $path = "iam/permissions/$Id"
            } else {
                $path = "iam/permissions"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve permission(s): $($_.Exception.Message)"
            return $null
        }
    }
}
