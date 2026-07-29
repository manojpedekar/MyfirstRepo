function New-CloudVPC {
    <#
    .SYNOPSIS
        Creates a new VPC.
    
    .DESCRIPTION
        Creates a new Virtual Private Cloud (VPC) with a specified CIDR block.
    
    .PARAMETER Name
        The name of the VPC (mandatory).
    
    .PARAMETER SubprojectId
        The sub-project ID where the VPC will be created (mandatory).
    
    .PARAMETER CIDR
        The CIDR block for the VPC (e.g., '10.0.0.0/16') (mandatory).
    
    .EXAMPLE
        PS> New-CloudVPC -Name "production-vpc" -SubprojectId "subproject-..." -CIDR "10.0.0.0/16"
        
        Creates a new VPC with the specified CIDR.
    
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
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$CIDR
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("VPC '$Name' in subproject '$SubprojectId'", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        $body = @{
            name = $Name
            subprojectId = $SubprojectId
            cidr = $CIDR
        }
        
        $response = Invoke-CloudAPIRequest -Path 'network/vpcs' -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to create VPC: $($_.Exception.Message)"
        return $null
    }
}
