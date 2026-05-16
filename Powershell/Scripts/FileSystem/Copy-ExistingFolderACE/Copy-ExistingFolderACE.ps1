<#
	.SYNOPSIS
		This script will duplicate an existing ACE using a new TargetID.
	
	.DESCRIPTION
		This script will duplicate an existing ACE using a new TargetID.  The script will evaluate all sub directories starting at the RootFolder for the source ID.  Where it is found, a new ACE will be added to the folder ACLs.
			
	.PARAMETER TargetID
		Specify the ID to be used in the duplicated ACE.  This should be in the form of DOMAIN\DomainLocalGroup
		
		TargetGroup should be in the local domain only
	
	.PARAMETER SourceID
		Specify the Source ID to duplicate.  This should be in the form of DOMAIN\Group.
		
		This value will be found on the IdentityRefrence attribute on an existing ACE
	
	.PARAMETER RootFolder
		Specify the root folder where the permissions are to be updated.  All sub folders will be evaluated.
	
	.PARAMETER SNOWTicket
		Enter the SNOW Ticket Number that will cover this permission change.  This ticket number will be used as the event log name and can be attached to the SNOW ticket as evidence.

		The event log file will be saved in the same directory as the script in the following format: RITM0123456_yyyyMMdd-HHmmss.log
	
	.PARAMETER BypassADCheck
		Use this switch to override the validation of the target group in AD.  This will allow the script to run when the execution context does not have access to query Active Directory
	
	.EXAMPLE
		PS C:\> .\Copy-ExistingFolderACE -TargetID 'Value1' -SourceID 'Value2' -RootFolder 'Value3' -SNOWTicket RITM123456
	
	.NOTES
		Version: $($scriptVersion)
		Date: $(Get-Date)

#>
$scriptVersion = "2.1.0"

Param
(
	[Parameter(Mandatory = $true)]
	[String]$TargetID,
	[Parameter(Mandatory = $true)]
	[String]$SourceID,
	[Parameter(Mandatory = $true)]
	[string]$RootFolder,
	[Parameter(Mandatory = $true)]
	[String]$SNOWTicket,
	[switch]$BypassADCheck
)


###########################################################
##                    Functions                          ##
###########################################################

Function Test-ADGroupExists {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[string]$GroupName
	)
	
	# Get the current domain
	$domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
	
	# Get the root of the domain
	$root = $domain.GetDirectoryEntry()
	
	# Set the search filter to find the group
	$searchFilter = "(&(objectCategory=group)(cn=$GroupName))"
	
	# Set the properties to retrieve
	$searchProperties = @("cn")
	
	# Search for the group in the domain
	$searcher = New-Object System.DirectoryServices.DirectorySearcher($root, $searchFilter, $searchProperties)
	$searchResult = $searcher.FindOne()
	
	# If the search result is not null, the group exists, otherwise it does not
	If ($searchResult) {
		Return $true
	} Else {
		Return $false
	}
}

Function Test-DomainGroupFormat {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[string]$InputString
	)
	
	# Split the input string into domain and group name components
	$domain, $group = $InputString -split '\\'
	
	# Check that both domain and group name are non-empty
	If (-not $domain -or -not $group) {
		Return $false
	}
	
	# Check that the domain name is a valid DNS name
	$dnsRegex = "^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$"
	If (-not ($domain -match $dnsRegex)) {
		Return $false
	}
	
	# Check that the group name contains only alphanumeric characters and certain special characters
	$groupRegex = "^[a-zA-Z0-9][a-zA-Z0-9_\-\$\.\(\) ]*$"
	If (-not ($group -match $groupRegex)) {
		Return $false
	}
	
	Return $true
}

Function Test-ACEExists {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[System.Security.AccessControl.FileSystemAccessRule]$ACE,
		[Parameter(Mandatory = $true)]
		[System.Security.AccessControl.DirectorySecurity]$ACL
	)
	
	# Check if the ACE already exists in the ACL
	$aceExists = $ACL.Access | Where-Object {
		$_.IdentityReference -eq $ACE.IdentityReference -and
		$_.FileSystemRights -eq $ACE.FileSystemRights -and
		$_.AccessControlType -eq $ACE.AccessControlType -and
		$_.InheritanceFlags	-eq $ACE.InheritanceFlags
	}
	
	# Return bool value represeting the existence of the ACE
	Return [bool]($aceExists)
}

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

Function Update-FolderOwnerToAdmin {
	
	<#
	.SYNOPSIS
		This will set the owner of a folder to the local Administrators group
	
	.DESCRIPTION
		A detailed description of the Update-FolderOwnerToAdmin function.
	
	.PARAMETER FolderPath
		A description of the FolderPath parameter.
	
	.EXAMPLE
		PS C:\> Update-FolderOwnerToAdmin
	
	.NOTES
		Additional information about the function.
	#>
	
	[CmdletBinding()]
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$FolderPath
	)
	
	$Results = [PSCustomObject]@{
		Updated = $null
		Message = $null
	}
	
	Try {
		# Check if the folder exists
		If (!(Test-Path $folderPath)) {
			$Results.Updated = $false
			$Results.Message = "Folder does not exist."
			return $Results
		}
		
		$acl = Get-Acl $folderPath
		$NewOwner = New-Object -TypeName System.Security.Principal.NTAccount -ArgumentList 'BUILTIN\Administrators'
		$acl.SetOwner($NewOwner)
		Set-Acl $folderPath $acl
		$Results.Updated = $true
		$Results.Message = "Owner of folder '$folderPath' changed to the local Administrators group."
	} Catch {
		$Results.Updated = $false
		$Results.Message = "Error: $_"
	}
	return $Results
}

