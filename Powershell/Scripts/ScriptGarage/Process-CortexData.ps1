<#
    .SYNOPSIS
        A brief description of the Process-CortexData.ps1 file.
    
    .DESCRIPTION
        This script imports data from a TSV file, processes it, and uploads it to a SQL Server table.
    
    .PARAMETER ImportFile
        A description of the ImportFile parameter.
    
    .NOTES
        ===========================================================================
        Created with:     SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
        Created on:       6/26/2024 6:51 PM
        Created by:       DT234083
        Organization:     SS&C
        Filename:
        ===========================================================================
#>
Param (
	[Parameter(Mandatory = $true)]
	[string]$ImportFile = "C:\Users\dt234083\Downloads\XDR_Agents_2025-04-01T08_52_18.tsv",
	[string]$server = "dskcbisql01.ad.dstsystems.com",
	[string]$database = "InfrasrtructureInventory",
	[string]$table = "Processed_XDR_Agents",
	[string]$schema = "dbo"
)

# Setup connection parameters
$connectionString = "Server=$server;Database=$database;Integrated Security=SSPI;"

# Import necessary modules
Import-Module SqlServer

Write-Host "Using $ImportFile"

# Load TSV data
$data = Import-Csv -Path $ImportFile -Delimiter "`t"

# Process data to convert date fields and format column names
$processedData = $data | ForEach-Object {
	# Initialize variables to hold converted dates
	$lastSeenDate = $null
	$firstSeenDate = $null
	
	# Specify the date format
	$dateFormat = "MMM d yyyy HH:mm:ss"
	
	# Remove ordinal suffixes and attempt to convert to datetime
	Try {
		$lastSeen = $_."Last Seen" -replace "(\d+)(st|nd|rd|th)", '$1'
		If ($lastSeen) {
			$lastSeenDate = [datetime]::ParseExact($lastSeen, $dateFormat, $null)
		}
	} Catch {
		Write-Warning "Failed to convert Last Seen date for $($_.'Endpoint Name'): $_.'Last Seen'"
	}
	
	Try {
		$firstSeen = $_."First Seen" -replace "(\d+)(st|nd|rd|th)", '$1'
		If ($firstSeen) {
			$firstSeenDate = [datetime]::ParseExact($firstSeen, $dateFormat, $null)
		}
	} Catch {
		Write-Warning "Failed to convert First Seen date for $($_.'Endpoint Name'): $_.'First Seen'"
	}
	
	[PSCustomObject]@{
		Last_Upgrade_Status = $_."Last Upgrade Status"
		Endpoint_Name	    = $_."Endpoint Name"
		Endpoint_Status	    = $_."Endpoint Status"
		Domain			    = $_."Domain"
		Endpoint_Type	    = $_."Endpoint Type"
		Operating_System    = $_."Operating System"
		Agent_Version	    = $_."Agent Version"
		OS_Version		    = $_."OS Version"
		Installation_Type   = $_."Installation Type"
		Golden_Image_ID	    = $_."Golden Image ID"
		IP_Address		    = $_."IP Address"
		User			    = $_."User"
		Endpoint_Alias	    = $_."Endpoint Alias"
		Last_Seen		    = $lastSeenDate
		First_Seen		    = $firstSeenDate
		Tags			    = $_."Tags"
		Endpoint_ID		    = $_."Endpoint ID"
		Agent_License_Type  = $_."Agent License Type"
	}
}

#put the columns in the right order
$processedData = $processedData | Select-Object Endpoint_Status,
												Endpoint_Name,
												Domain,
												Operating_System,
												Endpoint_Type,
												Agent_Version,
												OS_Version,
												Last_Seen,
												First_Seen,
												Last_Upgrade_Status,
												Installation_Type,
												Golden_Image_ID,
												IP_Address, User,
												Endpoint_Alias,
												Tags,
												Endpoint_ID,
												Agent_License_Type

# Truncate the table
Invoke-Sqlcmd -ConnectionString $connectionString -Query "TRUNCATE TABLE $table"

# Bulk copy data to SQL Server
Try {
	Write-SqlTableData -ServerInstance $server -DatabaseName $database -TableName $table -SchemaName $schema -InputData $processedData
} Catch {
	Write-Error "Failed to write data: $_"
}

