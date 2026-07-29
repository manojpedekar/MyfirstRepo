function Remove-CloudIPPool {
    <#
    .SYNOPSIS
        Deletes an IP pool.
    
    .DESCRIPTION
        Permanently deletes an IP pool.
        Use -Force to bypass confirmation prompts.
    
    .PARAMETER Id
        The unique identifier of the IP pool (mandatory).
    
    .PARAMETER Force
        Bypass confirmation prompts.
    
    .EXAMPLE
        PS> Remove-CloudIPPool -Id "ippool-..." -Force
        
        Deletes the IP pool without confirmation.
    
    .OUTPUTS
        PSCustomObject or $null. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('IPPoolId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("IP pool '$Id'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $response = Invoke-CloudAPIRequest -Path "network/ip-pools/$Id" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove IP pool: $($_.Exception.Message)"
        return $null
    }
}
