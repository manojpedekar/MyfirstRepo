function New-CloudSecondaryIP {
    <#
    .SYNOPSIS
        Creates a new secondary IP.
    
    .DESCRIPTION
        Creates a new secondary IP within a sub-project.
    
    .PARAMETER Name
        The name for the secondary IP. Required.
    
    .PARAMETER DeploymentZoneId
        The deployment zone ID. Required.
    
    .PARAMETER SubprojectId
        The sub-project ID. Required.
    
    .PARAMETER Network
        The network CIDR. Required.
    
    .EXAMPLE
        PS> $param = @{
            name = "MySecondaryIP"
            deploymentZoneId = "deploymentzone-na-central-kc"
            subprojectId = "subproject-..."
            network = "10.222.123.0/24"
        }
        PS> New-CloudSecondaryIP @Param
        
        Creates a new secondary IP.
    
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
        [string]$DeploymentZoneId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Network
    )
    
    try {
        $body = @{
            name = $Name
            deploymentZoneId = $DeploymentZoneId
            subprojectId = $SubprojectId
            network = $Network
        }
        
        if (-not $PSCmdlet.ShouldProcess("secondary IP '$Name'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path 'network/secondary-ips' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create secondary IP: $($_.Exception.Message)"
        return $null
    }
}
