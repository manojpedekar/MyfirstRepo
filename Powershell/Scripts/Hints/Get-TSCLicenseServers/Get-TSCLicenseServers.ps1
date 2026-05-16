<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	12/9/2022 4:08 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Get-TSCLicenseServers.PS1
	 Version:		1.0
	===========================================================================
	.DESCRIPTION
		A quick PS Script to locate the Terminal Services Licensing servers in a domain
#>



# Get the Configuration DN of your domain
$sConfiguration = ([adsi]"LDAP://rootdse").ConfigurationNamingContext

# Get ADSI object
$oDSE = [adsi]"LDAP://$sConfiguration"

# And looking for commen name TS-Enterprise-License-Server
$oSearcher = New-Object DirectoryServices.DirectorySearcher ($oDSE, "CN=TS-Enterprise-License-Server")
$aLicenseServer = $oSearcher.FindAll()

# Print all
$aLicenseServer | ForEach-Object{ $_.Properties.siteserver }
