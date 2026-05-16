<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	11/7/2022 4:04 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Disable-StaleOpbjects.ps1
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>
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
			$Latency = (Test-Connection $DC.IPAddress -Count 1 -ErrorAction SilentlyContinue).ResponseTIme
			
			$null = $result.Add([PSCustomObject]@{
					RemoteHostIP = $DC.IPAddress
					PortOpened   = $PortTest.PortOpened
					Latency	     = $Latency
					Doamin	     = $DomainName
				})
			
		}
	}
	END
	{
		return $result
	}
}


#get a unique list of domains
$Domains = Get-ADTrust -Filter * -Server admgmt.ssncad.global | select Target, DCIP

#loop through the list of domains
foreach ($Domain in $Domains)
{

	$Domain.DCIP = Test-DomainADWS -DomainName $Domain.Target | Where-Object { $_.PortOpened -eq $true } | sort Latency | select -First 1 -expand RemoteHostIP
	
}



$DaysInactive = 45

$time = (Get-Date).Adddays(-($DaysInactive))

Get-ADComputer -Filter { LastLogonTimeStamp -lt $time } -ResultPageSize 2000 -resultSetSize $null -Properties Name, OperatingSystem, SamAccountName, DistinguishedName, LastLogonDate

