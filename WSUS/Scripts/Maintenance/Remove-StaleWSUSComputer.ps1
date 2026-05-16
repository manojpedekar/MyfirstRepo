<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	5/20/2024 3:11 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Cleanup-StaleWSUSComputers
	 Version:		1.0
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

Function Remove-StaleComputers {
	
	# Load WSUS Server assemblies
	[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
	
	# Connect to the local WSUS Server
	$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $False, 8530)
	
	# Get the current date
	$currentDate = Get-Date
	
	# Define the cutoff date (30 days ago)
	$cutoffDate = $currentDate.AddDays(-30)
	
	# Get the list of computers
	$computers = $wsus.GetComputerTargetGroups() | ForEach-Object { $_.GetComputerTargets() } | Where-Object { $_.LastSyncTime -lt $cutoffDate }
	
	# Remove computers that haven't contacted the WSUS server in 30+ days
	ForEach ($computer In $computers) {
		Write-Host "Removing computer: $($computer.FullDomainName)"
		$computer.Delete()
	}
	
	Write-Host "Cleanup complete. Removed $($computers.Count) computers."
	
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File 'C:\Scripts\Remove-StaleComputers.ps1'"
$trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -TaskName "WSUS Cleanup" -Description "Removes computers that have not contacted the WSUS server in 30+ days"
