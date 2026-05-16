<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	1/26/2023 11:54 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
        .Synopsis 
            Gets membership information of local groups in remote computer

        .Description
            This script by default queries the membership details of local administrators group on remote computers. 
			It has a provision to query any local group in remote server, not just administrators group.

        .Parameter ComputerName
            Computer Name(s) which you want to query for local group information

		.Parameter LocalGroupName
			Name of the local group which you want to query for membership information. It queries 'Administrators' group when
			this parameter is not specified

		.Parameter OutputDir
			Name of the folder where you want to place the output file. It creates the output file in c:\temp folder
			this parameter is not used.

        .Example
            Get-LocalGroupMembers.ps1 -ComputerName srvmem1, srvmem2

            Queries the local administrators group membership and writes the details to c:\temp\localGroupMembers.CSV

        .Example
			Get-LocalGroupMembers.ps1 -ComputerName (get-content c:\temp\servers.txt)

		.Example
			Get-LocalGroupMembers.ps1 -ComputerName srvmem1, srvmem2

        .Notes
			Author : Sitaram Pamarthi
			WebSite: http://techibee.com
			Edited 1/26/2023 - dt234083 - V2 script to streamline the effort
#>




[CmdletBinding()]
Param (
	[Parameter(ValueFromPipeline = $true,
			   ValueFromPipelineByPropertyName = $true
			   )]
	[string[]]$ComputerName = $env:ComputerName,
	[Parameter()]
	[string]$LocalGroupName = "Administrators",
	[Parameter()]
	[string]$OutputDir = "C:\scripts\NewKirkAuditv2\Output\$(get-date -Format yyyyMMdd_hhmmss)"
	
)

Function New-AuditEvent {
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$ComputerName,
		[string]$LocalGroupName,
		[string]$Status,
		[string]$MemberType,
		[string]$MemberDomain,
		[string]$MemberName,
		[string]$Source = $env:Computername
	)
	
	$AuditEvent = [PSCustomObject]@{
		ATTESTATION_DESCRIPTION = $ComputerName
		LocalGroupName		    = $LocalGroupName
		Status				    = $Status
		MemberType			    = $MemberType
		MemberDomain		    = $MemberDomain
		MemberName			    = $MemberName
		Source				    = $Source
	}
	
	Return $AuditEvent
}

Function New-FinalListItem {
	Param
	(
		[string]$SYSTEM_APPLICATION_ID,
		[string]$ACCOUNT_ID,
		[string]$EMPLOYEE_ID,
		[string]$ACCOUNT_STATUS,
		[string]$ATTESTATIONDESCRIPTION,
		[string]$AD_GROUP,
		[string]$APPLICATION,
		[string]$APPLICATION_OWNER,
		[string]$APPLICATION_OWNER_EMAIL,
		[string]$SA_OWNER,
		[string]$SA_OWNER_EMAIL
	)
	
	$FinalListItem = [PSCustomObject]@{
		SYSTEM_APPLICATION_ID	  = $SYSTEM_APPLICATION_ID
		ACCOUNT_ID			      = $ACCOUNT_ID
		EMPLOYEE_ID			      = $EMPLOYEE_ID
		ACCOUNT_STATUS		      = $ACCOUNT_STATUS
		"ATTESTATION DESCRIPTION" = $ATTESTATIONDESCRIPTION
		AD_GROUP				  = $AD_GROUP
		APPLICATION			      = $APPLICATION
		APPLICATION_OWNER		  = $APPLICATION_OWNER
		APPLICATION_OWNER_EMAIL   = $APPLICATION_OWNER_EMAIL
		SA_OWNER				  = $SA_OWNER
		SA_OWNER_EMAIL		      = $SA_OWNER_EMAIL
	}
	
	Return $FinalListItem
}

Add-Type -AssemblyName 'System.IO.Compression.FileSystem'

If (!(Test-Path $OutputDir)) { mkdir -Path $OutputDir  | Out-Null}
Write-Verbose "Script will write the output to $OutputFile folder"

$FileList = [System.Collections.ArrayList]@()
$LocalAdmins = [System.Collections.ArrayList]@() #NT_All_Users
$GroupMembers = [System.Collections.ArrayList]@() #NT_Group_Users
$ProcessedList = [System.Collections.ArrayList]@() #NT_Final_Output

$ScriptPath = split-path $MyInvocation.MyCommand.Path -Parent

[void]$FileList.Add("C:\scripts\NewKirkAuditv2\StaticInputs\Get-LocalAdmins-NTDOMAIN.txt")
[void]$FileList.Add($MyInvocation.MyCommand.path)

