Function Monitor-Jobs {
	[CmdletBinding()]
	Param (
		[string]$SuccessLogPath = "C:\Temp\SuccessLog.txt",
		[string]$ErrorLogPath = "C:\Temp\ErrorLog.txt"
	)
	
	# Function to write logs
	Function Write-Log([string]$Path, [string]$Message) {
		Add-Content -Path $Path -Value $Message
	}
	
	# Function to process and log jobs based on their state
	Function Process-Jobs {
		
		$SuccessLogPath = "C:\Temp\SuccessLog.txt"
		$ErrorLogPath = "C:\Temp\ErrorLog.txt"
		
		Get-Job | ForEach-Object {
			If ($_.State -eq 'Completed') {
				If ($_.HasMoreData -and (($_.ChildJobs[0].Error).Length -eq $null)) {
					# Log successful jobs
					Write-Log -Path $SuccessLogPath -Message "Success: $($_.Name)"
				} Else {
					# Log failed jobs
					Write-Log -Path $ErrorLogPath -Message "Error: $($_.Name) = $($_.ChildJobs[0].Error)"
					Export-Clixml "c:\temp\$($_.Name).xml" -InputObject $_
				}
				# Remove the job
				#Remove-Job -Job $_
			} ElseIf ($_.State -eq 'Running') {
				# Display progress of running jobs
				Write-Host "Running: $($_.Name)"
			}
		}
	}
	
	# Create a new runspace for the thread
	$runspace = [runspacefactory]::CreateRunspace()
	$runspace.Open()
	
	# Create a PowerShell instance and add the script block
	$powershell = [powershell]::Create().AddScript({
			While ($true) {
				Process-Jobs
				Start-Sleep -Seconds 5
			}
		})
	
	# Assign the runspace to the PowerShell instance and begin execution
	$powershell.Runspace = $runspace
	$asyncResult = $powershell.BeginInvoke()
	
	# Return the PowerShell and Runspace objects
	Return, @($powershell, $runspace)
}

# Function to stop the monitoring
Function Stop-Monitoring {
	Param (
		[System.Management.Automation.PowerShell]$PowerShellInstance,
		[System.Management.Automation.Runspaces.Runspace]$RunspaceInstance
	)
	
	$PowerShellInstance.Stop()
	$RunspaceInstance.Close()
	$PowerShellInstance.Dispose()
}

# Usage
$monitoringObjects = Monitor-Jobs
Start-Job -Name TestJob1 -ScriptBlock { Get-ChildItem c:\windows }
Start-Job -Name TestJob2 -ScriptBlock { Get-Content "C:\Path\To\NonExistentFile.txt"}


# To stop monitoring
Stop-Monitoring @monitoringObjects


Get-Job | % { If ($_.HasMoreData -and ($_.ChildJobs[0].Error -eq 0)) { $true } Else { $false } }

