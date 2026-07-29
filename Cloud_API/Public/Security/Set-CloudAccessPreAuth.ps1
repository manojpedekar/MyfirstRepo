function Set-CloudAccessPreAuth {
    <#
    .SYNOPSIS
        Updates an access pre-authorization.
    
    .DESCRIPTION
        Updates an existing firewall rule pre-authorization.
    
    .PARAMETER Id
        The ID of the pre-authorization to update.
    
    .PARAMETER Name
        New name for the pre-authorization.
    
    .PARAMETER Ports
        New port ranges.
    
    .PARAMETER Protocol
        New protocol.
    
    .PARAMETER ExpirationDate
        New expiration date.
    
    .EXAMPLE
        PS> Set-CloudAccessPreAuth -Id "preauth-abc123" -Ports "80,443,8080"
    
    .EXAMPLE
        PS> Get-CloudAccessPreAuth -Id "preauth-abc123" | Set-CloudAccessPreAuth -ExpirationDate "2027-12-31"
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [Alias('PreAuthId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$Ports,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('tcp', 'udp', 'icmp')]
        [string]$Protocol,
        
        [Parameter(Mandatory=$false)]
        [datetime]$ExpirationDate
    )
    
    process {
        try {
            if (-not $PSCmdlet.ShouldProcess("access pre-authorization '$Id'", 'Update')) {
                return $null
            }
            
            $headers = New-CloudAPIHeaders -IncludeContentType
            
            $body = @{}
            if ($Name) { $body['name'] = $Name }
            if ($Ports) { $body['ports'] = $Ports }
            if ($Protocol) { $body['protocol'] = $Protocol }
            if ($ExpirationDate) { $body['expirationDate'] = $ExpirationDate.ToString('o') }
            
            $response = Invoke-CloudAPIRequest -Path "security/access/pre-authorizations/$Id" -Method 'PUT' -Headers $headers -Body $body
            return $response
        }
        catch {
            Write-Error "Failed to update access pre-authorization '$Id': $($_.Exception.Message)"
            return $null
        }
    }
}
