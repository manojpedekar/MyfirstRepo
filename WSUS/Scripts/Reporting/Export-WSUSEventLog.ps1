<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	1/24/2024 8:05 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

Function Get-AppPoolMemoryLimits {
	Param (
	[string[]]$PoolNames = get-iis
	)
	
}


Function Build-WIDMemoryLimitSQL {
	Param
	(
		[int]$MemoryInGB = 16
	)
	
	$MemoryinMB = ($MemoryInGB * 1024).ToString()
	
	$SQLMemoryLimit = @"
		EXEC sys.sp_configure N'show advanced options', N'1'  RECONFIGURE WITH OVERRIDE;
		EXEC sys.sp_configure N'max server memory (MB)', N'$($MemoryinMB)';
		RECONFIGURE WITH OVERRIDE
		EXEC sys.sp_configure N'show advanced options', N'0'  RECONFIGURE WITH OVERRIDE;
"@
	
	return $SQLMemoryLimit
	
}

Function Build-ReportsDB {
	Param
	(
		[ValidateScript({
				If (Test-Path -Path $_ -PathType Container) {
					$true # Return true if the file exists
				} Else {
					Throw "The file '$_' does not exist." # Throws an error if the file does not exist
				}
			})]
		[string]$DBPath = "C:\Windows\WID\Data",
		[ValidateScript({
				If (Test-Path -Path $_ -PathType Container) {
					$true # Return true if the file exists
				} Else {
					Throw "The file '$_' does not exist." # Throws an error if the file does not exist
				}
			})]
		[string]$LogPath = "C:\Windows\WID\Data"
	)
	
	$TestExist_DB = "SELECT * FROM sys.databases WHERE name = 'SUSDB_Reports'"
	$TestExist_Function = "SELECT * FROM sys.all_objects WHERE name = 'fn_GetSummarizationState'"
	$TestExist_View = "SELECT * FROM sys.views WHERE name = 'vw_GetWSUSEvents'"
	
	$fn_GetSummarizationState = @"
		CREATE FUNCTION [dbo].[fn_GetSummarizationState] (@ActionID INT)
		RETURNS NVARCHAR(50)
		AS
		BEGIN
		    DECLARE @ActionName NVARCHAR(50)

		    SELECT @ActionName = CASE @ActionID
		        WHEN 0 THEN 'No Status'
		        WHEN 1 THEN 'Not Applicable'
		        WHEN 2 THEN 'Not Installed'
		        WHEN 3 THEN 'Downloaded'
		        WHEN 4 THEN 'Installed'
				WHEN 5 THEN 'Failed'
				WHEN 6 THEN 'Requires Reboot'
		        ELSE 'Unknown'
		    END

		    RETURN @ActionName
		END

"@
	
	$vw_GetWSUSEvents = @"
		CREATE VIEW [dbo].[vw_GetWSUSEvents]
		AS
			SELECT EI.[EventInstanceID]
				,EI.[EventID]
				,EMT.MessageTemplate
				,vU.DefaultTitle
				,vCT.Name AS [Client]
				,@@SERVERNAME as WSUSServer
				,ES.DisplayNameString AS [Source]
				,EI.[TimeAtTarget]
				,EI.[TimeAtServer]
				,EI.[Win32HResult]
				,EI.[AppName]
				,EI.[MiscData]
				,EI.[ReplacementStrings]
				,EI.[RevisionNumber]
				,EI.[EventOrdinalNumber]
				,E.[StateID]
				,E.[SeverityID]
				,E.[LogLevel]
				,EN.DisplayNameString AS [EventNameSpace]
				,EI.ComputerID
				,EI.UpdateID
				,CASE 
					WHEN EI.ComputerID IS NULL OR EI.UpdateID IS NULL THEN NULL
					ELSE [dbo].[fn_GetSummarizationState](vUIIB.State) 
				END as State
			FROM [SUSDB].[dbo].[tbEventInstance] AS EI
			LEFT JOIN [SUSDB].[dbo].[tbEventMessageTemplate] AS EMT ON EI.EventID = EMT.EventID
			LEFT JOIN [SUSDB].[PUBLIC_VIEWS].[vComputerTarget] AS vCT ON EI.ComputerID = vCT.ComputerTargetId
			LEFT JOIN [SUSDB].[PUBLIC_VIEWS].[vUpdate] AS vU ON EI.UpdateID = vU.UpdateID
			LEFT JOIN [SUSDB].[dbo].[tbEventSource] AS ES ON EI.[EventNamespaceID] = ES.EventNamespaceID AND EI.[EventSourceID] = ES.EventSourceID
			LEFT JOIN [SUSDB].[dbo].[tbEvent] AS E ON EI.[EventNamespaceID] = E.EventNamespaceID AND EI.[EventID] = E.[EventID]
			LEFT JOIN [SUSDB].[dbo].[tbEventNamespace] AS EN ON EI.[EventNamespaceID] = EN.[EventNamespaceID]
			LEFT JOIN [SUSDB].[PUBLIC_VIEWS].[vUpdateInstallationInfoBasic] vUIIB ON EI.ComputerID = vUIIB.ComputerTargetId AND EI.UpdateID = vUIIB.UpdateId;
"@
	
	$CreateSUSDBReports = @"
	    CREATE DATABASE [SUSDB_Reports]
	    CONTAINMENT = NONE
	    ON  PRIMARY 
	    ( NAME = N'SUSDB_Reports', FILENAME = N'$($DBPath)\SUSDB_Reports.mdf' , SIZE = 8192KB , MAXSIZE = UNLIMITED, FILEGROWTH = 65536KB )
	    LOG ON 
	    ( NAME = N'SUSDB_Reports_log', FILENAME = N'$($LogPath)\SUSDB_Reports_log.ldf' , SIZE = 8192KB , MAXSIZE = 2048GB , FILEGROWTH = 65536KB );
"@
	
	$CreateSUSDBReports_Post1 = @"
		ALTER DATABASE [SUSDB_Reports] SET COMPATIBILITY_LEVEL = 120

		IF (1 = FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'))
		begin
		EXEC [SUSDB_Reports].[dbo].[sp_fulltext_database] @action = 'enable'
		end

		ALTER DATABASE [SUSDB_Reports] SET ANSI_NULL_DEFAULT OFF 
		ALTER DATABASE [SUSDB_Reports] SET ANSI_NULLS OFF 
		ALTER DATABASE [SUSDB_Reports] SET ANSI_PADDING OFF 
		ALTER DATABASE [SUSDB_Reports] SET ANSI_WARNINGS OFF 
		ALTER DATABASE [SUSDB_Reports] SET ARITHABORT OFF 
		ALTER DATABASE [SUSDB_Reports] SET AUTO_CLOSE OFF 
		ALTER DATABASE [SUSDB_Reports] SET AUTO_SHRINK OFF 
		ALTER DATABASE [SUSDB_Reports] SET AUTO_UPDATE_STATISTICS ON 
		ALTER DATABASE [SUSDB_Reports] SET CURSOR_CLOSE_ON_COMMIT OFF 
		ALTER DATABASE [SUSDB_Reports] SET CURSOR_DEFAULT  GLOBAL 
		ALTER DATABASE [SUSDB_Reports] SET CONCAT_NULL_YIELDS_NULL OFF 
		ALTER DATABASE [SUSDB_Reports] SET NUMERIC_ROUNDABORT OFF 
		ALTER DATABASE [SUSDB_Reports] SET QUOTED_IDENTIFIER OFF 
		ALTER DATABASE [SUSDB_Reports] SET RECURSIVE_TRIGGERS OFF 
		ALTER DATABASE [SUSDB_Reports] SET  DISABLE_BROKER 
		ALTER DATABASE [SUSDB_Reports] SET AUTO_UPDATE_STATISTICS_ASYNC OFF 
		ALTER DATABASE [SUSDB_Reports] SET DATE_CORRELATION_OPTIMIZATION OFF 
		ALTER DATABASE [SUSDB_Reports] SET TRUSTWORTHY OFF 
		ALTER DATABASE [SUSDB_Reports] SET ALLOW_SNAPSHOT_ISOLATION OFF 
		ALTER DATABASE [SUSDB_Reports] SET PARAMETERIZATION SIMPLE 
		ALTER DATABASE [SUSDB_Reports] SET READ_COMMITTED_SNAPSHOT OFF 
		ALTER DATABASE [SUSDB_Reports] SET HONOR_BROKER_PRIORITY OFF 
		ALTER DATABASE [SUSDB_Reports] SET RECOVERY SIMPLE 
		ALTER DATABASE [SUSDB_Reports] SET  MULTI_USER 
		ALTER DATABASE [SUSDB_Reports] SET PAGE_VERIFY CHECKSUM  
		ALTER DATABASE [SUSDB_Reports] SET DB_CHAINING OFF 
		ALTER DATABASE [SUSDB_Reports] SET FILESTREAM( NON_TRANSACTED_ACCESS = OFF ) 
		ALTER DATABASE [SUSDB_Reports] SET TARGET_RECOVERY_TIME = 60 SECONDS 
		ALTER DATABASE [SUSDB_Reports] SET DELAYED_DURABILITY = DISABLED 
"@
	$CreateSUSDBReports_Post2 = @'
		ALTER DATABASE [SUSDB_Reports] SET  READ_WRITE 
'@
	Try {
		If (-not (Invoke-WIDQuery -Database master -Query $TestExist_DB -GetData $true)) {
			Invoke-WIDQuery -Database master -Query $CreateSUSDBReports
			Invoke-WIDQuery -Database master -Query $CreateSUSDBReports_Post1
			Invoke-WIDQuery -Database master -Query $CreateSUSDBReports_Post2
		}
		
		If (-not (Invoke-WIDQuery -Database master -Query $TestExist_Function -GetData $true)) {
			Invoke-WIDQuery -Database SUSDB_Reports -Query $fn_GetSummarizationState
		}
		
		If (-not (Invoke-WIDQuery -Database master -Query $TestExist_View -GetData $true)) {
			Invoke-WIDQuery -Database SUSDB_Reports -Query $vw_GetWSUSEvents
		}

	} Catch {
		Throw "An error occurred: $_"
	}
	return $true
}

Function Invoke-WIDQuery {
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$Query,
		[Parameter(Mandatory = $true)]
		[string]$Database,
		[boolean]$GetData = $false
	)
	
	# Define the connection string
	$connectionString = "Server=np:\\.\pipe\MICROSOFT##WID\tsql\query;Database=$($Database);Trusted_Connection=True;"
	
	# Create SQL connection
	$connection = New-Object System.Data.SqlClient.SqlConnection
	$connection.ConnectionString = $connectionString
	
	# Create SQL command
	$command = $connection.CreateCommand()
	$command.CommandText = $Query
	
	Try {
		
		# Open connection
		$connection.Open()
		
		If ($GetData) {
			# Execute command and receive data
			$adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
			$dataSet = New-Object System.Data.DataSet
			$adapter.Fill($dataSet) | Out-Null #user Out-Null to supress the console output of the record count
			
			# Store results in a variable
			$results = $dataSet.Tables[0]
			
		} Else {
			# Execute non data query
			$results = $command.ExecuteNonQuery()
		}
		
	} Catch {
		Throw "An error occurred: $_"
	} Finally {
		# Ensure the connection is closed even if an error occurs
		If ($connection.State -eq 'Open') {
			$connection.Close()
		}
	}
	
	# Return the results
	Return $results
}


