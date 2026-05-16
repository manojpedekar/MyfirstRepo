<#	
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	5/28/2024 9:50 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	WSUSTools.psm1
	-------------------------------------------------------------------------
	 Module Name:   WSUSTools
	===========================================================================
#>

Function Confirm-Admin {
	<#
		.SYNOPSIS
			Checks if the current user has administrative privileges.
		
		.DESCRIPTION
			This function determines if the script is being executed by a user with administrative privileges. 
			It utilizes the WindowsIdentity class to get the current user's identity, checks the role using 
			WindowsPrincipal, and verifies if the user is part of the Administrator role.
		
		.EXAMPLE
			Confirm-Admin
			This example calls the Confirm-Admin function to verify administrative privileges 
	
			If (-not (Confirm-Admin)) {
				Write-Host "This script must be run as an administrator." -ForegroundColor Red
			}
	
		.NOTES
			Additional information about the function.
	#>
	
	[OutputType([boolean])]
	Param ()
	
	# Get the current Windows identity
	$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
	# Create a Windows principal from the current identity
	$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
	# Check if the principal has administrative privileges
	$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	return $isAdmin
}

Function Search-Updates {
	<#
		.SYNOPSIS
			Searches for available system updates using Windows Update.
		
		.DESCRIPTION
			This function initiates a search for available updates on the Windows operating system.
			It uses the Microsoft.Update.Session COM object to create an update session and perform the search.
			The function attempts to find any updates that match the criteria specified in the `$criteria` variable.
			
			If the initial search fails, it automatically retries the search once and prints a message to the console.
			If successful, it returns a collection of updates found.
		
		.PARAMETER Criteria
			Criteria defined by the Windows Update Searcher API Documentation.
			
			"IsInstalled=0 and Type='Software'": Searches for software updates that are not currently installed.
			
			"IsInstalled=0 and Type='Driver'": Searches for driver updates that are not currently installed.
					
			"IsInstalled=1 and IsHidden=0": Searches for installed updates that are not hidden.
		
		.PARAMETER $update
			Specifies the search criteria for the updates.
			This parameter should be a string detailing specific search filters such as "IsInstalled=0 and Type='Software'"
			or other criteria recognized by Windows Update Search.
		
		.EXAMPLE
			$updateCriteria = "IsInstalled=0 and Type='Software'"
			Search-Updates -Criteria $updateCriteria
			This example searches for all software updates that are not currently installed on the system.
		
		.NOTES
			Ensure that the script is run with sufficient privileges to interact with Windows Update.
			The function may require modifications to handle complex error conditions or multiple retry mechanisms effectively.
	
		.LINK
			https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search
	#>
	
	Param
	(
		[string]$Criteria = $null
	)
	
	$updateSession = New-Object -ComObject "Microsoft.Update.Session"
	Try {
		Write-Host "Searching for updates..."
		Return $updateSession.CreateUpdateSearcher().Search($Criteria).Updates
	} Catch {
		Write-Host "Failed to search for updates, retrying..." -ForegroundColor Yellow
		Return $updateSession.CreateUpdateSearcher().Search($Criteria).Updates
	}
}

