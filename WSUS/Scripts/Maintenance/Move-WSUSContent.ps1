<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	3/8/2024 12:08 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



# PowerShell script to move WSUS content from D: drive to V: drive

# Define source and destination paths
$sourcePath = "D:\WSUS"
$destinationPath = "V:\WSUS"

# Stop WSUS services to ensure data consistency during the move
Write-Host "Stopping WSUS Service..."
Stop-Service -Name "WsusService" -Force

# Check if the destination directory exists, if not, create it
If (-not (Test-Path -Path $destinationPath)) {
	Write-Host "Creating destination directory..."
	New-Item -Path $destinationPath -ItemType Directory
}

# Use wsusutil.exe to move the content
#Write-Host "Moving WSUS content..."
#$wsusUtilPath = "C:\Program Files\Update Services\Tools\wsusutil.exe"
#& $wsusUtilPath movecontent $destinationPath "$destinationPath\wsus.bak" -skipcopy

# The -skipcopy flag is used because we will manually move the content
# If you want wsusutil.exe to move the content, remove the -skipcopy flag and ensure the source directory is correct.

# Manually move the content if you used the -skipcopy flag
If (Test-Path -Path $sourcePath) {
	Write-Host "Copying content to the new location..."
	robocopy $sourcePath $destinationPath /E /COPYALL /MOVE
}

# Restart WSUS services
Write-Host "Starting WSUS Service..."
Start-Service -Name "WsusService"

Write-Host "WSUS content move completed."
