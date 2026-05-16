<#
	.SYNOPSIS
		A brief description of the Pete - Folder Cleanup.ps1 file.
	
	.DESCRIPTION
		A description of the file.
	
	.PARAMETER RootFolder
		Specify the root folder to be cleaned
	
	.PARAMETER KeepDate
		Specifify a date for file retention.  all files before this date will be deleted
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	9/8/2023 12:59 PM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:
		===========================================================================
#>
Param
(
	[Parameter(Mandatory = $true)]
	[string]$RootFolder,
	[Parameter(Mandatory = $true)]
	[datetime]$KeepDate
)

Function CalculateFolderSize {
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$TargetFolder
	)
	
	$folderSize = (Get-ChildItem -Path $TargetFolder -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB
	$folderSize = [math]::Round($folderSize, 2)
	return $folderSize
}

Function CalculateFolderSizeFast {
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$TargetFolder
	)
	
	# Initialize folder size to 0
	$folderSize = 0
	
	# Create a DirectoryInfo object
	$dirInfo = New-Object System.IO.DirectoryInfo $TargetFolder
	
	# Recursive function to calculate folder size
	Function GetDirectorySize([System.IO.DirectoryInfo]$dirInfo) {
		$size = 0
		
		# Get size for all files in the directory
		ForEach ($file In $dirInfo.GetFiles()) {
			$size += $file.Length
		}
		
		# Get size for all subdirectories
		ForEach ($dir In $dirInfo.GetDirectories()) {
			$size += GetDirectorySize $dir
		}
		
		Return $size
	}
	
	# Calculate total size of folder
	$folderSize = GetDirectorySize $dirInfo
	
	# Convert to GB and round to 2 decimal places
	$folderSize = [math]::Round(($folderSize / 1GB), 2)
	
	Return $folderSize
}


# Import the Stopwatch class
$stopwatch = New-Object System.Diagnostics.Stopwatch

# Start the stopwatch
$stopwatch.Start()

#validate folder exists
If (-not (Test-Path $RootFolder)) {
	Write-Host "Folder path not found!"
	exit 1
}

$Results = [PSCustomObject]@{
	Folder		     = $RootFolder
	BeforeFolderSize = CalculateFolderSize -TargetFolder $RootFolder
	AfterFolderSize  = $null
	AmountDeleted = $null
	RunTime		     = $null
}

$archiveDate = ($KeepDate - (Get-Date).Date).days

Get-ChildItem -Path $RootFolder -Recurse | Where-Object { ($_.LastWriteTime -lt $archiveDate) } | Remove-Item

$Results.AfterFolderSize = CalculateFolderSize -TargetFolder $RootFolder
$Results.AmountDeleted = $folderSize_Before - $folderSize_After


# Stop the stopwatch
$stopwatch.Stop()

$Results.runtime = $stopwatch.Elapsed

$Results