Function Export-DataTableToSQLite {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [System.Data.DataTable]$DataTable,
        [Parameter(Mandatory)]
        [string]$DatabasePath,
        [Parameter(Mandatory)]
        [string]$TableName,
        [int]$BatchSize = 10000
    )
    
    # Load SQLite library (adjust version/path as needed)
    $sqliteDll = Get-ChildItem "$env:USERPROFILE\AppData\Local\PackageManagement\NuGet\Packages" -Recurse -Filter "System.Data.SQLite.dll" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
    
    If (-not $sqliteDll) {
        Throw "System.Data.SQLite.dll not found. Install it using: Install-Package System.Data.SQLite.Core -Scope CurrentUser"
    }
    
    Add-Type -Path $sqliteDll.FullName
    
    $connectionString = "Data Source=$DatabasePath;Version=3;"
    $connection = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
    $connection.Open()
    
    # Build CREATE TABLE statement
    $typeMap = @{
        "System.String"   = "TEXT"
        "System.Int32"    = "INTEGER"
        "System.Int64"    = "INTEGER"
        "System.Boolean"  = "BOOLEAN"
        "System.DateTime" = "TEXT"
        "System.Guid"     = "TEXT"
        "System.Double"   = "REAL"
    }
    
    $columns = $DataTable.Columns | ForEach-Object {
        $colName = $_.ColumnName
        $sqliteType = $typeMap[$_.DataType.FullName]
        If (-not $sqliteType) {
            Throw "Unsupported column type: $($_.DataType.FullName)"
        }
        "[$colName] $sqliteType"
    }
    
    $createSql = "CREATE TABLE IF NOT EXISTS [$TableName] (" + ($columns -join ", ") + ");"
    $createCmd = $connection.CreateCommand()
    $createCmd.CommandText = $createSql
    $createCmd.ExecuteNonQuery()
    
    # Build INSERT statement
    $colNames = ($DataTable.Columns | ForEach-Object { "[$($_.ColumnName)]" }) -join ", "
    $placeholders = ($DataTable.Columns | ForEach-Object { "?" }) -join ", "
    $insertSql = "INSERT INTO [$TableName] ($colNames) VALUES ($placeholders)"
    
    $insertCmd = $connection.CreateCommand()
    $insertCmd.CommandText = $insertSql
    
    # Prepare parameters
    ForEach ($col In $DataTable.Columns) {
        $param = New-Object System.Data.SQLite.SQLiteParameter
        [void]$insertCmd.Parameters.Add($param)
    }
    
    # Insert rows in batches
    $transaction = $connection.BeginTransaction()
    $rowCount = 0
    $totalRows = $DataTable.Rows.Count
    
    ForEach ($row In $DataTable.Rows) {
        For ($i = 0; $i -lt $DataTable.Columns.Count; $i++) {
            $insertCmd.Parameters[$i].Value = $row[$i]
        }
        
        [void]$insertCmd.ExecuteNonQuery()
        $rowCount++
        
        If ($rowCount % $BatchSize -eq 0) {
            $transaction.Commit()
            Write-Progress -Activity "Exporting to SQLite" -Status "$rowCount of $totalRows rows inserted" -PercentComplete ([math]::Round(($rowCount / $totalRows) * 100))
            $transaction = $connection.BeginTransaction()
        }
    }
    
    $transaction.Commit()
    $connection.Close()
    Write-Progress -Activity "Exporting to SQLite" -Completed
    Write-Host " Export complete. Total rows inserted: $rowCount"
}


#Export-DataTableToSQLite -DataTable $table -DatabasePath "C:\Export\FSPermsAll.sqlite" -TableName "FileSystemAudit"



Function Import-SQLiteToSqlServer {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string]$SQLitePath,
        [Parameter(Mandatory)]
        [string]$SQLiteTable,
        [Parameter(Mandatory)]
        [string]$SqlServerTable,
        [Parameter(Mandatory)]
        [string]$SqlConnectionString
    )
    
    # Load SQLite driver
    $sqliteDll = Get-ChildItem "$env:USERPROFILE\AppData\Local\PackageManagement\NuGet\Packages" -Recurse -Filter "System.Data.SQLite.dll" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
    
    If (-not $sqliteDll) {
        Throw "System.Data.SQLite.dll not found. Install it using: Install-Package System.Data.SQLite.Core -Scope CurrentUser"
    }
    
    Add-Type -Path $sqliteDll.FullName
    
    # Connect to SQLite
    $sqliteConn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$SQLitePath;Version=3;")
    $sqliteConn.Open()
    
    # Query all rows
    $sqliteCmd = $sqliteConn.CreateCommand()
    $sqliteCmd.CommandText = "SELECT * FROM [$SQLiteTable]"
    $reader = $sqliteCmd.ExecuteReader()
    
    # Connect to SQL Server
    $sqlConn = New-Object System.Data.SqlClient.SqlConnection($SqlConnectionString)
    $sqlConn.Open()
    
    # Use SqlBulkCopy for fast insert
    $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy($sqlConn)
    $bulkCopy.DestinationTableName = $SqlServerTable
    $bulkCopy.BatchSize = 10000
    $bulkCopy.BulkCopyTimeout = 0
    
    Try {
        $bulkCopy.WriteToServer($reader)
        Write-Host "✅ Import complete from [$SQLiteTable] to [$SqlServerTable]"
    } Finally {
        $reader.Close()
        $sqliteConn.Close()
        $sqlConn.Close()
    }
}


$importParams = @{
    SQLitePath          = "C:\Lighthouse\AllScan\FSPermsAll.sqlite"
    SQLiteTable         = "FileSystemAudit"
    SqlServerTable      = "dbo.FileSystemAuditAll"
    SqlConnectionString = "Server=NA000555W10;Database=FSPerms;Integrated Security=True"
}

Import-SQLiteToSqlServer @importParams


