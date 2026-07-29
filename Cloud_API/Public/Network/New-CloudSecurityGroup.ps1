function New-CloudSecurityGroup {
    <#
    .SYNOPSIS
        Creates a new security group.
    
    .DESCRIPTION
        Creates a new cloud security group in the specified sub-project.
    
    .PARAMETER Name
        The name for the security group. Required.
    
    .PARAMETER SubprojectId
        The sub-project ID where the security group will be created. Required.
    
    .PARAMETER Type
        The type of security group. Defaults to 'Standard'.
    
    .EXAMPLE
        PS> New-CloudSecurityGroup -Name "MySecurityGroup" -SubprojectId "subproject-..."
        
        Creates a new security group.
    
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
        [string]$Type = "Standard"
    )
    
    try {
        $body = @{
            subprojectId = $SubprojectId
            name = $Name
            groupPolicyEnabled = $false
            type = $Type
        }
        
        if (-not $PSCmdlet.ShouldProcess("security group '$Name' in sub-project '$SubprojectId'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path 'network/securitygroups' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create security group: $($_.Exception.Message)"
        return $null
    }
}
