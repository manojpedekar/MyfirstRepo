<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	10/31/2023 11:48 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Get-LogonEvents
	===========================================================================
	.DESCRIPTION
		Searches event logs for logon events for the past 7 days
#>


<# 
Define the logon event IDs
	4624: An account was successfully logged on.
	4625: An account failed to log on.
	4627: Group membership information.
	4634: An account was logged off.
	4647: User initiated logoff.
	4648: A logon was attempted using explicit credentials.
	4672: Special privileges assigned to new logon.
	4675: SIDs were filtered.
	4800: The workstation was locked.
	4801: The workstation was unlocked.
	4802: The screen saver was invoked.
	4803: The screen saver was dismissed.
	5378: The requested credentials delegation was disallowed by policy.
	540: Successful Network Logon (pre-Windows Vista and Windows Server 2008).
	528: Successful Logon (pre-Windows Vista and Windows Server 2008).
	538: User Logoff (pre-Windows Vista and Windows Server 2008).
	551: User initiated logoff (pre-Windows Vista and Windows Server 2008).
#>
$logonEventIDs = "4624", "4625"

<# 
Define the logon types
	Interactive (2): This logon type occurs when a user logs on at the console of a machine, i.e., at the keyboard and screen.
	Network (3): This logon type occurs when a user (or computer) accesses a remote computer over the network. For example, accessing shared folders or printers.
	Batch (4): This logon type is used when a batch job (scheduled task) is run.
	Service (5): Services use this logon type when they log on.
	Proxy (6): This is used for proxy logons.
	Unlock (7): This logon type occurs when a user unlocks their locked session.
	NetworkCleartext (8): This logon type allows the user to log on with a cleartext password. The password is sent to the machine where this logon is initiated, but not across the network.
	NewCredentials (9): This logon type is used when a process uses the LogonUser function to log on a user and specifies the LOGON32_LOGON_NEW_CREDENTIALS flag. It's similar to a network logon but the credentials are used to run the process on this machine.
	RemoteInteractive (10): This logon type occurs when a user logs on to a terminal server session from over the network. Examples include Remote Desktop, Terminal Server, and Remote Assistance.
	CachedInteractive (11): This logon type occurs when a user logs on to a machine with their cached domain credentials.
	CachedRemoteInteractive (12): This logon type occurs when a user logs on to a terminal server session from over the network with their cached domain credentials.
	CachedUnlock (13): This logon type occurs when a user unlocks their locked session with their cached domain credentials.
#>
$logonTypes = "2", "10"

# Get the current date and time
$currentDate = Get-Date

# Define the time span of how far back you want to search (e.g., 7 days)
$timeSpan = New-TimeSpan -Days 7

# Calculate the start date and time for the event log search
$startDate = $currentDate - $timeSpan

# Search the Security event log for logon events
Get-WinEvent -FilterHashtable @{
	LogName   = 'Security'
	ID	      = $logonEventIDs
	StartTime = $startDate
} | Where-Object {
	# Convert the event to XML
	$eventXml = [xml]($_.ToXml())
	
	# Extract the logon type
	$logonType = $eventXml.Event.System.EventData.Data | Where-Object { $_.Name -eq 'LogonType' } | Select-Object -ExpandProperty '#text'
	
	# Filter for the defined logon types
	$logonTypes -contains $logonType
} | ForEach-Object {
	# Convert the event to XML
	$eventXml = [xml]($_.ToXml())
	
	# Extract relevant information
	$userSid = $eventXml.Event.System.EventData.Data | Where-Object { $_.Name -eq 'TargetUserSid' } | Select-Object -ExpandProperty '#text'
	$userName = $eventXml.Event.System.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' } | Select-Object -ExpandProperty '#text'
	$logonType = $eventXml.Event.System.EventData.Data | Where-Object { $_.Name -eq 'LogonType' } | Select-Object -ExpandProperty '#text'
	$sourceIP = $eventXml.Event.System.EventData.Data | Where-Object { $_.Name -eq 'IpAddress' } | Select-Object -ExpandProperty '#text'
	$sourcePort = $eventXml.Event.System.EventData.Data | Where-Object { $_.Name -eq 'IpPort' } | Select-Object -ExpandProperty '#text'
	
	# Output the results
	[PSCustomObject]@{
		TimeCreated = $_.TimeCreated
		UserName    = $userName
		UserSID	    = $userSid
		LogonType   = Switch ($logonType) {
			"2" { "Interactive" }
			"10" { "RemoteInteractive (RDP)" }
			Default { $logonType }
		}
		SourceIP    = $sourceIP
		SourcePort  = $sourcePort
		EventID	    = $_.Id
	}
} | Format-Table -AutoSize
