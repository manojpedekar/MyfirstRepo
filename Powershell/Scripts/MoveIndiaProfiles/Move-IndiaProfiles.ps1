<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	5/17/2024 12:32 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



<#
	.SYNOPSIS
		Move user profiles out of the Resilio sync path to the new home directory location in the UK
	
	.DESCRIPTION
		Move user profiles out of the Resilio sync path to the new home directory location in the UK.
		This script will also remove the users legacy .system folder to a defined holding location
	
	.PARAMETER HomeDrive
		A description of the HomeDrive parameter.
	
	.PARAMETER NewHomeDriveRoot
		The fully qualified path to the root of the new users home folder.
		This is where the users folder will be created
	
	.PARAMETER OldProfileHoldingPen
		The fully qualified path to the folder where the backups of the users .system profile will be stored.
		A user folder will be created in this location
	
	.PARAMETER UserDomain
		Specify the FQDN of the users AD Domain
	
	.PARAMETER RootDirectory
		The fully qualified path to the root of the users home folder.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	11/15/2023 9:13 AM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:
		===========================================================================
#>
Param
(
	[Parameter(Mandatory = $true)]
	[String]$HomeDrive,
	[Parameter(Mandatory = $false)]
	[String]$NewHomeDriveRoot = 'D:\IND_Folder_Redirection_User_Data',
	[Parameter(Mandatory = $false)]
	[String]$OldProfileHoldingPen = 'D:\OldSystemProfiles',
	[String]$UserDomain = "globeop.com"
)

###########################################################
##                    Functions                          ##
###########################################################

Function Test-ACEExists {
<#
.SYNOPSIS
    Checks if an Access Control Entry (ACE) exists within an Access Control List (ACL).

.DESCRIPTION
    The Test-ACEExists function examines a given ACL to determine whether a specified ACE is already present. 
    It compares the properties of the ACE with those in the ACL to ascertain if an exact match exists.

.PARAMETER ACE
    Specifies the Access Control Entry (ACE) to check for in the ACL. This should be an object of type 
    System.Security.AccessControl.FileSystemAccessRule.

.PARAMETER ACL
    Specifies the Access Control List (ACL) in which to search for the specified ACE. 
    This should be an object of type System.Security.AccessControl.DirectorySecurity.

.EXAMPLE
    $acl = Get-Acl "C:\SomeFolder"
    $ace = New-Object System.Security.AccessControl.FileSystemAccessRule("DOMAIN\User", "Read", "Allow")
    $exists = Test-ACEExists -ACE $ace -ACL $acl
    This example checks if an ACE granting "Read" permission to "DOMAIN\User" exists in the ACL of "C:\SomeFolder".

.NOTES
    Useful for scripts that modify ACLs to avoid creating duplicate ACE entries.

#>
	
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
		$_.InheritanceFlags -eq $ACE.InheritanceFlags
	}
	
	# Return bool value represeting the existence of the ACE
	Return [bool]($aceExists)
}

Function Test-ADUserExists {
<#
	.SYNOPSIS
		Tests if a user account exists in Active Directory and checks its status.
	
	.DESCRIPTION
		This function checks for the existence of a user account in Active Directory and
		returns its status as either 'Enabled', 'Disabled', 'Missing' or 'ConnectionError'.
		It can search in the current domain or in a specified domain.
	
	.PARAMETER UserName
		The username of the user account to check. This parameter is mandatory.
	
	.PARAMETER DomainName
		The domain in which to search for the user account. If not specified, the function
		searches in the current domain. This parameter is optional.
	
	.EXAMPLE
		Test-ADUserExists -UserName "dt234083"
		Checks if the user 'dt234083' exists in the current domain and returns the account status.
	
	.EXAMPLE
		Test-ADUserExists -UserName "dt234083" -DomainName "ssnc-corp.global"
		Checks if the user 'dt234083' exists in the 'ssnc-corp.global' domain and returns the account status.
	
	.NOTES
		Requires access to System.DirectoryServices namespace.
#>
	[CmdletBinding()]
	[OutputType([string])]
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$UserName,
		[Parameter(Mandatory = $false)]
		[string]$DomainName
	)
	
	Try {
		# Prepare the root for searching
		If ($DomainName) {
			$root = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainName")
		} Else {
			# Get the current domain if no domain name is provided
			$currentDomain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
			$root = $currentDomain.GetDirectoryEntry()
		}
		
		# Set the search filter to find the user
		$searchFilter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$UserName))"
		
		# Set the properties to retrieve
		$searchProperties = @("sAMAccountName", "userAccountControl")
		
		# Search for the user in the domain
		$searcher = New-Object System.DirectoryServices.DirectorySearcher($root, $searchFilter, $searchProperties)
		$searchResult = $searcher.FindOne()
		
		# Check the result and determine the account status
		If ($searchResult) {
			$userAccountControl = $searchResult.Properties["userAccountControl"][0]
			$accountDisabled = $userAccountControl -band 2
			If ($accountDisabled) {
				Return "Disabled"
			} Else {
				Return "Enabled"
			}
		} Else {
			Return "Missing"
		}
	} Catch {
		# Handle the exception (e.g., connection failure)
		Write-Warning "Failed to connect to the domain or an error occurred: $_"
		Return "ConnectionError"
	}
}

