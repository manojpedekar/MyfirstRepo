<#
*-----------------------------------------------------------------------------*
* SCRIPT      : GetGroupMembersNT.ps1
* AUTHOR      : Bill Moxim
* DATE        : 03/15/2018
* 				03/27/2019 - revised to manage multiple domains
*				07/21/2021 - revised for NT_DOMAIN SOC audit only,
* 							 Changed script name from "GetGroupMembers" to "GetGroupMembersNT"
*   						 Removed all domain options other than NT (NT_DOMAIN)
* 							 Removed parameter requirement
*						
* PARAMETERS  :	none
*
* DESCRIPTION : Retrieves Group Members recursively from a list of group names
*
* DEFINE      : $OutFile - Name of the output file (can stay as default)
*				delimiter = ;
*			  :	$InFile  - Name of the input file (can stay as default)
*				format = single groupname per line
*-----------------------------------------------------------------------------*
#>
cls
Write-Host "`n***********************`n* GetGroupMembers.ps1 *`n***********************`n" -BackgroundColor Green -ForegroundColor Black
Write-Host "DOMAIN: NT`n" -BackgroundColor Blue -ForegroundColor Yellow

$DateTime = "$(get-date -Uformat "%Y%m%d-%H%M%S")"

$InFile	  = "GetGroupMembers_NT.txt"
$OutFile  = "GetGroupMembers_NT_$DateTime.csv"
$DCServer = "tech.newkirk.com" 

if (-NOT (Test-Path $InFile)) { 
	Write-Host "You must have an input file $InFile`n" -BackgroundColor Yellow -ForegroundColor Black
	exit }
if ((Get-Item $InFile).length -eq 0kb) {
	Write-Host "You must have a populated input file $InFile`n" -BackgroundColor Yellow -ForegroundColor Black
	exit }

Add-Content -Value "Group;SAM_Account_Name;Display_Name;Enabled;Description;AD_GROUP" -Path .\$OutFile

$groups = Get-Content $InFile

$results = foreach ($group in $groups) {
	$Members=""
	$Members=Get-ADGroupMember $group -server $DCserver -Recursive | select objectclass, samaccountname, name, @{n='GroupName';e={$group}}, @{n='Description';e={(Get-ADGroup $group -Server $DCserver -Properties description).description}}

	foreach ($member in $Members) { 
		$UserInfo=$adgroup=$output=""

		$UserInfo = (get-aduser $member.samaccountname -server $DCserver -properties *)
		$adgroup = "NT_DOMAIN\"+$group
		$output=$group+";"+$UserInfo.samaccountname+";"+$UserInfo.displayname+";"+$UserInfo.enabled+";"+$UserInfo.description+";"+$adgroup
		write-host $output
		Add-Content -Value $output -Path .\$OutFile
	}	
}
Write-Host "`nOUTPUT FILE: $OutFile`n`n[END OF SCRIPT]`n" -ForegroundColor Green
