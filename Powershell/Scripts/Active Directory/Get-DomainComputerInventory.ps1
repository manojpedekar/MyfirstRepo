<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	6/28/2023 4:52 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Get-DomainComputerInventory.ps1
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>


Function Get-DomainFromDn {
	<#
	.SYNOPSIS
	    Extracts the domain name from a distinguished name (DN) string.

	.DESCRIPTION
	    The Get-DomainFromDn function parses a distinguished name (DN) string
	    and extracts parts that represent the domain components (DC). It then
	    constructs and returns the domain name in a standard format.

	.PARAMETER dn
	    The distinguished name (DN) string from which to extract the domain.
	    This parameter is mandatory and expects a string input.

	.EXAMPLE
	    PS C:\> Get-DomainFromDn -dn "CN=John Doe,OU=Users,DC=example,DC=com"
	    example.com
	    
	    This example shows how to extract the domain name from a DN string that
	    includes common name (CN), organizational unit (OU), and domain components (DC).

	.NOTES
	    Version:        1.0
	    Author:         dt234083
	    Creation Date:  2/1/2024
	    Purpose/Change: Initial function development

	.OUTPUTS
	    String
	    Returns the domain name derived from the distinguished name (DN).

	#>
	
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$dn
	)
	
	$splitDn = $dn.Split(',')
	$domainParts = @()
	ForEach ($part In $splitDn) {
		If ($part -like "DC=*") {
			$domainPart = $part.Replace("DC=", "")
			$domainParts += $domainPart
		}
	}
	Return ($domainParts -join '.')
}

Function Get-ServerFromDn {
	<#
	.SYNOPSIS
	    Extracts the server name from a distinguished name (DN) string within Domain Controllers.

	.DESCRIPTION
	    The Get-ServerFromDn function parses a distinguished name (DN) string looking for an organizational unit (OU) indicating "Domain Controllers". 
	    If found, it extracts the common name (CN) of the server, which is assumed to be located immediately before the "Domain Controllers" OU in the DN string.

	.PARAMETER dn
	    The distinguished name (DN) string from which to extract the server name.
	    This parameter is mandatory and expects a string input.

	.EXAMPLE
	    PS C:\> Get-ServerFromDn -dn "CN=Server01,OU=Domain Controllers,DC=example,DC=com"
	    Server01
	    
	    This example shows how to extract the server name from a DN string that includes the server CN, Domain Controllers OU, and domain components (DC).

	.NOTES
	    Version:        1.0
	    Author:         dt234083
	    Creation Date:  2/1/2024
	    Purpose/Change: Initial function development

	.OUTPUTS
	    String
	    Returns the server name derived from the distinguished name (DN) if the DN string contains "OU=Domain Controllers". 
	    Returns $null if no such organizational unit is found.

	#>
	
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$dn
	)
	
	$splitDn = $dn.Split(',')
	ForEach ($part In $splitDn) {
		If ($part -like "OU=Domain Controllers") {
			$index = $splitDn.IndexOf($part)
			If ($index -gt 0) {
				$serverPart = $splitDn[$index - 1]
				$serverName = $serverPart.Replace("CN=", "")
				Return $serverName
			}
		}
	}
	Return $null
}

