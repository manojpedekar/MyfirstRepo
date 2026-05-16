<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	5/15/2024 9:57 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



Function sid2user {
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$sid
	)
	
	$sp = New-Object System.Security.Principal.SecurityIdentifier($sid)
	$user = $sp.Translate([System.Security.Principal.NTAccount])
	$user.Value
}


get-acl | Select-Object -ExpandProperty access | Select-Object *, @{ N = 'ResolvedName'; e = { sid2user -sid $_.IdentityReference } }



$CCUsers = Import-Csv C:\temp\Quincy_TargetUsers.csv | Select-Object *, localpath

ForEach ($ccuser In $ccusers) {
	
	
	
}



$ccuser.Homedirectory.Split("\")[5]




