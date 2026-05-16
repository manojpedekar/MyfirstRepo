<#	
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.248
	 Created on:   	12/13/2024 3:55 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	-------------------------------------------------------------------------
	 Module Name: SSNCWSUS.psm1
	===========================================================================
#>

Function Test-IsUsingWindowsInternalDatabase {
    
    # Load the required assembly
    [void][reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
    
    # Connect to the WSUS server.
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()
    
    # Access the database information
    $dbInfo = $wsus.GetDatabaseConfiguration()
    
    Return $dbInfo.IsUsingWindowsInternalDatabase
    
}

Function Build-SQLGetWSUSEvents {
    Param (
        [string]$Database = "SUSDB",
        [switch]$LocalWID,
        [System.Object[]]$dataRow
    )
    
    # Test WSUS DB Configuration
    If (Test-IsUsingWindowsInternalDatabase) {
        $ServerString = "$($env:COMPUTERNAME)\MICROSOFT##WID"
    } Else {
        $ServerString = $env:COMPUTERNAME
    }
    
    $IDBlocks = @()
    
    If (($dataRow | Measure-Object).Count -gt 0) {
        # Process each block of 1000 EventInstanceID
        $blockSize = 1000
        $numBlocks = [math]::Ceiling((($dataRow | Measure-Object).Count / $blockSize))
        
        For ($i = 0; $i -lt $numBlocks; $i++) {
            # Get the slice of EventInstanceIDs for the current block
            $currentBlock = $dataRow.EventInstanceID | Select-Object -Skip ($i * $blockSize) -First $blockSize
            
            # Convert DataRow to a list of GUID strings, wrapped with single quotes
            $FormattedValues = $currentBlock | ForEach-Object { "('$_')" }
            
            # Join the GUID strings into a single comma-separated list
            $SqlValues = "INSERT INTO @ExcludedIDs (EventInstanceID) VALUES" + ($FormattedValues -join ",")
            
            # Add the comma-separated list to the IDBlocks array
            $IDBlocks += $SqlValues
        }
    }
    
    # Build the query based on the information passed in
    If ($LocalWID) {
        $GetWSUSEvents += [Environment]::NewLine + "DECLARE @ExcludedIDs TABLE (EventInstanceID UNIQUEIDENTIFIER);"
        $GetWSUSEvents += [Environment]::NewLine + ""
        
        If ($IDBlocks) {
            $IDBlocks | ForEach-Object { $GetWSUSEvents += [Environment]::NewLine + $_ }
        }
        
        $GetWSUSEvents += [Environment]::NewLine
        $GetWSUSEvents += @"
SELECT
    vw.[EventInstanceID],
    vw.[EventID],
    vw.[MessageTemplate],
    vw.[DefaultTitle],
    vw.[Client],
    vw.[WSUSServer],
    vw.[Source],
    vw.[TimeAtTarget],
    vw.[TimeAtServer],
    vw.[Win32HResult],
    vw.[AppName],
    vw.[MiscData],
    vw.[ReplacementStrings],
    vw.[RevisionNumber],
    vw.[EventOrdinalNumber],
    vw.[StateID],
    vw.[SeverityID],
    vw.[LogLevel],
    vw.[EventNameSpace],
    vw.[ComputerID],
    vw.[UpdateID],
    vw.[State]
FROM [SUSDB].[dbo].[vw_GetWSUSEvents] AS vw
LEFT JOIN @ExcludedIDs AS excl ON vw.EventInstanceID = excl.EventInstanceID
WHERE excl.EventInstanceID IS NULL;
"@
        
    } Else {
        $GetWSUSEvents = "SELECT DISTINCT [EventInstanceID]"
        $GetWSUSEvents += [Environment]::NewLine + "FROM $($Database).[dbo].[tb_ConsolidatedWSUSEvents]"
        $GetWSUSEvents += [Environment]::NewLine + "WHERE [WSUSServer] = '$($ServerString)'"
    }
    
    Return $GetWSUSEvents
}

Function Build-SetWIDServerName {
    
    $SQL_SetWIDServerName = "EXEC sp_addserver 'your_server_name', 'local'"
    
    Return $SQL_SetWIDServerName.Replace('your_server_name', $env:COMPUTERNAME)
    
}

Function Build-vw_GetWSUSEvents {
    
    $SQL_vw_GetWSUSEvents = @"
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
    
    Return $SQL_vw_GetWSUSEvents
}

Function Build-fn_GetSummarizationState {
    $SQL_fn_GetSummarizationState = @"
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
    
    Return $SQL_fn_GetSummarizationState
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
    
    Return $SQLMemoryLimit
}

Function Insert-NewWSUSEvents {
    Param
    (
        [string]$UpstreamDB = "SUSDB_Reports",
        [string]$UpstreamServer = "wsusupstream.ssnc-corp.cloud",
        [string]$LocalDB = "SUSDB"
    )
    
    $results = [PSCustomObject]@{
        RecordCount = 0
        Message     = "No Action Taken"
        LocalQuery  = $null
    }
    
    $DistinctLogEvents = Invoke-WSUSQuery -DBServer $UpstreamServer -Database $UpstreamDB -Query (Build-SQLGetWSUSEvents -Database $UpstreamDB) -GetData $true
    $DistinctIDTable = $DistinctLogEvents.Tables[0]
    
    $Results.LocalQuery = Build-SQLGetWSUSEvents -LocalWID -datarow $DistinctIDTable -Database $LocalDB
    $EventstoSendUpstream = Invoke-WSUSQuery -Query $Results.LocalQuery -GetData $true -Database $LocalDB
    
    If (($EventstoSendUpstream.Tables[0] | Measure-Object).count -gt 0) {
        
        $connectionString = "Server=$($UpstreamServer);Initial Catalog=$($UpstreamDB);Trusted_Connection=True;"
        
        # Create SQL connection
        $Connection = New-Object System.Data.SqlClient.SqlConnection
        $Connection.ConnectionString = $connectionString
        
        Try {
            
            # Open connection
            $Connection.Open()
            
            # Set up the bulk copy operation
            $bulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy($Connection)
            $bulkCopy.DestinationTableName = "[dbo].[tb_ConsolidatedWSUSEvents]"
            
            # If the column names in both tables match exactly, no need for manual column mappings
            # Perform the bulk copy
            $EventsTable = $EventstoSendUpstream.Tables[0]
            $bulkCopy.WriteToServer($EventsTable)
            
        } Catch {
            Throw "An error occurred: $_"
        } Finally {
            $results.RecordCount = ($EventstoSendUpstream.Tables[0] | Measure-Object).count
            $results.Message = "Successfully transferred events to upstream server"
            
            $bulkCopy.Close()
            
            # Ensure the connection is closed even if an error occurs
            If ($Connection.State -eq 'Open') {
                $Connection.Close()
            }
        }
    }
    # Return the results
    Return $results
    
}

Function Invoke-WSUSQuery {
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$Query,
        [Parameter(Mandatory = $true)]
        [string]$Database,
        [boolean]$GetData = $false,
        [string]$DBServer,
        [int]$Timeout = 15
    )
    
    # Define the connection string
    If ($DBServer) {
        $connectionString = "Server=$($DBServer);Initial Catalog=$($Database);Trusted_Connection=True;Connection Timeout=$($Timeout)"
        #$connectionString = "Data Source=$($DBServer);Initial Catalog=$($Database);Integrated Security=True"
    } Else {
        $connectionString = "Server=np:\\.\pipe\MICROSOFT##WID\tsql\query;Database=$($Database);Trusted_Connection=True;Connection Timeout=$($Timeout)"
    }
    
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
            $results = $dataSet
            
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

# Set-WSUSAppPools is intentionally NOT defined here. The canonical version
# lives at Scripts/Server-Setup/Set-WsusAppPools.ps1 (more thorough error
# handling, verbose logging, IIS site existence check).

Function Get-WSUSConfig {
    Param (
        [switch]$Fix,
        [int]$MemoryInGB = 16
    )
    
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    
    $SQL_DBInfo = @"
SELECT 
    @@SERVERNAME AS [ServerName],
    (SELECT value FROM sys.configurations WHERE name = 'max server memory (MB)') AS [MaxMemory],
    (SELECT 
        CASE 
            WHEN EXISTS (
                SELECT 1
                FROM INFORMATION_SCHEMA.ROUTINES 
                WHERE ROUTINE_SCHEMA = 'dbo' 
                AND ROUTINE_NAME = 'fn_GetSummarizationState' 
                AND ROUTINE_TYPE = 'FUNCTION'
            ) THEN 'True'
            ELSE 'False'
        END
    ) AS [fn_GetSummarizationStateExists],
	(SELECT 
        CASE 
            WHEN EXISTS (
				SELECT 1 
				FROM sys.views 
				WHERE object_id = OBJECT_ID(N'dbo.vw_GetWSUSEvents')
            ) THEN 'True'
            ELSE 'False'
        END
    ) AS vw_GetWSUSEvents
"@
    
    $requery = $false
    $DBInfo = (Invoke-WSUSQuery -Database "SUSDB" -GetData $true -Query $SQL_DBInfo).Tables[0][0]
    $OSInfo = Get-WmiObject win32_operatingsystem
    
    $results = [PSCustomObject]@{
        QueryType                      = "NoFix"
        ComputerName                   = $ENV:COMPUTERNAME
        WIDDB                          = Test-IsUsingWindowsInternalDatabase
        SQLServerName                  = $DBInfo.ServerName
        SQLMaxMemory                   = $DBInfo.MaxMemory
        fn_GetSummarizationStateExists = $DBInfo.fn_GetSummarizationStateExists
        vw_GetWSUSEvents               = $DBInfo.vw_GetWSUSEvents
        OS                             = $OSInfo.Caption
        ServiceRestartRequired         = $false
        DefaultWebSitePresent          = Test-IISWebsiteExists -WebsiteName "Default Web Site"
    }
    
    If ($Fix) {
        If ([string]::IsNullOrWhiteSpace($results.SQLServerName)) {
            Invoke-WSUSQuery -Query (Build-SetWIDServerName) -Database master
            $results.ServiceRestartRequired = $true
            $requery = $true
        }
        
        If (($MemoryInGB * 1024) -ne $results.SQLMaxMemory) {
            Invoke-WSUSQuery -Query (Build-WIDMemoryLimitSQL -MemoryInGB $MemoryInGB) -Database master
            $results.ServiceRestartRequired = $true
            $requery = $true
        }
        
        If ('False' -eq $results.fn_GetSummarizationStateExists) {
            Invoke-WSUSQuery -Query (Build-fn_GetSummarizationState) -Database SUSDB
            $requery = $true
        }
        
        If ('False' -eq $results.vw_GetWSUSEvents) {
            Invoke-WSUSQuery -Query (Build-vw_GetWSUSEvents) -Database SUSDB
            $requery = $true
        }
        
        If ($results.DefaultWebSitePresent) {
            Remove-IISSite "Default Web Site" -Confirm:$false -ErrorAction SilentlyContinue
            $requery = $true
        }
    }
    
    If ($results.ServiceRestartRequired -and $results.WIDDB) {
        $DBServiceName = 'MSSQL$MICROSOFT##WID'
        Restart-Service $DBServiceName
    }
    
    If ($requery) {
        $results
        $results = Get-WSUSConfig
        $results.QueryType = "PostFix"
    }
    Return $results
}

Function Test-IISWebsiteExists {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$WebsiteName
    )
    
    # Attempt to get the website by name
    Return test-path (Join-Path -Path "IIS:\Sites\" -ChildPath $WebsiteName)
    
}

Function Install-WSUSFeatures {
    
    $WSUSFeatures = @(
        'File-Services',
        'FS-FileServer',
        'Web-Server',
        'Web-WebServer',
        'Web-Common-Http',
        'Web-Default-Doc',
        'Web-Static-Content',
        'Web-Performance',
        'Web-Dyn-Compression',
        'Web-Security',
        'Web-Filtering',
        'Web-Windows-Auth',
        'Web-App-Dev',
        'Web-Net-Ext45',
        'Web-Asp-Net45',
        'Web-ISAPI-Ext',
        'Web-ISAPI-Filter',
        'Web-Mgmt-Tools',
        'Web-Mgmt-Console',
        'Web-Mgmt-Compat',
        'Web-Metabase',
        'UpdateServices',
        'UpdateServices-WidDB',
        'UpdateServices-Services',
        'NET-Framework-45-ASPNET',
        'NET-WCF-HTTP-Activation45',
        'RSAT',
        'RSAT-Role-Tools',
        'UpdateServices-RSAT',
        'UpdateServices-API',
        'UpdateServices-UI',
        'Windows-Internal-Database',
        'WAS',
        'WAS-Process-Model',
        'WAS-Config-APIs')
    
    Try {
        $result = Install-WindowsFeature -Name $WSUSFeatures
    } Catch {
        Throw $_
        return $false
    }
    return $result
}

Function Install-WSUSServer {
    
    Initialize-WSUSDisks
        
    $WSUSBinaries = "W:\WSUS"
    $WSUSUtil = "C:\Program Files\Update Services\Tools\WsusUtil.exe"
    

    # Ensure the WSUS binaries directory exists
    If (-not (Test-Path $WSUSBinaries)) {
        New-Item -Path $WSUSBinaries -ItemType Directory | Out-Null
    }
    
    Try {
        Install-WSUSFeatures
    } Catch {
        Write-Error "An error occurred while installing Windows features: $_"
    }
    
    <#    
    Import-Module WebAdministration
    $DefaultSitePresent = Test-IISWebsiteExists "Default Web Site"
    If ($DefaultSitePresent) { Remove-IISSite "Default Web Site" -Confirm:$false -ErrorAction SilentlyContinue }
    #>
    
    # Validate WSUS Utility path
    If ((Test-Path $WSUSUtil) -eq $false) { Write-Error "WsusUtil.exe not found at the specified path: $WSUSUtil" }
    
    Try {
        # Execute the WSUS postinstall command
        & $WSUSUtil postinstall CONTENT_DIR=$WSUSBinaries
        If ($LASTEXITCODE -ne 0) {
            Throw "WsusUtil.exe failed with exit code $LASTEXITCODE"
        }
        Write-Output "WSUS postinstall completed successfully with content directory: $WSUSBinaries"
    } Catch { Write-Error "An error occurred while running WSUS postinstall: $_" }
    
    Set-WSUSAppPools
    
    Set-SSNCReplicaWSUSSettings
    
    
    
    <#
    cd "C:\Program Files\Update Services\Tools\"

    #Using WID
    wsusutil.exe postinstall CONTENT_DIR=W:\WSUS

    # Using SQL
    wsusutil.exe postinstall SQL_INSTANCE_NAME="YourSqlServerInstance" CONTENT_DIR=D:\WSUS



    Install-WindowsFeature -Name 'UpdateServices' -IncludeManagementTools -Verbose

    $WSUSContentDir = 'C:WSUS' 
    New-Item -Path $WSUSContentDir -ItemType Directory
    #Next command on one line, this textbox wraps it..
    & "$env:ProgramFilesUpdate ServicesToolsWsusUtil.exe" postinstall CONTENT_DIR=$WSUSContentDir



    # Discusses SSL on some app and not others
    https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/2-configure-wsus#232-configure-the-wsus-servers-iis-web-server-to-use-ssl-for-some-connections

    
    #>
    
    
}

Function Set-SSNCReplicaWSUSSettings {
    Param (
        [string]$upstreamServer = "wsusupstream.ssnc-corp.cloud"
    )
    
    [void][reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()
    
    $wsusConfig = $wsus.GetConfiguration()
    $wsusConfig.UpstreamWsusServerName = $upstreamServer
    $wsusConfig.SyncFromMicrosoftUpdate = $false
    $wsusConfig.IsReplicaServer = $true
    $wsusConfig.DownloadUpdateBinariesAsNeeded = $false
    $wsusConfig.DownloadExpressPackages = $true
    $wsusConfig.GetContentFromMU = $true
    $wsusConfig.MURollupOptin = $false
    $wsusConfig.TargetingMode = 'Client'
    $wsusConfig.CollectClientInventory = $true
    $wsusConfig.Save()
    
    <#    
    Other things to consider
    
    AutoApproveWsusInfrastructureUpdates
    DownloadExpressPackages
    ClientReportingLevel
    
    LogLevel and LogDestinations:
    These settings control the verbosity of the logging and where logs are sent, which can be crucial for troubleshooting and monitoring the health of the WSUS server.
    
    #>
    
    
    $subscription = $wsus.GetSubscription()
    $subscription.SynchronizeAutomatically = $true
    $subscription.NumberOfSynchronizationsPerDay = 24
    $subscription.Save()
    
}

Function Add-TargetGroupToApprovalRule {
	<#
	.SYNOPSIS
		Adds a ComputerTargetGroup from an existing rule
	
	.DESCRIPTION
		Adds a ComputerTargetGroup from an existing rule
	
	.PARAMETER WsusServer
		Name of the WSUS server to connect
	
	.PARAMETER WsusPort
		WSUS port
	
	.PARAMETER RuleName
		Existing WSUS Rule Name
	
	.PARAMETER TargetGroupName
		Esisting WSUS ComputerTargetGroup to update
	
	.EXAMPLE
				PS C:\> Add-TargetGroupFromApprovalRule -RuleName "Approval Rule" -TargetGroupName "My Existing Group"
	
	.NOTES
	    Author         : Pete Demers (DT234083)
	    Version        : 1.0
	    Changelog      : Initial function scripting
	
	.TODO
		- Review logic and address error handling.  Script is currently funcfional but not production ready
#>
    
    # Example usage
    #Add-TargetGroupToApprovalRule -RuleName "Nested Approval" -TargetGroupName "My New Group"
    
    [CmdletBinding()]
    Param (
        [string]$WsusServer = "localhost",
        [int]$WsusPort = 8530,
        [string]$RuleName,
        [string]$TargetGroupName
    )
    
    # Connect to WSUS server
    $wsus = Get-WsusServer -Name $WsusServer -PortNumber $WsusPort
    
    # Fetch the approval rule by its name
    $approvalRule = $wsus.GetInstallApprovalRules() | Where-Object { $_.Name -eq $RuleName }
    If ($null -eq $approvalRule) {
        Write-Error "Approval rule '$RuleName' not found."
        Return
    }
    
    # Fetch the target group by its name
    $targetGroup = $wsus.GetComputerTargetGroups() | Where-Object { $_.Name -eq $TargetGroupName }
    If ($null -eq $targetGroup) {
        Write-Error "Target group '$TargetGroupName' not found."
        Return
    }
    
    # Initialize ComputerTargetGroupCollection
    $group_coll = New-Object Microsoft.UpdateServices.Administration.ComputerTargetGroupCollection
    
    # Combine existing and new groups
    $allGroups = $approvalRule.GetComputerTargetGroups() + $targetGroup
    
    Try {
        # Add all groups to collection
        ForEach ($group In $allGroups) {
            [void]$group_coll.Add($group)
        }
        
        # Update approval rule
        $approvalRule.SetComputerTargetGroups($group_coll)
        $approvalRule.Save()
        
        Write-Host "Successfully added target group '$TargetGroupName' to approval rule '$RuleName'."
    } Catch {
        Write-Error "Failed to add target group to approval rule: $_"
    }
}

Function Remove-TargetGroupFromApprovalRule {
<#
	.SYNOPSIS
		Remove a ComputerTargetGroup from an existing rule
	
	.DESCRIPTION
		Remove a ComputerTargetGroup from an existing rule
	
	.PARAMETER WsusServer
		Name of the WSUS server to connect
	
	.PARAMETER WsusPort
		WSUS port
	
	.PARAMETER RuleName
		Existing WSUS Rule Name
	
	.PARAMETER TargetGroupName
		Esisting WSUS ComputerTargetGroup to update
	
	.EXAMPLE
				PS C:\> Remove-TargetGroupFromApprovalRule -RuleName "Approval Rule" -TargetGroupName "My Existing Group"
	
	.NOTES
	    Author         : Pete Demers (DT234083)
	    Version        : 1.0
	    Changelog      : Initial function scripting
	
	.TODO
		- Review logic and address error handling.  Script is currently funcfional but not production ready
#>
    
    [CmdletBinding()]
    Param
    (
        [string]$WsusServer = "localhost",
        [int]$WsusPort = 8530,
        [Parameter(Mandatory = $true)]
        [string]$RuleName,
        [Parameter(Mandatory = $true)]
        [string]$TargetGroupName
    )
    
    # Connect to WSUS server
    $wsus = Get-WsusServer -Name $WsusServer -PortNumber $WsusPort
    
    # Fetch the approval rule by its name
    $approvalRule = $wsus.GetInstallApprovalRules() | Where-Object { $_.Name -eq $RuleName }
    If ($null -eq $approvalRule) {
        Write-Error "Approval rule '$RuleName' not found."
        Return
    }
    
    # Initialize ComputerTargetGroupCollection
    $group_coll = New-Object Microsoft.UpdateServices.Administration.ComputerTargetGroupCollection
    
    # Get existing groups for the approval rule
    $existingGroups = $approvalRule.GetComputerTargetGroups()
    
    # Remove specified group from the list
    $updatedGroups = $existingGroups | Where-Object { $_.Name -ne $TargetGroupName }
    
    # Check if the group was actually removed (i.e., it existed in the first place)
    If ($updatedGroups.Count -eq $existingGroups.Count) {
        Write-Error "Target group '$TargetGroupName' not found in approval rule '$RuleName'."
        Return
    }
    
    Try {
        # Add remaining groups to collection
        ForEach ($group In $updatedGroups) {
            [void]$group_coll.Add($group)
        }
        
        # Update the approval rule
        $approvalRule.SetComputerTargetGroups($group_coll)
        $approvalRule.Save()
        
        Write-Host "Successfully removed target group '$TargetGroupName' from approval rule '$RuleName'."
    } Catch {
        Write-Error "Failed to remove target group from approval rule: $_"
    }
}



Function New-WSUSTargetGroup {
<#
	.SYNOPSIS
		Creates one or more Computer Target Groups in WSUS
	
	.DESCRIPTION
		Creates one or more Computer Target Groups in WSUS.  Specifying the ParentGroupName will create a folder hierarchy.
	
	.PARAMETER WsusServer
		Name of the WSUS server to connect
	
	.PARAMETER WsusPort
		WSUS port
	
	.PARAMETER GroupNames
		Names of the Computger Target Groups to be created in WSUS
	
	.PARAMETER ParentGroupName
		Parent folder for the new Compteur Target Groups
	
	.PARAMETER SSCEnvs
		Server Environments to be used to create sub ComputerTargetGroups
	
	.PARAMETER LoadFBU
		Specify if loading the top level folder for FBU's
	
	.PARAMETER GroupName
		WSUS server port
	
	.EXAMPLE
		PS C:\> New-WSUSTargetGroup -GroupName "My New Group"
	
	.EXAMPLE
		PS C:\> New-WSUSTargetGroup -GroupName "Nested Group" -ParentGroupName "My New Group"
	
	.NOTES
		Author         : Pete Demers (DT234083)
		Version        : 1.0
		Changelog      : Initial function scripting
#>
    
    [CmdletBinding()]
    Param
    (
        [string]$WsusServer = "localhost",
        [int]$WsusPort = 8530,
        [Parameter(Mandatory = $true)]
        [string[]]$GroupNames,
        [string]$ParentGroupName = $null,
        [array]$SSCEnvs = @('Dev', 'QA', 'UAT', 'PROD', 'NoEnv'),
        [switch]$LoadFBU
    )
    
    #Connect to the WSUS Server
    Try {
        # Connect to WSUS Server
        $wsus = Get-WsusServer -Name $WsusServer -PortNumber $WsusPort
        
        # Get a list of groups for comparison
        $existingGroups = $wsus.GetComputerTargetGroups()
        $existingGroupNames = $existingGroups.Name
        
        # If a parent group name is specified, find it
        $parentGroup = $null
        If ($ParentGroupName) {
            $parentGroup = $existingGroups | Where-Object { $_.Name -eq (Replace-SpecialCharacters -InputString $ParentGroupName) }
            If (-not $parentGroup) {
                $parentGroup = $wsus.CreateComputerTargetGroup($ParentGroupName)
            }
        }
        
        #Loop through the groups passed to the function
        ForEach ($GroupName In $GroupNames) {
            
            $SanitizedGroupName = Replace-SpecialCharacters -InputString $GroupName
            # check to see if group already exists
            If ($SanitizedGroupName -in $existingGroups.Name) {
                Write-Error "A group with the name '$SanitizedGroupName' already exists."
                Continue
            }
            
            #Create new group
            $newGroup = $wsus.CreateComputerTargetGroup($SanitizedGroupName, $parentGroup)
            
            #Check to see if we are creating FBU's or CMDBID Groups
            If (-not $LoadFBU) {
                ForEach ($SSCEnv In $SSCEnvs) {
                    $subGroupName = $SanitizedGroupName + "-" + $SSCEnv
                    [void]$wsus.CreateComputerTargetGroup($subGroupName, $newGroup)
                }
            }
        }
    } Catch [System.Net.WebException] {
        Write-Error "Could not connect ot WSUS server"
        Return $_.Exception
    } Catch {
        Write-Error "A general error occured connecting to the WSUS Server"
        Return $_.Exception
    }
}

Function Replace-SpecialCharacters {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$InputString
    )
    
    # Replace "SS&C" with "SSNC" as it's a special case
    $SanitizedString = $InputString -replace 'SS&C', 'SSNC'
    
    # Replace "&" with "and"
    $SanitizedString = $SanitizedString -replace '&', 'and'
    
    # Replace "(" with "- "
    $SanitizedString = $SanitizedString -replace '\(', '- '
    
    # Remove ")"
    $SanitizedString = $SanitizedString -replace '\)', ''
    
    Return $SanitizedString
}

Function Publish-AppIDData {
<#
	.SYNOPSIS
		Process the CMDB Application ID data for WSUS
	
	.DESCRIPTION
		Processes the CMDB Application ID Data to create the proper computer target groups in WSUS
	
	.PARAMETER CsvFilePath
		File name to process.  This file should have the following colums:
		
		AppID - The integer value of the CMDB Application ID
		FBU - The Financial Business Unit of the associated Application ID
	
	.EXAMPLE
		PS C:\> Publish-AppIDData
	
	.NOTES
		Additional information about the function.
#>
    
    Param
    (
        [string]$CsvFilePath
    )
    
    Try {
        # Import the CSV file
        $csvData = Import-Csv -Path $CsvFilePath
        
        # Validate that the CSV has data
        If ($csvData -eq $null -or $csvData.Count -eq 0) {
            Write-Error "The CSV file is empty or could not be read."
            Return
        }
        
        # Get the column names
        $columnNames = ($csvData[0] | Get-Member -MemberType NoteProperty).Name
        
        # Validate the required columns
        $requiredColumns = @("APPID", "FBU")
        $missingColumns = @()
        
        ForEach ($col In $requiredColumns) {
            If ($columnNames -notcontains $col) {
                $missingColumns += $col
            }
        }
        
        If ($missingColumns.Count -gt 0) {
            Write-Error ("The CSV file is missing the following required columns: " + [string]::Join(", ", $missingColumns))
            Return
        }
        
        # If you reach this point, the CSV has the required columns and you can continue processing $csvData
        Write-Host "CSV file has the required columns."
        
        $FBUList = $csvData | Select-Object -Unique FBU -ExpandProperty FBU
        
        New-WSUSTargetGroup -GroupNames $FBUList -ParentGroupName "ByAppID" -LoadFBU
        
        ForEach ($FBU In $FBUList) {
            $AppIDsByFBU = $csvData | Where-Object { $_.fbu -eq $FBU } | Select-Object -ExpandProperty APPID
            New-WSUSTargetGroup -GroupNames $AppIDsByFBU -ParentGroupName $FBU
        }
        
    } Catch [System.IO.FileNotFoundException] {
        Write-Error "The specified CSV file could not be found."
    } Catch [System.UnauthorizedAccessException] {
        Write-Error "You do not have permission to access the specified CSV file."
    } Catch {
        Write-Error "An unexpected error occurred: $_"
    }
}

Function Initialize-RawDrive {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [object]$Drive,
        [Parameter(Mandatory = $true)]
        [char]$DriveLetter,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )
    
    Try {
        # Initialize the disk
        Initialize-Disk -Number $Drive.Number -PartitionStyle GPT -PassThru | Out-Null
        
        # Create a new partition
        $partition = New-Partition -DiskNumber $Drive.Number -UseMaximumSize -AssignDriveLetter:$false
        
        # Format the partition
        $formattedVolume = Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel $Description -Confirm:$false
        
        # Assign the drive letter
        Add-PartitionAccessPath -DiskNumber $Drive.Number -PartitionNumber $partition.PartitionNumber -AccessPath "${DriveLetter}:"
        
        Write-Output "Drive initialized and formatted with the letter '$DriveLetter' and description '$Description'."
    } Catch {
        Write-Error "An error occurred: $_"
    }
}


