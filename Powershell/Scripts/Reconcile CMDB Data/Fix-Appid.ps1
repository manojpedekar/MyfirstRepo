<#
	.SYNOPSIS
		Compares salt application id against CMDB data and updates if necessary
	
	.DESCRIPTION
		Compares salt application id against CMDB data and updates if necessary
	
	.PARAMETER $APIKey
		Valid Cloud API Key
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	11/18/2023 5:51 AM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:       Fix-Appid.ps1
		===========================================================================
#>
Param
(
	[string]$APIKey = "eyJhbGciOiJIUzI1NiJ9.eyJlbWFpbCI6InBldGUuZGVtZXJzQHNzY2luYy5jb20iLCJqdGkiOiJlbnRpdHl0b2tlbi04OWNlZGRiNC04YWIzLTQ0NTEtOWZiMS0zZjQyN2M0MDE5YjIiLCJzdWIiOiJ1c2VyLWVlY2I4OGE1LTY3YjYtNDY3NS04ZDU5LTYxNjRkOTk3ZjJlMCIsImlzcyI6ImNsb3VkIiwiaWF0IjoxNzAwMjk3NzYwLCJleHAiOjE3MDA0NjAwMDB9.KhcvuudyAA02EDEMZaPFKJ0Z9cAmm7nA0yJNlYAArtc"
)

Function Get-CloudCMDB {
	Param
	(
		[Parameter(Mandatory = $false)]
		[ValidateNotNullOrEmpty()]
		[string]$APIKey,
		[Parameter(Mandatory = $true)]
		[ValidatePattern("\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}")]
		[string]$IPAddress
	)
	
	# Force TLS 1.2
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	
	Try {
		$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
		$headers.Add("x-api-key", $APIKey)
		$headers.Add("Content-Type", "application/json")
		
		$request = "https://portal.ssnc-corp.cloud/api/v2/cmdb/server?serverIp=$IPAddress"
		
		$response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
		Return $response.content
	} Catch {
		Write-Error "Failed to retrieve CMDB data. $($Error[0].Exception.Message)"
		Return $null
	}
	
}

$SaltAppID = (salt-call grains.get ssnc_app_id)
$CMDBData = Get-CloudCMDB -IPAddress (Resolve-DnsName $env:computername -Type A).ipaddress -APIKey $APIKey

If ($SaltAppID.count -gt 1) {
	$SaltAppID = $SaltAppID[1].trim()
}

If ($CMDBData) {
	If (($CMDBData -and $CMDBData.cmdb -and $CMDBData.cmdb.applicationId) -and ($CMDBData.cmdb.applicationId -ne $SaltAppID)) {
		salt-call grains.setval ssnc_app_id $CMDBData.cmdb.applicationId
	}
}





$APIKey = "eyJhbGciOiJIUzI1NiJ9.eyJlbWFpbCI6InBldGUuZGVtZXJzQHNzY2luYy5jb20iLCJqdGkiOiJlbnRpdHl0b2tlbi04OWNlZGRiNC04YWIzLTQ0NTEtOWZiMS0zZjQyN2M0MDE5YjIiLCJzdWIiOiJ1c2VyLWVlY2I4OGE1LTY3YjYtNDY3NS04ZDU5LTYxNjRkOTk3ZjJlMCIsImlzcyI6ImNsb3VkIiwiaWF0IjoxNzAwMjk3NzYwLCJleHAiOjE3MDA0NjAwMDB9.KhcvuudyAA02EDEMZaPFKJ0Z9cAmm7nA0yJNlYAArtc"

$badappid = Import-Csv '.\Servers-data-2023-11-18 06_23_12.csv' | Where-Object { $_.ipaddress -ne "" } | Select-Object *, @{ N = "CMDBAppID"; E = "NotValidated" }, @{ N = "CMDBServerName"; E = { $null } }
$total = $badappid.Count
$current = 0

# Start timer
$startTime = Get-Date

$badappid | ForEach-Object {
	$current++
	$percentComplete = ($current / $total) * 100
	
	# Calculate elapsed and remaining time
	$elapsedTime = New-TimeSpan -Start $startTime -End (Get-Date)
	$estimatedTotalTime = $elapsedTime.TotalSeconds / $percentComplete * 100
	$remainingTime = $estimatedTotalTime - $elapsedTime.TotalSeconds
	$remainingTimeSpan = [TimeSpan]::FromSeconds($remainingTime)
	$formattedTimeRemaining = [string]::Format("{0:00}:{1:00}:{2:00}", $remainingTimeSpan.Hours, $remainingTimeSpan.Minutes, $remainingTimeSpan.Seconds)
	
	# Format the percentage to two decimal points
	$formattedPercentComplete = "{0:N2}" -f $percentComplete
	
	# Display progress bar with formatted percentage and time remaining
	Write-Progress -Activity "Processing IP Addresses" -Status "$current of $total processed ($formattedPercentComplete%) - Est. Time Remaining: $formattedTimeRemaining" -PercentComplete $percentComplete -CurrentOperation $_.ipaddress
	
	$CMDBData = Get-CloudCMDB -IPAddress $_.ipaddress -APIKey $APIKey
	
	# Check if the ServerName is present and not null or empty
	If ($CMDBData -and $CMDBData.fqdn) {
		$_.CMDBServerName = $CMDBData.fqdn
	}
	
	# Check if the applicationId is present and not null or empty
	If ($CMDBData -and $CMDBData.cmdb -and $CMDBData.cmdb.applicationId) {
		$_.CMDBAppID = $CMDBData.cmdb.applicationId
	}
	
	
}

# Hide progress bar after completion
Write-Progress -Activity "Processing IP Addresses" -Completed