Function Get-ADSiteForIP {
	<#
	.SYNOPSIS
	    Retrieves the Active Directory site associated with a given IP address.

	.DESCRIPTION
	    The Get-ADSiteForIP function checks which Active Directory site an IP address belongs to by searching through subnet objects in the AD configuration partition. 
	    It matches the IP address against the subnets and returns the site associated with the matching subnet.

	.PARAMETER IPAddress
	    The IP address to be checked against the Active Directory subnets.
	    This parameter is mandatory and expects an IPv4 string input.

	.PARAMETER configurationPath
	    The LDAP path to the configuration partition where subnet objects are stored.
	    This parameter is mandatory and expects a string input.

	.EXAMPLE
	    PS C:\> Get-ADSiteForIP -IPAddress "192.168.1.100" -configurationPath "CN=Configuration,DC=example,DC=com"
	    ExampleSite
	    
	    This example demonstrates finding the AD site for an IP address by searching subnets in the specified configuration partition.

	.NOTES
	    Version:        1.0
	    Author:         dt234083
	    Creation Date:  2/1/2024
	    Purpose/Change: Initial function development to retrieve AD site based on IP address.

	.OUTPUTS
	    String
	    Returns the name of the Active Directory site if the IP address falls within a defined subnet.
	    Returns $null if no matching subnet is found.

	#>
	Param (
		[Parameter(Mandatory = $true)]
		[string]$IPAddress,
		[Parameter(Mandatory = $true)]
		[string]$configurationPath
	)
	
	# Create a DirectoryEntry object for the Configuration partition
	$configurationEntry = [ADSI]"LDAP://$configurationPath"
	
	# Create a DirectorySearcher object to find subnets
	$subnetSearcher = New-Object System.DirectoryServices.DirectorySearcher($configurationEntry)
	$subnetSearcher.Filter = "(objectClass=subnet)"
	$subnets = $subnetSearcher.FindAll()
	
	# Convert the IP address to a number for easier comparison
	$ip = [IPAddress]$IPAddress
	$ipBytes = $ip.GetAddressBytes()
	[Array]::Reverse($ipBytes)
	$ipNumber = [BitConverter]::ToUInt32($ipBytes, 0)
	
	ForEach ($subnet In $subnets) {
		# Parse the subnet object's CIDR notation
		$subnetCIDR = $subnet.Properties["cn"][0]
		$subnetParts = $subnetCIDR.Split('/')
		$subnetBaseIP = $subnetParts[0]
		$subnetPrefixLength = $subnetParts[1]
		
		# Convert the subnet base IP to a number for easier comparison
		$subnetBaseIPObject = [IPAddress]$subnetBaseIP
		$subnetBaseIPBytes = $subnetBaseIPObject.GetAddressBytes()
		[Array]::Reverse($subnetBaseIPBytes)
		$subnetBaseIPNumber = [BitConverter]::ToUInt32($subnetBaseIPBytes, 0)
		
		# Calculate the subnet mask
		$subnetMaskNumber = -bnot ([Math]::Pow(2, (32 - $subnetPrefixLength)) - 1)
		
		# Check if the IP address falls within the subnet
		If (($ipNumber -band $subnetMaskNumber) -eq ($subnetBaseIPNumber -band $subnetMaskNumber)) {
			# If it does, return the site name
			Return $subnet.Properties["siteobject"][0].Split(',')[0].Replace("CN=", "")
		}
	}
	
	# If no match was found, return null
	Return $null
}

Function ConvertTo-LdapDn {
	<#
	.SYNOPSIS
	    Converts a domain name into LDAP distinguished name (DN) format.

	.DESCRIPTION
	    The ConvertTo-LdapDn function takes a domain name as input and converts it into its equivalent LDAP distinguished name (DN) representation.
	    Each part of the domain name separated by dots is prefixed with "DC=" to denote domain components, which are then concatenated into a single string.

	.PARAMETER domain
	    The domain name to be converted into LDAP DN format.
	    This parameter is mandatory and expects a string input.

	.EXAMPLE
	    PS C:\> ConvertTo-LdapDn -domain "example.com"
	    DC=example,DC=com
	    
	    This example converts the domain name "example.com" into its LDAP distinguished name format.

	.NOTES
	    Version:        1.0
	    Author:         dt234083
	    Creation Date:  2/1/2024
	    Purpose/Change: Initial function development to convert domain names to LDAP DN format.

	.OUTPUTS
	    String
	    Returns the LDAP distinguished name format of the provided domain name.

	#>
	
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$domain
	)
	
	$dc = $domain.Split(".") | ForEach-Object { "DC=$_" }
	Return $dc -join ','
}

Function Get-PDCServerName {
	<#
	.SYNOPSIS
	    Retrieves the Primary Domain Controller (PDC) server name for a specified domain.

	.DESCRIPTION
	    The Get-PDCServerName function uses DNS resolution to find the primary domain controller (PDC) for the specified domain. 
	    It queries the DNS for the LDAP service record specific to the PDC, and if found, returns the server name of the PDC.

	.PARAMETER domain
	    The domain name for which to find the primary domain controller (PDC).
	    This parameter is mandatory and expects a string input.

	.EXAMPLE
	    PS C:\> Get-PDCServerName -domain "example.com"
	    pdc.example.com
	    
	    This example shows how to retrieve the name of the primary domain controller for the domain "example.com".

	.NOTES
	    Version:        1.0
	    Author:         dt234083
	    Creation Date:  2/1/2024
	    Purpose/Change: Initial function development to find the primary domain controller via DNS.

	.OUTPUTS
	    String
	    Returns the server name of the primary domain controller if found. Returns $null if the DNS query fails or no PDC can be located.

	.LINK
	    URL or further documentation if available
	#>
	
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$domain
	)
	
	Try {
		$ldapServer = Resolve-DnsName -Type A -Name "_ldap._tcp.pdc._msdcs.$Domain"
		Return $ldapServer.PrimaryServer
	} Catch {
		Return $null
	}
	
}

