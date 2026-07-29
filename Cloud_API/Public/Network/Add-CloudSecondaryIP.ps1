function Add-CloudSecondaryIP {
    <#
    .SYNOPSIS
        Attaches a secondary IP to an instance.
    
    .DESCRIPTION
        Attaches a secondary IP to a cloud instance.
    
    .PARAMETER SecondaryIpId
        The secondary IP ID. Required.
    
    .PARAMETER InstanceId
        The instance ID to attach the IP to. Required.
    
    .EXAMPLE
        PS> Add-CloudSecondaryIP -SecondaryIpId "ip-..." -InstanceId "i-..."
        
        Attaches the secondary IP to the instance.
    
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
        [string]$SecondaryIpId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$InstanceId
    )
    
    try {
        $body = @{
            instanceId = $InstanceId
        }
        
        if (-not $PSCmdlet.ShouldProcess("secondary IP '$SecondaryIpId' to instance '$InstanceId'", 'Attach')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path "network/secondary-ips/$SecondaryIpId/members" -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to attach secondary IP: $($_.Exception.Message)"
        return $null
    }
}
