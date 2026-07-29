function Remove-CloudAccessPolicy {
    <#
    .SYNOPSIS
        Deletes a cloud access policy.
    
    .DESCRIPTION
        Permanently removes an access policy from the cloud system. Policies
        that are currently in use cannot be deleted.
    
    .PARAMETER Id
        The unique identifier of the access policy to delete. Required.
    
    .PARAMETER Force
        If specified, suppresses the confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudAccessPolicy -Id "policy-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Prompts for confirmation before deleting the policy.
    
    .EXAMPLE
        PS> Remove-CloudAccessPolicy -Id "policy-55c319eb-5944-4d00-a927-02e2eff4430a" -Force
        
        Deletes the policy without prompting for confirmation.
    
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
        [Alias('PolicyId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Confirm action unless Force is specified
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("access policy '$Id'", 'Remove')) {
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders
            $response = Invoke-CloudAPIRequest -Path "iam/access-policies/$Id" -Method 'DELETE' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error -Message "Failed to remove access policy '$Id': $($_.Exception.Message)" -ErrorId 'RemoveCloudAccessPolicyFailed'
            return $null
        }
    }
}
