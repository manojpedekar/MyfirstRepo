function New-CloudNetAccess {
    <#
    .SYNOPSIS
        Creates a new network access rule.
    
    .DESCRIPTION
        Creates a new network access rule (firewall rule) defining source,
        destination, protocol, and ports.
    
    .PARAMETER Name
        The name for the access rule. Required.
    
    .PARAMETER Source
        The source security group or IP. Required.
    
    .PARAMETER SourceTenant
        The source tenant. Required.
    
    .PARAMETER Destination
        The destination security group or IP. Required.
    
    .PARAMETER DestinationTenant
        The destination tenant. Required.
    
    .PARAMETER Ports
        The ports to allow. Required.
    
    .PARAMETER Protocol
        The protocol (tcp or udp). Required.
    
    .EXAMPLE
        PS> $param = @{
            name = "New Access Rule on 443/tcp"
            source = "securitygroup-6bc70d2c-3e1e-4e59-9e1f-bb1a74d5711b"
            sourceTenant = "ssnc"
            destination = "securitygroup-8d38b3ea-c46f-434e-8c83-20e111b5d395"
            destinationTenant = "ssnc"
            protocol = "tcp"
            ports = "443"
        }
        PS> New-CloudNetAccess @Param
        
        Creates a new network access rule.
    
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
        [string]$Source,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceTenant,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationTenant,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Ports,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('tcp', 'udp')]
        [string]$Protocol
    )
    
    try {
        $body = @{
            name = $Name
            source = $Source
            sourceTenant = $SourceTenant
            destination = $Destination
            destinationTenant = $DestinationTenant
            ports = $Ports
            protocol = $Protocol
        }
        
        if (-not $PSCmdlet.ShouldProcess("network access rule '$Name'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path 'network/accesses' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create network access rule: $($_.Exception.Message)"
        return $null
    }
}
