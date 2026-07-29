function Remove-CloudServiceAccount {
    <#
    .SYNOPSIS
        Deletes a cloud service account.
    
    .DESCRIPTION
        Permanently removes a service account from the cloud system. Service
        accounts that are currently in use by running processes should be
        carefully considered before deletion. Supports ShouldProcess for confirmation.
    
    .PARAMETER Id
        The unique identifier of the service account to delete. Required.
    
    .PARAMETER Force
        If specified, suppresses the confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudServiceAccount -Id "sa-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Prompts for confirmation before deleting the service account.
    
    .EXAMPLE
        PS> Remove-CloudServiceAccount -Id "sa-55c319eb-5944-4d00-a927-02e2eff4430a" -Force
        
        Deletes the service account without prompting for confirmation.
    
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
        [Alias('ServiceAccountId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Confirm action unless Force is specified
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("service account '$Id'", 'Remove')) {
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders
            $response = Invoke-CloudAPIRequest -Path "iam/service-accounts/$Id" -Method 'DELETE' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error -Message "Failed to remove service account '$Id': $($_.Exception.Message)" -ErrorId 'RemoveCloudServiceAccountFailed'
            return $null
        }
    }
}
