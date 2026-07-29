function Set-CloudNetAccess {
    <#
    .SYNOPSIS
        Modifies an existing network access rule.
    
    .DESCRIPTION
        Updates an existing network access rule (firewall rule).
    
    .PARAMETER Id
        The unique identifier of the network access rule. Required.
    
    .PARAMETER Name
        The new name for the access rule. Required.
    
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
        PS> Set-CloudNetAccess -Id "networkaccess-..." -Name "Updated Rule" -Source "..."
        
        Updates the specified network access rule.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [Alias('NetAccessId')]
        [string]$Id,
        
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
    
    begin {
        $headers = $null
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        }
        catch {
            Write-Error -Message "Failed to initialize API headers: $($_.Exception.Message)" -ErrorId 'InitializeCloudAPIHeadersFailed'
            return
        }
        $results = @()
    }
    
    process {
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
            
            if (-not $PSCmdlet.ShouldProcess("network access rule '$Name' ($Id)", 'Update')) {
                return $null
            }
            
            $response = Invoke-CloudAPIRequest -Path "network/accesses/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            $results += $response
        }
        catch {
            Write-Error -Message "Failed to update network access rule '$Name' ($Id): $($_.Exception.Message)" -ErrorId 'SetCloudNetAccessFailed'
        }
    }
    
    end {
        return $results
    }
}
