<#
	.SYNOPSIS
		This script will write a 10GB file with random data in 1MB blocks to test file write speeds
	
	.DESCRIPTION
		This script will write a 10GB file with random data in 1MB blocks to test file write speeds
	
	.PARAMETER filePath
		Specify the path and file name
	
	.PARAMETER FileName
		Fully Qualified File Name to write
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	3/8/2024 10:46 AM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:     	Write-JunkFile
		===========================================================================
#>
Param
(
	[Parameter(Mandatory = $true,
			   HelpMessage = 'Specify the path to write the test file')]
	[string]$DestFolder = "C:\temp"
)

##########################################
###             FUNCTIONS             ###
##########################################

Function New-RandomFileName {
	Param (
		[string]$Path,
		[string]$Extension = "bin"
	)
	
	$randomFileName = [System.IO.Path]::GetRandomFileName()
	$randomFileName = [System.IO.Path]::ChangeExtension($randomFileName, $Extension)
	$fullPath = [System.IO.Path]::Combine($Path, $randomFileName)
	
	Return $fullPath
}

##########################################
###            MAIN SCRIPT             ###
##########################################

#create a random file name
$filePath = New-RandomFileName -Path $DestFolder

# Desired file size (10GB)
$fileSize = 10GB

# Block size for each write operation (1MB)
$blockSize = 1MB

Measure-Command {
		
	# Create a random byte array to write to the file
	$block = New-Object byte[] $blockSize
	$random = New-Object System.Random
	$random.NextBytes($block)
	
	# Open a file stream for writing
	$stream = [System.IO.File]::OpenWrite($filePath)
	
	# Initialize variables for loop
	$bytesWritten = 0
	$totalBlocks = $fileSize / $blockSize
	
	# Write blocks until the file reaches the desired size
	While ($bytesWritten -lt $fileSize) {
		$stream.Write($block, 0, $block.Length)
		$bytesWritten += $blockSize
		# Optional: Output progress
		$percentComplete = [math]::Round(($bytesWritten / $fileSize) * 100, 2)
		Write-Progress -PercentComplete $percentComplete -Status "Writing" -Activity "Writing to $($filePath): $percentComplete%"
	}
	
	# Close the stream
	$stream.Close()
	
}

Write-Output "File creation complete $($env:COMPUTERNAME) ."


