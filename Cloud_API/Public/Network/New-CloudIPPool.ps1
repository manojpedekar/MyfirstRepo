function New-CloudIPPool {
    <#
    .SYNOPSIS
        Creates a new IP pool.
    
    .DESCRIPTION
        Creates a new IP pool with a defined range of IP addresses.
    
    .PARAMETER Name
        The name of the IP pool (mandatory).
    
    .PARAMETER SubprojectId
        The sub-project ID where the IP pool will be created (mandatory).
    
    .PARAMETER Network
        The network CIDR (e.g., '10.0.0.0/24').
    
    .PARAMETER StartIP
        The starting IP address of the pool range.
    
    .PARAMETER EndIP
        The ending IP address of the pool range.
    
    .PARAMETER Gateway
        The gateway IP address for the pool.
    
    .EXAMPLE
        PS> New-CloudIPPool -Name "production-pool" -SubprojectId "subproject-..." -Network "10.0.1.0/24" -StartIP "10.0.1.10" -EndIP "10.0.1.250" -Gateway "10.0.1.1"
        
        Creates a new IP pool with the specified range.
    
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
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$Network,
        
        [Parameter(Mandatory=$false)]
        [string]$StartIP,
        
        [Parameter(Mandatory=$false)]
        [string]$EndIP,
        
        [Parameter(Mandatory=$false)]
        [string]$Gateway
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("IP pool '$Name' in subproject '$SubprojectId'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $body = @{
            name = $Name
            subprojectId = $SubprojectId
        }
        
        if ($Network) { $body['network'] = $Network }
        if ($StartIP) { $body['startIp'] = $StartIP }
        if ($EndIP) { $body['endIp'] = $EndIP }
        if ($Gateway) { $body['gateway'] = $Gateway }
        
        $response = Invoke-CloudAPIRequest -Path 'network/ip-pools' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create IP pool: $($_.Exception.Message)"
        return $null
    }
}
