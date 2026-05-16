<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	3/12/2023 3:36 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Get-BasicShareandACLInfo.ps1
	===========================================================================
	.DESCRIPTION
		Collects a list of the shares and root ACL Information fro non administrative shares.
#>

$SharePerms = [System.Collections.ArrayList]@()
$NTFSPerms = [System.Collections.ArrayList]@()

If (-not (Test-Path C:\temp)) {	mkdir C:\temp }

$Shares = Get-SmbShare | Where-Object { $_.Description -notmatch 'Remote Admin|Default share|Remote IPC' }

ForEach ($Share in $Shares)
{
	$ShareAccessList = Get-SmbShareAccess $Share.name
	
	foreach ($ShareAccess in $ShareAccessList)
	{
		$ShareObject = New-Object -TypeName PSOBject -Property @{
			Server = $env:COMPUTERNAME
			Name   = $ShareAccess.Name
			ScopeName = $ShareAccess.ScopeName
			AccountName = $ShareAccess.AccountName
			AccessControlType = $ShareAccess.AccessControlType
			AccessRight = $ShareAccess.AccessRight
		}
		[void]$SharePerms.Add($ShareObject)
	}
	
	$Access = Try {
		(Get-Acl $Share.Path -ErrorAction SilentlyContinue).Access
	} Catch {
		$NTFSObject = New-Object -TypeName PSOBject -Property @{
			Server = $env:COMPUTERNAME
			Share  = $Share.Name
			Path   = $Share.Path
			FileSystemRights = "DENIED"
			AccessControlType = "DENIED"
			IdentityReference = "DENIED"
			IsInherited = "DENIED"
			InheritanceFlags = "DENIED"
			PropagationFlags = "DENIED"
		}
		
		[void]$NTFSPerms.Add($NTFSObject)
		
		continue
	}
	
	ForEach ($ACL In $Access) {
		$NTFSObject = New-Object -TypeName PSOBject -Property @{
			Server = $env:COMPUTERNAME
			Share  = $Share.Name
			Path   = $Share.Path
			FileSystemRights = $ACL.FileSystemRights
			AccessControlType = $ACL.AccessControlType
			IdentityReference = $ACL.IdentityReference
			IsInherited = $ACL.IsInherited
			InheritanceFlags = $ACL.InheritanceFlags
			PropagationFlags = $ACL.PropagationFlags
		}
		
		[void]$NTFSPerms.Add($NTFSObject)
	}
	
}

$SharePerms | Export-csv C:\Temp\$($env:COMPUTERNAME)_Shares.csv -NoTypeInformation
$NTFSPerms | Export-csv c:\Temp\$($env:COMPUTERNAME)_NTFS.csv -NoTypeInformation
Write-Host "Script output was written to C:\Temp"


