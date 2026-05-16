Clear-Host

$cred_admgmt_adm = (Get-Credential -Message "Enter Your ADMGMT Credentials" -UserName "ADMGMT\DT234083-adm")
$cred_wss_safeguard = (Get-Credential -Message "Enter Your Safeguard Credentials" -UserName "wss-master\sfgwin01")

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

$Domains = @('ad.dstsystems.com',
	'dsths.ad.dstcorp.net',
	'dstinet.ad.he3.dstcorp.net',
	'dstinet1.ad.he1.dstcorp.net',
	'dstinet2.ad.he2.dstcorp.net',
	'external.ad.dstsystems.com',
	'int.ad.dstsystems.com',
	'dev.ad.testdev.dstcorp.net',
	'test.dstsystems.com',
	'sscdirect.com',
	'ssnc.global',
	'Portiahosting.com')

$Attributes = @('Name',
	'Created',
	'Description',
	'DNSHostName',
	'CanonicalName',
	'IPv4Address',
	'instanceType',
	'LastLogonDate',
	'lastLogonTimestamp',
	'OperatingSystem',
	'OperatingSystemServicePack',
	'PasswordLastSet')

$SelectAttributes = @('TNC_Resolvable', 'TNC_DNSName', 'TNC_DNSNameMatch', 'TNC_IP')

#, @{ N = 'Path'; E = { ($_.CanonicalName).Replace("/$($_.name)", "") } }, @{ N = 'LastLogonUTC'; E = { [DateTime]::FromFileTimeUtc($_.lastLogonTimestamp) } }

Remove-Variable Servers -ErrorAction SilentlyContinue

foreach ($Domain in $Domains)
{
	Write-Host "Querying $Domain"
	$Servers += get-adcomputer -filter { enabled -eq $true -and OperatingSystem -like "*Windows*Server*" } -server $Domain -Properties $Attributes -ErrorVariable err
}

$Servers=$Servers | select *, TNC_Ping, TNC_Resolvable, TNC_DNSName, TNC_DNSNameMatch, TNC_IP, @{ N = 'Path'; E = { ($_.CanonicalName).Replace("/$($_.name)", "") } }, @{ N = 'LastLogonUTC'; E = { [DateTime]::FromFileTimeUtc($_.lastLogonTimestamp) } } -ExcludeProperty CanonicalName, lastLogonTimestamp


$i = 0
$ServerCount = $Servers.count


foreach ($Server in $Servers)
{
	$ProgressPreference = 'Continue'
	$i++
	Write-Progress -Activity "Test-NetConnection" -PercentComplete (($i / $ServerCount) * 100) -Status "Progress-> [math]::round(($i / $ServerCount) * 100,2)" -CurrentOperation "$($Server.DNSHostName) -- $i of $ServerCount"
	
	$ProgressPreference = 'SilentlyContinue'
	$TNC = Test-NetConnection -Port 3389 $Server.DNSHostName
	
	
	if ($TNC.NameResolutionSucceeded -eq $false)
	{
		#if we can not resolve the host name, lets mark it as unresolvable and loop on
		$Server.TNC_Resolvable = $false
		continue
	}
	
	if ($TNC.NameResolutionSucceeded -eq $true)
	{
		$Server.TNC_Resolvable = $true
		$Server.TNC_DNSName = $tnc.AllNameResolutionResults.name
		$Server.TNC_IP = $tnc.AllNameResolutionResults.IPAddress
		
		if ($tnc.AllNameResolutionResults.name -eq $Server.DNSHostName)
		{
			$Server.TNC_DNSNameMatch = $true
		}		
	}
}



			
			