<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	5/10/2024 1:28 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.

	You can use the command line to force stop the service:
	taskkill /F /FI "SERVICES eq wuauserv"


#>

Function Check-Admin {
	# Get the current Windows identity
	$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
	# Create a Windows principal from the current identity
	$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
	# Check if the principal has administrative privileges
	$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	
	If (-not $isAdmin) {
		Write-Host "This script must be run as an administrator." -ForegroundColor Red
		Exit 1
	}
}

Function Search-Updates {
	$updateSession = New-Object -ComObject "Microsoft.Update.Session"
	Try {
		Write-Host "Searching for updates..."
		Return $updateSession.CreateUpdateSearcher().Search($update).Updates
	} Catch {
		Write-Host "Failed to search for updates, retrying..." -ForegroundColor Yellow
		Return $updateSession.CreateUpdateSearcher().Search($update).Updates
	}
}

# Function to safely manage the Windows Update service with timeout for stopping
Function Manage-WindowsUpdateService {
	Param ([string]$action)
	Try {
		If ($action -eq "stop") {
			Write-Host "Stopping the Windows Update service..."
			Stop-Service -Name wuauserv -Force
			$service = Get-Service -Name wuauserv
			$service.WaitForStatus('Stopped', '00:03:00') # 3 minutes timeout
		} ElseIf ($action -eq "start") {
			Write-Host "Starting the Windows Update service..."
			Start-Service -Name wuauserv
		}
	} Catch {
		Write-Host "Could not $action the Windows Update service, exiting" -ForegroundColor Red
		Exit 1
	}
}

# Main script execution

# Check if run as admin, if not exit
Check-Admin

Write-Host "Script is running with administrative privileges..." -ForegroundColor Green

# Define the registry path
$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# Retrieve the WUServer value and store it in a variable
Try {
	$WSUSServer = (Get-ItemProperty -Path $registryPath -Name WUServer).WUServer
	Write-Host "WSUS Server URL: $WSUSServer"
} Catch {
	Write-Error "Could not retrieve WSUS Server URL from registry: $_" 
	Exit 1
}

Manage-WindowsUpdateService -action "stop"

Try {
	Write-Host "Clearing folder C:\Windows\SoftwareDistribution\"
	Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Recurse -Force
} Catch {
	Write-Host "Failed to clear C:\Windows\SoftwareDistribution\, restarting service and exiting"
	Manage-WindowsUpdateService -action "start"
	Exit 1
}

Manage-WindowsUpdateService -action "start"
$updates = Search-Updates
$UpdateCount = $updates.count
If ($UpdateCount -gt 0) { Write-Host "Server needs $UpdateCount updates." -ForegroundColor Yellow }
If ($UpdateCount -eq 0) { Write-Host "No Updates required at this time" -ForegroundColor Green }


Write-Host "Reporting Status to WSUS Server"
Invoke-Expression "wuauclt /reportnow"
