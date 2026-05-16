<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	6/29/2023 5:37 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



# Define the AppID you are searching for
$appID = "{BDBED08B-7FB7-4EEA-AFD0-53DE534CB638}"





Function finddcomapp {
	Param
	(
		[string]$appID
	)
	
	# Search the registry for the AppID
	$registryPath = Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\Wow6432Node\AppID\*" | Where-Object { $_.PSChildName -eq $appID }
	
	# Check if the registry path was found
	If ($registryPath.'(default)') {
		# Output the DCOM Application Name
		Write-Host "DCOM Application Name: $($registryPath.'(default)')"
	} Else {
		Write-Host "AppID not found"
	}
}