<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	9/30/2023 9:39 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



Function Get-CloudCMDB {
	Param
	(
		[Parameter(Mandatory = $false)]
		[ValidateNotNullOrEmpty()]
		[string]$APIKey = "eyJhbGciOiJIUzI1NiJ9.eyJlbWFpbCI6InBldGUuZGVtZXJzQHNzY2luYy5jb20iLCJqdGkiOiJlbnRpdHl0b2tlbi03YmRhMWNhZi1jNTUzLTQ5ZGYtYmQzYy03Mzc0M2JlZmRkNzEiLCJzdWIiOiJ1c2VyLWVlY2I4OGE1LTY3YjYtNDY3NS04ZDU5LTYxNjRkOTk3ZjJlMCIsImlzcyI6ImNsb3VkIiwiaWF0IjoxNjg1NTM1OTY2LCJleHAiOjE3MTcwNzE5NjZ9.LSJt-aHxB2dXOAbFjbIc2nQcSI76WbGEPe7k9n128HA",
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

$zzdata = Import-Csv .\zzneedbu.csv | Select-Object *, cmdb_appID, cmdb_env, cmdb_dc, cmdb_bu, cmdb_appName, cmdb_fqdn, cmdb_name

# Initialize a counter for progress tracking
$counter = 0
$totalRecords = $zzdata.Count

ForEach ($record In $zzdata) {
	# Update progress bar
	$counter++
	$progress = @{
		Activity = "Processing Records"
		Status   = "Processing record $counter of $totalRecords"
		PercentComplete = ($counter / $totalRecords) * 100
	}
	Write-Progress @progress
	
	$Results = $null
	$Results = Get-CloudCMDB -IPAddress $record.ipaddress
	
	If ($Results.name) { $record.cmdb_name = $Results.name }
	If ($Results.fqdn) { $record.cmdb_fqdn = $Results.fqdn }
	If ($results.datacenter) { $record.cmdb_dc = $results.datacenter }
	If ($results.environment) { $record.cmdb_env = $results.environment }
	If ($results.cmdb.applicationId) { $record.cmdb_appID = $results.cmdb.applicationId }
	If ($results.cmdb.businessUnit) { $record.cmdb_bu = $results.cmdb.businessUnit }
	If ($results.cmdb.applicatnameionId) { $record.cmdb_appName = $results.cmdb.name }
	
	Start-Sleep -Seconds 1
}

# Complete the progress bar
Write-Progress -Activity "Processing Records" -Completed
