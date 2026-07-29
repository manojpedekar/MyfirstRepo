function Remove-CloudSecurityGroupMember {
    <#
    .SYNOPSIS
        Removes a member from a security group.
    
    .DESCRIPTION
        Removes a member IP from a specified security group.
    
    .PARAMETER SecuritygroupId
        The security group ID. Required.
    
    .PARAMETER Member
        The member IP to remove. Required.
    
    .EXAMPLE
        PS> Remove-CloudSecurityGroupMember -SecuritygroupId "securitygroup-..." -Member "10.10.10.10"
        
        Removes the specified IP from the security group.
    
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
        [string]$SecuritygroupId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Member
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("member '$Member' from security group '$SecuritygroupId'", 'Remove')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "network/securitygroups/$SecuritygroupId/members/$Member" -Method 'DELETE' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to remove security group member: $($_.Exception.Message)"
        return $null
    }
}
