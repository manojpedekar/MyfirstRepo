<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	3/9/2023 5:14 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>


$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$Action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-ExecutionPolicy Bypass -File "C:\temp\resetprocess.ps1"' -WorkingDirectory C:\temp
$Trigger = New-ScheduledTaskTrigger -Once -At "8:00 PM"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -WakeToRun -Priority 7
$Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Settings $Settings -Description "Resetting process at 5pm" -Principal $principal

Register-ScheduledTask -TaskName "Reset Process" -InputObject $Task -TaskPath "\"


<#
This format can be used to create a task with multiple actions
$actions = (New-ScheduledTaskAction -Execute 'foo.ps1'), (New-ScheduledTaskAction -Execute 'bar.ps1')
#>
