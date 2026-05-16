<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	12/7/2023 4:57 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



Function Get-UniqueSearchTerms {
<#
    .SYNOPSIS
        Extracts and lists unique KB and MS update IDs from a text file.

    .DESCRIPTION
        This PowerShell function reads a text file containing KB (Knowledge Base) and MS (Microsoft Security) update references. 
        It uses regular expressions to extract the IDs and returns a list of unique KB and MS IDs, removing any duplicates.

    .PARAMETER FilePath
        The fully qualified path to the file containing the text to process. 
        The file should contain strings in the format of KBxxxxxx or MSxx-xxx to be recognized by the function.

    .EXAMPLE
        PS C:\> Get-UniqueSearchTerms -FilePath "C:\path\to\updates.txt"
        This command will read the file updates.txt and output a list of unique update IDs found within the file.

    .NOTES
        This function can be utilized for parsing log files, update lists, or any text files containing references to Microsoft updates.
        It's particularly useful for inventory scripts, compliance checks, or update verification tasks.
#>
	
	Param (
		[string]$FilePath
	)
	
	$content = Get-Content -Path $FilePath
	# Regex patterns for KB and MS articles
	$kbPattern = "(?i)KB\d+"
	$msPattern = "(?i)MS\d{2}-\d{3,}"
	
	# Find all matches for KB and MS articles
	$kbMatches = Select-String -InputObject $content -Pattern $kbPattern -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value.Trim().ToUpper() }
	$msMatches = Select-String -InputObject $content -Pattern $msPattern -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value.Trim().ToUpper() }
	
	# Combine KB and MS matches
	$combinedMatches = $kbMatches + $msMatches
	
	# Select unique articles only
	$uniqueArticles = $combinedMatches | Sort-Object | Get-Unique
	
	Return $uniqueArticles
}

Function Validate-WSUSID {
<#
    .SYNOPSIS
        Validates if a given update ID exists in the Windows Server Update Services (WSUS).

    .DESCRIPTION
        This function checks the existence of an update in WSUS by its unique GUID (Update ID). 
        It attempts to retrieve the update from WSUS, and if found, returns true, otherwise returns false.

    .PARAMETER updateID
        The GUID of the update to validate. This is a mandatory parameter.
        The GUID should be in the form of a valid GUID string that WSUS can recognize.

    .EXAMPLE
        PS C:\> Validate-WSUSID -updateID "4b674828-3565-4d19-9b0c-4c5b4d3f6f4b"
        This command will check if the update with the specified GUID exists in WSUS and return true or false.

    .NOTES
        This function is useful in scripts where there is a need to programmatically verify the presence of specific updates in WSUS.
        It requires that the WSUS PowerShell module is installed and available.
        An error is written to the host if the update ID is not found, but the function will still return false in this case.

    .OUTPUTS
        Boolean
        Returns true if the update ID exists in WSUS, false otherwise.

#>
	
	Param (
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
		Return $false
	}
}

