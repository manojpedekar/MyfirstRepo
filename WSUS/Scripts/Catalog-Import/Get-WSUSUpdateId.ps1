<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	12/6/2023 3:48 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>


Function Get-UniqueArticles {
	Param (
		[string]$FilePath
	)
	
	$content = Get-Content -Path $FilePath
	# Regex patterns for KB and MS articles
	$kbPattern = "KB\d+"
	$msPattern = "MS\d{2}-\d{3,}"
	
	# Find all matches for KB and MS articles
	$kbMatches = Select-String -InputObject $content -Pattern $kbPattern -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }
	$msMatches = Select-String -InputObject $content -Pattern $msPattern -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }
	
	# Combine KB and MS matches
	$combinedMatches = $kbMatches + $msMatches
	
	# Select unique articles only
	$uniqueArticles = $combinedMatches | Sort-Object | Get-Unique
	
	Return $uniqueArticles
}


Function Validate-WSUSID {
	Param
	(
		[Parameter(Mandatory = $true)]
		[guid]$updateID
	)
	
	Try {
		$wsusUpdate = Get-WsusUpdate -UpdateId $updateID -ErrorAction Stop
		
		If ($wsusUpdate) {
			Return $true
		} Else {
			Return $false
		}
	} Catch {
		Write-Host "   - Error: Update with ID $updateID not found." -ForegroundColor Yellow
		Return $false
	}
}


