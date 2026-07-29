function Remove-CloudUser {
    <#
    .SYNOPSIS
        Deletes a user from the cloud IAM system.
    
    .DESCRIPTION
        Permanently removes a user from the cloud IAM system. This action cannot
        be undone. Supports ShouldProcess for confirmation.
    
    .PARAMETER Id
        The unique identifier of the user to delete. Required.
    
    .PARAMETER Force
        If specified, suppresses the confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudUser -Id "user-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Prompts for confirmation before deleting the user.
    
    .EXAMPLE
        PS> Remove-CloudUser -Id "user-55c319eb-5944-4d00-a927-02e2eff4430a" -Force
        
        Deletes the user without prompting for confirmation.
    
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
        [Alias('UserId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Confirm action unless Force is specified
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("user '$Id'", 'Remove')) {
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders
            $response = Invoke-CloudAPIRequest -Path "iam/users/$Id" -Method 'DELETE' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error -Message "Failed to remove user '$Id': $($_.Exception.Message)" -ErrorId 'RemoveCloudUserFailed'
            return $null
        }
    }
}
