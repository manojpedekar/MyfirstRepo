Class LDAPQueryTest {
    [string]$Username
    [string]$TargetDomainController
    [string]$Domain
    [int]$Port
    [double]$responseTime
    [string]$Status
    
    LDAPQueryTest([string]$Username, [string]$TargetDomainController, [string]$Domain, [int]$Port = 636) {
        $this.Username = $Username
        $this.TargetDomainController = $TargetDomainController
        $this.Domain = $Domain
        $this.Port = $Port
        $this.TestQuery()
    }
    
    [void]TestQuery() {

        Try {
            # Verify network connection to the domain controller
            $connectionTest = Test-Netconnection -ComputerName $this.TargetDomainController -Port $this.Port
            If ($connectionTest.TcpTestSucceeded) {
                $DomainDN = "DC=$($this.Domain.replace(".", ",DC="))"
                $DNPath = "LDAP://$($this.TargetDomainController):$($this.Port)/$DomainDN"
                $Searcher = [ADSISearcher]$DomainDN
                $Searcher.Filter = "(cn=$($this.Username))"
                
                # Measure query time
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $Container = $Searcher.FindAll()
                $stopwatch.Stop()
                
                $this.ResponseTime = $stopwatch.Elapsed.TotalMilliseconds
                $this.Status = "Success"
            } Else {
                $this.Status = "Port Failed"
            }
        } Catch {
            $this.Status = "Error: $($_.Exception.Message)"
        }
        
    }
}

Class LDAPTestParams {
    [string]$TargetDomain
    [string]$LDAPUserToQuery
    [string]$WorkingDir
    [int]$NumberOfTests
    [int32]$DataFileSize = 104857600
    
    # Properties for directory paths
    [string]$LogFileDirectory
    [string]$ConfigDirectory
    [string]$DataFileDirectory
    
    # Properties for file names
    [string]$DataFileName
    [string]$LogFileFN
    [string]$ConfigFileFN
    [string]$DataFileFN
    
    # Property for the Test location
    [string]$TestLocation
    
    LDAPTestParams([string]$targetDomain, [string]$workingDir, [string]$LDAPUserToQuery, [int]$NumberOfTests) {
        $this.TargetDomain = $targetDomain
        $this.WorkingDir = $workingDir
        $this.LDAPUserToQuery = $LDAPUserToQuery
        $this.NumberOfTests = $NumberOfTests
        
        # Initialize directories based on working directory
        $this.InitializeDirectories()
        # Define file names
        $this.DefineFileNames()
        $this.GetTestSystemFQDN()
        
    }
    
    [void]InitializeDirectories() {
        $this.LogFileDirectory = Join-Path -Path $this.WorkingDir -ChildPath "Logs"
        $this.ConfigDirectory = Join-Path -Path $this.WorkingDir -ChildPath "Config"
        $this.DataFileDirectory = Join-Path -Path $this.WorkingDir -ChildPath "Output"
        
        # Ensure directories exist
        @($this.LogFileDirectory, $this.ConfigDirectory, $this.DataFileDirectory) | ForEach-Object {
            If (-not (Test-Path $_)) {
                New-Item -Path $_ -ItemType Directory | Out-Null
            }
        }
    }
    [void]GetTestSystemFQDN() {
        $hostName = [System.Net.Dns]::GetHostName()
        $this.TestLocation = [System.Net.Dns]::GetHostEntry($hostName).HostName
    }
    
    [void]DefineFileNames() {
        $fileTime = Get-Date -Format "yyyyMMddHHmmss"
        $userName = $env:USERNAME
        
        $this.DataFileName = "$($this.TargetDomain)-ldaptimes.csv"
        $this.DataFileFN = Join-Path -Path $this.DataFileDirectory -ChildPath $this.DataFileName
        
        $logFileName = "Test-MeasureLDAPResponse-$userName$fileTime.log"
        $this.LogFileFN = Join-Path -Path $this.LogFileDirectory -ChildPath $logFileName
        
        $configFileName = "$($this.TargetDomain).cfg"
        $this.ConfigFileFN = Join-Path -Path $this.ConfigDirectory -ChildPath $configFileName
    }
}

