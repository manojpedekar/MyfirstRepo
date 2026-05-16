<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	12/5/2022 12:41 PM
	 Created by:   	DT234083
	 Organization: 	
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>


Measure-Command {
	$BrokenInheritance = New-Object System.Collections.ArrayList
	
	Get-ChildItem D:\Departments -Directory -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable gci_errors | ForEach-Object {
		$tmpACL += Get-Acl $_ -ErrorAction SilentlyContinue -ErrorVariable gacl_errors
		If ($tmpACL.AreAccessRulesProtected) { $BrokenInheritance.add($tmpACL) }
	}
}

$gci_errors | Select-Object -ExpandProperty CategoryInfo | Export-Csv -NoTypeInformation -Path C:\Temp\gci_errors.csv
$gacl_errors | Select-Object -ExpandProperty CategoryInfo | Export-Csv -NoTypeInformation -Path C:\Temp\gacl_errors.csv















$DirectoryList = New-Object System.Collections.ArrayList
$BrokenInheritance = New-Object System.Collections.ArrayList
$AccessErrors = New-Object System.Collections.ArrayList

$Shares = Get-SmbShare | Where-Object { $_.name -notlike "*$" }

ForEach ($Share In $Shares) {
	
	If ($Share.AreAccessRulesProtected) { $BrokenInheritance.Add($Share.Path) } Else {
		
		ForEach ($D In (Get-ChildItem $Share.Path -Directory -Recurse)) {
			Try {
				get-acl $D | Where-Object { $_.AreAccessRulesProtected } | Select-Object @{ Name = "Path"; Expression = { Convert-Path $_.Path } }, AreAccessRulesProtected
			} Catch {
				$AccessErrors += $Error.CategoryInfo
			}
		}
	}
	
}


Get-ChildItem D:\Departments -Directory -Recurse | ForEach-Object {
	$Path = $_.FullName
	try
	{
		(Get-Acl $Path).Access | where { $_.IsInherited -eq $false }
		
	}
	catch
	{
		Write-Error $_
	}
}





dir D:\Departments -Directory -Recurse | ForEach-Object {
	$Path = $_.FullName
	try
	{
		Get-Acl $Path |
		select -ExpandProperty Access |
		where { $_.IsInherited -eq $false } |
		Add-Member -MemberType NoteProperty -Name Path -Value $Path -PassThru
	}
	catch
	{
		$AccessErrors += $_
	}
}










$Spath = "D:\Departments\GoBook\Statistics"
$Spath = "C:\Windows"
Try
{
	[System.IO.Directory]::EnumerateDirectories($Spath, '*.*', 'AllDirectories')
}
catch
{
	$_.Exception.message
	continue
}


<#


	try { dir $Share.Path -Directory -recurse | get-acl | Where { $_.AreAccessRulesProtected } | Select @{ Name = "Path"; Expression = { Convert-Path $_.Path } }, AreAccessRulesProtected }
	catch { $AccessErrors.Add($_.CategoryInfo) }




#>





$DirectoryToSearch = ""
$DirectoryPath = Get-ChildItem -Directory -Path $DirectoryToSearch -Recurse -Force

$Output = @()
ForEach ($Folder in $FolderPath)
{
	$Acl = Get-Acl -Path $Folder.FullName
	ForEach ($Access in $Acl.Access)
	{
		$Properties = [ordered]@{ 'Folder Name' = $Folder.FullName; 'Group/User' = $Access.IdentityReference; 'Permissions' = $Access.FileSystemRights; 'Inherited' = $Access.IsInherited }
		$Output += New-Object -TypeName PSObject -Property $Properties
	}
}
$Output | Out-GridView

