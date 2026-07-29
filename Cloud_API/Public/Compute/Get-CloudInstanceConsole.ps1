function Get-CloudInstanceConsole {
    <#
    .SYNOPSIS
        Retrieves console access information for an instance.
    
    .DESCRIPTION
        Gets console access URL or connection information for a cloud instance.
        This allows direct access to the instance console through the cloud platform.
    
    .PARAMETER Id
        The unique identifier of the instance. This parameter is mandatory.
    
    .PARAMETER Type
        The type of console to retrieve. Options: "vnc", "serial", "web".
        Default is "web" for web-based console.
    
    .EXAMPLE
        PS> Get-CloudInstanceConsole -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Gets web console URL for the specified instance.
    
    .EXAMPLE
        PS> Get-CloudInstanceConsole -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Type "vnc"
        
        Gets VNC console connection details.
    
    .OUTPUTS
        PSCustomObject with properties:
        - consoleUrl: URL for web console access
        - connectionInfo: Connection details for VNC/serial consoles
        - expiresAt: Expiration time for the console session
        Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('InstanceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('vnc', 'serial', 'web')]
        [string]$Type = 'web'
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders
            
            # Validate instance exists
            $instanceExists = Test-CloudAPIResource -ResourceType 'compute/instances' -ResourceId $Id
            if (-not $instanceExists) {
                Write-Error "Instance '$Id' not found"
                return $null
            }
            
            # Build query parameters
            $queryParams = @{
                type = $Type
            }
            
            # Get console info
            $path = "compute/instances/$Id/console"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve console information: $($_.Exception.Message)"
            return $null
        }
    }
}