Function New-FileSystemAccessRule {
<#
.SYNOPSIS
    Creates a new FileSystemAccessRule object with customizable parameters.

.DESCRIPTION
    The New-FileSystemAccessRule function creates a new access control entry (ACE) 
    for file system security. This function allows customization of permissions, 
    inheritance, and propagation settings.

.PARAMETER IdentityReference
    Specifies the identity to which the access rule applies, such as a user or group name.

.PARAMETER AccessRights
    Specifies the access rights, like FullControl, Modify, Read, Write, etc.

.PARAMETER InheritanceFlags
    Specifies how access rules are inherited by subfolders and files. Options are None, ContainerInherit, ObjectInherit.

.PARAMETER PropagationFlags
    Specifies how access rules are propagated to child objects. Options are None, NoPropagateInherit, InheritOnly.

.PARAMETER AccessControlType
    Specifies the type of access control. Options are Allow or Deny.

.EXAMPLE
    $ace = New-FileSystemAccessRule -IdentityReference "DOMAIN\User" -AccessRights FullControl
    This command creates a new access rule granting FullControl permissions to "DOMAIN\User".

.EXAMPLE
    $ace = New-FileSystemAccessRule -IdentityReference "User" -AccessRights Read -InheritanceFlags ContainerInherit -PropagationFlags InheritOnly -AccessControlType Allow
    This command creates a new access rule granting Read permissions to "User", with specific inheritance and propagation settings.

.NOTES
    Use this function to create a customizable access rule for file or folder ACL modification.

#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[string]$IdentityReference,
		[Parameter(Mandatory = $false)]
		[string]$AccessRights = "FullControl",
		[Parameter(Mandatory = $false)]
		[System.Security.AccessControl.InheritanceFlags]$InheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit,
		[Parameter(Mandatory = $false)]
		[System.Security.AccessControl.PropagationFlags]$PropagationFlags = [System.Security.AccessControl.PropagationFlags]::None,
		[Parameter(Mandatory = $false)]
		[System.Security.AccessControl.AccessControlType]$AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
	)
	
	# Create a new access rule with specified parameters
	$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
		$IdentityReference,
		$AccessRights,
		$InheritanceFlags,
		$PropagationFlags,
		$AccessControlType
	)
	
	# Return the access rule
	Return $accessRule
}

Function Set-FolderOwner {
<#
.SYNOPSIS
    Sets the owner of a folder to a specified domain user.

.DESCRIPTION
    This function changes the ownership of a specified folder to a given user account in a domain.

.PARAMETER FolderPath
    The path of the folder whose ownership you want to change.

.PARAMETER UserName
    The domain user name in the format 'DOMAIN\Username' who will be set as the new owner of the folder.

.EXAMPLE
    Set-FolderOwner -FolderPath "C:\TestFolder" -UserName "DOMAIN\JohnDoe"
    Sets the ownership of 'C:\TestFolder' to the user 'JohnDoe' in 'DOMAIN'.

.NOTES
    Requires administrative privileges to change folder ownership.

#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[string]$FolderPath,
		[Parameter(Mandatory = $true)]
		[string]$UserName
	)
	
	Try {
		# Get the current ACL of the folder
		$acl = Get-Acl $FolderPath
		
		# Translate the username to NTAccount
		$newOwner = New-Object System.Security.Principal.NTAccount($UserName)
		
		# Set the new owner
		$acl.SetOwner($newOwner)
		
		# Apply the new ACL to the folder
		Set-Acl -Path $FolderPath -AclObject $acl
		
		Write-Host "Ownership of the folder '$FolderPath' has been changed to '$UserName'."
	} Catch {
		Write-Error "An error occurred: $_"
	}
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