Function Set-WindowsUpdateService {
	<#
	.SYNOPSIS
	    Manages the Windows Update Service (wuauserv) by starting or stopping it.

	.DESCRIPTION
	    This function allows you to start or stop the Windows Update service on demand. 
		It supports an action parameter that determines the operation to perform. 
		When stopping the service, it includes a 3-minute timeout to ensure the service stops gracefully. 
		If the service does not stop within the specified time, the script will proceed without changing the service state.

	.PARAMETER action
	    Specifies the action to perform on the Windows Update service. Valid values are "stop" and "start".
	    - "stop": Attempts to stop the Windows Update service and waits up to 3 minutes for the service to stop.
	    - "start": Starts the Windows Update service if it is not already running.

	.EXAMPLE
	    Set-WindowsUpdateService -action "stop"
	    This example stops the Windows Update service, with a timeout of 3 minutes to ensure it stops gracefully.

	.EXAMPLE
	    Set-WindowsUpdateService -action "start"
	    This example starts the Windows Update service if it is not already running.

	.NOTES
	    Ensure that the script is run with administrative privileges to manage the Windows Update service successfully.
	    If the service cannot be started or stopped as requested, the script will output an error message and terminate with an exit code of 1.
	#>
	
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

Function Reset-WSUSClient {
	<#
	.SYNOPSIS
	    Resets the Windows Server Update Services (WSUS) client configuration and checks for updates.

	.DESCRIPTION
	    This function first checks if it is running with administrative privileges and then performs a 
		series of steps to reset the WSUS client. It stops the Windows Update service, clears the update cache, 
		and restarts the service to force a re-check for updates. It retrieves and displays the WSUS server URL 
		from the registry, clears the SoftwareDistribution folder, and then rechecks for updates. Finally, it 
		sends a status report to the WSUS server.

	.NOTES
	    The function requires administrative privileges to execute successfully. It makes modifications to the 
		system registry and file system, which are critical operations.

	    This function is dependent on other custom functions:
	    - Confirm-Admin: Ensures the script is run with administrative privileges.
	    - Set-WindowsUpdateService: Starts and stops the Windows Update service.
	    - Search-Updates: Searches for updates after resetting the WSUS client.

	.EXAMPLE
	    Reset-WSUSClient
	    This example runs the Reset-WSUSClient function, which resets the WSUS client settings, clears the update 
		cache, and checks for new updates.
	#>
	
	
	If (-not (Confirm-Admin)) {
		Write-Host "This script must be run as an administrator." -ForegroundColor Red
		Exit 1
	}
	
	Write-Host "Script is running with administrative privileges..." -ForegroundColor Green
	
	$wsusUri = Get-MyWSUSServer
	
	If ($wsusUri) {
		Write-Host "WSUS Server URL: $wsusUri"
	} Else {
		Write-Error "Could not retrieve WSUS Server URL from registry: $_"
		Exit 1
	}
	
	Set-WindowsUpdateService -action "stop"
	
	Try {
		Write-Host "Clearing folder C:\Windows\SoftwareDistribution\"
		Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Recurse -Force
	} Catch {
		Write-Host "Failed to clear C:\Windows\SoftwareDistribution\, restarting service and exiting"
		Set-WindowsUpdateService -action "start"
		Exit 1
	}
	
	Set-WindowsUpdateService -action "start"
	$updates = Search-Updates
	$UpdateCount = $updates.count
	If ($UpdateCount -gt 0) { Write-Host "Server needs $UpdateCount updates." -ForegroundColor Yellow }
	If ($UpdateCount -eq 0) { Write-Host "No Updates required at this time" -ForegroundColor Green }
	
	Write-Host "Reporting Status to WSUS Server"
	Invoke-Expression "wuauclt /reportnow"
	
}

Function Get-UpdateFiles {
	<#
	.SYNOPSIS
	    Downloads update files from specified URIs to a designated local directory.

	.DESCRIPTION
	    This function downloads a set of update files based on the provided UpdateFile objects. 
		Each UpdateFile object must include a URI pointing to the file location. The function 
		checks if the specified download directory exists, creates it if it doesn't, and then 
		downloads each file to this directory. 

	.PARAMETER UpdateFile
	    An array of Microsoft.UpdateServices.Administration.UpdateFile objects that include the 
		URI of the update files to be downloaded. Each object must have a 'Name' property for the 
		filename and a 'FileUri' property for the file's download URI.

	.PARAMETER DownloadPath
	    The local path where the update files will be downloaded. If the path does not exist, it will be created.

	.EXAMPLE
	    $updateFiles = Get-UpdateMetaData -SearchTerm "EAC55D9B-F7DA-42BF-9540-D0103DFBFFDD"
	    $downloadPath = "C:\Updates"

	    Get-UpdateFiles -UpdateFile $updateFiles.GetInstallableItems().files -DownloadPath $downloadPath
	    This example downloads two update files to the C:\Updates directory.

	.NOTES
	    The function requires the presence of an internet connection and adequate permissions to access the 
		specified URIs and write to the local file system. Errors during the download process are caught and 
		reported, but do not halt the execution of other downloads.
	#>

	Param (
		[Parameter(Mandatory = $true)]
		[Microsoft.UpdateServices.Administration.UpdateFile[]]$UpdateFile,
		[Parameter(Mandatory = $true)]
		[string]$DownloadPath
	)
	
	# Ensure the download directory exists
	If (-not (Test-Path -Path $DownloadPath)) {
		New-Item -ItemType Directory -Path $DownloadPath -Force
	}
	
	# Iterate through each file and download it
	ForEach ($file In $UpdateFile) {
		Try {
			$destinationPath = Join-Path -Path $DownloadPath -ChildPAth $file.Name
			
			Write-Host "Downloading $($file.Name) to $destinationPath..."
			Invoke-WebRequest -Uri $file.FileUri -OutFile $destinationPath
			Write-Host "Download complete: $destinationPath"
		} Catch {
			Write-Error "Failed to download file: $file. Error: $_"
		}
	}
}

Function Import-AssemblyIfNotLoaded {
    <#
    .SYNOPSIS
        Loads a specified .NET assembly into the current application domain based on a partial name.
    .DESCRIPTION
        This function checks if a .NET assembly with a matching partial name is already loaded within the 
        current application domain. If no matching assembly is found, it attempts to load any assembly that 
        matches the partial name. If a matching assembly is already present, no further action is taken.
    .PARAMETER AssemblyNamePartial
        The partial name of the .NET assembly to load. This should be a string without version, culture, or 
        public key token.
    .EXAMPLE
        Import-AssemblyIfNotLoaded -AssemblyNamePartial "System.Xml"
        Attempts to load an assembly with the name 'System.Xml' regardless of its version.
    .NOTES
        This function can potentially load an incorrect version if multiple versions are present. It is 
        designed for scenarios where exact version matching is not feasible.
    #>
	
	Param (
		[string]$AssemblyNamePartial
	)
	
	# Check for any already loaded assembly that matches the partial name
	$assemblyLoaded = [AppDomain]::CurrentDomain.GetAssemblies() |
	Where-Object { $_.FullName -like "$AssemblyNamePartial,*" }
	
	# Load the assembly if it is not already loaded
	If (-not $assemblyLoaded) {
		Try {
			# Attempt to load an assembly with a matching partial name
			$loadedAssembly = [System.Reflection.Assembly]::LoadWithPartialName($AssemblyNamePartial)
			If ($loadedAssembly) {
				Write-Host "Assembly loaded: $($loadedAssembly.FullName)"
			} Else {
				Write-Host "No assembly found with partial name: $AssemblyNamePartial"
			}
		} Catch {
			Write-Host "Failed to load assembly with partial name: $AssemblyNamePartial"
		}
	} Else {
		Write-Host "Assembly is already loaded: $($assemblyLoaded.FullName)"
	}
}


Function Test-IsGuid {
	<#
	.SYNOPSIS
	    Checks if a given string is a valid GUID.

	.DESCRIPTION
	    This function takes a string input and attempts to parse it as a GUID. If the parsing is successful, 
		it indicates that the string is a valid GUID by returning true; otherwise, it returns false. This 
		is useful for validating input data or configuration settings that are expected to be in GUID format.

	.PARAMETER GuidString
	    The string that needs to be tested to determine if it represents a valid GUID.

	.EXAMPLE
	    $isValid = Test-IsGuid -GuidString "123e4567-e89b-12d3-a456-426614174000"
	    This example tests whether the provided string is a valid GUID and stores the result (true or false) 
		in the variable $isValid.

	.EXAMPLE
	    If (Test-IsGuid -GuidString "example-guid-string") {
	        Write-Host "The string is a valid GUID."
	    } Else {
	        Write-Host "The string is not a valid GUID."
	    }
	
	    This example demonstrates how to use the function in a conditional statement to provide feedback based 
		on whether a string is a valid GUID.

	.NOTES
	    This function uses the System.Guid.Parse method from .NET, which throws an exception if the input 
		string is not in a recognized format. Handling this exception allows the function to gracefully return 
		false instead of terminating with an error.
	#>
	
	Param (
		[string]$GuidString
	)
	
	Try {
		[void][System.Guid]::Parse($GuidString)
		#Write-Host "$GuidString is a valid GUID."
		Return $true
	} Catch {
		#Write-Host "$GuidString is not a valid GUID."
		Return $false
	}
}

Function Get-MyWSUSServer {
	<#
	.SYNOPSIS
	    Retrieves the WSUS server URL from the Windows registry.

	.DESCRIPTION
	    This function fetches the URL of the Windows Server Update Services (WSUS) server configured in the system registry. 
		It attempts to retrieve the WUServer registry value from a specific path and converts it into a System.Uri object. 
		If the URL cannot be retrieved, the function returns null and reports an error.

	.EXAMPLE
	    $wsusUri = Get-MyWSUSServer
	    This example retrieves the WSUS server URL as a System.Uri object.
	#>	
	
	# Define the registry path
	$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
	
	# Retrieve the WUServer value and store it in a variable
	Try {
		$WSUSServer = (Get-ItemProperty -Path $registryPath -Name WUServer).WUServer
		$uri = New-Object System.Uri($WSUSServer)
		Return $uri
	} Catch {
		Write-Error "Could not retrieve WSUS Server URL from registry: $_"
		Return $null
	}
}

Function Get-UpdateMetaData {
	<#
	.SYNOPSIS
	    Retrieves update metadata from a WSUS server based on a specified search term.

	.DESCRIPTION
	    This function connects to a WSUS server and retrieves update metadata. It supports 
		searching by GUID for specific updates or by text for a broader search. The function 
		handles different connection protocols (HTTP/HTTPS) based on the server's URI scheme.

	.PARAMETER SearchTerm
	    The GUID of a specific update or a text term to search for updates within the WSUS server.

	.EXAMPLE
	    $updateInfo = Get-UpdateMetaData -SearchTerm "KB4012212"
	    This example retrieves metadata for the update specified by the KB number.
	
		$updateInfo = Get-UpdateMetaData -SearchTerm "EAC55D9B-F7DA-42BF-9540-D0103DFBFFDD"
		This example retrieves metadata for the update specified by the Update ID value.

	.NOTES
	    This function depends on the Get-MyWSUSServer function to obtain the server details and 
		requires the Microsoft.UpdateServices.Administration assembly to be loaded and accessible.
	#>
	
	Param (
		[string]$SearchTerm
	)
	
	$assemblyNamePartial = "Microsoft.UpdateServices.Administration"
	Import-AssemblyIfNotLoaded -AssemblyNamePartial $assemblyNamePartial
	
	# returns a System.Uri object
	$ServerDetails = Get-MyWSUSServer
	
	If ($ServerDetails -eq $null) {
		Write-Host "WSUS Server not available in the registry.  Exiting."
		Exit 1
	}
	
	switch ($ServerDetails.Scheme) {
		"http" {
			$useSSL = $false
		}
		"https" {
			$useSSL = $true
		}
		default {
			$useSSL = $false
		}
	}
	
	Try {
		$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($ServerDetails.Host, $useSSL, [int]$ServerDetails.Port)
	} Catch {
		Write-Error "Failed to connect to WSUS Server: $_"
		return $null 
	}
	
	If (Test-IsGuid -GuidString $SearchTerm) {
		Try {
			$scope = New-Object System.Guid($SearchTerm)
			$updates = $wsus.GetUpdate($scope)
		} Catch {
			Write-Error "Failed to retrieve updates or specific KB: $_"
			Return $null
		}
		
	} Else {
		Try {
			# Define the update scope (adjust these as needed)
			$scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
			$scope.TextIncludes = $SearchTerm
			$updates = $wsus.GetUpdates($scope)
		} Catch {
			Write-Error "Failed to retrieve updates or specific KB: $_"
			Return $null
		}
	}
	
	If ($updates) {
		$updates
	} Else {
		Write-Host "KB Article $SearchTerm is not available on WSUS server $WSUSServer"
		return $null
	}
}

Function Install-WSUSUpdate {
	# List of CAB files
	$cabFiles = "C:\Updates"
	
	# Install each CAB file using DISM
	
	Write-Host "Installing $cab..."
	Start-Process "dism.exe" -ArgumentList "/online /add-package /packagepath:$cabFiles /NoRestart" -Wait -NoNewWindow
	If ($LASTEXITCODE -eq 0) {
		Write-Host "Installed $cab successfully."
		#Remove-Item $cab -Confirm:$false  -- need to fix this line
	} Else {
		Write-Host "Failed to install $cab."
	}
	
}





#$update = Get-UpdateMetaData -SearchTerm "EAC55D9B-F7DA-42BF-9540-D0103DFBFFDD"
#$update = Get-UpdateMetaData -SearchTerm "AA446948-B221-4FDC-A8B9-6FC4C1680A81"
#Get-UpdateFiles -UpdateFile $update.GetInstallableItems().files -DownloadPath C:\Updates

