<#
	.SYNOPSIS
		Get the account status of a users home drive folder.
	
	.DESCRIPTION
		This script assumes the folder name is the user name.  It will query Active Directory for an account status
	
	.PARAMETER HomeDrivePaths
		One or more folder patsh wher user home drive folders exist
	
	.PARAMETER HoldingPen
		A folder name where disabled users should be moved.  This will be created in the root of the same drive the suers profile is located.
	
	.PARAMETER UserDomain
		Specify the FQDN of the users AD Domain.  If not specified, then the default domain will be the domain of the computer the script is running on.
	
	.PARAMETER MoveDisabled
		A switch parameter that, when set, will enable the script to move disabled user profiles to the specified holding pen.
	
    .EXAMPLE
         .\Get-HomeDriveFolderStatus.ps1 -HomeDrivePaths E:\homedirs\, E:\homedirs2\, E:\homedirs3\, G:\homedirs2\, I:\Userhome\, J:\profiles\, K:\homedirs3\, M:\profiles\

    .EXAMPLE
         .\Get-HomeDriveFolderStatus.ps1 -HomeDrivePaths E:\homedirs\, E:\homedirs2\, E:\homedirs3\, G:\homedirs2\, I:\Userhome\, J:\profiles\, K:\homedirs3\, M:\profiles\

    

	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	11/15/2023 9:13 AM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:		Get-HomeDriveFolderStatus.ps1
		===========================================================================
#>
Param
(
	[Parameter(Mandatory = $true)]
	[ValidateScript({
			ForEach ($path In $_) {
				If (-not (Test-Path -Path $path -PathType Container)) {
					Throw "The path '$path' does not exist or is not a valid directory."
				}
			}
			Return $true
		})]
	[ValidateNotNullOrEmpty()]
	[String[]]$HomeDrivePaths,
	[String]$HoldingPen,
	[String]$UserDomain = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain().Name,
	[switch]$MoveDisabled
)

###########################################
##               CLASSES                 ##
###########################################

Class HomeFolder {
	[string]$FullPath
	[string]$SamAccountName
	[string]$FolderStatus
	[string]$FolderName
	[string]$Domain
	[int]$PermCount
	
	
	HomeFolder([string]$FullPath, [string]$FolderStatus, [string]$Domain) {
		$this.FullPath = $FullPath
		$this.FolderName = [System.IO.Path]::GetFileName($FullPath)
		$this.SamAccountName = [System.IO.Path]::GetFileName($FullPath)
		$this.FolderStatus = $FolderStatus
		$this.Domain = $Domain
		$this.PermCount = Get-CustomPermissionCount -FullPath $FullPath
	}
}

###########################################
##              FUNCTIONS                ##
###########################################

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

Function Get-CustomPermissionCount {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[string]$FullPath
	)
	Try {
		$customAccessCount = (Get-Acl $FullPath).Access |
		Where-Object {
			$_.IdentityReference.Value -notmatch '(ADMGMT|BUILTIN|NT AUTHORITY|perm)' -and
			$_.IdentityReference.Value -notlike 's-1-5*' -and
			$_.IsInherited -eq $false 
		} |
		Measure-Object |
		Select-Object -ExpandProperty Count
		
		Return $customAccessCount
	} Catch {
		Write-Error "Error retrieving ACLs: $_"
		Return $null
	}
}

###########################################
##                 VARS                  ##
###########################################



###########################################
##               SCRIPT                  ##
###########################################

# Initialize a counter for the outer loop
$outerLoopIndex = 0
$outerLoopTotal = $HomeDrivePaths.Count

ForEach ($HomeDrivePath In $HomeDrivePaths) {
	# Increment the outer loop counter
	$outerLoopIndex++
	
	# Update outer loop progress
	Write-Progress -Activity "Processing Home Drive Paths - $($outerLoopIndex) of $outerLoopTotal" -Status "$HomeDrivePath" -PercentComplete (($outerLoopIndex / $outerLoopTotal) * 100) -Id 1
	
	# Get a list of folders from the path
	$HomeFolders = Get-ChildItem $HomeDrivePath -Directory
	
	# Set default value for HoldingPen if it's not provided
	If (-not $HoldingPen) {
		$HoldingPen = [System.IO.Path]::GetPathRoot($HomeDrivePath) + "OldProfiles"
	}
	
	If ($MoveDisabled) {
		Write-Host "Holding Pen Folder: $HoldingPen"
		
	}
	
	# Initialize a counter for the inner loop
	$innerLoopIndex = 0
	$innerLoopTotal = $HomeFolders.Count
	
	ForEach ($HomeFolder In $HomeFolders) {
		# Increment the inner loop counter
		$innerLoopIndex++
		
		# Update inner loop progress
		Write-Progress -Activity "Processing Home Folders - $($innerLoopIndex) of $($innerLoopTotal)" -Status "$HomeFolder" -PercentComplete (($innerLoopIndex / $innerLoopTotal) * 100) -Id 2
		
		[HomeFolder]::new(
			$HomeFolder.FullName,
			(Test-ADUserExists -UserName $HomeFolder.BaseName -DomainName $UserDomain),
			$UserDomain
		)
		
		If ($MoveDisabled) {
			# Add code to move the disabled users to a different folder
		}
	}
}

# Ensure to clear the progress bar once done
Write-Progress -Activity "Processing Complete" -Completed

	