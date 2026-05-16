<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	9/28/2023 3:26 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

Function Export-LocalGroupsToXML {
<#
    .SYNOPSIS
        Export local security group information
    
    .DESCRIPTION
        Export local security groups and membership. Excludes well-known groups
    
    .PARAMETER outputPath
        File to export results
    
    .EXAMPLE
        Export-LocalGroupsToXML -outputPath "C:\Temp\localGroups.xml"
    
    .NOTES
        Version 1.1
        Created by dt234083
        Created on 9/28/2023
#>
	
	Param
	(
		[string]$outputPath = "C:\Temp\localGroups.xml"
	)
	
	# Ensure outputPath directory exists
	$directory = [System.IO.Path]::GetDirectoryName($outputPath)
	If (-not (Test-Path -Path $directory)) {
		New-Item -ItemType Directory -Path $directory
	}
	
	$groups = @()
	
	# Define well-known groups to ignore
	$wellKnownGroups = @("Administrators", "Users", "Guests", "Backup Operators",
		"Certificate Service DCOM Access", "Cryptographic Operators", "Distributed COM Users",
		"Event Log Readers", "IIS_IUSRS", "Network Configuration Operators", "Performance Log Users",
		"Performance Monitor Users", "Power Users", "Print Operators", "Remote Desktop Users", "Replicator",
		"ConfigMgr Remote Control Users")
	
	$localGroups = Get-WmiObject Win32_Group -Filter "LocalAccount='True'"
	$groupCount = $localGroups.Count
	$count = 0
	
	ForEach ($localGroup In $localGroups) {
		$count++
		
		# Update progress bar
		Write-Progress -Activity "Exporting Local Groups to XML -- $($count) of $($groupCount)" -Status "$($localGroup.Name)" -PercentComplete (($count / $groupCount) * 100)
		
		# Continue to the next iteration if the group is a well-known group
		If ($wellKnownGroups -contains $localGroup.Name) {
			Continue
		}
		
		$groupMembers = @()
		
		$members = Get-WmiObject Win32_GroupUser -Filter "GroupComponent=`"Win32_Group.Domain='$($localGroup.Domain)',Name='$($localGroup.Name)'`""
		
		ForEach ($member In $members) {
			$matches = $null # Clear previous matches
			$matchFound = $member.PartComponent -match ".+Domain=""(.+)"",Name=""(.+)"""
			
			If ($matchFound -and $matches.Count -ge 2) {
				$groupMembers += New-Object PSObject -property @{
					Domain = $matches[1]
					Name   = $matches[2]
				}
			}
		}
		
		$groups += New-Object PSObject -property @{
			GroupName = $localGroup.Name
			Description = $localGroup.Description
			OldSID    = $localGroup.SID
			Members   = $groupMembers
		}
	}
	
	# Close the progress bar
	Write-Progress -Activity "Exporting Local Groups to XML" -Completed -Status "Complete"
	
	$groups | Export-Clixml -Path $outputPath
}

Function Export-LocalUsersToXML {
<#
    .SYNOPSIS
        Export local user information
    
    .DESCRIPTION
        Export local security users and membership. Excludes well-known users
    
    .PARAMETER outputPath
        File to export results
    
    .EXAMPLE
        Export-LocalUsersToXML -outputPath "C:\Temp\localUsers.xml"
    
    .NOTES
        Version 1.2
        Created by dt234083
        Created on 9/28/2023
#>
	
	Param
	(
		[string]$outputPath = "C:\localUsers.xml"
	)
	
	# Ensure outputPath directory exists
	$directory = [System.IO.Path]::GetDirectoryName($outputPath)
	If (-not (Test-Path -Path $directory)) {
		New-Item -ItemType Directory -Path $directory
	}
	
	$users = @()
	
	# Define well-known users to ignore
	$wellKnownUsers = @("Administrator", "Guest", "DefaultAccount")
	
	$localUsers = Get-WmiObject Win32_UserAccount -Filter "LocalAccount='True'"
	$userCount = $localUsers.Count
	$count = 0
	
	ForEach ($localUser In $localUsers) {
		$count++
		
		# Update progress bar
		Write-Progress -Activity "Exporting Local Users to XML -- $($count) of $($userCount)" -Status "$($localUser.Name)" -PercentComplete (($count / $userCount) * 100)
		
		# Continue to the next iteration if the user is a well-known user
		If ($wellKnownUsers -contains $localUser.Name) {
			Continue
		}
		
		# Fetching additional user properties
		$userFlag = [ADSI]("WinNT://./$($localUser.Name),user")
		$userFlagValue = $userFlag.UserFlags.Value
		
		# Improved check for AccountIsDisabled
		$accountIsDisabled = $localUser.Disabled
		
		$passwordNeverExpires = $userFlagValue -band 0x10000 -ne 0
		$userCannotChangePassword = $userFlagValue -band 0x40 -ne 0
		$description = $userFlag.Description
		
		$users += New-Object PSObject -property @{
			UserName = $localUser.Name
			Description = $description
			PasswordNeverExpires = $passwordNeverExpires
			UserCannotChangePassword = $userCannotChangePassword
			AccountIsDisabled = $accountIsDisabled
		}
	}
	
	# Close the progress bar
	Write-Progress -Activity "Exporting Local Users to XML" -Completed -Status "Complete"
	
	$users | Export-Clixml -Path $outputPath
}

Function Import-LocalUsersFromXML {
<#
    .SYNOPSIS
        Import local user information from XML
    
    .DESCRIPTION
        Import local users and their properties from an XML file and create them on the local computer.
    
    .PARAMETER inputPath
        File path to read the XML data from.
    
    .PARAMETER Credential
        Credential object to set the password for the new accounts. If not provided, a prompt will appear for password.
    
    .EXAMPLE
        Import-LocalUsersFromXML -inputPath "C:\Temp\localUsers.xml"
    
    .EXAMPLE
        $cred = Get-Credential
        Import-LocalUsersFromXML -inputPath "C:\Temp\localUsers.xml" -Credential $cred
    
    .NOTES
        Version 1.1
        Modified on 9/28/2023
#>
	
	Param
	(
		[string]$inputPath = "C:\localUsers.xml",
		[PSCredential]$Credential
	)
	
	#load the assembly type for account management
	Add-Type -AssemblyName System.DirectoryServices.AccountManagement
	
	# Set up the context type for the machine
	$contextType = [System.DirectoryServices.AccountManagement.ContextType]::Machine
	
	# Create a new principal context
	$principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext $contextType
		
	# Ensure inputPath file exists
	If (-not (Test-Path -Path $inputPath)) {
		Write-Error "The specified inputPath file does not exist."
		Return
	}
	
	# Import users from XML
	$users = Import-Clixml -Path $inputPath
	$userCount = $users.Count
	$count = 0
	
	ForEach ($user In $users) {
		$count++
		
		# Create a new user principal object
		$userPrincipal = New-Object System.DirectoryServices.AccountManagement.UserPrincipal $principalContext
		

		
		# Update progress bar
		Write-Progress -Activity "Importing Local Users from XML -- $($count) of $($userCount)" -Status "$($user.UserName)" -PercentComplete (($count / $userCount) * 100)
		
		# If user already exists, skip to the next iteration
		If (Get-WmiObject Win32_UserAccount -Filter "LocalAccount='True' AND Name='$($user.UserName)'") {
			Write-Warning "User $($user.UserName) already exists. Skipping..."
			Continue
		}
		
		# If Credential is not provided, prompt for password
		If (-not $Credential) {
			$Password = Read-Host "Enter the password for $($user.UserName)" -AsSecureString
		} Else {
			$Password = $Credential.Password
		}
		
		# Set user details
		$userPrincipal.Name = $user.UserName
		$userPrincipal.SetPassword($Password)
		$userPrincipal.Description = $user.Description
		$userPrincipal.UserCannotChangePassword = $user.UserCannotChangePassword
		$userPrincipal.PasswordNeverExpires = $user.PasswordNeverExpires
		$userPrincipal.Enabled = $true
		
		# Save the user principal
		Try {
			$userPrincipal.Save()
			Write-Output "User $($user.UserName) has been created."
		} Catch {
			"An error occurred: $_"
		}
		
		# Disable the user account if it was disabled in the source
		If ($user.AccountIsDisabled) {
			Disable-LocalUser -Name $user.UserName -Verbose
		}
		
	}
	
	# Close the progress bar
	Write-Progress -Activity "Importing Local Users from XML" -Completed -Status "Complete"
}

Function Import-LocalGroupsFromXML {
	
<#
.SYNOPSIS
    Import local security group information

.DESCRIPTION
    Import local security groups and membership from an XML file.

.PARAMETER inputPath
    File to import results from.

.EXAMPLE
    Import-LocalGroupsFromXML -inputPath "C:\Temp\localGroups.xml"

.NOTES
    Version 1.6
    Created on 9/28/2023
#>
	
	
	Param
	(
		[string]$inputPath = "C:\Temp\localGroups.xml"
	)
	
	# Add .NET types needed to manage local groups and users
	Add-Type -AssemblyName System.DirectoryServices.AccountManagement
	
	# Ensure the inputPath file exists
	If (-not (Test-Path -Path $inputPath)) {
		Write-Error "The specified inputPath file does not exist."
		Return
	}
	
	# Import groups from XML
	$groups = Import-Clixml -Path $inputPath
	$groupCount = $groups.Count
	$count = 0
	
	# Context to operate local machine
	$contextType = [System.DirectoryServices.AccountManagement.ContextType]::Machine
	$context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($contextType)
	
	ForEach ($group In $groups) {
		$count++
		
		# Update progress bar
		Write-Progress -Activity "Importing Local Groups from XML -- $($count) of $($groupCount)" -Status "$($group.GroupName)" -PercentComplete (($count / $groupCount) * 100)
		
		# Find existing group
		$existingGroup = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($context, $group.GroupName)
		
		If ($existingGroup) {
			Write-Warning "Group $($group.GroupName) already exists. Skipping..."
		} Else {
			# Create new group
			$newGroup = New-Object System.DirectoryServices.AccountManagement.GroupPrincipal($context)
			$newGroup.Name = $group.GroupName
			$newGroup.Description = $group.Description
			$newGroup.Save()
			Write-Output "Group $($group.GroupName) has been created."
		}
	}
	
	$count = 0
	
	ForEach ($group In $groups) {
		$count++
		
		# Update progress bar
		Write-Progress -Activity "Updating Group Membership -- $($count) of $($groupCount)" -Status "$($group.GroupName)" -PercentComplete (($count / $groupCount) * 100)
		
		# Find group again for membership update
		$updateGroup = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($context, $group.GroupName)
		
		If ($updateGroup) {
			# Add members to the group
			ForEach ($member In $group.Members) {
				# Check if the domain is 'SSNC' or 'SSNC-CORP' and set context accordingly
				If ($member.Domain -eq 'SSNC') {
					$domainContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Domain, "ssnc.global")
					$userPrincipal = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($domainContext, $member.Name)
				} ElseIf ($member.Domain -eq 'SSNC-CORP') {
					$domainContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Domain, "ssnc-corp.global")
					$userPrincipal = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($domainContext, $member.Name)
				} Else {
					$userPrincipal = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($context, $member.Name)
				}
				
				# Proceed if userPrincipal is found
				If ($userPrincipal) {
					# Check if the user is already a member of the group
					$isMemberAlready = $false
					ForEach ($groupMember In $updateGroup.Members) {
						If ($groupMember.SamAccountName -eq $userPrincipal.SamAccountName) {
							$isMemberAlready = $true
							Break
						}
					}
					
					If (-not $isMemberAlready) {
						Try {
							$updateGroup.Members.Add($userPrincipal)
							$updateGroup.Save()
							Write-Verbose "User $($userPrincipal.Name) added to $($updateGroup.Name)."
						} Catch {
							Write-Warning "An error occurred adding user $($userPrincipal.Name) to $($updateGroup.Name): $_"
						}
					} Else {
						#Write-Verbose "User $($userPrincipal.Name) is already a member of $($updateGroup.Name). No action taken."
					}
				} Else {
					Write-Warning "Member $($member.Name) with domain $($member.Domain) does not exist. Skipping..."
				}
			}
		}
		
		
	}
	
	# Close the progress bar
	Write-Progress -Activity "Updating Group Membership" -Completed -Status "Complete"
	
}
