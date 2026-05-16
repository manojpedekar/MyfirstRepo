

$DomainData = import-csv .\20220817_183655_ValidateSaltFireeye.csv


$ADDomains = @('ad.dstsystems.com',
	'bostonfinancial.biz',
	'dsths.ad.dstcorp.net',
	'dstinet.ad.he3.dstcorp.net',
	'dstinet1.ad.he1.dstcorp.net',
	'dstinet2.ad.he2.dstcorp.net',
	'external.ad.dstsystems.com',
	'external.bostonfinancial.biz',
	'extranet.bostonfinancial.biz',
	'int.ad.dstsystems.com',
	'SSNC.Global'
)

$OldOS = @('Windows 2000 Server',
	'Windows Server',
	'Windows Server? 2008 Enterprise',
	'Windows Server Standard',
	'Windows Server? 2008 Standard',
	'Windows Server? 2008 Standard without Hyper-V',
	'Windows Server 2003'
)

$result = [System.Collections.ArrayList]::new()

foreach ($Domain in $ADDomains)
{
	$null = $result.Add([PSCustomObject]@{
			Domain        = $Domain
			Total         = ($DomainData | ? { $_.domain -eq $Domain }).count
			NotReachable  = ($DomainData | ? { $_.domain -eq $Domain -and $_.TestPing -eq $false }).count
			NotInScope    = ($DomainData | ? { $_.domain -eq $Domain -and $_.operatingsystem -in $OldOS }).count
			CitrixServers = 0
			PendingSalt   = ($DomainData | ? { $_.domain -eq $Domain -and $_.SaltInstalled -eq $false -and $_.operatingsystem -notin $OldOS }).count
			PendingHX     = ($DomainData | ? { $_.domain -eq $Domain -and $_.HXInstalled -eq $false }).count
			Stale         = ($DomainData | ? { $_.domain -eq $Domain -and $_.Stale -eq $True }).count
		}
	)
}

$result | FT


