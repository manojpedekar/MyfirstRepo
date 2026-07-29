function Add-CloudSecurityGroupMember {
    <#
    .SYNOPSIS
        Adds a member to a security group.
    
    .DESCRIPTION
        Adds a member IP to a specified security group.
        Only one member IP can be specified at a time.
    
    .PARAMETER SecuritygroupId
        The security group ID. Required.
    
    .PARAMETER Member
        The member IP to add. Required.
    
    .EXAMPLE
        PS> Add-CloudSecurityGroupMember -SecuritygroupId "securitygroup-..." -Member "10.10.10.10"
        
        Adds the specified IP to the security group.
    
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
        [string]$SecuritygroupId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Member
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("member '$Member' to security group '$SecuritygroupId'", 'Add')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "network/securitygroups/$SecuritygroupId/members/$Member" -Method 'POST' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to add security group member: $($_.Exception.Message)"
        return $null
    }
}
