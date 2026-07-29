function New-CloudAccessPreAuth {
    <#
    .SYNOPSIS
        Creates a new access pre-authorization.
    
    .DESCRIPTION
        Creates a firewall rule pre-authorization request for a resource.
        This requires security team approval workflow.
    
    .PARAMETER Name
        The name of the pre-authorization.
    
    .PARAMETER ResourceId
        The ID of the resource to authorize access to.
    
    .PARAMETER Ports
        The port ranges (e.g., "80,443" or "22-25").
    
    .PARAMETER Protocol
        The protocol (tcp, udp, icmp).
    
    .PARAMETER Type
        Optional type of pre-authorization.
    
    .PARAMETER ExpirationDate
        When the authorization expires (ISO 8601 datetime).
    
    .PARAMETER GenerateSecurityAuthorization
        Auto-generate security authorization.
    
    .PARAMETER EnforceAuditMatching
        Enforce audit log matching.
    
    .EXAMPLE
        PS> New-CloudAccessPreAuth -Name "Web Access" -ResourceId "instance-xyz789" -Ports "80,443" -Protocol "tcp"
    
    .EXAMPLE
        PS> New-CloudAccessPreAuth -Name "SSH Access" -ResourceId "instance-xyz789" -Ports "22" -Protocol "tcp" -ExpirationDate "2026-12-31"
    
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
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Ports,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('tcp', 'udp', 'icmp')]
        [string]$Protocol,
        
        [Parameter(Mandatory=$false)]
        [string]$Type,
        
        [Parameter(Mandatory=$false)]
        [datetime]$ExpirationDate,
        
        [Parameter(Mandatory=$false)]
        [switch]$GenerateSecurityAuthorization,
        
        [Parameter(Mandatory=$false)]
        [switch]$EnforceAuditMatching
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("access pre-authorization '$Name' for resource '$ResourceId'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        $body = @{
            name = $Name
            resourceId = $ResourceId
            ports = $Ports
            protocol = $Protocol
        }
        
        if ($Type) { $body['type'] = $Type }
        if ($ExpirationDate) { $body['expirationDate'] = $ExpirationDate.ToString('o') }
        if ($GenerateSecurityAuthorization) { $body['generateSecurityAuthorization'] = $true }
        if ($EnforceAuditMatching) { $body['enforceAuditMatching'] = $true }
        
        $response = Invoke-CloudAPIRequest -Path 'security/access/pre-authorizations' -Method 'POST' -Headers $headers -Body $body
        return $response
    }
    catch {
        Write-Error "Failed to create access pre-authorization: $($_.Exception.Message)"
        return $null
    }
}
