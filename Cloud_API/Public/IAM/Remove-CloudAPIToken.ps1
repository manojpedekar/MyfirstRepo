function Remove-CloudAPIToken {
    <#
    .SYNOPSIS
        Revokes an API token.
    
    .DESCRIPTION
        Permanently revokes an API token, preventing it from being used
        for authentication. This action cannot be undone.
    
    .PARAMETER Id
        The unique identifier of the API token to revoke. Required.
    
    .PARAMETER Force
        If specified, suppresses the confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudAPIToken -Id "token-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Prompts for confirmation before revoking the token.
    
    .EXAMPLE
        PS> Remove-CloudAPIToken -Id "token-55c319eb-5944-4d00-a927-02e2eff4430a" -Force
        
        Revokes the token without prompting for confirmation.
    
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
        [Alias('TokenId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Confirm action unless Force is specified
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("API token '$Id'", 'Revoke')) {
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders
            $response = Invoke-CloudAPIRequest -Path "iam/tokens/$Id" -Method 'DELETE' -Headers $headers
            
            Write-Verbose "API token '$Id' has been revoked"
            
            return $response
        }
        catch {
            Write-Error -Message "Failed to revoke API token '$Id': $($_.Exception.Message)" -ErrorId 'RemoveCloudAPITokenFailed'
            return $null
        }
    }
}
