function Get-CloudInstanceVNC {
    <#
    .SYNOPSIS
        Retrieves VNC connection details for an instance.
    
    .DESCRIPTION
        Gets VNC (Virtual Network Computing) connection details for a cloud instance.
        This provides direct graphical console access to the instance.
    
    .PARAMETER Id
        The unique identifier of the instance. This parameter is mandatory.
    
    .EXAMPLE
        PS> Get-CloudInstanceVNC -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Gets VNC connection details for the specified instance.
    
    .OUTPUTS
        PSCustomObject with properties:
        - host: VNC server host
        - port: VNC server port
        - password: VNC password (if applicable)
        - url: Direct VNC URL
        - expiresAt: Expiration time for the VNC session
        Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
        
        This is a convenience wrapper around Get-CloudInstanceConsole -Type vnc.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('InstanceId')]
        [string]$Id
    )
    
    process {
        try {
            # Use the console endpoint with VNC type
            $response = Get-CloudInstanceConsole -Id $Id -Type 'vnc'
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve VNC information: $($_.Exception.Message)"
            return $null
        }
    }
}
