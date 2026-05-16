<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	5/21/2024 12:54 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

Function Backup-StaticRoutes {
	Param (
		[string]$BackupFile = "C:\Temp\BackupStaticRoutes.ps1"
	)
	
	# Enumerate all static routes
	$routes = Get-WmiObject -Class Win32_IP4RouteTable | Where-Object { $_.Destination -ne "0.0.0.0" }
	
	# Prepare the script content
	$scriptContent = @"
# This script restores static routes
foreach (\$route in \$routes) {
    \$destination = \$route.Destination
    \$mask = \$route.Mask
    \$nextHop = \$route.NextHop
    \$interfaceIndex = \$route.InterfaceIndex
    \$metric1 = \$route.Metric1
    route add \$destination mask \$mask \$nextHop metric \$metric1 if \$interfaceIndex
}
"@
	
	# Write the script content to the backup file
	$scriptContent | Set-Content -Path $BackupFile
	
	# Add the routes to the script
	Add-Content -Path $BackupFile -Value "`$routes = @()"
	ForEach ($route In $routes) {
		$routeCommand = "`$routes += [PSCustomObject]@{Destination='$($route.Destination)'; Mask='$($route.Mask)'; NextHop='$($route.NextHop)'; InterfaceIndex='$($route.InterfaceIndex)'; Metric1='$($route.Metric1)'}"
		Add-Content -Path $BackupFile -Value $routeCommand
	}
	
	Write-Host "Backup script created at $BackupFile"
}

Function Restore-StaticRoutes {
	Param (
		[string]$BackupFile = "C:\Temp\BackupStaticRoutes.ps1"
	)
	
	If (Test-Path $BackupFile) {
		. $BackupFile
		Write-Host "Static routes restored from $BackupFile"
	} Else {
		Write-Host "Backup file not found: $BackupFile"
	}
}

# Example usage
Backup-StaticRoutes -BackupFile "C:\BackupStaticRoutes.ps1"
# Restore-StaticRoutes -BackupFile "C:\BackupStaticRoutes.ps1"


