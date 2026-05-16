<#
	.SYNOPSIS
		A script to add SS&C cloud perm groups to windows devices
	
	.DESCRIPTION
		A description of the file.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	3/21/2024 4:21 PM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:		add-localadmins.ps1
		===========================================================================

		# SS-2142 ssnc-baseline/ssnc-win-addpermgrpstoadmins
		# Hollis 03/12/2024
		# Demers 07/23/2024

		Purpose: Add selected perm groups to local administrators group
		#    1. Set functions
		#          Get-LocalGroupMemberDetails
		#          Add-DomainToLocal
		#    2. Set Variables -- servername, Powershell version, project/subproject,  server product type (to filter out Domain Controllers), Administrators group membership
		#    3. Main script
		#        End script if server product type equals 3 (domain controller)
		#        Add project/subproject perm groups to $PermGrps variable if the server has a project/subproject
		#        Foreach perm- group
		#            If perm- group is not in local administrators group, add it

		Change record
		Date             Change
		2024-07-23		 Update script to take arguments for project and subproject -- values will be passed from jinja in the init.sls
						 Clean up code and logic for readability
						 Allow to run on all product types except domain controllers (type 2)
#>

#######################################
#            FUNCTIONS                #
#######################################

Function Get-LocalGroupMemberDetails {
	<#
	.SYNOPSIS
		Example of getting local group members using PSv2 with ADSI
	
	.DESCRIPTION
		A detailed description of the Get-LocalGroupMemberDetailsV2 function.
	
	.PARAMETER Computer
		The computer name to query.  Local computer name is the default value.
	
	.PARAMETER LogOnly
		A description of the LogOnly parameter.
	
	.EXAMPLE
		PS C:\> Get-LocalGroupMemberDetails
	
	.EXAMPLE
		PS C:\> Get-LocalGroupMemberDetails -Computer DSKCUTIL02
	
	#>
	
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
				'ObjType'	   = $GroupMember.GetType().InvokeMember("Class", 'GetProperty', $Null, $GroupMember, $Null);
				'ObjPath'	   = $GroupMember.GetType().InvokeMember("ADsPath", 'GetProperty', $Null, $GroupMember, $Null)
			}
			$obj = New-Object -TypeName PSOBject -Property $props
			Write-Output $obj
		}
	}
}

Function Add-DomainToLocal {
	<#
    .SYNOPSIS
    Adds a domain user or domain group to a local group on a specified computer.

    .DESCRIPTION
    This function adds a domain member (user or group) to a local group on the specified computer.
    If the computer is not specified, it defaults to the current machine. The domain is automatically
    detected from the computer system properties unless provided explicitly.

    .PARAMETER LocalGroup
    The name of the local group to which the domain member will be added.

    .PARAMETER DomainMember
    The name of the domain user or group to be added to the local group.

    .PARAMETER Computer
    The name of the computer where the local group resides. Defaults to the current computer.

    .PARAMETER Domain
    The domain of the domain member. This is automatically determined from the system properties unless specified.

    .EXAMPLE
    Add-DomainToLocal -LocalGroup "Administrators" -DomainMember "DomainGroup"
    Adds the 'DomainGroup' from the detected domain to the 'Administrators' group on the local computer.

    .EXAMPLE
    Add-DomainToLocal -LocalGroup "Administrators" -DomainMember "DomainGroup" -Computer "RemoteServer" -Domain "mydomain.com"
    Adds the 'DomainGroup' from 'mydomain.com' to the 'Administrators' group on 'RemoteServer'.
    #>

	Param
	(
		[String]$LocalGroup,
		[String]$DomainMember,
		[String]$Computer = $env:COMPUTERNAME,
		[String]$Domain = (Get-WmiObject -Namespace root\cimv2 -Class Win32_ComputerSystem).Domain
	)
	
	Try {
		([ADSI]"WinNT://$Computer/$LocalGroup,group").psbase.Invoke("Add", ([ADSI]"WinNT://$Domain/$DomainMember").path)
	} Catch {
		# Catch all other exceptions thrown by one of those commands
		Return $false
	}
	
	Return $true
}

#######################################
#            SET VARIABLES            #
#######################################

# Set Variables
# Computer product type
$productType = (Get-CimInstance -ClassName Win32_OperatingSystem).ProductType

$SrvName = $env:COMPUTERNAME

$PermGrps = @()
$PermGrps += "perm-$SrvName-admin"

$GrainData = (salt-call grains.items --out=json | ConvertFrom-Json).local
$saltproj = $null
$saltsubproj = $null

$saltproj = $GrainData.ssnc_cloud_project_id
$saltsubproj = $GrainData.ssnc_cloud_subproject_id
$domain = $GrainData.domain

$updateperms = $false

#######################################
#            MAIN SCRIPT              #
#######################################

# End script if server product type equals 2 (domain controller)
# validate product type https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem
Switch ($productType) {
	1 {
		# workstation
		# has to be a member of cloudad to add groups
		# if they are not in cloudad.ssncad.global we add nothing
		If ($domain -eq 'cloudad.ssncad.global') {
			$updateperms = $true
		}
	}
	2 {
		# This is Domain Controller and skip
		Write-Output "Product type is $productType, stopping script" 
		Exit 0
	}
	3 {
		# Domain Server always run
		$updateperms = $true
	}
	default {
		# should never get here
	}
}

# Add project/subproject perm groups to $PermGrps variable if the server has a project/subproject
If ($updateperms) {
	$OrigLocGrpMems = Get-LocalGroupMemberDetails | Where-Object { $_.LocalGroup -eq 'Administrators' -and $_.ObjType -eq 'Group' }
	If ($saltproj) { $PermGrps += "perm-$saltproj-admin" } else {Write-Output "Project ID not found"}
	If ($saltsubproj) { $PermGrps += "perm-$saltsubproj-admin" }else {Write-Output "Sub-Project ID not found"}
	
	# Foreach perm- group
	# If perm- group is not in local administrators group, add it
	
	ForEach ($PermGrp In $PermGrps) {
		If ($OrigLocGrpMems.Member -contains $PermGrp) {
			Write-Output "$PermGrp is already a member of Administrators"
		} Else {
			Write-Output "Attempting to add $PermGrp to Administrators" 
			
			Try {
				If ($PSVersionTable.PSVersion.Major -lt 5) {
					Add-DomainToLocal -LocalGroup Administrators -DomainMember $PermGrp
				} Else {
					Add-LocalGroupMember -Group "Administrators" -Member $PermGrp
				}
				Write-Output "Successfully added $PermGrp to Administrators."  
			} Catch {
				Write-Output "Failed to add $PermGrp to Administrators: $_"  
			}
		}
	}
} ELSE {
	Write-Output "Product type is $productType in $domain, no updates to Administrators group"
}