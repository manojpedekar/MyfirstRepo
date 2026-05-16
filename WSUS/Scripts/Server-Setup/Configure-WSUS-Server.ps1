<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	1/14/2024 9:48 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>


Function Install-WIDService {
	Try {
		# Check if the Windows Internal Database is already installed
		$widFeature = Get-WindowsFeature -Name Windows-Internal-Database
		
		If ($widFeature.InstallState -eq "Installed") {
			Write-Verbose "Windows Internal Database is already installed."
			Return $widFeature.InstallState
		}
		
		# Install the Windows Internal Database
		$installationResult = Install-WindowsFeature -Name Windows-Internal-Database -IncludeManagementTools
		
		# Check the result of the installation
		If ($installationResult.Success -eq $true) {
			Write-Verbose "Windows Internal Database installed successfully."
		} Else {
			Write-Error "Failed to install Windows Internal Database."
		}
		
		Return $installationResult.InstallState
	} Catch {
		Write-Error "An error occurred: $_"
		Return "Failed"
	}
}


Function Change-DriveLetter {
	Param (
		[Parameter(Mandatory = $true)]
		[string]$CurrentDriveLetter,
		[Parameter(Mandatory = $true)]
		[string]$NewDriveLetter
	)
	
	Try {
		# Ensure drive letters end with a colon
		$CurrentDriveLetter = $CurrentDriveLetter.TrimEnd(':') + ':'
		$NewDriveLetter = $NewDriveLetter.TrimEnd(':') + ':'
		
		# Get the volume that matches the current drive letter
		$volume = Get-CimInstance -ClassName Win32_Volume | Where-Object { $_.DriveLetter -eq $CurrentDriveLetter }
		
		If ($null -eq $volume) {
			Write-Error "Volume with drive letter $CurrentDriveLetter not found."
			Return
		}
		
		# Change the drive letter
		$volume | Set-CimInstance -Property @{ DriveLetter = $NewDriveLetter }
		
		# Verify the change
		$updatedVolume = Get-CimInstance -ClassName Win32_Volume | Where-Object { $_.DeviceID -eq $volume.DeviceID }
		If ($updatedVolume.DriveLetter -eq $NewDriveLetter) {
			Write-Host "Drive letter changed from $CurrentDriveLetter to $NewDriveLetter successfully."
		} Else {
			Write-Error "Failed to change drive letter."
		}
	} Catch {
		Write-Error "An error occurred: $_"
	}
}

# Function to set the drive letter
Function Set-DriveLetter {
	Param (
		$Partition,
		$DesiredLetter
	)
	
	$currentLetter = ($Partition | Get-Partition).DriveLetter
	If ($currentLetter -ne $DesiredLetter.TrimEnd(':')) {
		$Partition | Set-Partition -NewDriveLetter $DesiredLetter
		Write-Host "Drive letter set to $DesiredLetter"
	} Else {
		Write-Host "Drive letter is already set to $DesiredLetter"
	}
}


Function Set-WSUSDisks {
	# Get all raw disks
	$rawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' }
	
	# Initialize disks as GPT
	$rawDisks | ForEach-Object { Initialize-Disk -Number $_.Number -PartitionStyle GPT }
	
	# Sort the disks based on size (smallest to largest)
	$sortedDisks = $rawDisks | Sort-Object Size
	
	# Check if we have at least two disks
	If ($sortedDisks.Count -lt 2) {
		Write-Error "At least two raw disks are required."
		Exit
	}
	
	# Assign drive letters
	# D:\ to the smaller disk
	# W:\ to the larger disk
	$smallDisk = $sortedDisks[0]
	$largeDisk = $sortedDisks[1]
	
	# Create a partition and format the smaller disk
	$smallPartition = New-Partition -DiskNumber $smallDisk.Number -UseMaximumSize -AssignDriveLetter
	$smallPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel "WSUS Data" -Confirm:$false -AllocationUnitSize 65536
	Set-DriveLetter -Partition $smallPartition -DesiredLetter "E"
	
	# Create a partition and format the larger disk
	$largePartition = New-Partition -DiskNumber $largeDisk.Number -UseMaximumSize -AssignDriveLetter
	$largePartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel "WSUS Binaries" -Confirm:$false
	Set-DriveLetter -Partition $largePartition -DesiredLetter "W"
	
	Write-Host "Disk setup completed."
}





Change-DriveLetter -CurrentDriveLetter 'D:' -NewDriveLetter 'Z:'
Set-WSUSDisks

Install-WIDService









Function Copy-WIDFolder {
	Param (
		[string]$destinationPath = "E:\WID"
	)
	
	Try {
		# Source path of the WID folder
		$sourcePath = "C:\Windows\WID"
		
		# Check if the source folder exists
		If (-not (Test-Path -Path $sourcePath)) {
			Write-Error "Source WID folder does not exist at $sourcePath"
			Return
		}
		
		# Create destination directory if it does not exist
		If (-not (Test-Path -Path $destinationPath)) {
			New-Item -ItemType Directory -Path $destinationPath
		}
		
		# Copy the folder with content and preserve the permissions (ACLs)
		Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Container -Force -PassThru -Verbose
		
		Write-Host "WID folder copied successfully to $destinationPath"
	} Catch {
		Write-Error "An error occurred: $_"
	}
}