Class LDAPTestRecord {
    [DateTime]$DateTime
    [string]$Name
    [string]$DeviceType
    [double]$ResponseTime
    [string]$Status
    [string]$TestLocation
    
    LDAPTestRecord([string]$Name, [string]$DeviceType, [double]$ResponseTime, [string]$Status, [string]$TestLocation) {
        $this.DateTime = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fff'
        $this.Name = $Name
        $this.DeviceType = $DeviceType
        $this.ResponseTime = $ResponseTime
        $this.Status = $Status
        $this.TestLocation = $TestLocation
    }
    
    # Method to create DataRow from this instance
    [System.Data.DataRow]CreateDataRow([System.Data.DataTable]$DataTable) {
        $DataRow = $DataTable.NewRow()
        
        $DataRow["DateTime"] = $this.DateTime
        $DataRow["Name"] = $this.Name
        $DataRow["DeviceType"] = $this.DeviceType
        $DataRow["ResponseTime"] = $this.ResponseTime
        $DataRow["Status"] = $this.Status
        $DataRow["TestLocation"] = $this.TestLocation
        
        $DataTable.Rows.Add($DataRow)
        Return $DataRow
    }
    
    # Static method to create an instance, add to DataTable, and return a DataRow
    Static [System.Data.DataRow]NewDataRow([string]$Name, [string]$DeviceType, [double]$ResponseTime, [string]$Status, [string]$TestLocation, [System.Data.DataTable]$DataTable) {
        $record = [LDAPTestRecord]::new($Name, $DeviceType, $ResponseTime, $Status, $TestLocation)
        Return $record.CreateDataRow($DataTable)
    }
    
}

Class DataTableManager {
    [System.Data.DataTable]$DataTable
    
    DataTableManager() {
        $this.DataTable = New-Object System.Data.DataTable
        $this.InitializeDataTable()
    }
    
    [void]InitializeDataTable() {
        [void]$this.DataTable.Columns.Add("DateTime", [System.Type]::GetType("System.DateTime"))
        [void]$this.DataTable.Columns.Add("Name", [System.Type]::GetType("System.String"))
        [void]$this.DataTable.Columns.Add("DeviceType", [System.Type]::GetType("System.String"))
        [void]$this.DataTable.Columns.Add("ResponseTime", [System.Type]::GetType("System.Double"))
        [void]$this.DataTable.Columns.Add("Status", [System.Type]::GetType("System.String"))
        [void]$this.DataTable.Columns.Add("TestLocation", [System.Type]::GetType("System.String"))
    }
   
    [void]ClearTable() {
        $this.DataTable.Rows.Clear()
    }
    
    [void]ExportToCSV([string]$FilePath) {
        $this.DataTable | Export-Csv -Path $FilePath -NoTypeInformation -Append
    }
    
    [PSCustomObject]SQLBulkInsert([string]$SQLServer, [string]$SQLDB, [string]$SQLTable, [string]$SQLSchema,[int]$SQLPort) {
        
        $connectionString = "Server=$($SQLServer),$SQLPort;Initial Catalog=$($SQLDB);Trusted_Connection=True;"
        $Connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $bulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy($Connection)
        $bulkCopy.DestinationTableName = "[$SQLSchema].[$SQLTable]"
        
        $results = [PSCustomObject]@{
            RecordCount = 0
            Message     = "No Action Taken"
        }
        
        Try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $Connection.Open()
            $bulkCopy.WriteToServer($this.DataTable)
            $results.RecordCount = $this.DataTable.Rows.Count
            $stopwatch.Stop()
            $results.Message = "Successfully transferred records to the SQL Server in $($stopwatch.Elapsed.TotalMilliseconds)ms"
        } Catch {
            $results.Message = "An error occurred during SQL Bulk Insert: $_"
            Throw $results.Message
        } Finally {
            $bulkCopy.Close()
            If ($Connection.State -eq 'Open') {
                $Connection.Close()
            }
        }
        
        Return $results
    }
}
