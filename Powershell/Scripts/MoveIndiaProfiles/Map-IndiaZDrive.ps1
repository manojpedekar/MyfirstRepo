# Define the network path root and append the current username
$rootPath = "\\10-57-50-158\IND_Folder_Redirection_UserData\$env:USERNAME"

# Check if Z: drive is already mapped
$drive = Get-WmiObject -Query "SELECT * FROM Win32_MappedLogicalDisk WHERE DeviceID = 'Z:'"

If ($null -eq $drive) {
	Write-Host "Z: drive is not mapped. Checking access to $rootPath..."
	
	# Check if the folder exists
	If (Test-Path $rootPath) {
		$result = net use Z: $rootPath /PERSISTENT:YES
		If ($LASTEXITCODE -eq 0) {
			Write-Host "Z: drive mapped successfully to $rootPath."
		} Else {
			Write-Host "Failed to map Z: drive. net use exited with code $LASTEXITCODE."
		}
	} Else {
		Write-Host "The specified path $rootPath does not exist. Please check the path and try again."
	}
} Else {
	Write-Host "Z: drive is already mapped. No action taken."
}
