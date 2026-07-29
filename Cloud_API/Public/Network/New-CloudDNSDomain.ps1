function New-CloudDNSDomain {
    <#
    .SYNOPSIS
        Creates a new DNS domain.
    
    .DESCRIPTION
        Creates a new DNS domain managed by the cloud platform.
    
    .PARAMETER Name
        The domain name (e.g., 'example.com') (mandatory).
    
    .PARAMETER SubprojectId
        The sub-project ID where the domain will be created (mandatory).
    
    .EXAMPLE
        PS> New-CloudDNSDomain -Name "example.com" -SubprojectId "subproject-..."
        
        Creates a new DNS domain.
    
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
        [string]$SubprojectId
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("DNS domain '$Name' in subproject '$SubprojectId'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $body = @{
            name = $Name
            subprojectId = $SubprojectId
        }
        
        $response = Invoke-CloudAPIRequest -Path 'network/dns/domains' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create DNS domain: $($_.Exception.Message)"
        return $null
    }
}
