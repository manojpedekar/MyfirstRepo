<#
	.SYNOPSIS
		A brief description of the Get-LocalGroupMemberDetailsV2.ps1 file.
	
	.DESCRIPTION
		A detailed description of the Get-LocalGroupMemberDetailsV2.ps1 file.
	
	.PARAMETER LogPath
		The directory where the log log file and output file should be written
	
	.PARAMETER LocalGroups
		Local group(s) to check
	
	.PARAMETER InventoryOnly
		Will cause the script to run in Inventory Only mode and no updates to group membership will be performed
	
	.EXAMPLE
		PS C:\> .\Get-LocalGroupMemberDetailsV2.ps1
	
	.NOTES
		Additional information about the file.
#>
[CmdletBinding()]
Param
(
	[ValidateScript({ If ($_) { Test-Path $_ } })]
	[Alias('Path')]
	[string]$LogPath = "c:\audit",
	[String[]]$LocalGroups,
	[switch]$CleanGroup
)

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

Function Test-Allowed {
	Param
	(
		[string[]]$ListWithWildCard,
		[string]$ItemToCompare
	)
	
	$Matched = $false
	
	ForEach ($l In $ListWithWildCard) {
		If ($ItemToCompare -eq $l) { $Matched = $true }
		If ($ItemToCompare -like $l) { $Matched = $true }
	}
	
	Return $Matched
}

Function Remove-Principal {
	Param
	(
		[Parameter(Mandatory = $true)]
		[psobject]$MemberObject
	)
	
	#setup the action Mesage.  False is successful, True is an error
	$ActionMessage = $false
	
	$Computer = $env:COMPUTERNAME
	
	$ADSI = [ADSI]("WinNT://$Computer")
	
	$Group = $ADSI.Children.Find($MemberObject.Localgroup, $MemberObject.Type)
	
	# Try and take action on the principal
	Try {
		$Group.Remove(($MemberObject.Path))
	} Catch {
		# Catch all other exceptions thrown by one of those commands
		$ActionMessage = $true
	}
	
	Return $ActionMessage
}

Function Add-LogMessage {
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$LogMessage,
		[Parameter(Mandatory = $true)]
		[psobject]$MemberObject
	)
	
	# This was an ordered dictionary list, however this requires PS 3.0
	# To Support the lowest version of PS, we need to remove the ordered dictionary list option
	$props = @{
		'DateTime' = Get-Date (Get-Date).ToUniversalTime() -format s;
		'Computer' = $MemberObject.ComputerName;
		'LocalGroup' = $MemberObject.LocalGroup;
		'Member'   = $MemberObject.Member;
		'SID'	   = $MemberObject.SID;
		'Type'	   = $MemberObject.Type;
		'Path'	   = $MemberObject.Path;
		'Message'  = $LogMessage
	}
	
	# We will try and force order on the properties with a select statement
	$obj = New-Object -TypeName PSObject -Property $props | Select-Object DateTime, Computer, LocalGroup, Member, SID, 'Type', Path, Message
	
	Return $obj
}

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
Function Get-LocalGroupMemberDetailsV2 {
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
				"Type"		   = $GroupMember.GetType().InvokeMember("Class", 'GetProperty', $Null, $GroupMember, $Null);
				"Path"		   = $GroupMember.GetType().InvokeMember("ADsPath", 'GetProperty', $Null, $GroupMember, $Null)
			}
			$obj = New-Object -TypeName PSOBject -Property $props
			Write-Output $obj
		}
	}
}

##############################################################
# Begin Main Script
##############################################################

#Create a list of non-standard account names that we will allow
$AllowedList = @('ansible*',
	'ansibleuser*'
)

$LogMessagesTable = @{
	1 = "No Action Taken - This is an allowed perm group"
	2 = "GROUP REMOVED"
	3 = "ERROR - This group remove was unsuccessful"
	4 = "No Action Taken - This is the local Administrator account"
	5 = "No Action Taken - This is likely a Service Account"
	6 = "No Action Taken - this is a mandatory account"
	7 = "No Action Taken - this is a allowed account"
	8 = "No Action Taken - This is a user account -- need to find a way to reconcile the account"
	9 = "USER REMOVED"
}

#Create an array to store events
$EventLog = @()

#Define Log File name -- needs to be fixed for filebeat
$LogFileName = "localadmins.csv"

#get the membership of all the groups
$LocalMembership = Get-LocalGroupMemberDetailsV2

#check groups in the local admin group

ForEach ($item In ($LocalMembership | Where-Object { $_.localgroup -eq "Administrators" })) {
	$FoundAdmin = $false
	Switch ($item.type) {
		"Group" {
			Switch ($item.Member) {
				{ $_ -eq "Exchange Trusted Subsystem" }{ $EventLog += Add-LogMessage -MemberObject $item -LogMessage $LogMessagesTable[1] }					
				{ $_ -like "perm-*" } { $EventLog += Add-LogMessage -MemberObject $item -LogMessage $LogMessagesTable[1] }
				{ $_ -notlike "perm-*" } {
					If ($CleanGroup) {
						# in theory, this command will remove the unwanted group				
						If (Remove-Principal -MemberObject $item) {
							$EventLog += Add-LogMessage -MemberObject $item -LogMessage $LogMessagesTable[2]
						} Else {
							$EventLog += Add-LogMessage -MemberObject $item -LogMessage $LogMessagesTable[3]
						}
					}
				}
				default {
					#<code>
				}
			}
		}
		"User" {
			# Check to see if the user is the local admin.  
			# The account name may not be a standard name, so validate using the Well Known SID
			If ($item.sid -like "S-1-5-*-500") {
				$EventLog += Add-LogMessage -MemberObject $item -LogMessage $LogMessagesTable[4]
				$FoundAdmin = $true
			}
			
			Switch ($item.Member) {
				{ $_ -like "_*" -and $FoundAdmin -eq $false } {
					$EventLog += Add-LogMessage -MemberObject $item -LogMessage $LogMessagesTable[5]
				}
				{ $_ -eq "cloudbase-init" }{
					$EventLog += Add-LogMessage -MemberObject $item -LogMessage $LogMessagesTable[6]
				}
				{ (Test-Allowed -ListWithWildCard $AllowedList -ItemToCompare $_) }{
					$EventLog += Add-LogMessage -MemberObject $item -LogMessage $LogMessagesTable[7]
				}
				default {
					#Log Users -- take no action in the first pass
					If ($FoundAdmin -eq $false) {
						$EventLog += Add-LogMessage -MemberObject $item -LogMessage $LogMessagesTable[8]
					}
				}
			}
		}
		default {
			#We should never get here
		}
	}
}

If (Test-Path $LogPath\$LogFileName) {
	#Log File exists so we will add to it
	($EventLog | ConvertTo-Csv -NoTypeInformation) | Add-Content -Path $LogPath\$LogFileName
} Else {
	#Log File dosn't exist, test if the path exists and if not, create it
	If (!(Test-Path $LogPath)) { new-item $LogPath -itemtype directory | Out-Null }
	#set the log content -- this will write a new file or overwrite an existing file
	($EventLog | ConvertTo-Csv -NoTypeInformation) | Set-Content -Path $LogPath\$LogFileName
}

$EventLog