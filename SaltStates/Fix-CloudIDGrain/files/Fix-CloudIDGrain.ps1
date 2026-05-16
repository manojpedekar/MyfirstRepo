<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	2/8/2023 10:20 AM
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
		#[Parameter(Mandatory = $true)]
		[string]$APIKey = "",
		[Parameter(Mandatory = $true)]
		[string]$IPAddress
	)
	
	$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
	$headers.Add("x-api-key", $APIKey)
	$headers.Add("Content-Type", "application/json")
	
	$request = "https://portal.ssnc-corp.cloud/api/v2/cmdb/server?serverIp=$IPAddress"
	
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	$response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
	
	Return $response.content
}

If (Test-Path C:\salt\conf\minion.d\99-metadata-grains.conf) {
	Write-Host "99-metadata-grains.conf Present" -ForegroundColor Green
	Get-ChildItem C:\salt\conf\minion.d\99-metadata-grains.conf
}

$Update = $false
$CloudIDGrain = (salt-call grains.get ssnc_cloud_id)
$CloudPlatformGrain = (salt-call grains.get ssnc_cloud_platform)
$CMDBData = Get-CloudCMDB -IPAddress (Resolve-DnsName $env:computername -Type A).ipaddress

If (($CloudIDGrain | measure).count -gt 1){ $CloudIDGrain = $CloudIDGrain[1].trim()}

If ($CloudIDGrain -notlike 'i-*') {
	
	If ($CMDBData.vcenterId -like "i-*") {
		salt-call grains.setval ssnc_cloud_id $CMDBData.vcenterId
		$Update = $true
	}
	
	If ($CMDBData.vcenterId -notlike "i-*") {
		salt-call grains.setval wineng_cloudid_update failed
		$Update = $true
	}

}

If (($CloudPlatformGrain | Measure-Object).count -ne 2 -and $CMDBData.vcenterId -like "i-*") {
	salt-call grains.setval ssnc_cloud_platform prod
	$Update = $true
}

If ($Update -eq $true) { salt-call state.apply }

If ($Update -eq $false) { Write-Host "No Updates Required" }