Function Get-WSUSBaseline {
    Param (
        [switch]$SQL
    )
    
    If (-not ($SQL)) {
        #define the base settings for a WID database config
        $BaseConfig = [PSCustomObject]@{
            WIDDB                          = $true
            SQLServerName                  = $DBInfo.ServerName
            SQLMaxMemory                   = 16384
            fn_GetSummarizationStateExists = $true
            vw_GetWSUSEvents               = $true
            DefaultWebSitePresent          = $false
        }
    } Else {
        #define the base settings for a SQL database config (there should only be one of these, the upstream server)
        $BaseConfig = [PSCustomObject]@{
            WIDDB                          = $false
            SQLServerName                  = $DBInfo.ServerName
            SQLMaxMemory                   = 16384
            fn_GetSummarizationStateExists = $true
            vw_GetWSUSEvents               = $true
            DefaultWebSitePresent          = $false
        }
    }
    Return $BaseConfig
}


Function Initialize-WSUSDisks {
    
    $RawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' }
    
    ForEach ($RawDisk In $RawDisks) {
        Switch ($RawDisk.Size/1gb) {
            100 {
                # this is the data disk
                $cdDrive = Get-CimInstance -ClassName Win32_Volume | Where-Object { $_.DriveLetter -eq "D:" -and $_.FileSystem -eq 'CDFS' }
                
                If ($cdDrive) { Update-CDROMDriveLetter }
                
                Initialize-RawDrive -Drive $RawDisk -DriveLetter D -Description "Data"
                
            }
            { $_ -gt 1000 } {
                #<code>
                Initialize-RawDrive -Drive $RawDisk -DriveLetter W -Description "WSUS Data"
            }
            default {
                #Nothing happened
            }
        }
    }
    
}

