<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	8/18/2022 11:56 AM
	 Created by:   	DT234083
	 Organization: 	
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

# Define domains to query
$ADDomains = @('ad.dstsystems.com',
	'bostonfinancial.biz',
	'dev.ad.testdev.dstcorp.net',
	'dsths.ad.dstcorp.net',
	'dstinet.ad.he3.dstcorp.net',
	'dstinet1.ad.he1.dstcorp.net',
	'dstinet2.ad.he2.dstcorp.net',
	'external.ad.dstsystems.com',
	'external.bostonfinancial.biz',
	'extranet.bostonfinancial.biz',
	'int.ad.dstsystems.com',
	'globeop.com',
	'ssnc.global',
	'ssnc-corp.global',
	'cloudad.ssncad.global'
)

$WindowsServers = Import-Csv .\20220818_164828_ValidateSaltFireeye.csv |  select *, IsVM
$VMData = import-csv '.\Active VMs-data-2022-08-18 10_27_44.csv' | ? { $_.osconfigfullname -like "*windows*server*" } | select vm_name, dns_name, powerstate

#Create VMHashTables
$VMShortNameHash = @{ }
$VMFQDNHash = @{ }

#populate the $VMShortNameHash 
foreach ($VM in $VMData)
{

	# Try one or more commands
	try {
		$VMShortNameHash.add($VM.vm_name, $VM.powerstate)
	}

	# Catch all other exceptions thrown by one of those commands
	catch
	{
		
	}

}

#populate the $VMFQDNHash 
foreach ($VM in ($VMData | Where-Object { $_.dns_name -ne "" }))
{
	
	# Try one or more commands
	try
	{
		$VMFQDNHash.add($VM.dns_name, $VM.powerstate)
	}
	
	# Catch all other exceptions thrown by one of those commands
	catch
	{
		
	}
	
}


foreach ($Server in $WindowsServers)
{
	$VMMatched = $false
	
	if ($VMShortNameHash.Item($Server.Name))
	{
		$VMMatched = $true
		$Server.IsVM = $VMShortNameHash.Item($Server.Name)
	}
	
	if ($VMFQDNHash.Item($Server.DNSHostName) -and $VMMatched -eq $false)
	{
		$VMMatched = $true
		$Server.IsVM = $VMFQDNHash.Item($Server.DNSHostName)
	}
	
	if ($VMMatched -eq $false)
	{
		$Server.IsVM = $VMMatched
	}
}

$FormattedData = [System.Collections.ArrayList]::new()
foreach ($Domain in $ADDomains)
{
	$null = $FormattedData.Add([PSCustomObject]@{
			Domain = $Domain
			Total  = ($WindowsServers | ? { $_.domain -eq $Domain }).count
			NotReachable = ($WindowsServers | ? { $_.domain -eq $Domain -and $_.TestPing -eq $false }).count
			NotInScope = ($WindowsServers | ? { $_.domain -eq $Domain -and $_.operatingsystem -in $OldOS }).count
			CitrixServers = 0
			PendingSalt = ($WindowsServers | ? { $_.domain -eq $Domain -and $_.SaltInstalled -eq $false -and $_.operatingsystem -notin $OldOS }).count
			PendingHX = ($WindowsServers | ? { $_.domain -eq $Domain -and $_.HXInstalled -eq $false }).count
			Stale  = ($WindowsServers | ? { $_.domain -eq $Domain -and $_.Stale -eq $True }).count
			
		}
	)
}

$FormattedData | FT

