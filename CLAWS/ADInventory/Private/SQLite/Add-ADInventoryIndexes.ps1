function Add-ADInventoryIndexes {
    <#
    .SYNOPSIS
        Creates indexes on AD Inventory database tables for query performance

    .DESCRIPTION
        Extracts and executes CREATE INDEX statements from the schema file.
        This is called after bulk data loading to optimize query performance
        while avoiding the overhead of maintaining indexes during inserts.

        Performance optimization strategy:
        1. Load tables without indexes (fast bulk insert)
        2. Load all data
        3. Create indexes once at the end (one-time cost)

    .PARAMETER Connection
        The SQLite connection object (must be open)

    .PARAMETER SchemaPath
        Optional path to the schema SQL file
        If not provided, uses the default schema from module Resources folder

    .OUTPUTS
        Returns the number of indexes created

    .EXAMPLE
        $conn = New-SqliteConnection -DataSource "inventory.db"
        try {
            Add-ADInventoryIndexes -Connection $conn
            Write-Host "Indexes created successfully"
        } finally {
            $conn.Close()
        }

    .NOTES
        Part of SSNC.ADInventory module

        This function should only be called after all data has been loaded
        into the database. Creating indexes on large tables can take several
        minutes but dramatically improves query performance.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Data.SQLite.SQLiteConnection]$Connection,

        [Parameter(Mandatory = $false)]
        [string]$SchemaPath
    )

    process {
        # Validate connection state
        if ($Connection.State -ne [System.Data.ConnectionState]::Open) {
            throw "SQLite connection is not open. Current state: $($Connection.State)"
        }

        # Determine schema file path
        if (-not $SchemaPath) {
            # Use default schema from module Resources
            $modulePath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
            $SchemaPath = Join-Path $modulePath "ADInventory\Resources\Schema\ADInventory.sql"
        }

        # Verify schema file exists
        if (-not (Test-Path $SchemaPath -PathType Leaf)) {
            throw "Schema file not found: $SchemaPath"
        }

        Write-ADInventoryLog -Level Info -Message "Creating database indexes for query optimization"

        try {
            # Read schema SQL file
            $schemaSql = Get-Content -Path $SchemaPath -Raw -ErrorAction Stop

            # Extract only CREATE INDEX statements
            $sqlStatements = $schemaSql -split ';' | Where-Object { $_.Trim() }
            $indexStatements = $sqlStatements | Where-Object {
                $_ -match '^\s*CREATE\s+INDEX'
            }

            if ($indexStatements.Count -eq 0) {
                Write-ADInventoryLog -Level Warning -Message "No CREATE INDEX statements found in schema"
                return 0
            }

            Write-ADInventoryLog -Level Info -Message "Creating indexes" `
                -Context @{
                    IndexCount = $indexStatements.Count
                    DatabasePath = $Connection.DataSource
                }

            $createdCount = 0
            $startTime = Get-Date

            foreach ($indexSql in $indexStatements) {
                try {
                    # Extract index name for logging
                    if ($indexSql -match 'CREATE\s+INDEX\s+(\S+)') {
                        $indexName = $Matches[1]
                    } else {
                        $indexName = "Unknown"
                    }

                    Write-ADInventoryLog -Level Debug -Message "Creating index" `
                        -Context @{ IndexName = $indexName }

                    Invoke-SqliteQuery -SQLiteConnection $Connection -Query "$indexSql;" -ErrorAction Stop
                    $createdCount++
                }
                catch {
                    Write-ADInventoryLog -Level Warning -Message "Failed to create index" `
                        -Context @{
                            IndexName = $indexName
                            SQL = $indexSql
                        } `
                        -Exception $_.Exception
                    # Continue with other indexes
                }
            }

            $duration = ((Get-Date) - $startTime).TotalSeconds

            Write-ADInventoryLog -Level Info -Message "Indexes created successfully" `
                -Context @{
                    IndexesCreated = $createdCount
                    TotalIndexes = $indexStatements.Count
                    DurationSeconds = [Math]::Round($duration, 2)
                }

            return $createdCount
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to create indexes" `
                -Exception $_.Exception
            throw
        }
    }
}