Function Get-MSCatalogPatchInfo {
<#
	.SYNOPSIS
		Checks the MS Catalog site for patch details based on search terms in a file
	
	.DESCRIPTION
		Checks the MS Catalog site for patch details based on search terms in a file
	
	.PARAMETER InputFile
		Fully qualified file with search terms to process
	
	.EXAMPLE
		PS C:\> Get-MSCatalogPatchInfo -InputFile C:\temp\kblist.txt
	
	.NOTES
		Additional information about the function.
#>
	
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$InputFile
	)
	
	# Define the base URL and the KB number
	$baseUrl = 'https://www.catalog.update.microsoft.com/Search.aspx?q='
	$idPattern = "goToDetails\(""(.*?)\""\)"
	$Records = New-Object System.Collections.Generic.List[object]
	
	$kbarticles = Get-UniqueSearchTerms -FilePath $InputFile
	
	# Initialize the counter for the first loop
	$kbCount = 0
	$totalKb = $kbarticles.Count
	If ($totalKb -eq 0) { $totalKb = 1 } # Prevent division by zero
	
	ForEach ($kbNumber In $kbarticles) {
		# Update the progress bar for the first loop
		$kbCount++
		Write-Progress -Activity "Searching Microsoft Patch Catalog" -Status "Processing search term $kbCount of $totalKb" -PercentComplete (($kbCount / $totalKb) * 100) -Id 1 -CurrentOperation $kbNumber
		
		#Write-Host "Processing $kbNumber" -ForegroundColor Green
		# Construct the full URL
		$searchUrl = $baseUrl + $kbNumber
		
		# Send a request to the URL
		$response = (Invoke-WebRequest -Uri $searchUrl).Links | Where-Object { $_.id -like "*_link" }
		
		# Initialize the counter for the second loop
		$itemCount = 0
		$totalItems = $response.Count
		If ($totalItems -gt 0) {
			
			ForEach ($item In $response) {
				# Update the progress bar for the second loop
				$itemCount++
				Write-Progress -Activity "Web Response Processing" -Status "Processing Item $itemCount of $totalItems for search term $kbNumber" -PercentComplete (($itemCount / $totalItems) * 100) -Id 2
				
				$record = [PSCustomObject]@{
					id		   = $null
					InWSUS	   = $null
					PatchText  = $null
					SearchText = $kbNumber
				}
				
				If ($item.innerText -and -not $record.PatchText) {
					$record.PatchText = $item.innerText
				}
				
				If ($item -match $idPattern) {
					$updateId = $matches[1]

					If ($updateId) {
						$record.id = $updateId
						$record.InWSUS = Validate-WSUSID -updateID $updateId
					}
				} Else {
					$record.PatchText = "No Data Returned"
				}
				
				$Records.Add($record)
				
			}
			
			# Reset the progress bar for the second loop at the end of each KB article
			Write-Progress -Activity "Web Response Processing" -Status "Completed Processing Items in KB Article $kbNumber" -Completed -Id 2
		} Else {
			#add something here to update the object with no data returned
			
			$record = [PSCustomObject]@{
				id		   = $null
				InWSUS	   = $null
				PatchText  = "No Valid Web Data Returned"
				SearchText = $kbNumber
			}
			
			$Records.Add($record)
			
		}
		
	}
	
	# Reset the progress bar for the first loop after all KB articles are processed
	Write-Progress -Activity "Searching Microsoft Patch Catalog" -Status "Completed Processing All Search Terms" -Completed -Id 1
	
	Return $Records
}

