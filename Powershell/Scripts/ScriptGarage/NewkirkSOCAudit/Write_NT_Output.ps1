<#
*-----------------------------------------------------------------------------*
* SCRIPT      : Write_NT_Output.ps1
* AUTHOR      : Bill Moxim
* DATE        : 03/31/2021, 07/21/2021
* 			  : 08/09/2021 Added $memstat field for member status in AD
*
* DESCRIPTION : Writes the final output csv for the SOC2 audit and NT_DOMAIN
*				based on user and group outputs from the below script:
*				Get-LocalAdmins.ps1
*				GetGroupMembers.ps1
*				This is a temporary manual process until Gary's regular scripts
* 				can be updated to access the NT_DOMAIN (tech.newkirk.com)
* 
* REQUIREMENT :	Input files	"NT_All_Users.csv" (output from "Get-LocalAdmins.ps1"
*							"NT_Group_Users.csv" (output from "GetGroupMembers.ps1"
* 
*-----------------------------------------------------------------------------*
#>

$DateTime   = "$(get-date -Uformat "%Y%m%d-%H%M%S")"

$WorkFolder = "."

$OutputFile = "NT_Final_Output_$DateTime.csv"
Add-Content -Value "SYSTEM_APPLICATION_ID;ACCOUNT_ID;EMPLOYEE_ID;ACCOUNT_STATUS;ATTESTATION DESCRIPTION;AD_GROUP;APPLICATION;APPLICATION_OWNER;APPLICATION_OWNER_EMAIL;SA_OWNER;SA_OWNER_EMAIL" -Path $OutputFile

$InFileAll  = ".\NT_All_Users.csv"
$InFileGrp  = ".\NT_Group_Users.csv"

$ALLUSERS   = Import-Csv $InFileAll -delimiter ","
$ALLGROUPS  = Import-Csv $InFileGrp -delimiter ";"

ForEach ($U in $ALLUSERS) {
	if ($u.MemberType -ne "DomainGroup") {
		$member=$memdom=$memstat=$server=""
		$member  = $U.MemberName
		$memdom  = $U.MemberDomain
		$memstat = $U.Status
		$server  = $U.ATTESTATION_DESCRIPTION
		Write-Host "Adding $member on $server" -ForegroundColor Green
		if ($memdom -eq $server) {
			Add-Content -Path "$OutputFile" -Value "Windows_SOC1_NONEMP;$member;;$memstat;$server"}
		else {
			Add-Content -Path "$OutputFile" -Value "Windows_SOC1_NONEMP;$member;;$memstat;$server;$memdom"
		}
	}
	else {
		ForEach ($G in $ALLGROUPS) {
			$mgroup=$server=$member=$memstat=$AD_grp=$DOMgrp=""
			$mgroup  = $U.MemberName
			$server  = $U.ATTESTATION_DESCRIPTION
			$member  = $G.SAM_Account_Name
			$memstat = $G.Enabled
			$AD_grp  = $G.AD_GROUP
			$DOMgrp  = $G.Group
			if ($G.GROUP -eq $mgroup) {
				Add-Content -Path "$OutputFile" -Value "Windows_SOC1_NONEMP;$member;;$memstat;$server;$AD_Grp"
				Write-Host "Adding DOMAIN GROUP $mgroup USER $member" -ForegroundColor Cyan
			}
		}
	}	
}			
			
