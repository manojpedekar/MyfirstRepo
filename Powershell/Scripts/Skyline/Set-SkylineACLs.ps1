<#
	.SYNOPSIS
		Sets permissions on the skyline database folder
	
	.DESCRIPTION
		Sets the access on the Skyline folder to remove the default BUILTIN\USERS permission and sets access for the customer
	
	.PARAMETER FolderPath
		Full path to the folder to update
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	2/3/2024 3:02 PM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:		Set-SkylineAcls
		===========================================================================
#>
Param
(
	[Parameter(Mandatory = $true)]
	[ValidateScript({
			If (Test-Path -Path $_ -PathType Container) {
				$true
			} Else {
				Throw "The path '$_' is not a valid directory."
			}
		})]
	[string]$FolderPath
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
		[string]$AccessRights = [System.Security.AccessControl.FileSystemRights]::Modify -bor [System.Security.AccessControl.FileSystemRights]::Synchronize,
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


#Define the server and permission alignment
$ServerPermsArray = Import-Csv .\SkylinePermGrps.csv | Where-Object { $_.PermName -ne '' }

# Create an empty hash table
$ServerPermsHashTable = @{ }

# Skip the first item (header) and iterate through the rest of the array
ForEach ($item In $ServerPermsArray) {
	# Use the first part as the key and the second part as the value
	$ServerPermsHashTable[$Item.ServerName] = $Item.PermName
}

# Attempt to retrieve the server permission using the computer's name
$ServerPerm = $ServerPermsHashTable[$env:computername]

# Check if the permission was not found
If (-not $ServerPerm) {
	Write-Error "Permission not found for $($env:COMPUTERNAME)"
	EXIT 1	
}

# If the permission exists, continue with the script
If ($ServerPerm) {
	$NewACE = New-FileSystemAccessRule -IdentityReference "SSCCLIENT01\$($ServerPerm)"
	
	# Get the current ACL of the folder
	$CurrentACL = Get-Acl -Path $FolderPath
	$CurrentACEList = $CurrentACL.Access | Where-Object { $_.IsInherited -eq $true -and $_.IdentityReference -ne "BUILTIN\Users" -and $_.IdentityReference -notlike 'ADMGMT\*' }
	
	#Create new ACL, remove inheritance, and add customer ACE
	$NewACL = $CurrentAcl
	$NewACL.SetAccessRuleProtection($true, $false)
	$NewACL.AddAccessRule($NewACE)
	
	# update the new ACL list with necessary ACE from current ACE
	ForEach ($CurrentACE In $CurrentACEList ) {
		If (-not (Test-ACEExists -ACE $CurrentACE -ACL $NewACL)) {
			$NewACL.AddAccessRule($CurrentACE)
		}
	}
		
	# Set the updated ACL back on the folder
	Set-Acl -Path $FolderPath -AclObject $NewACL
}
