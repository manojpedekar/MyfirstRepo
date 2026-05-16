


$agentFile = "C:\ProgramData\Cyvera\LocalSystem\OsPersistence\agent.id"; If (Test-Path $agentFile) { $id = Get-Content $agentFile } Else { $id = 'unknown' }; salt-call grains.setval ssnc_xdr_id $id


$agentFile = "C:\ProgramData\Cyvera\LocalSystem\OsPersistence\agent.id"

If (Test-Path $agentFile) {
	$id = Get-Content $agentFile
} Else {
	$id = 'unknown'
}

salt-call grains.setval ssnc_xdr_id $id

