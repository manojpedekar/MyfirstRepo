<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	11/7/2022 3:00 PM
	 Created by:   	DT234083
	 Organization: 	
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



# Fast dedup of large lists
# This method took 41ms to dedup a list of 99,715 IP Addresses
# Select -Unique took 1h 41mn
Measure-Command { ([System.Collections.Generic.HashSet[ipaddress]]$hashsetIP = $Logevents.IP) }