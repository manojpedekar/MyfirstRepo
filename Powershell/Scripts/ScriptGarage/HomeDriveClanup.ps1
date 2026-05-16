<#
	.SYNOPSIS
		A brief description of the HomeDriveClanup.ps1 file.
	
	.DESCRIPTION
		A description of the file.
	
	.PARAMETER HomeDriveRootFolder
		A description of the HomeDriveRootFolder parameter.
	
	.PARAMETER InputFile
		A description of the InputFile parameter.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	1/11/2024 9:46 AM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:
		===========================================================================
#>
Param
(
	[Parameter(Mandatory = $true)]
	[string]$HomeDriveRootFolder,
	[Parameter(Mandatory = $true)]
	[string]$InputFile
)

#  .\HomeDriveCleanup.ps1 -HomeDriveRootFolder D:\Users -InputFile C:\Mydata\MyImportFile.csv

If (!(Test-Path $InputFile)) { Exit }
If (!(Test-Path $HomeDriveRootFolder)) { Exit }

$AllUserHomeDriveData = Import-Csv $InputFile | Where-Object { $_.Server -eq $env:COMPUTERNAME }

If (($AllUserHomeDriveData).count -eq 0) { Exit }

#Create/Import hash tables for lookups
$TermHash = @{ }
$AllUserHomeDriveData | Where-Object { $_.Status -eq 'PositiveTerm' } | ForEach-Object { $TermHash.add($_.FolderName, $_.Status) }

#Create/Import hash tables for lookups
$LegalHoldHash = @{ }
$AllUserHomeDriveData | ? {$_.Hold -eq 'LegalHold'} | ForEach-Object { $LegalHoldHash.add($_.FolderName, $_.Hold) }

$UserFolders = Get-ChildItem $HomeDriveRootFolder | Where-Object ($_.PSIsContainer -eq $true)

ForEach ($UserFolder In $UserFolders) {
	
	If ($TermHash.item($UserFolder.BaseName)) {
		#user is termed and we need to check LH Status
		
		If ($LegalHoldHash.item($UserFolder.BaseName)) {
			#add command to move to LH folder
			continue
		}
		
		#add code to move to delete in a week folder
	}
	
	
	
	
}


D:\Cleanup
D:\Cleanup\LegalHold
D:\Cleanup\Delete_<date>




