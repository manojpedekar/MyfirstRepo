<#
	.SYNOPSIS
		A brief description of the Validate-SaltAndFireeye.ps1 file.
	
	.DESCRIPTION
		A description of the file.
	
	.PARAMETER HXFile
		File name of the HX Data File
	
	.PARAMETER SaltFile
		File name of the Salt Data File
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	8/1/2022 1:29 PM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:     	Validate-SaltAndFireeye.ps1
		===========================================================================
#>
param
(
	[Parameter(Mandatory = $true,
			   HelpMessage = 'File name of the HX Data File')]
	[string]$HXFile,
	[Parameter(Mandatory = $true,
			   HelpMessage = 'File name of the Salt Data File')]
	[string]$SaltFile
)
# TODO - add params for input files (Fireeye, Salt and domains)
# TODO - Document script better

function Show-ProgressV3
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
		[PSObject[]]$InputObject,
		[string]$Activity = "Processing items"
	)
	
	[int]$TotItems = $Input.Count
	[int]$Count = 0
	
	$Input | foreach {
		$_
		$Count++
		[int]$percentComplete = ($Count/$TotItems * 100)
		Write-Progress -Activity $Activity -PercentComplete $percentComplete -Status ("Working - " + $percentComplete + "%")
	}
}

function Get-DomainDetails
{
	
	[CmdletBinding()]
	param
	(
		[string]$Domain
	)
	
	#Set Vars
	$LAPSInstalled = $false
	
	#Read Domain Data
	$ADForest = Get-ADForest -Server $Domain
	$ADDomain = Get-ADDomain -Server $Domain
	$SchemaExtensions = Get-ADObject -SearchBase ((Get-ADRootDSE).schemaNamingContext) -SearchScope OneLevel -Filter * -Server $Domain
	
	if ($SchemaExtensions | Where-Object { $_.name -eq "ms-mcs-admpwd" }) { $LAPSInstalled = $True }
	
	$props = [ordered]@{
		'Forest' = $ADForest.Name;
		'Domain' = $ADDomain.DNSRoot;
		'NetBIOSName' = $ADDomain.NetBIOSName;
		'Laps_Ext' = $LAPSInstalled;
		'FFL'    = $ADForest.ForestMode;
		'DFL'    = $ADDomain.DomainMode
	}
	$obj = New-Object -TypeName PSOBject -Property $props
	Write-Output $obj
}

function Test-Port
{
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline = $true, HelpMessage = 'Could be suffixed by :Port')]
		[String[]]$ComputerName,
		[Parameter(HelpMessage = 'Will be ignored if the port is given in the param ComputerName')]
		[Int]$Port = 5985,
		[Parameter(HelpMessage = 'Timeout in millisecond. Increase the value if you want to test Internet resources.')]
		[Int]$Timeout = 1000
	)
	
	begin
	{
		$result = [System.Collections.ArrayList]::new()
	}
	
	process
	{
		foreach ($originalComputerName in $ComputerName)
		{
			$remoteInfo = $originalComputerName.Split(":")
			if ($remoteInfo.count -eq 1)
			{
				# In case $ComputerName in the form of 'host'
				$remoteHostname = $originalComputerName
				$remotePort = $Port
			}
			elseif ($remoteInfo.count -eq 2)
			{
				# In case $ComputerName in the form of 'host:port',
				# we often get host and port to check in this form.
				$remoteHostname = $remoteInfo[0]
				$remotePort = $remoteInfo[1]
			}
			else
			{
				$msg = "Got unknown format for the parameter ComputerName: " `
				+ "[$originalComputerName]. " `
				+ "The allowed formats is [hostname] or [hostname:port]."
				Write-Error $msg
				return
			}
			
			$tcpClient = New-Object System.Net.Sockets.TcpClient
			$portOpened = $tcpClient.ConnectAsync($remoteHostname, $remotePort).Wait($Timeout)
			
			$null = $result.Add([PSCustomObject]@{
					RemoteHostname	     = $remoteHostname
					RemotePort		     = $remotePort
					PortOpened		     = $portOpened
					TimeoutInMillisecond = $Timeout
					SourceHostname	     = $env:COMPUTERNAME
					OriginalComputerName = $originalComputerName
				})
		}
	}
	
	end
	{
		return $result
	}
}


