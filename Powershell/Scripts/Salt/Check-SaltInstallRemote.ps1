<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	11/21/2023 1:23 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

# Define the domain
$domain = "sscclient01.ssncad.global"

$ldapPath = "LDAP://DC=$($domain -replace '\.', ',DC=')"
$staleThreshold = (Get-Date).AddDays(-45).ToFileTimeUtc()

# Create a DirectorySearcher object
$searcher = New-Object System.DirectoryServices.DirectorySearcher
$searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry($ldapPath)
$searcher.Filter = "(&(objectCategory=computer)(operatingSystem=*Server*)(userAccountControl:1.2.840.113556.1.4.803:=512))"

# Search and get the list of servers
$serverList = $searcher.FindAll()

# Initialize an array to hold the results
$results = @()

# Total number of servers
$totalServers = $serverList.Count
$currentServer = 0

# Iterate through each server
ForEach ($server In $serverList) {
	$currentServer++
	# Update progress bar
	Write-Progress -Activity "Processing Servers" -Status "Server $currentServer of $totalServers" -PercentComplete (($currentServer / $totalServers) * 100) -CurrentOperation "Starting Server"
	
	# Extract server properties
	$serverName = $server.Properties["name"][0]
	$serverDNSHostName = $server.Properties["dnshostname"][0]
	$lastLogonTimestamp = [DateTime]::FromFileTime($server.Properties["lastlogontimestamp"][0])
	
	# Determine if the computer object is stale
	$isStale = $lastLogonTimestamp -lt (Get-Date).AddDays(-30)
	
	# Create a custom object for each server
	$serverResult = [PSCustomObject]@{
		ServerName		    = $serverName
		distinguishedname   = $server.Properties["distinguishedname"][0]
		IsReachable		    = $false
		SaltDirectoryExists = $null
		SaltVersion		    = $null
		IsStaleObject	    = $isStale
	}
	
	Write-Progress -Activity "Processing Servers" -Status "Server $currentServer of $totalServers" -PercentComplete (($currentServer / $totalServers) * 100) -CurrentOperation "Testing connection to $($serverName)"
	# Test remote connectivity
	$ping = Test-Connection -ComputerName $serverDNSHostName -Count 2 -Quiet
	$serverResult.IsReachable = $ping
	
	If ($ping) {
		# Check for C:\salt and run salt-call --version
		$scriptBlock = {
			$result = [PSCustomObject]@{
				SaltDirectoryExists = Test-Path "C:\salt"
				NewerSaltDirectoryExists = Test-Path "C:\ProgramData\Salt Project\Salt"
				SaltVersion		    = $null
			}
			
			If ($result.SaltDirectoryExists) {
				Try {
					$result.SaltVersion = salt-call --version
				} Catch {
					$result.SaltVersion = "Error running salt-call"
				}
			}
			
			Return $result
		}
		
		Write-Progress -Activity "Processing Servers" -Status "Server $currentServer of $totalServers" -PercentComplete (($currentServer / $totalServers) * 100) -CurrentOperation "Running Remote Command on $($serverName)"
		# Invoke the script block on the remote server using the provided credentials
		$remoteResult = Invoke-Command -ComputerName $serverDNSHostName -ScriptBlock $scriptBlock -Credential $creds -ErrorAction SilentlyContinue
		$serverResult.SaltDirectoryExists = $remoteResult.SaltDirectoryExists
		$serverResult.SaltVersion = $remoteResult.SaltVersion
	}
	
	# Add the result to the results array
	$results += $serverResult
}

# Complete progress bar
Write-Progress -Activity "Processing Servers" -Completed

# Return the results
Return $results