Function Test-FolderOwner {
	Param (
		[Parameter(Mandatory = $true)]
		[string]$FolderPath
	)
	
	$Results = [PSCustomObject]@{
		Allowed = $null
		Message = $null
	}
	
	# Get the current owner of the folder
	$Folder = Get-Item $FolderPath
	$currentOwner = $folder.GetAccessControl().Owner
	
	# Check if the current owner is allowed to be the owner
	$acl = Get-Acl $FolderPath
	ForEach ($ace In $acl.Access) {
		If (($ace.IdentityReference -eq $currentOwner) -and ($ace.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::TakeOwnership)) {
			$Results.Message = "The current owner $currentOwner is allowed to be the owner of $FolderPath."
			$Results.Allowed = $true
			Return $Results
		}
	}
	
	# If the current owner and the security identifier are not allowed to be the owner
	$Results.Message = "The current owner $currentOwner is allowed to be the owner of $FolderPath."
	$Results.Allowed = $false
	Return $Results
}

###########################################################
##                 Begin Main Script                     ##
###########################################################

# Create a variable to store the updated Folder Count and errors
$UpdatedFolderCount = 0
$FolderErrors = 0

#Setup Log Properties
$LogArguments = @{
	Message  = ""
	Facility = 14
	Severity = 6
	Hostname = $env:COMPUTERNAME
	Appname  = $MyInvocation.MyCommand.Name
	Procid   = $PID
	Msgid    = "0"
	Logfile  = Join-Path (Split-Path $MyInvocation.MyCommand.Path) ($SNOWTicket + "_" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
}

# Define the scriptblock to be used to apply the new ACL
$ApplyACLScriptBlock = {
	Param (
		[Parameter(Mandatory = $true)]
		[String]$Folder,
		[Parameter(Mandatory = $true)]
		[System.Security.AccessControl.DirectorySecurity]$ACL
	)
	Set-Acl -Path $Folder -AclObject $ACL
}

# Log the script parameters
$LogArguments.Message = "Script Parameters - ["
ForEach ($key In $PSBoundParameters.Keys) {
	$value = $PSBoundParameters[$key]
	$LogArguments.Message += "$key=$value;"
}
$LogArguments.Message = $LogArguments.Message.TrimEnd(";")
$LogArguments.Message += "]"
Write-SyslogMessage @LogArguments

# Check the powershell version.
# The directory command requires a minimum of version 3.0
If ($PSVersionTable.PSVersion.Major -lt 3) {
	$LogArguments.Message = "This script requires PowerShell version 3.0 or later.  Exiting Script!"
	$LogArguments.Severity = 3
	Write-SyslogMessage @LogArguments
	Write-Host $LogArguments.Message
	Exit 1
}

# Validate the TargetPath folder exists
If (-not (Test-Path $RootFolder)) {
	$LogArguments.Message = "The path $RootFolder does not exist.  Exiting Script!"
	$LogArguments.Severity = 3
	Write-SyslogMessage @LogArguments
	Write-Host $LogArguments.Message
	Exit 1
}

# Validate SourceID format
If (-not (Test-DomainGroupFormat $SourceID)) {
	$LogArguments.Message = "The SourceID $SourceID is not in the correct format.  Exiting Script!"
	$LogArguments.Severity = 3
	Write-SyslogMessage @LogArguments
	Write-Host $LogArguments.Message
	Exit 1
}

# Validate TargetID format
If (-not (Test-DomainGroupFormat $TargetID)) {
	$LogArguments.Message = "The TargetID $TargetID is not in the correct format.  Exiting Script!"
	$LogArguments.Severity = 3
	Write-SyslogMessage @LogArguments
	Write-Host $LogArguments.Message
	Exit 1
}

# Validate the TargetID Exists in AD.  This is to ensure we do not creat junk Access Control Entries
If (-not (Test-ADGroupExists -GroupName $TargetID) -and $BypassADCheck) {
	$LogArguments.Message = "The TargetID $TargetID could not be found in AD.  Exiting Script!"
	$LogArguments.Severity = 3
	Write-SyslogMessage @LogArguments
	Write-Host $LogArguments.Message
	Exit
}

$LogArguments.Message = "Retriving directory list for $RootFolder"
$LogArguments.Severity = 6
Write-SyslogMessage @LogArguments

# Get a list of all the folders in the RootFolder
$FolderList = Get-ChildItem -Directory -Path $RootFolder -Recurse -Force -ErrorAction SilentlyContinue

$LogArguments.Severity = 6
$LogArguments.Message = "Identified $($FolderList.Count) folders for ACL check"
Write-SyslogMessage @LogArguments

$LogArguments.Message = "Checking directory access in $RootFolder subdirectories"
$LogArguments.Severity = 6
Write-SyslogMessage @LogArguments

$LogArguments.Message = "Starting ACL check on $RootFolder subdirectories"
Write-SyslogMessage @LogArguments

ForEach ($Folder In $FolderList) {
	
	# Set the update flag to false
	$ApplyACL = $false
	
	Try {
		[System.IO.Directory]::GetDirectories($Folder.FullName) | Out-Null
	} Catch [System.UnauthorizedAccessException] {
		$FolderErrors++
		$LogArguments.Message = "UnauthorizedAccessException error on folder $($Folder.FullName). Not all folder ACLs evaluated"
		$LogArguments.Severity = 3
		Write-SyslogMessage @LogArguments
	}
	
	# Get the ACL on the folder
	$Acl = Get-Acl -Path $Folder.FullName
	
	$NonInheritedAceList = $Acl.Access | Where-Object { $_.IsInherited -eq $false }
	
	# Loop through all the ACEs in the ACL
	ForEach ($ACE In $Acl.Access) {
		
		# Determine if we have the found the ACE that we want to duplicate
		# The ACE needs to be explictly set on the folder and not Inherited
		If ($ACE.IsInherited -eq $false -and $ACE.IdentityReference -eq $SourceID) {
			
			$LogArguments.Severity = 6
			$LogArguments.Message = "Identified $SourceID ACE on $($Folder.FullName), Creating Duplicate ACE using $TargetID"
			Write-SyslogMessage @LogArguments
			
			$PermHash = @{
				inheritance = $ACE.InheritanceFlags
				type	    = $ACE.AccessControlType
				propagation = $ACE.PropagationFlags
				rights	    = $ACE.FileSystemRights
				identity    = $TargetID
			}
			
			$TargetACE = New-Object System.Security.AccessControl.FileSystemAccessRule($PermHash.identity, $PermHash.rights, $PermHash.inheritance, $PermHash.propagation, $PermHash.type)
						
			# Check to see if the new ACE already exists.  If not lets add it to the ACL
			If (-not (Test-ACEExists -ACE $TargetACE -ACL $Acl)) {
				
				# Increment the folder counter to provide status at the end of the script
				$UpdatedFolderCount++
				
				$LogArguments.Severity = 6
				$LogArguments.Message = "Adding $TargetID to $($Folder.FullName) ACL"
				Write-SyslogMessage @LogArguments
				
				# Log the new ACE
				$LogArguments.Message = "New ACE Properties - ["
				ForEach ($key In $PermHash.Keys) {
					$LogArguments.Message += "$key=$($PermHash[$key]);"
				}
				$LogArguments.Message = $LogArguments.Message.TrimEnd(";")
				$LogArguments.Message += "]"
				Write-SyslogMessage @LogArguments
				
				# Add the new ACE to the ACL
				$Acl.AddAccessRule($TargetACE)
				
				# Set the Update flag 
				$ApplyACL = $True
			}
			
			If (Test-ACEExists -ACE $TargetACE -ACL $Acl) {
				$LogArguments.Severity = 5
				$LogArguments.Message = "ACE for $TargetID on $($Folder.FullName) ACL already exitsts"
				Write-SyslogMessage @LogArguments
				$ApplyACL = $false
			}
			
		}
	}
	
	# Check to see if we need to apply the updated ACL
	If ($ApplyACL) {
		
		#test to see if the owner is valid.  There have been issues with folders not inheriting permissions with invalid owners
		$OwnerTest = Test-FolderOwner $Folder.FullName
		
		If ($OwnerTest.Allowed -eq $false) {
			$LogArguments.Message = $OwnerTest.Message
			$LogArguments.Severity = 4
			Write-SyslogMessage @LogArguments
			
			$NewOwner = New-Object -TypeName System.Security.Principal.NTAccount -ArgumentList 'BUILTIN\Administrators'
			$Acl.SetOwner($NewOwner)
		}
		
		# Define the job name for the Start-Job command
		$JobName = $Folder.FullName.replace("\", "").replace(":", "")
		
		$LogArguments.Severity = 6
		$LogArguments.Message = "Applying updated ACL.  Starting Job $JobName"
		Write-SyslogMessage @LogArguments
		
		# This command will apply the new ACL to the folder in the background and move on to the next folder
		Start-Job -ArgumentList $Folder.FullName, $ACL -ScriptBlock $ApplyACLScriptBlock -Name $JobName
	}
}

# Log $UpdatedFolderCount
$LogArguments.Severity = 6
$LogArguments.Message = "Folder with updated ACLs = $UpdatedFolderCount"
Write-SyslogMessage @LogArguments

If ($FolderErrors -gt 0) {
	$LogArguments.Severity = 6
	$LogArguments.Message = "Identified $FolderErrors folders with access errors.  Use alternate credentials to evaluate permissions"
	Write-SyslogMessage @LogArguments
}