Function Insert-DataIntoRemoteServer {
	Param (
		[Parameter(Mandatory = $true)]
		[System.Data.DataTable]$Data,
		[string]$TargetDatabase = 'YourTargetDatabaseName',
		[string]$TargetServer = 'ykt-wsus.ssnc-corp.cloud'
	)
	
	# Define the connection string for the target server
	$targetConnectionString = "Server=$TargetServer;Database=$TargetDatabase;Integrated Security=True;"
	
	Try {
		# Create SQL connection to the target server
		$targetConnection = New-Object System.Data.SqlClient.SqlConnection
		$targetConnection.ConnectionString = $targetConnectionString
		
		# Open connection
		$targetConnection.Open()
		
		ForEach ($row In $Data.Rows) {
			# Construct your INSERT statement here. Example:
			$insertQuery = @"
INSERT INTO [dbo].[remoteEventLogs] (Column1, Column2, ...)
VALUES ('$($row.Column1)', '$($row.Column2)', ...)
"@
			
			# Create SQL command
			$insertCommand = $targetConnection.CreateCommand()
			$insertCommand.CommandText = $insertQuery
			
			# Execute the insert command
			$insertCommand.ExecuteNonQuery()
		}
	} Catch {
		throw "An error occurred: $_"
	} Finally {
		# Close the connection
		If ($targetConnection.State -eq 'Open') {
			$targetConnection.Close()
		}
	}
}

<#
Invoke-WIDQuery -Query (Build-WIDMemoryLimitSQL) -Database master
Restart-Service 'MSSQL$MICROSOFT##WID'
Build-ReportsDB
#>

# validate service account is a member of the local admin group
# Setup scheduled task to move event data to upstream server
# create script to move data


<## Example usage
$query = "SELECT * FROM [master].[dbo].[vw_GetWSUSEvents]"
$data = Invoke-WIDQuery -Database master -Query $query -GetData $true

# Insert data into remote server
Insert-DataIntoRemoteServer -Data $data -TargetDatabase 'YourTargetDatabaseName'

#>
