<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	7/15/2022 12:38 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Add-DomainGroupToLocaGroup.ps1
	===========================================================================
	.DESCRIPTION
		Quick Script to add domain security groups to local security groups
#>

#===============================================================================
# Script Functions
#===============================================================================

Function Test-CommandExists
{
	# Simple function to test for a powershell command
	Param ($command)
	$oldPreference = $ErrorActionPreference
	$ErrorActionPreference = 'stop'
	
	try { if (Get-Command $command) { $true } }
	Catch { $false }
	Finally { $ErrorActionPreference = $oldPreference }
}



#get the local computer name
$Computer = $env:COMPUTERNAME

#define the local and domain groups to be updated
$Groups = @("LocalGroup,DomainGroup,Status";
	"Administrators,perm-$($env:COMPUTERNAME)-admin,";
	"Remote Desktop Users, perm-$($env:COMPUTERNAME)-rdp,") | ConvertFrom-Csv

#Determine what domain this computer is joined to
if (Test-CommandExists -command Get-CimInstance){
	$objDomain = (Get-CimInstance -ClassName win32_computersystem).Domain
}else { $objDomain = (Get-WmiObject -Class win32_computersystem).Domain }

#validate we have a domain from the computer
if ($objDomain)
{
	#loop through groups to be updated
	foreach ($Group in $Groups)
	{
		#Query the local group using ADSI
		$localGroup = [ADSI]"WinNT://$Computer/$($Group.LocalGroup),group"
		
		#Get a list of local group members
		$LocalMembers = ((@($localGroup.psbase.Invoke("Members"))) | foreach { $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null) })
		
		#test if the group already contains the domain group
		If ($LocalMembers -notcontains $Group.DomainGroup)
		{
			#add domain group to the local group
			$localGroup.Add("WinNT://$ObjDomain/$($Group.DomainGroup)")
			$Group.Status = "Added"
		}Else{$Group.Status = "Present"}
	}
}

return $Groups