Function Get-DCServers {
	<#
	.SYNOPSIS
	    Retrieves a list of domain controllers for a specified domain, including additional details such as server name, FQDN, site name, and IP address.

	.DESCRIPTION
	    The Get-DCServers function performs a comprehensive search for all domain controllers within a given domain. It utilizes LDAP queries to retrieve each controller's distinguished name, from which it extracts and resolves further details like the server name, FQDN, site affiliation, and IP address. This function relies on several helper functions to parse DNs and resolve site names based on IP addresses.

	.PARAMETER Domain
	    The domain name for which to retrieve the list of domain controllers.
	    This parameter is mandatory and expects a string input.

	.EXAMPLE
	    PS C:\> Get-DCServers -Domain "example.com"
	    This example retrieves details of all domain controllers for "example.com", including their server names, FQDNs, site names, IP addresses, and distinguished names.

	.NOTES
	    Version:        1.0
	    Author:         dt234083
	    Creation Date:  2/1/2024
	    Purpose/Change: Initial function development to retrieve and detail domain controllers in a specified domain.

	.OUTPUTS
	    PSCustomObject
	    Outputs a custom object for each domain controller found, including the following properties:
	    - ServerName: The name of the server.
	    - ServerFQDN: The fully qualified domain name of the server.
	    - SiteName: The site name associated with the server, based on its IP.
	    - ServerIP: The IP address of the server.
	    - ExtractedDomainName: The domain name extracted from the distinguished name.
	    - DistinguishedName: The full distinguished name of the domain controller.

	#>
	
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$Domain
	)
	
	#convert the domain into a DN for use in LDAP Queries
	$ldapDN = ConvertTo-LdapDn $Domain
	
	#Get the name of the PDC for the domain
	$ldapServer = Get-PDCServerName $Domain
	
	#Define the condiguration DN for the domain
	$configurationPathDN = "CN=Configuration,$ldapDN"
	
	#Define LDAP filter for domain controllers
	$ldapFilter = "(&(objectCategory=computer))"
	
	[void][System.Reflection.Assembly]::LoadWithPartialName("System.DirectoryServices.Protocols")
	$ldapConnection = New-Object System.DirectoryServices.Protocols.LdapConnection($ldapServer)
	$searchScope = [System.DirectoryServices.Protocols.SearchScope]::Subtree
	$ldapSearchRequest = New-Object System.DirectoryServices.Protocols.SearchRequest($ldapDN, $ldapFilter, $searchScope, $null)
	
	Try {
		$ldapResponse = $ldapConnection.SendRequest($ldapSearchRequest)
		
		ForEach ($entry In $ldapResponse.Entries) {
			$ServerName = Get-ServerFromDn $entry.DistinguishedName
			$ExtractedDomainName = Get-DomainFromDn $entry.DistinguishedName
			$serverFQDN = $ServerName, $ExtractedDomainName -join '.'
			$siteName = $null
			
			$serverIP = $null
			Try {
				$serverIP = [System.Net.Dns]::GetHostAddresses($serverFQDN) | Where-Object { $_.AddressFamily -eq "InterNetwork" } | Select-Object -First 1 -ExpandProperty IPAddressToString
				$siteName = Get-ADSiteForIP -IPAddress $serverIP -configurationPath $configurationPathDN
			} Catch {
				# Log the error if needed
			}
			
			[PSCustomObject]@{
				ServerName		    = $ServerName
				ServerFQDN		    = $serverFQDN
				SiteName		    = $siteName
				ServerIP		    = $serverIP
				ExtractedDomainName = $ExtractedDomainName
				DistinguishedName   = $entry.DistinguishedName
			}
		}
	} Catch {
		Write-Error $_.Exception.Message
	} Finally {
		$ldapConnection.Dispose()
	}
}