Function Import-UpdateToWSUS {
<#
	.SYNOPSIS
		Powershell script to import an update, or multiple updates into WSUS based on the UpdateID from the catalog.
	
	.DESCRIPTION
		This script takes user input and attempts to connect to the WSUS server.
		Then it tries to import the update using the provided UpdateID from the catalog.
	
	.PARAMETER WsusServer
		Specifies the name of a WSUS server, if not specified connects to localhost.
	
	.PARAMETER PortNumber
		Specifies the port number to use to communicate with the upstream WSUS server, default is 8530.
	
	.PARAMETER UseSsl
		Specifies that the WSUS server should use Secure Sockets Layer (SSL) via HTTPS to communicate with an upstream server.
	
	.PARAMETER Updates
		A list of updates to add
	
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
	
	.OUTPUTS
		Writes logging information to standard output.
	
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
	
	.INPUTS
		The script takes WSUS server Name/IP, WSUS server port, SSL configuration option and UpdateID as input. UpdateID can be viewed and copied from the update details page for any update in the catalog, https://catalog.update.microsoft.com.
#>
	
	Param
	(
		[Parameter(Mandatory = $false,
				   HelpMessage = 'Specifies the name of a WSUS server, if not specified connects to localhost')]
		[string]$WsusServer,
		[Parameter(Mandatory = $false,
				   HelpMessage = 'Specifies the port number to use to communicate with the upstream WSUS server, default is 8530')]
		[ValidateSet('80', '443', '8530', '8531')]
		[int32]$PortNumber = 8530,
		[Parameter(Mandatory = $false,
				   HelpMessage = 'Specifies that the WSUS server should use Secure Sockets Layer (SSL) via HTTPS to communicate with an upstream server')]
		[Switch]$UseSsl,
		[Parameter(ParameterSetName = 'Multiple',
				   Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object[]]$Updates
	)
	
	Set-StrictMode -Version Latest
	
	# set server options
	$serverOptions = "Get-WsusServer"
	If ($psBoundParameters.containsKey('WsusServer')) { $serverOptions += " -Name $WsusServer -PortNumber $PortNumber" }
	If ($UseSsl) { $serverOptions += " -UseSsl" }
	
	# empty updateID list
	$Updates = $Updates | select *, ImportStatus
	
	# get WSUS server
	Try {
		Write-Progress -Activity "Attempting WSUS Connection ..." 
		$server = invoke-expression $serverOptions
	} Catch {
		Write-Error $_
		Return
	}
	
	# empty file list
	$FileList = @()
	
	# Initialize progress counter
	$counter = 0
	$totalUpdates = $Updates.Count
	
	# call ImportUpdateFromCatalogSite on WSUS
	ForEach ($update In $Updates) {
		Try {
			# Update progress bar
			$counter++
			$percentComplete = $percentComplete = [Math]::Round(($counter / $totalUpdates) * 100, 2)
			Write-Progress -Activity "Importing Update $($update.id)" -CurrentOperation "$($update.PatchText)" -PercentComplete $percentComplete -Status "$($counter) of $($totalUpdates) -- $($percentComplete)% Completed"
			$server.ImportUpdateFromCatalogSite($update.id, $FileList)
			$update.ImportStatus = "Success"

		} Catch {
			$update.ImportStatus = "Fail"
		}
	}
	
	return $Updates
}

Function Clean-SecurityList {
	$excludes = @('Exchange', 'Sharepoint', 'Windows Embedded', 'Windows 8.1', 'Windows 7')
	$WebData = Get-MSCatalogPatchInfo -InputFile C:\temp\kblist.txt | Where-Object {$_.InWSUS -eq $false}
	
	# Loop through each exclude item and filter the WebData
	ForEach ($exclude In $excludes) {
		$WebData = $WebData | Where-Object { $_.patchText -notlike "*$exclude*" }
	}
	
	If ($WebData.count -gt 0) {	
		$WebData | Export-Clixml -Path c:\temp\WebData.xml -Force
		Write-Output "$($WebData.count) Updates need to be imported."
		$WebData | Format-Table -AutoSize
	}else{ Write-Output "No Updates need to be imported."}
}

Function Import-CleanedData {
	$WebData = Import-Clixml -Path c:\temp\WebData.xml | Where-Object { $_.inwsus -eq $false }
	Import-UpdateToWSUS -Updates $WebData
}

Function Get-UpdatePages {
<#
    .SYNOPSIS
        This function will return the number of pages that a catalog.update.microsoft.com search  returns
    
    .DESCRIPTION
        A detailed description of the Get-UpdatePages function.
    
    .PARAMETER url
        Initial URL for the Microsoft Update Catalog search
    
    .EXAMPLE
        		PS C:\> Get-UpdatePages -url "https://www.catalog.update.microsoft.com/Search.aspx?q=Broadcom%20system"
    
    .NOTES
        Additional information about the function.
#>
    
    Param
    (
        [string]$url = "https://www.catalog.update.microsoft.com/Search.aspx?q=Broadcom%20system"
    )
    
    
    # https://www.catalog.update.microsoft.com/Search.aspx?q=Broadcom%20system
    # https://www.catalog.update.microsoft.com/Search.aspx?q=Broadcom+system&p=1
    
    $UrlList = [System.Collections.ArrayList]::new()
    
# Get the page content
    $response = Invoke-WebRequest -Uri $url #-UseBasicParsing
    $content = $response.Content
    
    # Regular Expression to find the text '(page X of Y)'
    $regex = "\(page \d+ of (\d+)\)"
    
    # Extract the maximum page number using the regex
    If ($content -match $regex) {
        For ($i = 1; $i -le $matches[1]; $i++) {
            $pageUrl = "$Url$($i * 25)"
            $UpdateURL = $url + "&p=$($i)"
            [void]$UrlList.Add($UpdateURL)
        }
    } Else {
        $UrlList.Add($Url)
    }
    return $UrlList
}