Function Update-CDROMDriveLetter {
    Param (
        [string]$ExistingDriveLetter = "D:",
        [string]$NewDriveLetter = "E:"
    )
    
    Try {
        # Get the CDROM drive with the letter $ExistingDriveLetter
        $cdDrive = Get-CimInstance -ClassName Win32_Volume | Where-Object { $_.DriveLetter -eq $ExistingDriveLetter -and $_.FileSystem -eq 'CDFS' }
        $NewDrive = Get-CimInstance -ClassName Win32_Volume | Where-Object { $_.DriveLetter -eq $NewDriveLetter }
        
        If ($cdDrive -and -not $newDrive) {
            $cdDrive | Set-CimInstance -Property @{ DriveLetter = $NewDriveLetter }
            
            Write-Output "Drive letter changed from $ExistingDriveLetter to $NewDriveLetter."
        } Else {
            Write-Output "Drive $ExistingDriveLetter is not present or is not a CDROM."
        }
    } Catch {
        Write-Error "An error occurred: $_"
    }
}

Function Connect-WSUS {
    <#
    .SYNOPSIS
        Connects to a Windows Server Update Services (WSUS) server.

    .DESCRIPTION
        Loads the Microsoft.UpdateServices.Administration assembly (preferring
        the on-disk DLL if present, otherwise the deprecated
        LoadWithPartialName fallback) and returns a WSUS server object via
        AdminProxy::GetUpdateServer.

    .PARAMETER serverName
        Server to connect to. Defaults to the local computer name.

    .PARAMETER useSecureConnection
        Use HTTPS. Default $false.

    .PARAMETER portNumber
        WSUS port. Default 8530 (HTTP); use 8531 for HTTPS.

    .PARAMETER DLLPath
        Fully qualified path to Microsoft.UpdateServices.Administration.dll.

    .EXAMPLE
        Connect-WSUS

    .EXAMPLE
        Connect-WSUS -serverName "wsus.example.com" -useSecureConnection $true -portNumber 8531
    #>

    Param
    (
        [string]$serverName = $env:COMPUTERNAME,
        [boolean]$useSecureConnection = $false,
        [int]$portNumber = 8530,
        [string]$DLLPath = "C:\Program Files\Update Services\Api\Microsoft.UpdateServices.Administration.dll"
    )

    Try {
        If (Test-Path $DLLPath) {
            Add-Type -Path $DLLPath
            Write-Verbose "Method loaded using the DLL: $DLLPath"
        } Else {
            Write-Verbose "DLL not found trying with LoadWithPartialName"
            [void][reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
            Write-Verbose "LoadWithPartialName Successfull"
        }
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($serverName, $useSecureConnection, $portNumber)
    } Catch {
        Throw $_
    }

    Return $wsus
}

Class WSUSQueryBuilder {
    # Static method that builds the GetWSUSEvents SQL.
    # Mirrors Build-SQLGetWSUSEvents above but as a class method using
    # Connect-WSUS rather than Test-IsUsingWindowsInternalDatabase.
    Static [string] SQLGetWSUSEvents ([string]$Database = "SUSDB", [bool]$LocalWID, [System.Object[]]$dataRow) {
        Try {
            $wsus = Connect-WSUS
            $dbInfo = $wsus.GetDatabaseConfiguration()
        } Catch {
            Throw $_
        }

        If ($dbInfo.IsUsingWindowsInternalDatabase) {
            $ServerString = "$($env:COMPUTERNAME)\MICROSOFT##WID"
        } Else {
            $ServerString = $env:COMPUTERNAME
        }

        $IDBlocks = @()

        If (($dataRow | Measure-Object).Count -gt 0) {
            $blockSize = 1000
            $numBlocks = [math]::Ceiling((($dataRow | Measure-Object).Count / $blockSize))

            For ($i = 0; $i -lt $numBlocks; $i++) {
                $currentBlock = $dataRow.EventInstanceID | Select-Object -Skip ($i * $blockSize) -First $blockSize
                $FormattedValues = $currentBlock | ForEach-Object { "('$_')" }
                $SqlValues = "INSERT INTO @ExcludedIDs (EventInstanceID) VALUES" + ($FormattedValues -join ",")
                $IDBlocks += $SqlValues
            }
        }

        If ($LocalWID) {
            $GetWSUSEvents = [Environment]::NewLine + "DECLARE @ExcludedIDs TABLE (EventInstanceID UNIQUEIDENTIFIER);"
            $GetWSUSEvents += [Environment]::NewLine + ""

            If ($IDBlocks) {
                $IDBlocks | ForEach-Object { $GetWSUSEvents += [Environment]::NewLine + $_ }
            }

            $GetWSUSEvents += [Environment]::NewLine
            $GetWSUSEvents += @"
SELECT
    vw.[EventInstanceID],
    vw.[EventID],
    vw.[MessageTemplate],
    vw.[DefaultTitle],
    vw.[Client],
    vw.[WSUSServer],
    vw.[Source],
    vw.[TimeAtTarget],
    vw.[TimeAtServer],
    vw.[Win32HResult],
    vw.[AppName],
    vw.[MiscData],
    vw.[ReplacementStrings],
    vw.[RevisionNumber],
    vw.[EventOrdinalNumber],
    vw.[StateID],
    vw.[SeverityID],
    vw.[LogLevel],
    vw.[EventNameSpace],
    vw.[ComputerID],
    vw.[UpdateID],
    vw.[State]
FROM [SUSDB].[dbo].[vw_GetWSUSEvents] AS vw
LEFT JOIN @ExcludedIDs AS excl ON vw.EventInstanceID = excl.EventInstanceID
WHERE excl.EventInstanceID IS NULL;
"@
        } Else {
            $GetWSUSEvents = "SELECT DISTINCT [EventInstanceID]"
            $GetWSUSEvents += [Environment]::NewLine + "FROM $($Database).[dbo].[tb_ConsolidatedWSUSEvents]"
            $GetWSUSEvents += [Environment]::NewLine + "WHERE [WSUSServer] = '$($ServerString)'"
        }

        Return $GetWSUSEvents
    }
}
