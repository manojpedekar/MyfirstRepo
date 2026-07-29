function Remove-CloudNetAccess {
    <#
    .SYNOPSIS
        Removes a network access rule.
    
    .DESCRIPTION
        Deletes a specified network access rule (firewall rule).
    
    .PARAMETER Id
        The unique identifier of the network access rule. Required.
    
    .PARAMETER Force
        If specified, bypasses the confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudNetAccess -Id "networkaccess-00000000-0000-0000-0000-0000000000000"
        
        Prompts for confirmation before removing the rule.
    
    .EXAMPLE
        PS> Remove-CloudNetAccess -Id "networkaccess-..." -Force
        
        Removes the rule without prompting.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('NetAccessId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("network access rule '$Id'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path "network/accesses/$Id" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove network access rule: $($_.Exception.Message)"
        return $null
    }
}
