<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	11/4/2022 12:22 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Update-DNSResolvers.ps1
	 Version:		1.2
	===========================================================================
	.DESCRIPTION
		A script to replace ols BEM DNS servers with new unicast dns servers
#>

#################################################
##                  Setup                      ##
#################################################

# Define the DNS Server Settings to replace
$DNStoReplace = @('10.225.66.4',
'10.225.66.5',
'192.168.186.38',
'192.168.186.39',
'10.224.2.134',
'10.224.2.135',
'10.192.75.72',
'10.193.75.72',
'10.194.75.71',
'10.194.75.72',
'10.225.79.150',
'172.27.20.254',
'172.27.183.250',
'10.118.1.200',
'10.118.5.200',
'10.192.75.74',
'170.40.27.237',
'10.193.75.74',
'170.40.83.128',
'192.168.187.74',
'192.168.187.72',
'192.168.187.73',
'10.243.2.71',
'10.243.2.72')

# Define the new DNS settings
$NewDNS = "170.40.0.100", "170.40.127.100"

# Variable to validate DNS connectivity
$DNSConnectivity = $true

# DNS Resolver information
$client = "www.dstsystems.com"

#################################################
##                Main Script                  ##
#################################################

#test connectivity to the new DNS servers
ForEach ($NS In $NewDNS) {
	Try { (nslookup $client $ns | Select-String name).toString().split(":")[1].trim() }
	Catch { $DNSConnectivity = $false }
}

If ($DNSConnectivity)
{
	# Save this info for rollback
	$NICS = Get-WmiObject win32_networkadapterconfiguration -filter "ipenabled = 'true'"
	
	# Remove dns servers that we do not need to replace to see if we have one of the servers that needs to be replaced
	# We are using this method to ensure compatibility with .NET 2.0
	ForEach ($NIC In $NICS) {
		
		#save the old dns in case we need to roll back
		$olddns = $NIC.SetDNSServerSearchOrder
		
		#set the update flag to $false
		$UpdateDNS = $false
		
		ForEach ($DNSValue In $NIC.DNSServerSearchOrder) {
			#set the update flag to $true if the NIC is configured to use the DNS servers to be replaced
			If ($DNStoReplace -contains $DNSValue) { $UpdateDNS=$true }
		}
		
		# Test to see if the update flag is set
		If ($UpdateDNS) {
			# Set the value of the dns resolvers on the system
			Try {
				# Update the DNS settings
				$NIC.SetDNSServerSearchOrder($newdns)
				[System.Net.Dns]::GetHostByName("ad.dstsystems.com")
				salt-call grains.setval dns_check_failed_host false
				salt-call grains.setval dns_update_required false
			} Catch [System.Net.Sockets.SocketException] {
				Write-Host "System.Net.Sockets.SocketException, rolling back"
				$NIC.SetDNSServerSearchOrder($olddns)
				salt-call grains.setval dns_check_failed_host SocketError
			} Catch {
				Write-Host "Unspecified Error, Rolling back"
				$NIC.SetDNSServerSearchOrder($olddns)
				salt-call grains.setval dns_check_failed_host true
			}
		}
	}
}


# We could not connect to one or more DNS servers
# Set the salt grain to note the failure
if(-not $DNSConnectivity) { salt-call grains.setval dns_check_failed_host true  }

