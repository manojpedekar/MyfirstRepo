[CmdletBinding()]
Param (
	[Parameter(Mandatory = $true)]
	[string]$DomainName
)

Function Test-DCGC {
	[CmdletBinding()]
	Param
	(
		[string]$dcName
	)
	
	$ldapPath = "LDAP://$dcName"
	$gcAttribute = [System.DirectoryServices.ActiveDirectory.ActiveDirectorySiteLink].AttributeNames | Where-Object { $_ -like "options*" }
	$gcValue = 1
	
	Try {
		$directoryEntry = New-Object System.DirectoryServices.DirectoryEntry($ldapPath)
		$directorySearcher = New-Object System.DirectoryServices.DirectorySearcher($directoryEntry)
		$directorySearcher.Filter = "(&(objectCategory=nTDSDSA)(options:$gcAttribute:1.2.840.113556.1.4.803:=$gcValue))"
		$searchResult = $directorySearcher.FindOne()
		If ($searchResult) {
			$results =  $true
		} Else {
			$results = $false
		}
	} Catch {
		Write-Host "Error: $($_.Exception.Message)"
	} Finally {
		If ($directoryEntry) { $directoryEntry.Dispose() }
	}
	
	Return $results
	
}

$Output = [System.Collections.ArrayList]@()

#Get all domain controllers in the domain
$searcher = New-Object DirectoryServices.DirectorySearcher("(&(objectClass=computer)(objectCategory=computer)(userAccountControl:1.2.840.113556.1.4.803:=8192))")
$searcher.SearchScope = "subtree"
$searcher.PropertiesToLoad.Add("name") | Out-Null
$searcher.PropertiesToLoad.Add("dNSHostName") | Out-Null
$searcher.Filter = "(&(objectClass=computer)(userAccountControl:1.2.840.113556.1.4.803:=8192))"
$searcher.SearchRoot = "LDAP://$DomainName"
$domainControllers = $searcher.FindAll()

# Timeout variables for port checks
$Timeout = 1000

# Test TCP ports for each domain controller
ForEach ($dc In $domainControllers) {
	$dcName = $dc.Properties["name"][0]
	$dcHostname = $dc.Properties["dNSHostName"][0]
	
	$TestResults = @{
		ComputerName = $env:COMPUTERNAME
		ComputerIP   = ([System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) | Where-Object { $_.AddressFamily -eq "InterNetwork" } | Select-Object -First 1).IPAddressToString
		DomainController = $dcHostname
		DCIP = ([System.Net.Dns]::GetHostAddresses($dcHostname) | Where-Object { $_.AddressFamily -eq "InterNetwork" } | Select-Object -First 1).IPAddressToString
		Port		 = $null
		PortState    = $null
	}
	
	If (Test-DCGC -dcName $dcHostname) {
		$adPorts = @(389, 636, 3268, 3269, 53, 88, 445, 139, 9389)
	} Else {
		$adPorts = @(389, 636, 3268, 3269, 53, 88, 445, 139)
	}
	
	ForEach ($port In $adPorts) {
		$TestResults.Port = $port
		
		Try {
			$tcpClient = New-Object System.Net.Sockets.TcpClient
			$portOpened = $tcpClient.ConnectAsync($dcHostname, $port).Wait($Timeout)
			$TestResults.PortState = $portOpened
		} Catch {
			$TestResults.PortState = $false
		}
		$tcpClient.Close()
		$obj = New-Object -TypeName PSObject -Property $TestResults
		[void]$Output.Add($obj)
		$obj
	}
}

$Output | Export-Csv .\dctestoutput.csv -NoTypeInformation -Force