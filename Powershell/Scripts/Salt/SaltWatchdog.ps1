<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	5/13/2024 10:34 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>


# Define service name and timeout in seconds
$serviceName = 'salt-minion'
$timeout = 30 # Timeout after x seconds

# Start the job that gets the process ID of the service
$job = Start-Job -ScriptBlock {
	$service = Get-WmiObject -Query "SELECT * FROM Win32_Service WHERE Name = '$using:serviceName'"
	$service.ProcessId
}

# Wait for the job to complete with a timeout
If (Wait-Job -Job $job -Timeout $timeout) {
	# If job completes within the timeout, get the result
	$processId = Receive-Job -Job $job
	Write-Output "Process ID of $serviceName is $processId"
} Else {
	# If job does not complete within the timeout, execute alternative action
	Write-Output "Timed out retrieving process ID for $serviceName. Executing alternative action."
	# Add code to notify admins via file beat or some other method
	#the command to list the services should not take this long and is indicitive of a problem
}

# Stop the job if it's still running
If ($job.JobStateInfo.State -eq 'Running') {
	Stop-Job -Job $job
}

# Force removal of the job
Remove-Job -Job $job -Force