Function ImportUpdateToWSUS {
<#
.SYNOPSIS
Powershell script to import an update, or multiple updates into WSUS based on the UpdateID from the catalog.

.DESCRIPTION
This script takes user input and attempts to connect to the WSUS server.
Then it tries to import the update using the provided UpdateID from the catalog.

.INPUTS
The script takes WSUS server Name/IP, WSUS server port, SSL configuration option and UpdateID as input. UpdateID can be viewed and copied from the update details page for any update in the catalog, https://catalog.update.microsoft.com. 

.OUTPUTS
Writes logging information to standard output.

.EXAMPLE
# Use with remote server IP, port and SSL
.\ImportUpdateToWSUS.ps1 -WsusServer 127.0.0.1 -PortNumber 8531 -UseSsl -UpdateId 12345678-90ab-cdef-1234-567890abcdef

.EXAMPLE
# Use with remote server Name, port and SSL
.\ImportUpdateToWSUS.ps1 -WsusServer WSUSServer1.us.contoso.com -PortNumber 8531 -UseSsl -UpdateId 12345678-90ab-cdef-1234-567890abcdef

.EXAMPLE
# Use with remote server IP, defaultport and no SSL
.\ImportUpdateToWSUS.ps1 -WsusServer 127.0.0.1  -UpdateId 12345678-90ab-cdef-1234-567890abcdef

.EXAMPLE
# Use with localhost default port
.\ImportUpdateToWSUS.ps1 -UpdateId 12345678-90ab-cdef-1234-567890abcdef

.EXAMPLE
# Use with localhost default port, file with updateID's
.\ImportUpdateToWSUS.ps1 -UpdateIdFilePath .\file.txt


.NOTES  
# On error, try enabling TLS: https://learn.microsoft.com/mem/configmgr/core/plan-design/security/enable-tls-1-2-client

# Sample registry add for the WSUS server from command line. Restarts the WSUSService and IIS after adding:
reg add HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\.NETFramework\v4.0.30319 /V SchUseStrongCrypto /T REG_DWORD /D 1

## Sample registry add for the WSUS server from PowerShell. Restarts WSUSService and IIS after adding:
$registryPath = "HKLM:\Software\Microsoft\.NETFramework\v4.0.30319"
$Name = "SchUseStrongCrypto"
$value = "1" 
if (!(Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}
New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType DWORD -Force | Out-Null
Restart-Service WsusService, w3svc

# Update import logs/errors are under %ProgramFiles%\Update Services\LogFiles\SoftwareDistribution.log

#>
	
	Param (
		[Parameter(Mandatory = $false, HelpMessage = "Specifies the name of a WSUS server, if not specified connects to localhost")]
		# Specifies the name of a WSUS server, if not specified connects to localhost.
		[string]$WsusServer,
		[Parameter(Mandatory = $false, HelpMessage = "Specifies the port number to use to communicate with the upstream WSUS server, default is 8530")]
		# Specifies the port number to use to communicate with the upstream WSUS server, default is 8530.
		[ValidateSet("80", "443", "8530", "8531")]
		[int32]$PortNumber = 8530,
		[Parameter(Mandatory = $false, HelpMessage = "Specifies that the WSUS server should use Secure Sockets Layer (SSL) via HTTPS to communicate with an upstream server")]
		# Specifies that the WSUS server should use Secure Sockets Layer (SSL) via HTTPS to communicate with an upstream server.
		[Switch]$UseSsl,
		[Parameter(Mandatory = $true, HelpMessage = "Specifies the update Id we should import to WSUS", ParameterSetName = "Single")]
		# Specifies the update Id we should import to WSUS
		[ValidateNotNullOrEmpty()]
		[String]$UpdateId,
		[Parameter(Mandatory = $true, HelpMessage = "Specifies path to a text file containing a list of update ID's on each line", ParameterSetName = "Multiple")]
		# Specifies path to a text file containing a list of update ID's on each line.
		[ValidateNotNullOrEmpty()]
		[String]$UpdateIdFilePath
	)
	
	Set-StrictMode -Version Latest
	
	# set server options
	$serverOptions = "Get-WsusServer"
	If ($psBoundParameters.containsKey('WsusServer')) { $serverOptions += " -Name $WsusServer -PortNumber $PortNumber" }
	If ($UseSsl) { $serverOptions += " -UseSsl" }
	
	# empty updateID list
	$updateList = @()
	
	# get update id's
	If ($UpdateIdFilePath) {
		If (Test-Path $UpdateIdFilePath) {
			ForEach ($id In (Get-Content $UpdateIdFilePath)) {
				$updateList += $id.Trim()
			}
		} Else {
			Write-Error "[$UpdateIdFilePath]: File not found"
			Return
		}
	} Else {
		$updateList = @($UpdateId)
	}
	
	# get WSUS server
	Try {
		Write-Host "   - Attempting WSUS Connection using $serverOptions... " -NoNewline
		$server = invoke-expression $serverOptions
		Write-Host "   - Connection Successful"
	} Catch {
		Write-Error $_
		Return
	}
	
	# empty file list
	$FileList = @()
	
	# call ImportUpdateFromCatalogSite on WSUS
	ForEach ($uid In $updateList) {
		Try {
			Write-Host "   - Attempting WSUS update import for Update ID: $uid... " -NoNewline
			$server.ImportUpdateFromCatalogSite($uid, $FileList)
			Write-Host "   - Import Successful"
		} Catch {
			Write-Error "Failed. $_"
		}
	}
	
}

Function Validate-GUID {
<#
    .SYNOPSIS
        Checks if the provided string is a valid GUID (Globally Unique Identifier).

    .DESCRIPTION
        This function attempts to parse a string as a GUID. If the parsing is successful, it returns true indicating that the string is a valid GUID. If the parsing fails, it returns false, indicating that the string is not a valid GUID.

    .PARAMETER Id
        The string that needs to be validated as a GUID.

    .EXAMPLE
        PS C:\> Validate-GUID -Id "e0c9e38d-55ae-4a80-b11d-55c3a3b9a7c3"
        This command will return true if the string is a valid GUID, or false if it is not.

    .NOTES
        This function can be used to validate input strings before attempting operations that require a valid GUID, thus preventing errors or exceptions related to invalid format.

    .OUTPUTS
        Boolean
        Returns true if the input is a valid GUID, false otherwise.

#>
	
	Param (
		[string]$Id
	)
	
	Try {
		[guid]::Parse($Id) | Out-Null
		Return $true
	} Catch {
		Return $false
	}
}

# Define the base URL and the KB number
$baseUrl = 'https://www.catalog.update.microsoft.com/Search.aspx?q='
$pattern = "goToDetails\(""(.*?)\""\)"

$kbarticles = Get-UniqueArticles -FilePath C:\temp\kblist.txt



ForEach ($kbNumber In $kbarticles) {
	
	Write-Host "Processing $kbNumber" -ForegroundColor Green
	# Construct the full URL
	$searchUrl = $baseUrl + $kbNumber
	
	# Send a request to the URL
	$response = Invoke-WebRequest -Uri $searchUrl
	
	ForEach ($item In ($response.Links | Where-Object { $_.id -like "*_link" })) {
		If ($item -match $pattern) {
			$updateId = $matches[1]
			
			# Check if the $updateId is a valid GUID
			If (-not (Validate-GUID -Id $updateId)) {
				Write-Host "   - $updateId is not a valid GUID" -ForegroundColor Red
				Continue
			}
			
			If (-not (Validate-WSUSID -updateID $updateId)) {
				Write-Host "   - $updateId not in WSUS" -ForegroundColor Yellow
				ImportUpdateToWSUS -UpdateId $updateId
			} Else {
				Write-Host "   - $updateId already in WSUS" -ForegroundColor Yellow
			}
		} Else {
			Write-Output "UpdateID not found for $kbNumber"
		}
	}
}