function Test-DomainADWS
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $false,
				   ValueFromPipeline = $true,
				   HelpMessage = 'Enter Domain Name')]
		[string]$DomainName
	)
	
	BEGIN
	{
		$result = [System.Collections.ArrayList]::new()
	}
	PROCESS
	{
		$DCs = Resolve-DnsName -Name $DomainName | Where-Object { $_.querytype -ne "NS" -and $_.type -eq "A" -and $_.name -eq $DomainName }
		
		$i = 0
		$TotalItems = $DCs.Count
		
		foreach ($DC in $DCs)
		{
			$i++
			Write-Progress -Activity $DC.Name -PercentComplete ($i / $TotalItems * 100) -Status "DC $i of $TotalItems -- $($DC.IPAddress)"
			$PortTest = Test-Port -ComputerName $DC.IPAddress -Port 9389
			$Latency = (Test-connection $DC.IPAddress -Count 1 -ErrorAction SilentlyContinue).Latency
 			
			$null = $result.Add([PSCustomObject]@{
					RemoteHostIP = $DC.IPAddress
					PortOpened   = $PortTest.PortOpened
					Latency      = $Latency
					Doamin       = $DomainName
				})
			
		}
	}
	END
	{
		return $result
	}
}

Get-Date

$DCTest= [System.Collections.ArrayList]::new()

# Create a hash table from the salt export from Grafana
# Data can be retrievewd from this URL
# https://grafanaprod.ssnc-corp.cloud/grafana/d/DCAklgR7k/salt-discovery?orgId=1
# Besure to include all environments and exclude Linux servers
Write-Progress -Activity "Setting up Salt Hash Table"
$SaltHash = @{}
Import-Csv $SaltFile | ForEach-Object { $SaltHash.add($_."Minion Name", $true) }

# Create a hash table of windows servers reporting into the HX console
# A current list of servers registered in the HX console can be obtained from the Security Team
Write-Progress -Activity "Setting up HX Hash Table"
$HXHash = @{ }
$HXData = Import-Csv $HXFile | ? { $_.os -like "*Windows*Server*" }

# Remove duplicates in the data.  The HX Console presents a list of servers with many duplicates
# LINQ is case sensitive so force everything TOLOWWER()
[Linq.Enumerable]::Distinct([String[]]@($HXData.HostName.tolower())) | ForEach-Object { $HXHash.add($_, $true) }

# Define a date we will consider AD Objects stale
$StaleDate = (Get-Date).AddDays(-60)

#Define the names of OS'es to be considered "Out of scope"
$OldOS = @('Windows 2000 Server',
	'Windows Server? 2008 Enterprise',
	'Windows Server Standard',
	'Windows Server? 2008 Standard',
	'Windows Server? 2008 Standard without Hyper-V',
	'Windows Server 2003'
)

# sscclient01.ssncad.global -- can not connect from DSKCUTIL01

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
	'sscdirect.com',
	'portiahosting.com',
	'advent.com',
	'admgmt.ssncad.global'
)

# Define AD Properties ro query
$ADProps = @(
	'Name',
	'OperatingSystem',
	'OperatingSystemVersion',
	'IPv4Address',
	'LastLogonDate',
	'PasswordLastSet',
	'pwdLastSet',
	'lastLogonTimestamp',
	'CanonicalName',
	'ms-Mcs-AdmPwd',
	'Description'
)

#@{ Name = "TestPing"; Expression = { if ((Test-Port $_.DNSHostName -Port 3389).PortOpened) { $true } else { $false } } },

# Define select statement for AD Data and calculate some values
$ADSelect = @(
	'DistinguishedName',
	'Name',
	'DNSHostName',
	'Enabled',
	'IPv4Address',
	'Description',
	'LastLogonDate',
	'OperatingSystem',
	'OperatingSystemVersion',
	'PasswordLastSet',
	@{ name = "pwdLastSet"; expression = { [datetime]::FromFileTime($_.pwdLastSet) } },
	@{ name = "lastLogonTimestamp"; expression = { [datetime]::FromFileTime($_.lastLogonTimestamp) } },
	@{ Name = "SaltInstalled"; Expression = { If ($SaltHash.Item($_.DNSHostName)) { $true }	else { $false } } },
	@{ Name = "Stale"; Expression = { if ([datetime]::FromFileTime($_.LastLogonTimeStamp) -lt $StaleDate) { $true }	else { $false } } },
	@{ Name = "Path"; Expression = { $_.CanonicalName.Replace("/$($_.name)", "") } },
	@{ Name = "HXInstalled";  Expression = { if ($HXHash.Item($_.Name)) { $true } else { $false } } },
	@{ Name = "LAPS";  Expression = { if ($_."ms-Mcs-AdmPwd") { $true } else { $false } } },
	'Domain'
)

