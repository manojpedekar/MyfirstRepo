function Stop-CloudInstance {
    <#
    .SYNOPSIS
        Gracefully stops a running cloud instance.
    
    .DESCRIPTION
        Performs a graceful shutdown of a cloud instance that is currently running.
        This sends a STOPGUEST action to the instance's power endpoint.
    
    .PARAMETER Id
        The unique identifier of the instance to stop. Required.
    
    .PARAMETER Wait
        If specified, waits for the instance to reach the 'off' state.
    
    .PARAMETER Force
        If specified, performs a hard stop (RESET) instead of graceful shutdown.
    
    .EXAMPLE
        PS> Stop-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Gracefully stops the specified instance.
    
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
        [Alias('InstanceId', 'ResourceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    begin {
        $headers = $null
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType
        }
        catch {
            Write-Error -Message "Failed to initialize API headers: $($_.Exception.Message)" -ErrorId 'InitializeCloudAPIHeadersFailed'
            return
        }
        $results = @()
    }
    
    process {
        try {
            if (-not $PSCmdlet.ShouldProcess("instance '$Id'", 'Stop')) {
                return $null
            }
            
            $action = if ($Force) { 'RESET' } else { 'STOPGUEST' }
            $response = Invoke-CloudAPIRequest -Path "compute/instances/$Id/power?action=$action" -Method 'PUT' -Headers $headers
            
            if ($Wait) {
                Write-Verbose "Waiting for instance '$Id' to shut down..."
                $startTime = Get-Date
                do {
                    Start-Sleep -Seconds 3
                    $instance = Get-CloudInstance -Id $Id
                    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                    Write-Verbose "Current state: $($instance.state) (elapsed: ${elapsed}s)"
                } while ($instance.state -ne 'off')
                $totalElapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                Write-Verbose "Instance '$Id' is now stopped after $totalElapsed seconds"
            }
            
            $results += $response
        }
        catch {
            Write-Error -Message "Failed to stop instance '$Id': $($_.Exception.Message)" -ErrorId 'StopCloudInstanceFailed'
        }
    }
    
    end {
        return $results
    }
}
