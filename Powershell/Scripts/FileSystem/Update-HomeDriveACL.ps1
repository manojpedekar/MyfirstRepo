<#
	.SYNOPSIS
		This script will update the ACL's on a users home drive with the same account name from another domain..
	
	.DESCRIPTION
		This script will attempt to update the ACL's on a users home drive with the same account name from another domain.
		
		This script assumes the users home drive folder name is the same as the users SamAccountName
	
	.PARAMETER TargetFolder
		Specify the root home folder.
	
	.PARAMETER SourceDomain
		Specify the FQDN source domain name.
	
	.PARAMETER TargetDomain
		Specify the FQDN target domain name.
	
	.PARAMETER SNOWTicket
		A description of the SNOWTicket parameter.
	
	.PARAMETER AllFolders
		All home drive folders in the TargetFolder location will be processed. If not used, the ACLs on only the target folder will be processed
	
	.PARAMETER AdminCreds
		A description of the AdminCreds parameter.
	
	.EXAMPLE
		Update-HomeDriveACLs.ps1 -TargetFolder E:\Data\HomeDirs -SourceDomain ad.dstsystems.com -TargetDomain ssnc-corp.global -AllFolders
		
		This will process all the directories in the folder E:\Data\HomeDirs
	
	.EXAMPLE
		Update-HomeDriveACLs.ps1 -TargetFolder E:\Data\HomeDirs\dt234083 -SourceDomain ad.dstsystems.com -TargetDomain ssnc-corp.global
		
		This will process only the folder E:\Data\HomeDirs\dt234083
	
	.OUTPUTS
		This script will return an event log of the activities.  The event log will detal Updates, and user search results.
		
		The output can be used to identify home drive folders that should be deleted.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	2/10/2023 12:38 PM
		Updateed on:    2/17/2023 14:40 PM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:     	Update-HomeDriveACLs.ps1
		Version:        1.1
		===========================================================================
#>
Param
(
	[Parameter(Mandatory = $true)]
	[String]$TargetFolder,
	[String]$SourceDomain,
	[Parameter(Mandatory = $true)]
	[String]$TargetDomain,
	[Parameter(Mandatory = $true)]
	[String]$SNOWTicket,
	[Switch]$AllFolders,
	[Parameter(Mandatory = $true)]
	[pscredential]$AdminCreds
)

#Requires -Modules ActiveDirectory

<#
TODO:

Add a progress bar when using all users
Update logging so that all events are written to disk as they are generated

#>



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

Function Add-LogMessage {
	Param
	(
		[Parameter(Mandatory = $true)]
		[psobject]$MemberObject
	)
	
	# This was an ordered dictionary list, however the [ordered] accelerator requires PS 3.0
	# To Support the lowest version of PS, we need to remove the ordered dictionary list option
	$props = @{
		'DateTime'	   = Get-Date (Get-Date).ToUniversalTime() -format s;
		'Server'	   = $ENV:COMPUTERNAME;
		'SourceDomain' = $MemberObject.SourceDomain;
		'SourceNetBIOS' = $MemberObject.SourceNetBIOS;
		'TargetDomain' = $MemberObject.TargetDomain;
		'TargetNetBIOS' = $MemberObject.TargetNetBIOS;
		'Step'		   = $MemberObject.Step;
		'Message'	   = $MemberObject.Message;
		'UserID'	   = $MemberObject.UserID;
		'Folder'	   = $MemberObject.Folder;
	}
	
	# We will force order on the properties with a select statement 
	$obj = New-Object -TypeName PSObject -Property $props | Select-Object DateTime, Server, UserID, Folder, SourceDomain, SourceNetBIOS, TargetDomain, TargetNetBIOS, Step, Message
	
	Return $obj
}

Function Test-DomainCredentials {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true, Position = 0)]
		[System.Management.Automation.PSCredential]$Credential
	)
	
	Try {
		$de = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$($Credential.GetNetworkCredential().Domain)", $Credential.UserName, $Credential.GetNetworkCredential().Password)
		$ds = New-Object System.DirectoryServices.DirectorySearcher($de)
		$ds.Filter = "(samAccountName=$($Credential.GetNetworkCredential().UserName))"
		$result = $ds.FindOne()
		If ($result -ne $null) {
			#Write-Output "Credentials are valid."
			Return $true
		} Else {
			#Write-Output "Credentials are invalid."
			Return $false
		}
	} Catch {
		#Write-Output "An error occurred while validating credentials: $_"
		Return $false
	}
}


