<#
	.SYNOPSIS
		Scans a folder structure to identify explicitly assigned permissions
	
	.DESCRIPTION
		Scans a folder structure to identify explicitly assigned permissions
	
	.PARAMETER folderPath
		Specifies the root folder to be scanned for explicit permissions
	
	.PARAMETER logFilePath
		Specifies the output log file.  Results will be in CSV format
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	3/12/2023 3:36 PM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:     	Get-ExplicitFolderPermissions.ps1
		===========================================================================
#>
Param
(
	[Parameter(Mandatory = $true)]
	[ValidateScript({ Test-Path $_ -PathType 'Container' })]
	[string]$folderPath,
	[Parameter(Mandatory = $true)]
	[ValidateScript({ Test-Path $_ -PathType 'Container' })]
	[string]$logFilePath
)

$StartTime = Get-Date

$Results = [PSCustomObject]@{
	permissionsList = [System.Collections.ArrayList]@()
	ExecutionTime = New-TimeSpan
}

Get-ChildItem -Path $folderPath -Directory -Recurse | ForEach-Object {
	#$directory = $_.FullName
	Try {
		$dirSecurity = $_.GetAccessControl()
		
		# Use FilesystemWatcher to flush the directory's metadata to disk before reading it
		$watcher = New-Object System.IO.FileSystemWatcher($_.FullName)
		$watcher.EnableRaisingEvents = $true
		[void]$watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 1000)
		
		# Loop through each access rule in the directory's ACL and add it to the permissions list
		ForEach ($rule In $dirSecurity.GetAccessRules($true, $false, [System.Security.Principal.NTAccount])) {
			$permissions = [PSCustomObject]@{
				FolderPath = $_.FullName
				FileSystemRights = $rule.FileSystemRights
				FolderOwner = $dirSecurity.GetOwner([System.Security.Principal.NTAccount])
				AccessControlType = $rule.AccessControlType
				IdentityReference = $rule.IdentityReference
				IsInherited = $rule.IsInherited
				InheritanceFlags = $rule.InheritanceFlags
				PropagationFlags = $rule.PropagationFlags
			}
			
			[void]$Results.permissionsList.add($permissions)
		}
	} Catch [System.UnauthorizedAccessException] {
		# Ignore directories we can't access or set up logging
	}
}

$EndTime = Get-Date
$Results.ExecutionTime = New-TimeSpan -Start $StartTime -End $EndTime

# Write the permissions list to the log file in CSV format
$Results.permissionsList | Export-Csv -Path $logFilePath -NoTypeInformation -Encoding UTF8

Write-Host "Finished"
