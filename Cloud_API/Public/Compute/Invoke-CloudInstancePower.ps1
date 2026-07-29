function Invoke-CloudInstancePower {
    <#
    .SYNOPSIS
        Sends an arbitrary power action to a cloud instance.
    
    .DESCRIPTION
        Wraps the /power endpoint to allow callers to send any supported power action
        (START, STOP, RESET, RESETGUEST, STOPGUEST) in a single call. For common
        operations like start, stop, and restart, prefer the specific functions
        Start-CloudInstance, Stop-CloudInstance, and Restart-CloudInstance.
    
    .PARAMETER Id
        The unique identifier of the instance. Required.
    
    .PARAMETER Action
        The power action to perform. Valid values: START, STOP, RESET, RESETGUEST, STOPGUEST. Required.
    
    .PARAMETER Wait
        If specified, waits for the action to complete.
    
    .EXAMPLE
        PS> Invoke-CloudInstancePower -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Action STOPGUEST
        
        Sends a STOPGUEST action to the instance.
    
    .EXAMPLE
        PS> Invoke-CloudInstancePower -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Action RESETGUEST
        
        Sends a RESETGUEST action to the instance.
    
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
        [Alias('InstanceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('START', 'STOP', 'RESET', 'RESETGUEST', 'STOPGUEST')]
        [string]$Action,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("instance '$Id'", "Power action: $Action")) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "compute/instances/$Id/power?action=$Action" -Method 'PUT' -Headers $headers -Wait:$Wait
        
        return $response
    }
    catch {
        Write-Error "Failed to perform power action: $($_.Exception.Message)"
        return $null
    }
}
