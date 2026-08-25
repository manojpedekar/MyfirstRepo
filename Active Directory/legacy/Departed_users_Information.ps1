# Before running, update the $HomeDirsPath and $Domain variables below to match your environment.

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
	
	$root = $null
	$searcher = $null
	Try {
		# Prepare the root for searching
		If ($DomainName) {
			$root = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainName")
		} Else {
			# Get the current domain if no domain name is provided
			$currentDomain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
			$root = $currentDomain.GetDirectoryEntry()
		}

		# Escape characters that are special in an LDAP filter so folder names
		# like "john*" or values containing ( ) \ cannot break or widen the search.
		$escapedUserName = $UserName -replace '([\\*()\x00/])', '\$1'

		# Set the search filter to find the user
		$searchFilter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$escapedUserName))"

		# Set the properties to retrieve
		$searchProperties = @("sAMAccountName", "userAccountControl")

		# Search for the user in the domain
		$searcher = New-Object System.DirectoryServices.DirectorySearcher($root, $searchFilter, $searchProperties)
		$searchResult = $searcher.FindOne()

		# Check the result and determine the account status
		If ($searchResult) {
			If ($searchResult.Properties["userAccountControl"].Count -gt 0) {
				$userAccountControl = $searchResult.Properties["userAccountControl"][0]
				$accountDisabled = ($userAccountControl -band 2) -ne 0
				If ($accountDisabled) {
					Return "Disabled"
				} Else {
					Return "Enabled"
				}
			} Else {
				# Account found but status attribute unavailable (e.g. insufficient rights)
				Write-Warning "Found '$UserName' but could not read userAccountControl."
				Return "ConnectionError"
			}
		} Else {
			Return "Missing"
		}
	} Catch {
		# Handle the exception (e.g., connection failure)
		Write-Warning "Failed to connect to the domain or an error occurred: $_"
		Return "ConnectionError"
	} Finally {
		# Release unmanaged directory-services resources
		If ($searcher) { $searcher.Dispose() }
		If ($root)     { $root.Dispose() }
	}
}

# --- Configuration: update these for your environment ---
$HomeDirsPath = 'D:\Homedirs'
$Domain       = 'ad.dstsystems.com'
$ReportPath   = 'D:\Homedirs_UserStatus.csv'

If (-not (Test-Path -LiteralPath $HomeDirsPath)) {
	Throw "Home directory path '$HomeDirsPath' was not found. Update `$HomeDirsPath and try again."
}

$Dirs = Get-ChildItem -LiteralPath $HomeDirsPath -Directory

$Report = Foreach ($Dir in $Dirs) {

	$Status = Test-ADUserExists -UserName $Dir.BaseName -DomainName $Domain

	# Human-readable note + console feedback while building the report
	Switch ($Status) {
		"Enabled" {
			$Note = "Account exists and is active"
			Write-Host "The user id $($Dir.BaseName) was found in the directory" -ForegroundColor Magenta
		}
		"Disabled" {
			$Note = "Account exists but is disabled"
			Write-Host "The user id $($Dir.BaseName) is disabled" -ForegroundColor Yellow
		}
		"Missing" {
			$Note = "No matching AD account (possible departed user)"
			Write-Host "The user id $($Dir.BaseName) was not found in the directory" -ForegroundColor Red
		}
		"ConnectionError" {
			$Note = "AD domain not available / status unreadable - no action taken"
			Write-Host "The AD domain is not available. No action taken on folder $($Dir.FullName)"
		}
		Default {
			$Note = "Unexpected status"
			Write-Host "The user id $($Dir.BaseName) should not have gone here" -ForegroundColor Blue
		}
	}

	# Emit one record per folder for the CSV report
	[PSCustomObject]@{
		UserID     = $Dir.BaseName
		Status     = $Status
		Note       = $Note
		FolderPath = $Dir.FullName
	}

}

$Report | Export-Csv -LiteralPath $ReportPath -NoTypeInformation -Encoding UTF8
Write-Host "`nReport exported to $ReportPath ($($Report.Count) folders processed)." -ForegroundColor Green
