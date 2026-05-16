
Clear-Host

#===============================================================================
# Script Functions
#===============================================================================

Function Test-CommandExists
{
	# Simple function to test for a powershell command
	Param ($command)
	$oldPreference = $ErrorActionPreference
	$ErrorActionPreference = 'stop'
	
	try { if (Get-Command $command) { $true } }
	Catch { $false }
	Finally { $ErrorActionPreference = $oldPreference }
}


#===============================================================================
# Main Script
#===============================================================================

Write-Host "Checking C:\Salt directory Exists" -ForegroundColor Yellow
$SaltExists = Test-Path C:\salt

if ($SaltExists){
	Write-Host "   Salt Directory exists" -ForegroundColor Green
	Write-Host "Comparing Computername and minion_id" -ForegroundColor Yellow
	$Minion_ID = Get-Content C:\Salt\conf\minion_id
	
	if (Test-CommandExists -command Get-CimInstance)
	{
		$sysinfo = Get-CimInstance -ClassName win32_computersystem
	}
	else { $sysinfo = Get-WmiObject -Class win32_computersystem }
	
	$CompName = $sysinfo.Name, $sysinfo.Domain -join "."
	
	$OSArchitecture = if ([System.IntPtr]::Size -eq 4 | Out-Null) { "32-bit" } else { "64-bit" } 
	
	Write-Host "   OSArchitecture = $OSArchitecture"
	Write-Host "   ComputerName   = $CompName"
	Write-Host "   Minion_id      = $Minion_ID"
	
	if ($CompName -eq $Minion_ID) {
		Write-Host "   Computername and minion_id match" -ForegroundColor Green
	} else {
		Write-Host "   Computername and minion_id DO NOT match" -ForegroundColor Red
	}
	
	Write-Host "Checking number of python processes" -ForegroundColor Yellow
	$PythonCount = get-process | ? { $_.name -eq "python" }
	
	if ($PythonCount) { $PythonCount = ($PythonCount | measure).count }
	else { $PythonCount = 0 }
	
	if ($pythoncount -gt 2) { Write-Host "  There may be a hung python/salt.state process" -foregroundcolor red }
	else { write-host "  Python count seems correct" -ForegroundColor green }
	
	Write-Host "Checking Salt Version" -ForegroundColor yellow
	if (($Version = (salt-call --version).replace("salt-call ", "")) -eq "3003.4") { Write-Host "   Version is correct" -ForegroundColor Green }
	else { Write-Host "   Check Salt Version -- Version = $Version" -ForegroundColor Red }
	
	$MiniondFile = "C:\salt\conf\minion.d\ssnc_minion.conf"
	Write-Host "Checking $MiniondFile Servers" -ForegroundColor yellow
	if (Test-Path $MiniondFile){ get-content C:\salt\conf\minion.d\ssnc_minion.conf | select -skip 1 -first 2 } else { Write-Host "   $MiniondFile Missing" -ForegroundColor Red}
}Else { Write-Host "   SALT NOT INSTALLED!!" -ForegroundColor Red }


Write-Host "Checking System.Net.Sockets.TcpClient" -ForegroundColor Yellow

Write-Host "   Checking network access"

$NetworkPorts = @('System,IP,Port',
	'Artifactory,170.40.40.48,80',
	'Artifactory,170.40.40.48,443',
	'Artifactory-KC,10.222.75.144,443',
	'Artifactory-KC,10.222.75.144,80',
	'Artifactory-YKT,10.239.26.96,443',
	'Artifactory-YKT,10.239.26.96,80',
	'Artifactory-SAC,10.2.160.80,443',
	'Artifactory-SAC,10.2.160.80,80',
	'Artifactory-MUM,10.74.19.242,443',
	'Artifactory-MUM,10.74.19.242,80',
	'Kafka_ES,10.222.34.210,9094',
	'Kafka_ES,10.222.35.203,9094',
	'Kafka_ES,10.222.42.211,9094',
	'Kafka_ES,10.222.43.204,9094',
	'Kafka_ES,10.222.43.212,9094',
	'Kafka_Telegraf,10.225.142.63,9092',
	'Kafka_Telegraf,10.225.142.64,9092',
	'Kafka_Telegraf,10.225.142.65,9092',
	'SaltMast_KC_01,10.222.42.222,4505',
	'SaltMast_KC_01,10.222.42.222,4506',
	'SaltMast_KC_02,10.222.91.105,4505',
	'SaltMast_KC_02,10.222.91.105,4506',
	'SaltMast_Legacy,10.42.117.76,4505',
	'SaltMast_Legacy,10.42.117.76,4506',
	'SaltMast_STL_01,10.234.55.130,4505',
	'SaltMast_STL_01,10.234.55.130,4506',
	'SaltMast_STL_02,10.234.58.39,4505',
	'SaltMast_STL_02,10.234.58.39,4506',
	'SaltMast_YKT_01,10.239.27.74,4505',
	'SaltMast_YKT_01,10.239.27.74,4506',
	'SaltMast_YKT_02,10.239.37.14,4505',
	'SaltMast_YKT_02,10.239.37.14,4506',
	'Zabbix,10.225.142.113,10051',
	'Zabbix,10.225.142.114,10051',
	'Zabbix,10.225.142.115,10051',
	'Zabbix,10.225.142.116,10051',
	'Zabbix,10.225.142.117,10051',
	'WSUS-KC,10.222.35.137,8530',
	'WSUS-YKT,10.239.34.39,8530',
	'WSUS-STL,10.234.28.14,8530') | ConvertFrom-Csv | Select-Object *, Connected

# Create variables for port checks
$Timeout = 1000

foreach ($NetworkPort in $NetworkPorts)
{
	$TCPClient = New-Object -TypeName System.Net.Sockets.TCPClient
	$AsyncResult = $TCPClient.BeginConnect($NetworkPort.IP, $NetworkPort.Port, $null, $null)
	$Wait = $AsyncResult.AsyncWaitHandle.WaitOne($Timeout)
	
	$NetworkPort.Connected = $TCPClient.Connected
	$TCPClient.Close()
}

$NetworkPorts


