function Sync-CloudPOSIXGroup {
    <#
    .SYNOPSIS
        Synchronizes POSIX groups for a project.
    
    .DESCRIPTION
        Synchronizes a project's group membership with LDAP/AD.
        This ensures POSIX groups are properly configured for the project.
    
    .PARAMETER ProjectId
        The project ID. Required.
    
    .EXAMPLE
        PS> Sync-CloudPOSIXGroup -ProjectId "project-00000000-0000-0000-0000-0000000000000"
        
        Synchronizes POSIX groups for the specified project.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectId
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("POSIX groups for project '$ProjectId'", 'Synchronize')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeAccept
        # Note: This uses Admin API v1
        $baseUri = $script:ModuleConfig.BaseUri
        $uri = "$baseUri/api/$($script:ModuleConfig.AdminApiVersion)/admin/ldap/ensurePosixGroups/project/$ProjectId"
        
        # Use Invoke-RestMethod directly for this v1 endpoint
        $response = Invoke-RestMethod -Uri $uri -Method 'GET' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to synchronize POSIX groups: $($_.Exception.Message)"
        return $null
    }
}
