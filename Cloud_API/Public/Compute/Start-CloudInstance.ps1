function Start-CloudInstance {
    <#
    .SYNOPSIS
        Starts a stopped cloud instance.
    
    .DESCRIPTION
        Powers on a cloud instance that is currently in a stopped state.
        This sends a START action to the instance's power endpoint.
    
    .PARAMETER Id
        The unique identifier of the instance to start. Required.
    
    .PARAMETER Wait
        If specified, waits for the instance to reach the 'available' state.
    
    .EXAMPLE
        PS> Start-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Starts the specified instance.
    
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
        [switch]$Wait
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
            if (-not $PSCmdlet.ShouldProcess("instance '$Id'", 'Start')) {
                return $null
            }
            
            $response = Invoke-CloudAPIRequest -Path "compute/instances/$Id/power?action=START" -Method 'PUT' -Headers $headers
            
            if ($Wait) {
                Write-Verbose "Waiting for instance '$Id' to become available..."
                $startTime = Get-Date
                do {
                    Start-Sleep -Seconds 3
                    $instance = Get-CloudInstance -Id $Id
                    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                    Write-Verbose "Current state: $($instance.state) (elapsed: ${elapsed}s)"
                } while ($instance.state -ne 'available')
                $totalElapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                Write-Verbose "Instance '$Id' is now available after $totalElapsed seconds"
            }
            
            $results += $response
        }
        catch {
            Write-Error -Message "Failed to start instance '$Id': $($_.Exception.Message)" -ErrorId 'StartCloudInstanceFailed'
        }
    }
    
    end {
        return $results
    }
}
