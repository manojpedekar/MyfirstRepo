<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	6/6/2023 9:42 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Find-MissingComputerObject.PS1
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



Import-Module ActiveDirectory

# Define the name of the computer
$computerName = "YourComputerName"

# Look for the computer in Active Directory
$computer = Get-ADComputer -Identity $computerName -ErrorAction SilentlyContinue

If ($computer) {
	Write-Output "Found computer in Active Directory: $computerName"
} Else {
	# If not found, look for the computer in the AD Recycle Bin
	$deletedComputer = Get-ADObject -filter 'isDeleted -eq $true -and name -like "*DEL:$computerName*"' -includeDeletedObjects -ErrorAction SilentlyContinue
	If ($deletedComputer) {
		Write-Output "Found computer in AD Recycle Bin: $computerName"
	} Else {
		Write-Output "Computer not found: $computerName"
	}
}
