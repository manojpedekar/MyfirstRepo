$Scriptblock = {
    Function Get-Uptime {
        Param (
            [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
            [string[]]$ComputerName = @(".")
        )
        Process {
            ForEach ($Name In $ComputerName) {
                Try {
                    # Ping the computer to check for availability
                    $ping = Test-Connection -ComputerName $Name -Count 1 -Quiet
                    If ($ping) {
                        # Get operating system information if the ping succeeds
                        $os = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $Name -ErrorAction Stop
                        $LastBootUpTime = $os.ConvertToDateTime($os.LastBootUpTime)
                        $LocalDateTime = $os.ConvertToDateTime($os.LocalDateTime)
                        # Calculate uptime
                        $uptimeSpan = $LocalDateTime - $LastBootUpTime
                        $formattedUptime = "{0} days, {1}h, {2}mins" -f $uptimeSpan.Days, $uptimeSpan.Hours, $uptimeSpan.Minutes
                        # Construct the result object
                        $results = [PSCustomObject]@{
                            ComputerName   = $os.CSName
                            LastBootUpTime = $LastBootUpTime
                            Uptime         = $formattedUptime
                            Days           = $uptimeSpan.Days
                            Hours          = $uptimeSpan.Hours
                            Minutes        = $uptimeSpan.Minutes
                        }
                        # Output the results
                        $results
                    } Else {
                        Write-Warning "$Name is not responding to ping."
                    }
                } Catch {
                    Write-Error "Failed to get uptime for $($Name): $_"
                }
            }
        }
    }
    Get-Uptime -ComputerName localhost | select ComputerName,LastBootUpTime,uptime | ft
    get-winevent -LogName System | where-object {$_.id -eq 1074} | select -expandproperty Message
}

$Servers | ForEach-Object {
    $Session = New-PSSession -ComputerName $_
    Invoke-Command -Session $Session -ScriptBlock $Scriptblock
    Remove-PSSession $Session
}