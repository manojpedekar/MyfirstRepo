<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	5/1/2024 7:47 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



Function Get-WindowsUpdateInitiator {
	# Define the event IDs that indicate the start of an update process
	$updateEventIds = @(19, 20, 21) # These event IDs might need to be adjusted
	
	# Prepare a hashtable for filtering events directly in the Get-WinEvent call
	$filterHashtable = @{
		LogName = "System"
		ID	    = $updateEventIds
		ProviderName = "Microsoft-Windows-WindowsUpdateClient"
	}
	
	# Query the event log using the filter hashtable for efficiency
	$events = Get-WinEvent -FilterHashtable $filterHashtable
	
	# Extract and display the relevant information
	$events | ForEach-Object {
		$eventXml = [xml]($_.ToXml())
		$properties = $eventXml.Event.EventData.Data
		$initiator = $properties | Where-Object { $_.Name -eq "UserID" } | Select-Object -ExpandProperty '#text'
		$initiatorName = (New-Object System.Security.Principal.SecurityIdentifier($initiator)).Translate([System.Security.Principal.NTAccount])
		
		[pscustomobject]@{
			TimeCreated = $_.TimeCreated
			EventID	    = $_.Id
			Initiator   = $initiatorName.Value
		}
	}
}


Function Get-InteractiveLogonEvents {
	Param (
		[Parameter(Mandatory = $true)]
		[datetime]$Date
	)
	
	# Convert the input date to the correct format to compare in the filter
	$dateStart = $Date.Date
	$dateEnd = $Date.Date.AddDays(1)
	
	# Prepare a hashtable for filtering events
	$filterHashtable = @{
		LogName   = "Security"
		ID	      = 4624
		StartTime = $dateStart
		EndTime   = $dateEnd
	}
	
	# Query the event log using the filter hashtable
	$events = Get-WinEvent -FilterHashtable $filterHashtable
	
	# Filter for interactive logons (Logon Type 2)
	$events | Where-Object {
		$eventXml = [xml]$_.ToXml()
		$logonType = $eventXml.Event.EventData.Data | Where-Object { $_.Name -eq "LogonType" } | Select-Object -ExpandProperty '#text'
		$logonType -eq 2
	} | ForEach-Object {
		$eventXml = [xml]$_.ToXml()
		$targetUser = $eventXml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetUserName" } | Select-Object -ExpandProperty '#text'
		$targetDomain = $eventXml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetDomainName" } | Select-Object -ExpandProperty '#text'
		$logonId = $eventXml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetLogonId" } | Select-Object -ExpandProperty '#text'
		
		[pscustomobject]@{
			TimeCreated = $_.TimeCreated
			TargetUserName = $targetUser
			TargetDomainName = $targetDomain
			LogonId	    = $logonId
		}
	}
}

# Example usage: Get interactive logon events for May 5, 2023
Get-InteractiveLogonEvents -Date '2023-05-05'
