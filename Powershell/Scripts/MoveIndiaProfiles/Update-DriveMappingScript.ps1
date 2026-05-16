<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	1/23/2024 9:23 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

# Define the path to the existing drive mapping script
$textFilePath = "c:\temp\olddrivemap.cmd"
$UpdatedDriveMappingScript = @()

# Define all old/new share pairs
$ShareDriveMaps = @(
	'OldShare,NewShare',
	'\\globeop.com\usshare\Fundservices,\\hrs1flsprd15.globeop.com\FundServices',
	'\\mum1flsprd11\,\\10-57-49-115.globeop.com\',
	'\\mum1flsprd12\,\\10-57-49-115.globeop.com\',
	'\\mum1taledgprd1.globeop.com\FASTData\Ykt1\10-239-51-26\HFS_Dept,\\10-239-51-26.globeop.com\HFS_Dept',
	'\\mum2taledgprd1\FASTData\Ykt1\hrs1flsprd15\HR,\\hrs1flsprd15.globeop.com\HR',
	'\\Hrs1flsprd15\HR,\\hrs1flsprd15.globeop.com\HR',
	'\\globeop.com\indshare\INDOperation,\\10-57-49-115.globeop.com\indoperation',
	'\\mum1taledgprd1\FASTData\Ykt1\10-239-51-26\HFS_Dept,\\10-239-51-26.globeop.com\HFS_Dept'
) | ConvertFrom-Csv

# Read the contents of the drive mapping script
$fileContent = Get-Content -Path $textFilePath

# Loop through each line in the file
ForEach ($line In $fileContent) {
	# For each mapping, replace the old share with the new share in the line
	ForEach ($map In $ShareDriveMaps) {
		$line = $line.Replace($map.OldShare,$map.NewShare)
	}
	# Output the updated line (this can be redirected to a new file)
	$UpdatedDriveMappingScript += $line
}

