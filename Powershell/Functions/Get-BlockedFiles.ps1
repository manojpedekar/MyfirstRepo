<#
    .SYNOPSIS
        Lists and optionally unblocks files blocked due to Internet or other computer origin in a specified directory.

    .DESCRIPTION
        This script checks for files in a specified directory that have a Zone.Identifier stream,
        indicating they are blocked because they originated from the Internet or another computer.
        Files with this stream are typically blocked by Windows to prevent potentially unsafe code
        from running without user consent. The script can also unblock these files if the 'UnblockFiles'
        switch is used.

    .PARAMETER directoryPath
        Specifies the path to the directory where files will be checked for the Zone.Identifier stream.
        This parameter must be a valid directory path on the local machine.

    .PARAMETER UnblockFiles
        When specified, this switch causes the script to unblock any files found to have the Zone.Identifier stream.

    .EXAMPLE
        .\Get-BlockedFiles.ps1 -directoryPath "C:\Users\Download" -UnblockFiles

        Checks and lists all blocked files in the 'C:\Users\Download' directory and unblocks them.

    .NOTES
        ===========================================================================
        Created with:    SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.248
        Created on:      11/11/2024 10:21 AM
        Created by:      DT234083
        Organization:    SS&C
        Filename:        Get-BlockedFiles.ps1
        ===========================================================================
#>
Param
(
	[Parameter(Mandatory = $true)]
	[string]$directoryPath,
	[Parameter()]
	[switch]$UnblockFiles
)

# Validate the directory exists
If (-Not (Test-Path -Path $directoryPath -PathType Container)) {
	Write-Error "The specified directory path '$directoryPath' does not exist."
	Return
}

# Get all files in the directory
Try {
	$files = Get-ChildItem -Path $directoryPath -Recurse -ErrorAction Stop
} Catch {
	Write-Error "Error accessing files in directory: $_"
	Return
}

# Check each file for the 'Zone.Identifier' stream and optionally unblock
ForEach ($file In $files) {
	Try {
		# Try to get the stream
		$zoneIdentifier = Get-Item -Path "$($file.FullName):Zone.Identifier" -ErrorAction SilentlyContinue
		If ($zoneIdentifier) {
			Write-Output "Blocked file: $($file.FullName)"
			If ($UnblockFiles) {
				Unblock-File -Path $file.FullName -ErrorAction Stop
				Write-Output "Unblocked file: $($file.FullName)"
			}
		}
	} Catch {
		Write-Error "Failed to process file $($file.FullName): $_"
	}
}
