<#
	.SYNOPSIS
		A brief description of the  file.
	
	.DESCRIPTION
		Queries AD for OS with GPO inheritance blocked
	
	.PARAMETER Server
		Specifies the Active Directory Domain Services instance to connect to, by providing one of the following values for a corresponding domain name or directory server. The service may be any of the following: Active Directory Lightweight Domain Services, Active Directory Domain Services or Active Directory snapshot instance.
	
	.PARAMETER SearchBase
		Specifies an Active Directory path to search under.
	
	.PARAMETER WithServers
		True = List only blocked OU's with servers
		False = List all blocked OU's
		
		Default is False

	.EXAMPLE
		.\Test-BlockedOU.ps1 -Server bostonfinancial.biz -SearchBase "dc=bostonfinancial,dc=biz" -WithServers $true

		This will display only the OU and server count of OU's with inheritance blocked that have servers objects

	.EXAMPLE
		.\Test-BlockedOU.ps1 -Server bostonfinancial.biz -SearchBase "dc=bostonfinancial,dc=biz"

		This will display the OU and server count of all OU's with inheritance blocked

	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	9/29/2022 7:08 AM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:     	Test-BlockedOU
		Version:		1.1 20220929
		===========================================================================
#>

#Requires -Module ActiveDirectory
#Requires -Module GroupPolicy

param
(
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $false)]
	[ValidateNotNullOrEmpty()]
	[String]$Server,
	[Parameter(Mandatory = $true,
			   ValueFromPipelineByPropertyName = $false)]
	[ValidateNotNullOrEmpty()]
	[string]$SearchBase,
	[bool]$WithServers = $false
)

BEGIN 
{
	$BlockedOUs = Get-ADOrganizationalUnit -SearchBase $SearchBase -Filter * -Server $Server | ?{ (Get-GPInheritance $_.DistinguishedName).GpoInheritanceBlocked -eq "Yes" } | select -expand DistinguishedName
}
PROCESS
{
	foreach ($BlockedOU in $BlockedOUs)
	{
		$ADServers = Get-ADComputer -filter { operatingsystem -like "*Server*" -and enabled -eq $true } -properties operatingsystem -Searchbase $BlockedOU -server $Server
		if (($WithServers -eq $false) -or ($WithServers -eq $true -and $ADServers.count -gt 0))
		{
			$obj = New-Object PSObject -Property ([ordered]@{
					OU		     = $BlockedOU
					ServersCount = if ($ADServers.count -gt 0) { $ADServers.count }else{ 0 }
				})
			$obj
		}
	}
}
END
{
	
}