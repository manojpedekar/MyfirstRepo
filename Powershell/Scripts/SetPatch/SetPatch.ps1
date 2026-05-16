#User Set Variable
$APIKey = "eyJhbGciOiJIUzI1NiJ9.eyJlbWFpbCI6InBldGUuZGVtZXJzQHNzY2luYy5jb20iLCJqdGkiOiJlbnRpdHl0b2tlbi1lMmE1MjNmZC1mOTc4LTQ5OWMtYTE2Yy00NTg0OTYzY2UwMTEiLCJzdWIiOiJ1c2VyLWVlY2I4OGE1LTY3YjYtNDY3NS04ZDU5LTYxNjRkOTk3ZjJlMCIsImlzcyI6ImNsb3VkIiwiaWF0IjoxNjY2ODA2OTA0LCJleHAiOjE2NjcyNzg4MDB9.m8dH-lNmJc0m4v1ER90flgmvwH9KQ74ANZ1S1RMKy_8"

$servers = import-csv .\servers.csv

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("x-api-key", $APIKey)
$headers.Add("Content-Type", "application/json")

ForEach ($server In $servers) {
	
	$MachineId = $server.id
	
	$body = [PSCustomObject]@{
		patchingGroup = $server.patch
		domainDelegation = $server.domain
	} | ConvertTo-Json
	
	$request = "https://portal.ssnc-corp.cloud/api/v1/instances/$MachineId"
	write-output $request
	#  Write-Output $body
	$response = Invoke-RestMethod $request -Method 'PUT' -Headers $headers -Body $body
	$response | Export-Csv -NoTypeInformation -Append .\log.csv
}
