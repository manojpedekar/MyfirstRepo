function Remove-CloudRole {
    <#
    .SYNOPSIS
        Deletes an IAM role from the cloud system.
    
    .DESCRIPTION
        Permanently removes an IAM role from the cloud system. Roles that
        are currently assigned to users cannot be deleted. Supports ShouldProcess for confirmation.
    
    .PARAMETER Id
        The unique identifier of the role to delete. Required.
    
    .PARAMETER Force
        If specified, suppresses the confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudRole -Id "role-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Prompts for confirmation before deleting the role.
    
    .EXAMPLE
        PS> Remove-CloudRole -Id "role-55c319eb-5944-4d00-a927-02e2eff4430a" -Force
        
        Deletes the role without prompting for confirmation.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [Alias('RoleId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Confirm action unless Force is specified
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("role '$Id'", 'Remove')) {
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders
            $response = Invoke-CloudAPIRequest -Path "iam/roles/$Id" -Method 'DELETE' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error -Message "Failed to remove role '$Id': $($_.Exception.Message)" -ErrorId 'RemoveCloudRoleFailed'
            return $null
        }
    }
}