Function Ensure-DirectoryExists {
	Param (
		[string]$Path
	)
	If (-not (Test-Path -Path $Path -PathType Container)) {
		New-Item -Path $Path -ItemType Directory -Force
		Return "Created"
	} Else { Return "Exists" }
}

Function Update-ACLIfNecessary {
	Param (
		[string]$FolderPath,
		[System.Security.AccessControl.FileSystemAccessRule]$AccessRule
	)
	$acl = Get-Acl $FolderPath
	If (-not (Test-ACEExists -ACL $acl -ACE $AccessRule)) {
		$acl.AddAccessRule($AccessRule)
		Set-Acl -Path $FolderPath -AclObject $acl
	}
}


Function Process-Jobs {
<#
	.SYNOPSIS
		A brief description of the Process-Jobs function.
	
	.DESCRIPTION
		A detailed description of the Process-Jobs function.
	
	.PARAMETER LogDir
		Path to logging folder
	
	.EXAMPLE
				PS C:\> Process-Jobs
	
	.NOTES
		Additional information about the function.
#>
	
	Param
	(
		[string]$LogDir = "C:\temp\"
	)
	
	$SuccessLogPath = "$($LogDir)\SuccessLog.txt"
	$ErrorLogPath = "$($LogDir)\ErrorLog.txt"
	
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

Function RewriteMapDrives {
	Param
	(
		[string]$DriveMapScripts
	)
	$UpdatedDriveMappingScript = @()
	$sharedrivemaps = import-csv .\sharedrivemaps.csv
	# Read the contents of the drive mapping script
	$fileContent = Get-Content -Path $DriveMapScripts | Where-Object { $_ -notlike "net use z: *" }
	# Loop through each line in the file
	ForEach ($line In $fileContent) {
		# For each mapping, replace the old share with the new share in the line
		ForEach ($map In $ShareDriveMaps) {
			$line = $line.Replace($map.OldShare, $map.NewShare)
		}
		# Output the updated line (this can be redirected to a new file)
		$UpdatedDriveMappingScript += $line
	}
	Return $UpdatedDriveMappingScript
	
}

###########################################################
##                 Begin Main Script                     ##
###########################################################

$LogArguments = @{
	Message  = "Starting migration"
	Facility = 14
	Severity = 6
	Hostname = $env:COMPUTERNAME
	Appname  = $MyInvocation.MyCommand.Name
	Procid   = $PID
	Msgid    = "ID123"
	Logfile  = "C:\Temp\$(get-date -Format yyyy-MM-dd)_syslog.log"
}

$LogArguments.Message = "Starting migration for $($HomeDrive)"
Write-SyslogMessage @LogArguments

$LogArguments.Message = "Moving Home Drive to $($NewHomeDriveRoot)"
Write-SyslogMessage @LogArguments

$LogArguments.Message = "Holding pen for .System Folder $($OldProfileHoldingPen)"
Write-SyslogMessage @LogArguments

$LogArguments.Message = "User Domain $($Domain)"
Write-SyslogMessage @LogArguments


# Test if the HomeDrive folder exists, if not exit with a message
If (-not (Test-Path -Path $HomeDrive -PathType Container)) {
	$LogArguments.message = "$HomeDrive Folder does not exist.  Exiting"
	Write-Warning $LogArguments.message
	Write-SyslogMessage @LogArguments
	Exit 1
}

$Dir = Get-Item $HomeDrive

Switch (Test-ADUserExists -UserName $Dir.BaseName -DomainName globeop.com) {
	"Enabled" {
		
		#Create new home drive folder
		$folderstatus = Ensure-DirectoryExists -Path "$NewHomeDriveRoot\$($Dir.BaseName)"
		
		$LogArguments.Message = "$NewHomeDriveRoot\$($Dir.BaseName) exists = $($folderstatus)"
		Write-SyslogMessage @LogArguments
		
		# Set the folder owner so the user has permissions to the folder
		Set-FolderOwner -FolderPath "$NewHomeDriveRoot\$($Dir.BaseName)" -UserName "GLOBEOP\$($Dir.BaseName)"
		
		$LogArguments.Message = "Folder Owner set to GLOBEOP\$($Dir.BaseName)"
		Write-SyslogMessage @LogArguments
		
		# Check if the user has a .system directory to move
		If (Test-Path "$($Dir.FullName)\.system" -PathType Container) {
			# Check to see if the holding folder needs to be created	
			$folderstatus = Ensure-DirectoryExists -Path "$OldProfileHoldingPen\$($Dir.BaseName)"
			
			$LogArguments.Message = "$OldProfileHoldingPen\$($Dir.BaseName) exists = $($folderstatus)"
			Write-SyslogMessage @LogArguments
			
			#move the .system folder
			Move-Item -Path "$($Dir.FullName)\.system" -Destination "$OldProfileHoldingPen\$($Dir.BaseName)"
		}
		
		# Create the new CORP ACE and add if necessary
		$CorpACE = New-FileSystemAccessRule -IdentityReference "SSNC-CORP\$($Dir.BaseName)"
		
		Update-ACLIfNecessary -FolderPath "$NewHomeDriveRoot\$($Dir.BaseName)" -AccessRule $CorpACE
		
		# Create the new GlobeOp ACE and add if necessary
		$GlobeOpACE = New-FileSystemAccessRule -IdentityReference "Globeop\$($Dir.BaseName)"
		
		Update-ACLIfNecessary -FolderPath "$NewHomeDriveRoot\$($Dir.BaseName)" -AccessRule $GlobeOpACE
		
		# move remaining files to new home drive
		Move-Item -Path "$($Dir.FullName)\*" -Destination "$NewHomeDriveRoot\$($Dir.BaseName)" -Force
		
		# Update inheritance for all items in the new destination as a background task
		$job = Start-Job -ScriptBlock {
			Param ($DirectoryPath)
			
			# Ensure the path exists
			If (-not (Test-Path $DirectoryPath)) {
				Write-Error "Path does not exist: $DirectoryPath"
				Return
			}
			
			# Get the ACL of the parent folder
			$parentAcl = Get-Acl -Path $DirectoryPath
			
			# Apply the ACL to all child items
			Get-ChildItem -Path $DirectoryPath -Recurse | ForEach-Object {
				Try {
					# Set the ACL on the item, replacing any existing ACLs
					Set-Acl -Path $_.FullName -AclObject $parentAcl
					Write-Host "Successfully reset ACLs for $($_.FullName)"
				} Catch {
					Write-Error "Failed to set ACL for $($_.FullName): $_"
				}
			}
			
			Write-Host "Inheritance set for all items in $DirectoryPath"
			
		} -ArgumentList "$NewHomeDriveRoot\$($Dir.BaseName)" -Name $Dir.BaseName
		
		#copy the readmen to the desktop
		Copy-Item C:\Software\README.url "$NewHomeDriveRoot\$($Dir.BaseName)\Desktop\"
		
		
		# Test whether map drive script exist
		If (Test-path -path "$NewHomeDriveRoot\$($Dir.BaseName)\remapDrives.cmd") {
			$NewDrivemappings = RewriteMapDrives -DriveMapScripts "$NewHomeDriveRoot\$($Dir.BaseName)\remapDrives.cmd"
			$NewDrivemappings | out-string | Set-Content -Path "$NewHomeDriveRoot\$($Dir.BaseName)\Desktop\UK-remapDrives.cmd"
		}
		
		#Remove-item -path $dir.fullname -recurse
		Move-Item -Path $dir.FullName -Destination "D:\MigrationScriptIssues\Completed\$($Dir.BaseName)"
	}
	"Disabled"  {
		# Decide action to take on these accounts
		Move-Item -Path $dir.FullName -Destination "D:\MigrationScriptIssues\Disabled\$($Dir.BaseName)"
		$LogArguments.message = "$HomeDrive account is disabled.  Exiting"
		Write-Warning $LogArguments.message
		Write-SyslogMessage @LogArguments
	}
	"Missing"  {
		$LogArguments.message = "The user id $($Dir.BaseName) was not found in the directory"
		Move-Item -Path $dir.FullName -Destination "D:\MigrationScriptIssues\Missing\$($Dir.BaseName)"
		Write-Warning $LogArguments.message
		Write-SyslogMessage @LogArguments
	}
	"ConnectionError" {
		$LogArguments.message = "The AD Domiain is not available.  No Action taken on folder $($Dir.FullName)"
		Write-Warning $LogArguments.message
		Write-SyslogMessage @LogArguments
	}
	Default {
		# This is the default condition for the switch statment and would 
	}
}





