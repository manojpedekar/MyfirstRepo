<#
	.SYNOPSIS
		A brief description of the Connect-PureiSCSI.ps1 file.
	
	.DESCRIPTION
		A description of the file.
	
	.PARAMETER NicIP
		A description of the NicIP parameter.
	
	.PARAMETER Site
		A description of the Site parameter.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	3/8/2024 2:20 PM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:
		===========================================================================
#>
Param
(
	[Parameter(Mandatory = $true)]
	[ipaddress]$NicIP,
	[Parameter(Mandatory = $true)]
	[ValidateSet('KAO', 'NGD')]
	[string]$Site
)


# Retrieve all IP addresses assigned to NICs on this server
$assignedIPs = Get-NetIPAddress | Select-Object -ExpandProperty IPAddress

# Check if $NicIP is in the list of assigned IP addresses
If ($NicIP -notin $assignedIPs) {
	Write-Error "The IP address '$NicIP' is not assigned to any NICs on this server."
	Exit 1
}


switch ($Site) {
	"KAO" {
		# Define the list of IP addresses of the iSCSI target
		$targetIPs = @(
			'10.57.84.6',
			'10.57.84.7',
			'10.57.84.8',
			'10.57.84.9',
			'10.57.84.10',
			'10.57.84.11',
			'10.57.84.12',
			'10.57.84.13',
			'10.57.84.14',
			'10.57.84.15',
			'10.57.84.16',
			'10.57.84.17'
		)
	}
	"NGD" {
		$targetIPs = @(
			'10.136.84.6',
			'10.136.84.7',
			'10.136.84.8',
			'10.136.84.9',
			'10.136.84.10',
			'10.136.84.11',
			'10.136.84.12',
			'10.136.84.13',
			'10.136.84.14',
			'10.136.84.15',
			'10.136.84.16',
			'10.136.84.17'
		)
	}
	default {
		Write-Host "iSCSI Target IPs not set"
		exit 1
	}
}

# Specify the iSCSI target IQN (iSCSI Qualified Name)
$targetIQN = (Get-IscsiTarget | select -First 1).NodeAddress

If (-not ($targetIQN)) {
	Write-Error "N ot able to identify a Target IQN"
	Exit 1
}

ForEach ($ip In $targetIPs) {
	# Connect to the iSCSI target using the specified network adapter on the initiator side
	Connect-IscsiTarget -TargetPortalAddress $ip -NodeAddress $targetIQN -InitiatorPortalAddress $NicIP -IsPersistent $True -IsMultipathEnabled $True	
}

# List all connected iSCSI sessions
Get-IscsiSession




