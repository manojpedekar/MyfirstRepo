<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.248
	 Created on:   	12/19/2024 5:59 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

Param (
    [string]$assemblyPath = "C:\Program Files\Update Services\Api\Microsoft.UpdateServices.Administration.dll"
)

# List all types in the assembly to verify that AdminProxy is included
Try {
    $assembly = [System.Reflection.Assembly]::LoadFile($assemblyPath)
    $assembly.GetTypes() | Select-Object FullName
} Catch {
    Write-Error $_
}