###########################################################
##                 Begin Main Script                     ##
###########################################################

# Setup Vars
$EventLog = [System.Collections.ArrayList]@()
$i = 0

$Logfile  = Join-Path (Split-Path $MyInvocation.MyCommand.Path) ($SNOWTicket + "_" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".csv")

$LogMessage = New-Object psobject -Property @{
	SourceDomain  = $SourceDomain
	SourceNetBIOS = $null
	TargetDomain  = $TargetDomain
	TargetNetBIOS = $null
	Step		  = $null
	Message	      = $null
	UserID	      = $null
	Folder	      = $null
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

$TargetDomainArgs = @{
	Server	   = $TargetDomain
	Credential = $AdminCreds
}

$SourceDomainArgs = @{
	Server	   = $SourceDomain
	Credential = $AdminCreds
}

If (-not (Test-Path $TargetFolder)) {
	Write-Host "Target Folder $TargetFolder does not exist!"
	Exit 1
}

# Lookup the source domian to get the domain data
# Need to put logging in place and catch if we can not communicate with the domain
Try {
	$LogMessage.Step = "Source Domain Lookup"
	$SourceADDomain = Get-ADDomain @SourceDomainArgs
	$SourceNetBIOS = $SourceADDomain.NetBIOSName
	$LogMessage.SourceNetBIOS = $SourceNetBIOS
} Catch {
	# Catch all other exceptions thrown by one of those commands
	$LogMessage.Message = "Cound not access the source domain data"
	[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
}

# Lookup the target domian to get the domain data
# Need to put logging in place and catch if we can not communicate with the domain
Try {
	$LogMessage.Step = "Target Domain Lookup"
	$TargetADDomain = Get-ADDomain @TargetDomainArgs
	$TargetNetBIOS = $TargetADDomain.NetBIOSName
	$LogMessage.TargetNetBIOS = $TargetNetBIOS
} Catch {
	# Catch all other exceptions thrown by one of those commands
	$LogMessage.Message = "Cound not access the target domain data"
	[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
}

$LogMessage.Step = "Retrieving Directory Information"
$LogMessage.Message = "Reading $TargetFolder, AllFolders switch = $($AllFolders)"
[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))

If ($AllFolders) {
	# Get a list of the directories in the specified home drive location
	$HomeDriveFolders = Get-ChildItem -Directory $TargetFolder
} Else {
	$HomeDriveFolders = Get-Item -Path $TargetFolder
}

$LogMessage.Message = "Folder Count = $($HomeDriveFolders.Count)"
[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))

# Loop through the folders to try and determine new ACLs and Update if needed
ForEach ($HomeDriveFolder In $HomeDriveFolders) {
	
	#Setup User Specific Vars
	$ApplyNewACL= $false
	$LogMessage.Step = "Folder Processing"
	$LogMessage.Folder = $HomeDriveFolder.FullName
	$LogMessage.UserID = $HomeDriveFolder.BaseName
	
	# Check to see if the user identity exists in Source domain
	Try {
		$LogMessage.Step = "Source Domain Lookup"
		$SourceUserInfo = Get-ADUser $HomeDriveFolder.BaseName @SourceDomainArgs
		$SourceIdentity = $SourceNetBIOS + "\" + $HomeDriveFolder.BaseName
		
		If ($SourceUserInfo.enabled -eq $false) {
			$LogMessage.Message = "$SourceIdentity is disabled in source domain"
			[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
			Continue
		}
				
		$LogMessage.Message = "Source ID $SourceIdentity found in AD"
		[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
	} Catch {
		# Catch all other exceptions thrown by one of those commands
		$LogMessage.Message = "User in source domain can not be found"
		[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
		Continue
	}
	
	# Check to see if the user identity exists in target domain
	Try {
		$LogMessage.Step = "Target Domain Lookup"
		$TargetUserInfo = Get-ADUser $HomeDriveFolder.BaseName @TargetDomainArgs
		$TargetIdentity = $TargetNetBIOS + "\" + $HomeDriveFolder.BaseName
		
		If ($TargetUserInfo.enabled -eq $false) {
			$LogMessage.Message = "$TargetIdentity is disabled in target domain"
			[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
			Continue
		}
		
		$LogMessage.Message = "Target ID $TargetIdentity found in AD"
		[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))

	} Catch {
		# Catch all other exceptions thrown by one of those commands
		$LogMessage.Message = "User in target domain can not be found"
		[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
		Continue
	}
	
	# Get the ACL's from the users home drive folder
	Try {
		$TargetHomeDriveACE = $null
		$SourceHomeDriveACE = $null
		
		$LogMessage.Step = "Reading Folder ACL"
		#Get the user folder information
		$SourceHomeDriveACL = Get-Acl $HomeDriveFolder.FullName
		# Try to determine the user specific ACE based on the folder name
		$SourceHomeDriveACE = $SourceHomeDriveACL.Access | Where-Object { $_.IdentityReference.Value -like "$($SourceIdentity)" }
		$TargetHomeDriveACE = $SourceHomeDriveACL.Access | Where-Object { $_.IdentityReference.Value -like "$($TargetIdentity)" }
		$FolderACECount = $SourceHomeDriveACL.Access.Count
		
		$LogMessage.Message = "SourceHomeDriveACE Count = $($SourceHomeDriveACE.count)"
		[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
		$LogMessage.Message = "TargetHomeDriveACE Count = $($TargetHomeDriveACE.count)"
		[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
	} Catch {
		# Catch all other exceptions thrown by one of those commands
		$LogMessage.Message = "Could not retrieve the ACL's from the users home folder"
		[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
		Continue
	}
	
	If ($SourceHomeDriveACE.Count -eq 0) {
		$LogMessage.Message = "Could not identify user ACE on $($HomeDriveFolder.FullName)"
		[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
		Continue
	}
		
	ForEach ($ACE In $SourceHomeDriveACE) {
		Try {
			$TargetHomeDriveACE = $null
			
			# Test if the value is a predefined value of the enumeration
			If (-not [System.Enum]::IsDefined([System.Security.AccessControl.FileSystemRights], $ACE.FileSystemRights)) {
				$LogMessage.Message = "The value $($ACE.FileSystemRights) is not a predefined value of the FileSystemRights enumeration."
				[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
				Continue
			}			
			
			# Build a new target ACE
			#Set vars
			$inheritance = $ACE.InheritanceFlags
			$type = $ACE.AccessControlType
			$propagation = $ACE.PropagationFlags
			$rights = $ACE.FileSystemRights
			$identity = $TargetIdentity
			
			$TargetHomeDriveACE = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $rights, $inheritance, $propagation, $type)
			
			$ACEValidation = Test-ACEExists -ACE $TargetHomeDriveACE -ACL $SourceHomeDriveACL
			
			If ($ACEValidation) {
				$LogMessage.Message = "ACE already exists, skipping"
				[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
				Continue
			}
			
			If ($SourceHomeDriveACL.Owner -ne "BUILTIN\Administrators") {
				$LogMessage.Step = "Updating folder owner"
				$LogMessage.Message = "Updating folder owner from $($SourceHomeDriveACL.Owner) to BUILTIN\Administrators"
				[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
				
				$NewOwner = New-Object -TypeName System.Security.Principal.NTAccount -ArgumentList 'BUILTIN\Administrators'
				$SourceHomeDriveACL.SetOwner($NewOwner)
			}
			
			If (-not $ACEValidation) {
				$LogMessage.Step = "Creating new ACE"
				$LogMessage.Message = $TargetHomeDriveACE | ConvertTo-Json
				[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
				
				$SourceHomeDriveACL.AddAccessRule($TargetHomeDriveACE)
				$ApplyNewACL = $true
			}
		} Catch {
			$LogMessage.Message = $_.Exception
			[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
			$LogMessage.Message = $_.InvocationInfo.Line
			[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
		}
	}
	
	# Apply the ACL with the new ACE
	If ($ApplyNewACL) {
		$JobName = $HomeDriveFolder.FullName.replace("\", "").replace(":", "")
		
		$LogMessage.Step = "Applying ACL"
		$LogMessage.Message = "Setting new ACLs"
		[void]$EventLog.Add((Add-LogMessage -MemberObject $LogMessage))
		Start-Job -ArgumentList $HomeDriveFolder.FullName, $SourceHomeDriveACL -ScriptBlock $ApplyACLScriptBlock -Name $JobName
	}
}

$EventLog | Export-Csv $Logfile -NoTypeInformation

Write-Host "Event log $Logfile created"

