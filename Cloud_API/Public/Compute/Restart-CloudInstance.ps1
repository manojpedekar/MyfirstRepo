function Restart-CloudInstance {
    <#
    .SYNOPSIS
        Restarts a cloud instance.
    
    .DESCRIPTION
        Performs a restart (stop then start) of a cloud instance.
        If the instance is already stopped, prompts to power it on.
    
    .PARAMETER Id
        The unique identifier of the instance to restart. Required.
    
    .PARAMETER Force
        If specified, does not prompt when instance is already off.
    
    .EXAMPLE
        PS> Restart-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Restarts the specified instance.
    
    .OUTPUTS
        PSCustomObject. Returns status object with success/failure information.
    
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
        [switch]$Force
    )
    
    begin {
        $results = @()
    }
    
    process {
        try {
            if (-not $PSCmdlet.ShouldProcess("instance '$Id'", 'Restart')) {
                return $null
            }
            
            $instance = Get-CloudInstance -Id $Id
            
            if (-not $instance) {
                Write-Error -Message "Instance '$Id' not found" -ErrorId 'RestartCloudInstanceNotFound'
                return $null
            }
            
            $startTime = Get-Date
            $result = $null
            
            if ($instance.state -eq 'available') {
                Write-Verbose "Restarting machine '$($instance.name)' with ID $($instance.id)."
                
                # Stop the instance
                Stop-CloudInstance -Id $Id | Out-Null
                do {
                    Write-Verbose "The instance is shutting down..."
                    Start-Sleep -Seconds 3
                    $instance = Get-CloudInstance -Id $Id
                    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                    Write-Verbose "Current state: $($instance.state) (elapsed: ${elapsed}s)"
                } while ($instance.state -ne 'off')
                
                Write-Verbose "Instance is shut down, waiting 30 seconds for the cloud task to complete before starting up."
                Start-Sleep -Seconds 30
                
                # Start the instance
                Start-CloudInstance -Id $Id | Out-Null
                do {
                    Write-Verbose "The instance is booting up..."
                    Start-Sleep -Seconds 3
                    $instance = Get-CloudInstance -Id $Id
                    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                    Write-Verbose "Current state: $($instance.state) (elapsed: ${elapsed}s)"
                } while ($instance.state -ne 'available')
                
                $totalElapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                Write-Verbose "Instance '$($instance.name)' with ID $($instance.id) is now available after $totalElapsed seconds"
                
                $result = [PSCustomObject]@{
                    Id = $Id
                    Name = $instance.name
                    State = $instance.state
                    ElapsedSeconds = $totalElapsed
                    Success = $true
                    Action = 'Restart'
                }
            }
            elseif ($instance.state -eq 'off') {
                if ($Force) {
                    Write-Verbose "Instance '$($instance.name)' is already stopped. Starting it up..."
                    Start-CloudInstance -Id $Id | Out-Null
                    do {
                        Write-Verbose "The instance is booting up..."
                        Start-Sleep -Seconds 3
                        $instance = Get-CloudInstance -Id $Id
                        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                        Write-Verbose "Current state: $($instance.state) (elapsed: ${elapsed}s)"
                    } while ($instance.state -ne 'available')
                    
                    $totalElapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                    Write-Verbose "Instance '$($instance.name)' with ID $($instance.id) is now available after $totalElapsed seconds"
                    
                    $result = [PSCustomObject]@{
                        Id = $Id
                        Name = $instance.name
                        State = $instance.state
                        ElapsedSeconds = $totalElapsed
                        Success = $true
                        Action = 'Start'
                    }
                } else {
                    $message = "The instance '$($instance.name)' with ID $($instance.id) is currently powered off. Would you like to power it on?"
                    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Power on the instance"
                    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Do not power on the instance"
                    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                    $choiceResult = $host.UI.PromptForChoice("Instance is Powered Off", $message, $options, 1)
                    
                    if ($choiceResult -eq 0) {
                        Write-Verbose "User chose to power on instance $Id"
                        Start-CloudInstance -Id $Id | Out-Null
                        do {
                            Write-Verbose "The instance is booting up..."
                            Start-Sleep -Seconds 3
                            $instance = Get-CloudInstance -Id $Id
                            $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                            Write-Verbose "Current state: $($instance.state) (elapsed: ${elapsed}s)"
                        } while ($instance.state -ne 'available')
                        
                        $totalElapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                        Write-Verbose "Instance '$($instance.name)' with ID $($instance.id) is now available after $totalElapsed seconds"
                        
                        $result = [PSCustomObject]@{
                            Id = $Id
                            Name = $instance.name
                            State = $instance.state
                            ElapsedSeconds = $totalElapsed
                            Success = $true
                            Action = 'Start'
                        }
                    } else {
                        Write-Verbose "User declined to power on instance $Id"
                        Write-Warning "No action taken. Instance remains powered off."
                        $result = [PSCustomObject]@{
                            Id = $Id
                            Name = $instance.name
                            State = $instance.state
                            ElapsedSeconds = 0
                            Success = $false
                            Action = 'None'
                        }
                    }
                }
            } else {
                Write-Error -Message "Instance '$($instance.name)' with ID $($instance.id) is in an unexpected state: $($instance.state). Please check the instance manually." -ErrorId 'RestartCloudInstanceInvalidState'
                $result = [PSCustomObject]@{
                    Id = $Id
                    Name = $instance.name
                    State = $instance.state
                    ElapsedSeconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                    Success = $false
                    Action = 'Error'
                }
            }
            
            if ($result) {
                $results += $result
            }
        }
        catch {
            Write-Error -Message "Failed to restart instance '$Id': $($_.Exception.Message)" -ErrorId 'RestartCloudInstanceFailed'
        }
    }
    
    end {
        return $results
    }
}
