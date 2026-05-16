<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	7/11/2023 8:22 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Validate-SaltCommunicating
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>


Function Validate-SaltCommunicating {
	$cmd = 'salt-call test.ping'
	$result = Invoke-Expression -Command $cmd
	
	# check if the result of the salt-call test.ping command is True
	If ($result -match 'True') {
		#Write-Output "Salt minion is communicating successfully with the Salt master."
		return $true
	} Else {
		#Write-Output "Salt minion failed to communicate with the Salt master."
		return $false
	}
	
}
