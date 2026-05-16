$servers = import-csv .\servers.csv
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("x-api-key", "")
$headers.Add("Content-Type", "application/json")

foreach ($server in $servers){
  $MachineId = $server.id
  $Domain = $server.domain
  $PatchSchedule = $server.patch
  $body = "{`n    `"patchingGroup`": `"$PatchSchedule`",`n    `"domainDelegation`": `"$Domain`"`n}"
  $request = "https://portal.ssnc-corp.cloud/api/v1/instances/$MachineId"
  write-output $request
#  Write-Output $body
  $response = Invoke-RestMethod $request -Method 'PUT' -Headers $headers -Body $body
  $response | Export-Csv -NoTypeInformation -Append .\log.csv
}