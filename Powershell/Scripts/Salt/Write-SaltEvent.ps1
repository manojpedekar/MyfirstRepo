<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	2/8/2024 5:29 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Write-SaltEvent
	 Version:     	1.0
	===========================================================================
	.DESCRIPTION
		A demonstration script to illustrate windows event logginf with defined event sets
#>




Param (
	[Parameter(Mandatory = $true)]
	[ValidateSet("Start", "End", "Reboot")]
	[string]$EventAction
)

# Validate the log source exists, if not, create it
If (-not [System.Diagnostics.EventLog]::SourceExists("Salt Patching Orchestration")) {
	New-EventLog -LogName Application -Source "Salt Patching Orchestration"
}

# Define common parameters for Write-EventLog
$eventParams = @{
	LogName   = "Application"
	Source    = "Salt Patching Orchestration"
	EntryType = "Information"
}

# Set specific parameters based on the event action
Switch ($EventAction) {
	"Start" {
		$eventParams.EventId = 10001
		$eventParams.Message = "Salt Patching has started"
	}
	"End" {
		$eventParams.EventId = 10002
		$eventParams.Message = "Salt Patching has ended"
	}
	"Reboot" {
		$eventParams.EventId = 10003
		$eventParams.Message = "Salt Patching has initiated a reboot"
	}
}

# Write the event log with the parameters
Write-EventLog @eventParams


