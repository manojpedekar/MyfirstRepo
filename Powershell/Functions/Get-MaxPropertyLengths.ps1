Function Get-MaxPropertyLengths {
<#
	.SYNOPSIS
		Calculates the maximum length of data in each property of objects in a given array.
	
	.DESCRIPTION
		This function analyzes an array of objects and determines the maximum length of the data contained in each property across all objects.
	
	.PARAMETER InputObject
		The array of objects to be analyzed.
	
	.PARAMETER Trim
		Calculate column length after removing whitespace.  Default value is false
	
	.EXAMPLE
		$data = @(
		[PSCustomObject]@{Name='Alice'; Age='29'},
		[PSCustomObject]@{Name='Bob'; Age='31'}
		)
		Get-MaxPropertyLengths -InputObject $data
		
		Returns a hashtable where each key is a property name, and the value is the maximum length of that property's data across all objects.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.248
		Created on:   	11/26/2024 9:14 AM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:     	Get-MaxPropertyLengths
		===========================================================================
#>
	
	[CmdletBinding()]
	Param
	(
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true)]
		[System.Object[]]$InputObject,
		[boolean]$Trim = $False
	)
	
	# Create a hashtable to store max lengths
	$maxLengths = @{ }
	
	# Initialize the progress counter
	$index = 0
	$totalItems = $InputObject.Count
	
	# Check each object in the $InputObject array
	ForEach ($item In $InputObject) {
		# Display progress
		$progressPercent = ($index / $totalItems) * 100
		Write-Progress -Activity "Analyzing Data" -Status "Processing item $index of $totalItems" -PercentComplete $progressPercent
		
		# Iterate over each property of the object
		ForEach ($property In $item.PSObject.Properties) {
			# Calculate the length of the current property's value
			If ($Trim) {
				$currentLength = ($property.Value | Out-String).Trim().Length
			} Else {
				$currentLength = ($property.Value | Out-String).Length
			}
			
			# If the property hasn't been added to the hashtable, add it with the current length
			If (-not $maxLengths.ContainsKey($property.Name)) {
				$maxLengths[$property.Name] = $currentLength
			}
			# If it has been added, and the current length is greater, update it
              ElseIf ($maxLengths[$property.Name] -lt $currentLength) {
				$maxLengths[$property.Name] = $currentLength
			}
		}
		
		# Increment the progress counter
		$index++
	}
	
	# Output the results
	$maxLengths
}

Function ConvertTo-SqlCreateTable {
    <#
    .SYNOPSIS
    Generates a SQL CREATE TABLE statement from a hashtable of property lengths.

    .DESCRIPTION
    This function constructs a SQL CREATE TABLE statement for Microsoft SQL Server, using property names as column names and their maximum lengths to determine appropriate VARCHAR sizes.

    .PARAMETER MaxLengths
    A hashtable where keys are property names and values are their maximum lengths.

    .PARAMETER TableName
    The name of the table to be created.
	
    .PARAMETER ScaleFactor
    The factor by which to scale the maximum length of each property to calculate VARCHAR sizes. Defaults to 1.4.

	.EXAMPLE
    $maxLengths = @{
        Name = 50;
        Age = 3;
    }
    ConvertTo-SqlCreateTable -MaxLengths $maxLengths -TableName "PersonData" -ScaleFactor 1.5

    Outputs a SQL statement to create a table named [dbo].[PersonData] with columns Name and Age, where each VARCHAR size is 1.5 times the maximum observed length.


    .NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.248
	 Created on:   	11/26/2024 9:14 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	ConvertTo-SqlCreateTable
	===========================================================================
    #>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[System.Collections.Hashtable]$MaxLengths,
		[Parameter(Mandatory = $true)]
		[string]$TableName,
		[Parameter(Mandatory = $false)]
		[double]$ScaleFactor = 1.4
	)
	
	# Start building the SQL CREATE TABLE statement
	$sql = "CREATE TABLE [TEMP].[$TableName] ("
	
	# Add columns based on the hashtable entries
	$columns = @()
	ForEach ($key In $MaxLengths.Keys) {
		# Calculate new length as the ScaleFactor times the max length, rounded up to the nearest whole number
		$newLength = [Math]::Ceiling($MaxLengths[$key] * $ScaleFactor)
		$columns += "`n    [$key] VARCHAR($newLength)"
	}
	
	# Join all column definitions with commas
	$columnDefinitions = $columns -join ','
	
	# Finish the SQL statement
	$sql += $columnDefinitions + "`n)"
	
	# Output the complete SQL statement
	Return $sql
}

