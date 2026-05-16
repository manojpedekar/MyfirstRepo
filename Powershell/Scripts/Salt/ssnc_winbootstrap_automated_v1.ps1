<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	7/12/2023 4:51 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	ssnc_winbootstrap_automated_v1.ps1
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



#===============================================================================
# Script Functions
#===============================================================================

Function Write-SyslogMessage {
	<#
	.SYNOPSIS
		Write a RFC 5424 Standardized syslog message to file
	
	.DESCRIPTION
		Write a RFC 5424 Standardized syslog message to file
	
	.PARAMETER Message
		The message to be logged
	
	.PARAMETER Facility
		In the Syslog protocol, the facility is used to indicate the subsystem that generated the log message.
		The facility value is a single digit number from 0 to 23 that is encoded in the message header.
		The standard facility values defined in the Syslog protocol are:
		
		0: kernel messages
		1: user-level messages
		2: mail system
		3: system daemons
		4: security/authorization messages
		5: messages generated internally by syslogd
		6: line printer subsystem
		7: network news subsystem
		8: UUCP subsystem
		9: clock daemon
		10: security/authorization messages
		11: FTP daemon
		12: NTP subsystem
		13: log audit
		14: log alert
		15: clock daemon (note: deprecated)
		16: local use 0 (local0)
		17: local use 1 (local1)
		18: local use 2 (local2)
		19: local use 3 (local3)
		20: local use 4 (local4)
		21: local use 5 (local5)
		22: local use 6 (local6)
		23: local use 7 (local7)
	
	.PARAMETER Severity
		The severity level is used to indicate the importance of the log message.
		The severity is a single digit number from 0 to 7 that is encoded in the message header.
		The standard severity values defined in the Syslog protocol are:
		
		0: Emergency: system is unusable
		1: Alert: action must be taken immediately
		2: Critical: critical conditions
		3: Error: error conditions
		4: Warning: warning conditions
		5: Notice: normal but significant condition
		6: Informational: informational messages
		7: Debug: debug-level messages
	
	.PARAMETER Hostname
		Name of the device or system generating the log message
	
	.PARAMETER Appname
		Name of the application or process that is generating the log message
	
	.PARAMETER Procid
		The ID of the process or application that generated the log message.
		This can be any text string that identifies the process or application that generated the message.
		The Procid parameter is optional, but can be useful in identifying the source of the message and grouping related messages together.
	
	.PARAMETER Msgid
		A unique identifier for the message.
		This can be any text string that uniquely identifies the message, such as a reference number or error code.
		The Msgid parameter is optional, but can be useful in tracking and identifying specific messages.
	
	.PARAMETER Logfile
		Fully qualified path to the log file
	
	.EXAMPLE
		PS C:\> Write-SyslogMessage -Message "This is an example Syslog message" -Facility 14 -Severity 6 -Hostname $env:COMPUTERNAME -Appname "MyApplication" -Procid 12345 -Msgid "ID123" -Logfile "C:\Syslog\syslog.log"
	
	.EXAMPLE
		This example uses Splatting to provide the function parameters
		
		$LogArguments = @{
		Message  = "This is a test message"
		Facility = 14
		Severity = 6
		Hostname = $env:COMPUTERNAME
		Appname  = $MyInvocation.MyCommand.Name
		Procid   = $PID
		Msgid    = "ID123"
		Logfile  = "C:\Temp\syslog.log"
		}
		
		Write-SyslogMessage @LogArguments
	
	.NOTES
		Additional information about the function.
	#>
	
	[CmdletBinding()]
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$Message,
		[Parameter(Mandatory = $true)]
		[int]$Facility,
		[Parameter(Mandatory = $true)]
		[int]$Severity,
		[Parameter(Mandatory = $true)]
		[string]$Hostname,
		[Parameter(Mandatory = $true)]
		[string]$Appname,
		[Parameter(Mandatory = $true)]
		[string]$Procid,
		[Parameter(Mandatory = $true)]
		[string]$Msgid,
		[Parameter(Mandatory = $true)]
		[string]$Logfile
	)
	
	# Calculate the combined value of the facility and severity levels
	$combinedValue = [int]($Facility * 8 + $Severity)
	
	# Get the current date and time in the format required by syslog
	$timestamp = [DateTime]::UtcNow.ToString("o")
	
	# Construct the message in the syslog format
	$syslogMessage = "<$combinedValue>1 $timestamp $Hostname $Appname $Procid $Msgid - $Message"
	
	# Write the message to the syslog file
	Add-Content $Logfile $syslogMessage
}

Function Get-IsAdministrator {
	$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
	$Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
	$Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

Function Get-IsUacEnabled {
	(Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System).EnableLua -ne 0
}



#===============================================================================
# Check for Elevated Privileges
#===============================================================================
If (!(Get-IsAdministrator)) {
	If (Get-IsUacEnabled) {
		# We are not running "as Administrator" - so relaunch as administrator
		# Create a new process object that starts PowerShell
		$newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
		
		# Specify the current script path and name as a parameter`
		$parameters = ""
		ForEach ($boundParam In $PSBoundParameters.GetEnumerator()) {
			$parameters = "$parameters -{0} '{1}'" -f $boundParam.Key, $boundParam.Value
		}
		$newProcess.Arguments = $myInvocation.MyCommand.Definition, $parameters
		
		# Specify the current working directory
		$newProcess.WorkingDirectory = "$script_path"
		
		# Indicate that the process should be elevated
		$newProcess.Verb = "runas";
		
		# Start the new process
		[System.Diagnostics.Process]::Start($newProcess);
		
		# Exit from the current, unelevated, process
		Exit
	} Else {
		Throw "You must be administrator to run this script"
	}
}