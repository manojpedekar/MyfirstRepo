<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	11/21/2022 11:55 AM
	 Created by:   	DT234083
	 Organization: 	
	 Filename:      test-ssncdns.ps1
	===========================================================================
	.DESCRIPTION
		This script will test the DNS resolvers on a Windows server to see if one of the 
		BAM servers is being used for name resolution.

		Two salt grains will be set as a result of this script

		dns_check_failed_host
		dns_update_required
		
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

# Salt grain default values
$dns_check_failed_host = $false
$dns_update_required = $false

#################################################
##                Main Script                  ##
#################################################

# Test connectivity to the new DNS servers
foreach ($NS in $NewDNS) {
	try { (nslookup $client $ns | Select-String name).toString().split(":")[1].trim() }
	catch { $dns_check_failed_host = $true }
}

# Set the dns_check_failed_host salt grain 
salt-call grains.setval dns_check_failed_host $dns_check_failed_host

# Query the DNS Servers on the server
$ServerDNSSettings = (Get-WmiObject win32_networkadapterconfiguration -filter "ipenabled = 'true'").DNSServerSearchOrder

# Validate local DNS server settings
foreach ($DNSServer in $ServerDNSSettings) {
	if ($DNStoReplace -contains $DNSServer) { $dns_update_required = $true }
}

# Set the dns_update_required salt grain 
salt-call grains.setval dns_update_required $dns_update_required
   