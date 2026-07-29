function Remove-CloudAccessPreAuth {
    <#
    .SYNOPSIS
        Removes an access pre-authorization.
    
    .DESCRIPTION
        Deletes a firewall rule pre-authorization.
    
    .PARAMETER Id
        The ID of the pre-authorization to remove.
    
    .PARAMETER Force
        Skip confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudAccessPreAuth -Id "preauth-abc123"
    
    .EXAMPLE
        PS> Get-CloudAccessPreAuth -ResourceId "instance-xyz789" | Remove-CloudAccessPreAuth -Force
    
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
        [ValidateNotNullOrEmpty()]
        [Alias('PreAuthId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("access pre-authorization '$Id'", 'Remove')) {
                return $null
            }
            
            $headers = New-CloudAPIHeaders
            
            $response = Invoke-CloudAPIRequest -Path "security/access/pre-authorizations/$Id" -Method 'DELETE' -Headers $headers
            return $response
        }
        catch {
            Write-Error "Failed to remove access pre-authorization '$Id': $($_.Exception.Message)"
            return $null
        }
    }
}
