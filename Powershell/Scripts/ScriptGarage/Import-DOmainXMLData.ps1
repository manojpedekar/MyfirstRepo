<#
	.SYNOPSIS
		A brief description of the Import-DOmainXMLData.ps1 file.
	
	.DESCRIPTION
		A description of the file.
	
	.PARAMETER ImportPath
		A description of the ImportPath parameter.
	
	.PARAMETER SqlServer
		A description of the SqlServer parameter.
	
	.PARAMETER SqlDatabase
		A description of the SqlDatabase parameter.
	
	.PARAMETER Path
		A description of the Path parameter.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.245
		Created on:   	7/1/2024 10:36 AM
		Created by:   	DT234083
		Organization: 	SS&C
		Filename:
		===========================================================================
#>
Param
(
	[string]$ImportPath = 'C:\temp\DCCImports',
	[string]$SqlServer = 'dskcbisql01.ad.dstsystems.com',
	[string]$SqlDatabase = 'InfrasrtructureInventory'
)

# Construct the initial part of the SQL insert statement
$SqlQuery = "Insert Into [dbo].[DCList_20240530]([FQDN],[operatingsystem],[IPv4Address]) VALUES "

# Read XML files and build the SQL values part of the query
$DCData = @()
Get-ChildItem $ImportPath -File *.xml | ForEach-Object {
	$DCData += Import-Clixml $_.FullName
}

$ValuesList = $DCData | ForEach-Object {
	"('{0}','{1}','{2}')" -f $_.HostName, $_.OperatingSystem, $_.IPv4Address
}

# Combine the values into one string separated by commas
$SqlValues = $ValuesList -join ","

# Append the values to the initial SQL insert statement
$SqlQuery += $SqlValues

# Add the SQL command to remove duplicates
$SqlQuery += ";
WITH DupRows AS (
    SELECT
        [FQDN],
        ROW_NUMBER() OVER (PARTITION BY [FQDN] ORDER BY (SELECT NULL)) AS rn
    FROM [dbo].[DCList_20240530]
)
DELETE FROM DupRows
WHERE rn > 1;"


# Create a SqlConnection using Windows Authentication
$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$SqlConnection.ConnectionString = "Server=$SqlServer; Database=$SqlDatabase; Integrated Security=True;"
$SqlConnection.Open()

# Execute SQL Query
$SqlCommand = $SqlConnection.CreateCommand()
$SqlCommand.CommandText = $SqlQuery
$SqlCommand.ExecuteNonQuery()

$SqlConnection.Close()