ForEach ($Computer In $ComputerName) {
	Write-host "Working on $Computer"
	
	If (!(Test-Connection -ComputerName $Computer -Count 1 -Quiet)) {
		Write-Verbose "$Computer is offline. Proceeding with next computer"
		[void]$LocalAdmins.add((New-AuditEvent -ComputerName $Computer -LocalGroupName $LocalGroupName -Status "Offline"))
		Continue
	}
	
	Write-Verbose "Working on $computer"
	Try {
		$group = [ADSI]"WinNT://$Computer/$LocalGroupName"
		$members = @($group.Invoke("Members"))
		Write-Verbose "Successfully queries the members of $computer"
		If (!$members) {
			#Add-Content -Path $OutputFile -Value "$Computer,$LocalGroupName,NoMembersFound"
			[void]$LocalAdmins.add((New-AuditEvent -ComputerName $Computer -LocalGroupName $LocalGroupName -Status "NoMembersFound"))
			Write-Verbose "No members found in the group"
			Continue
		}
	} Catch {
		Write-Verbose "Failed to query the members of $computer"
		#Add-Content -Path $OutputFile -Value "$Computer,,FailedToQuery"
		[void]$LocalAdmins.add((New-AuditEvent -ComputerName $Computer -Status "FailedToQuery"))
		Continue
	}
	
	ForEach ($member In $members) {
		Try {
			$MemberName = $member.GetType().Invokemember("Name", "GetProperty", $null, $member, $null)
			$MemberType = $member.GetType().Invokemember("Class", "GetProperty", $null, $member, $null)
			$MemberPath = $member.GetType().Invokemember("ADSPath", "GetProperty", $null, $member, $null)
			$MemberDomain = $null
			If ($MemberPath -match "^Winnt\:\/\/(?<domainName>\S+)\/(?<CompName>\S+)\/") {
				If ($MemberType -eq "User") {
					$MemberType = "LocalUser"
				} ElseIf ($MemberType -eq "Group") {
					$MemberType = "LocalGroup"
				}
				$MemberDomain = $matches["CompName"]
				
			} ElseIf ($MemberPath -match "^WinNT\:\/\/(?<domainname>\S+)/") {
				If ($MemberType -eq "User") {
					$MemberType = "DomainUser"
				} ElseIf ($MemberType -eq "Group") {
					$MemberType = "DomainGroup"
				}
				$MemberDomain = $matches["domainname"]
				
			} Else {
				$MemberType = "Unknown"
				$MemberDomain = "Unknown"
			}
			[void]$LocalAdmins.add((New-AuditEvent -ComputerName $Computer -LocalGroupName $LocalGroupName -Status "SUCCESS" -MemberType $MemberType -MemberDomain $MemberDomain -MemberName $MemberName))
			
		} Catch {
			Write-Verbose "failed to query details of a member. Details $_"
			#Add-Content -Path $OutputFile -Value "$Computer,,FailedQueryMember"
			[void]$LocalAdmins.add((New-AuditEvent -ComputerName $Computer -MemberType "FailedQueryMember"))
		}
		
	}
}

$OutputFile = Join-Path $OutputDir "NT_All_Users.csv"
$LocalAdmins | Export-Csv -Path $OutputFile -NoTypeInformation
[void]$FileList.Add($OutputFile)

##############################################
#GetGroupMembersNT
##############################################

$DCServer = "tech.newkirk.com"

$DomainGroups = $LocalAdmins | Where-Object { $_.MemberType -eq "DomainGroup" -and $_.Status -eq "SUCCESS"} | Select-Object -Unique MemberName -ExpandProperty MemberName

$OutputFile = Join-Path $OutputDir GetGroupMembers_NT.txt
Add-Content -Path $OutputFile -Value $DomainGroups
[void]$FileList.Add($OutputFile)

ForEach ($DomainGroup In $DomainGroups) {
	$Members = ""
	$Members = Get-ADGroupMember $DomainGroup -server $DCserver -Recursive | Select-Object objectclass, samaccountname, name, @{ n = 'GroupName'; e = { $DomainGroup } }, @{ n = 'Description'; e = { (Get-ADGroup $DomainGroup -Server $DCserver -Properties description).description } }
	
	ForEach ($member In $Members) {
		$UserInfo = $null
		
		$UserInfo = (Get-ADUser $member.samaccountname -server $DCserver -properties *)
		
		$GroupMembers += [PSCustomObject]@{
			Group		     = $DomainGroup
			SAM_Account_Name = $UserInfo.samaccountname
			Display_Name	 = $UserInfo.displayname
			Enabled		     = $UserInfo.enabled
			Description	     = $UserInfo.description
			AD_GROUP		 = "NT_DOMAIN\" + $DomainGroup
		}
	}
}
$OutputFile = Join-Path $OutputDir NT_Group_Users.csv
$GroupMembers | Export-Csv $OutputFile -NoTypeInformation
[void]$FileList.Add($OutputFile)

