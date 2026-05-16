<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	3/21/2024 4:21 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>




<#
# SS-2142 ssnc-baseline/ssnc-win-addpermgrpstoadmins
# Hollis 03/12/2024

Purpose: Add selected perm groups to local administrators group
#    1. Gather information, if server is a DC, stop script
#           -server purpose
#	        -project
#	        -subproject
#	        -servername
#	        -domain
#	        -local administrators group membership
#    2. Form perm- group names
#    3. Foreach perm- group
#            If perm- group is not in local administrators group, add it

Change record
Date             Change
#>

#######################################
#            FUNCTIONS                #
#######################################

<#
	.SYNOPSIS
		Example of getting local group members using PSv2 with ADSI
	
	.DESCRIPTION
		A detailed description of the Get-LocalGroupMemberDetailsV2 function.
	
	.PARAMETER Computer
		The computer name to quety.  Local computer name is the default value.
	
	.PARAMETER LogOnly
		A description of the LogOnly parameter.
	
	.EXAMPLE
		PS C:\> Get-LocalGroupMemberDetailsV2
	
	.EXAMPLE
		PS C:\> Get-LocalGroupMemberDetailsV2 -Computer DSKCUTIL02
	
	.NOTES
		Script created using the capibilities of PS v2 in order to support all possible configurations in the SS&C Environments.
#>
Function Get-LocalGroupMemberDetails {
	[CmdletBinding()]
	Param
	(
		[String]$Computer = $env:COMPUTERNAME
	)
	
	$LocalADSI = [ADSI]"WinNT://$Computer"
	
	$LocalGroups = $LocalADSI.psbase.children | Where-Object { $_.psbase.schemaClassName -eq 'group' }
	
	ForEach ($LocalGroup In $LocalGroups) {
		$LocalGroupName = $LocalGroup.name[0]
		
		$group = [ADSI]$LocalGroup.psbase.Path
		$GroupMembers = $group.psbase.Invoke("Members")
		
		ForEach ($GroupMember In $GroupMembers) {
			$username = $GroupMember.GetType().InvokeMember("Name", 'GetProperty', $null, $GroupMember, $null)
			$userObj = New-Object System.Security.Principal.NTAccount($username)
			
			# Try to translate the object into a SID
			# we catch the error because there are some accounts that dont translate
			# an example of this are accounts that are represneted by a sid or SQL Browser Account
			Try {
				$sid = $userObj.Translate([System.Security.Principal.SecurityIdentifier])
			} Catch {
				# Catch all other exceptions thrown by one of those commands 
				$sid = ""
			}
			
			$props = @{
				'ComputerName' = $Computer;
				'LocalGroup'   = $LocalGroupName;
				'Member'	   = $username;
				'SID'		   = $sid;
				'ObjType'		   = $GroupMember.GetType().InvokeMember("Class", 'GetProperty', $Null, $GroupMember, $Null);
				'ObjPath'		   = $GroupMember.GetType().InvokeMember("ADsPath", 'GetProperty', $Null, $GroupMember, $Null)
			}
			$obj = New-Object -TypeName PSOBject -Property $props
			Write-Output $obj
		}
	}
}

Function Add-DomainToLocal {
	Param
	(
		[String]$LocalGroup,
		[String]$DomainMember,
		[String]$Computer = $env:COMPUTERNAME,
		[String]$Domain = (Get-WmiObject -Namespace root\cimv2 -Class Win32_ComputerSystem).Domain
	)
	
	Try {
		([ADSI]"WinNT://$Computer/$LocalGroup,group").psbase.Invoke("Add", ([ADSI]"WinNT://$Domain/$DomainGroup").path)
	} Catch {
		# Catch all other exceptions thrown by one of those commands
		Return $false
	}
	
	Return $true
}

#######################################
#            SET VARIABLES            #
#######################################

#Set Variables
#Defining these vars upfront will elimnate additional logic below and simplify the code

# Using the internal variable to get the computer name is faster and will not spawn an additional process like hostname will
$SrvName = $env:COMPUTERNAME

$PermGrps = @()
$PermGrps += "perm-$SrvName-admin"

$saltproj = $null
$saltsubproj = $null

$productType = (Get-CimInstance -ClassName Win32_OperatingSystem).ProductType

$saltproj = "{{ salt['grains.get']('ssnc_cloud_project_id') }}"
$saltsubproj = "{{ salt['grains.get']('ssnc_cloud_subproject_id') }}"

$OrigLocGrpMems = Get-LocalGroupMemberDetails | Where-Object { $_.LocalGroup -eq 'Administrators' -and $_.ObjType -eq 'Group' }

#######################################
#            MAIN SCRIPT              #
#######################################

If ($productType -ne 3) {
	Write-Host "Product type is $productType, stopping script" -ForegroundColor Cyan
	exit 1 #replacing the break with an exit statement will eliminate the need for the else statement and clean up the code
}

If ($saltproj) { $PermGrps += "perm-$saltproj-admin"}
If ($saltsubproj) { $PermGrps +=  "perm-$saltsubproj-admin" }

ForEach ($PermGrp In $PermGrps) {
	
	If ($OrigLocGrpMems.Member -contains $PermGrp) {
		Write-Host "$PermGrp is already a member of Administrators" -ForegroundColor Green
	} Else {
		Write-host " Attempting to add $PermGrp to Administrators" -ForegroundColor Cyan
		Add-LocalGroupMember Administrators -Member $PermGrp
		Add-DomainToLocal -LocalGroup Administrators -DomainMember $PermGrp
	}

}