<#
,
	@{ Name = "TestPing"; Expression = { if ((Test-Port $_.DNSHostName -Port 3389).PortOpened) { $true } else { $false } } }

#>

# Define AD Filter for query
$ADFilter = { enabled -eq $true -and OperatingSystem -like "*Windows*server*" }

Remove-Variable Servers -ErrorAction SilentlyContinue

$i = 0
$TotalItems = $ADDomains.Count

# Loop through domains and query data
foreach ($ADDomain in $ADDomains)
{
	$i++
	Write-Progress -Activity "$ADDomain" -PercentComplete ($i / $TotalItems * 100) -Status "Domain $i of $TotalItems -- Testing ADWS Port 9389 Connectivity"
	
	# Test connectivity to all the DCs in the domain so we can ensure we don't try to connect to a server that is not responding'
	$results = Test-DomainADWS -DomainName $ADDomain
	$DCTest += $results
	
	if (($results | Where-Object { $_.PortOpened -eq $true }).count -gt 0)
	{
		Write-Progress -Activity "$ADDomain" -PercentComplete ($i / $TotalItems * 100) -Status "Domain $i of $TotalItems -- Querying Domain Data"
		$RespondingDC = $results | Where-Object { $_.PortOpened -eq $true } | sort Latency | select -First 1
		# Try one or more commands
		try
		{
			$Servers += Get-ADComputer -filter $ADFilter -properties $ADProps -Server $RespondingDC.RemoteHostIP | select *, @{ Name = "Domain"; Expression = { $ADDomain } }
		}
		# Catch all exceptions thrown by one of the commands in the try
		catch
		{
			write-host "There was an isuse querying computer objects in $ADDomain from $($RespondingDC.RemoteHostIP) "
		}
	}
}

Write-Progress -Activity "Finalizing Data" -Status "Post Processing Domain Data"
$DomainData = $Servers | Select $ADSelect | Show-ProgressV3
$TimeStamp = (get-date -format yyyyMMdd_HHmmss)

Write-Progress -Activity "Exporting Data" -Status "Exporting Server Data"
$file = "ValidateSaltFireeye.csv"
$fileTimestamp = $TimeStamp + "_" + [System.IO.Path]::GetFileNameWithoutExtension($file) + ([System.IO.Path]::GetExtension($file))
$DomainData | Export-Csv -Path .\$fileTimestamp -NoTypeInformation

Write-Progress -Activity "Exporting Data" -Status "Exporting DC Data"
$file = "DCTestReults.csv"
$fileTimestamp = $TimeStamp + "_" + [System.IO.Path]::GetFileNameWithoutExtension($file) + ([System.IO.Path]::GetExtension($file))
$DCTest | Export-Csv -Path .\$fileTimestamp -NoTypeInformation

Write-Progress -Activity "Presenting Data" -Status "Output"

$FormattedData = [System.Collections.ArrayList]::new()

# Will add this back in with a switch
# NotReachable = ($DomainData | ? { $_.domain -eq $Domain -and $_.TestPing -eq $false }).count

foreach ($Domain in $ADDomains)
{
	#Get a count of servers not in scopy (32-bit OS)
	$NIS = ($DomainData | ? { $_.domain -eq $Domain -and $_.operatingsystem -in $OldOS }).count
	$null = $FormattedData.Add([PSCustomObject]@{
			Domain = $Domain
			Total  = ($DomainData | ? { $_.domain -eq $Domain }).count
			NotReachable = ($DomainData | ? { $_.domain -eq $Domain -and $_.TestPing -eq $false }).count
			NotInScope = $NIS
			CitrixServers = 0
			PendingSalt = ($DomainData | ? { $_.domain -eq $Domain -and $_.SaltInstalled -eq $false -and $_.operatingsystem -notin $OldOS }).count - $NIS
			PendingHX = ($DomainData | ? { $_.domain -eq $Domain -and $_.HXInstalled -eq $false }).count - $NIS
			Stale  = ($DomainData | ? { $_.domain -eq $Domain -and $_.Stale -eq $True }).count - $NIS
		}
	)
}

$FormattedData | FT


Get-Date