##############################################
#Write_NT_Output
##############################################


$DateTime = "$(get-date -Uformat "%Y%m%d-%H%M%S")"

ForEach ($U In $LocalAdmins) {
	If ($u.MemberType -ne "DomainGroup") {
		$member = $memdom = $memstat = $server = ""
		$member = $U.MemberName
		$memdom = $U.MemberDomain
		$memstat = $U.Status
		$server = $U.ATTESTATION_DESCRIPTION
		Write-Host "Adding $member on $server" -ForegroundColor Green
		If ($memdom -eq $server) {
			[void]$ProcessedList.add((New-FinalListItem -SYSTEM_APPLICATION_ID "Windows_SOC1_NONEMP" -ACCOUNT_ID $member -ACCOUNT_STATUS $memstat -ATTESTATIONDESCRIPTION $server))
		} Else {
			[void]$ProcessedList.add((New-FinalListItem -SYSTEM_APPLICATION_ID "Windows_SOC1_NONEMP" -ACCOUNT_ID $member -ACCOUNT_STATUS $memstat -ATTESTATIONDESCRIPTION $server -AD_GROUP $memdom))
		}
	} Else {
		ForEach ($G In $GroupMembers) {
			$mgroup = $server = $member = $memstat = $AD_grp = $DOMgrp = ""
			$mgroup = $U.MemberName
			$server = $U.ATTESTATION_DESCRIPTION
			$member = $G.SAM_Account_Name
			$memstat = $G.Enabled
			$AD_grp = $G.AD_GROUP
			$DOMgrp = $G.Group
			If ($G.GROUP -eq $mgroup) {
				[void]$ProcessedList.add((New-FinalListItem -SYSTEM_APPLICATION_ID "Windows_SOC1_NONEMP" -ACCOUNT_ID $member -ACCOUNT_STATUS $memstat -ATTESTATIONDESCRIPTION $server -AD_GROUP $AD_Grp))
				Write-Host "Adding DOMAIN GROUP $mgroup USER $member" -ForegroundColor Cyan
			}
		}
	}
}

$OutputFile = Join-Path $OutputDir "NT_Final_Output_$DateTime.csv"
$ProcessedList | Export-Csv $OutputFile -NoTypeInformation
[void]$FileList.Add($OutputFile)

$today = Get-Date
$YearYYYYQQ = "NT_DOMAIN_Working_Files_{0}Q{1:d2}.zip" -f ($today.Year, [int][math]::Ceiling($today.Month/3))

$OutputFile = Join-Path $OutputDir $YearYYYYQQ

$zip = [System.IO.Compression.ZipFile]::Open($OutputFile, 'create')
$zip.Dispose()

$compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
$zip = [System.IO.Compression.ZipFile]::Open($OutputFile, 'update')
$FileList | ForEach-Object { [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_, (Split-Path $_ -Leaf), $compressionLevel) }
$zip.Dispose()





#region Email Notification

#Create HTML Report
#Common HTML head and styles
$htmlhead = "<!DOCTYPE html>
<html>
<head>
<style>
BODY{font-family: Arial; font-size: 8pt;}
H1{font-size: 16px;text-align:center;}
H2{font-size: 12px;text-align:center;}
H3{font-size: 14px;}
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black; background-color: #6495ED;}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
</style>
<title>Windows_SOC1_NONEMP $YearYYYYQQ</title>
</head>
<body>
<h1>Windows_SOC1_NONEMP $YearYYYYQQ</h1>
<h2>Generated: $today</h2>
<h3>Windows_SOC1_NONEMP $YearYYYYQQ processed Completed</h3>"


$reportbody = "<p>Windows_SOC1_NONEMP $YearYYYYQQ processed Completed</p>"


$htmltail = "</body>
				</html>"

$htmlreport = $htmlhead + $surnamesummaryhtml + $reportbody + $htmltail

#Construct e-mail message
$messageParameters = @{
	Subject = "Windows_SOC1_NONEMP $YearYYYYQQ - $env:COMPUTERNAME - $(Get-Date)"
	Body    = $htmlreport
	From    = "NTDOMAIN@tech.newkirk.com"
	To		= "tricia.adams@sscinc.com"
	bcc	    = "pete.demers@sscinc.com"
	SmtpServer = "mailrelay.ssnc-corp.cloud"
	Attachments = $OutputFile
}

#Send the mail message with associated data
Send-MailMessage @messageParameters -BodyAsHtml -DeliveryNotificationOption Never
#endregion Email Notification



#$date = (get-date).adddays(-45)
#get-adcomputer -filter { passwordlastset -lt $date -and enabled -eq $True -and operatingsystem -like "*Windows*Server*" } | select -ExpandProperty Name



