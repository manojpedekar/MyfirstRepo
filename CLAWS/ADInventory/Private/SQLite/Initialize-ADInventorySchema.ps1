function Initialize-ADInventorySchema {
    <#
    .SYNOPSIS
        Creates the AD Inventory database schema from external SQL file

    .DESCRIPTION
        Loads and executes the ADInventory.sql schema file to create tables,
        indexes, and initial data in a SQLite database.

        This fixes the issue from the original script where schema was hardcoded
        (lines 687-774), making it difficult to maintain and version.

    .PARAMETER Connection
        The SQLite connection object (must be open)

    .PARAMETER SchemaPath
        Optional path to the schema SQL file
        If not provided, uses the default schema from module Resources folder

    .PARAMETER Force
        If specified, drops existing tables before creating schema
        WARNING: This will delete all data!

    .OUTPUTS
        None. Throws exception if schema creation fails.

    .EXAMPLE
        $conn = New-SqliteConnection -DataSource "inventory.db"
        try {
            Initialize-ADInventorySchema -Connection $conn
            Write-Host "Schema created successfully"
        } finally {
            $conn.Close()
        }

    .EXAMPLE
        # Use custom schema file
        Initialize-ADInventorySchema -Connection $conn -SchemaPath "C:\Custom\Schema.sql"

    .EXAMPLE
        # Recreate schema (WARNING: deletes data)
        Initialize-ADInventorySchema -Connection $conn -Force

    .NOTES
        Part of SSNC.ADInventory module

        Improvements over original script:
        - Schema externalized to SQL file (maintainable)
        - Version tracking in Schema_Version table
        - Proper error handling
        - Optional schema validation
        - Force option for testing/development

        Schema Features:
        - Foreign key support enabled
        - WAL mode for better concurrency
        - Optimized cache settings
        - Comprehensive indexes
        - Version tracking
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Data.SQLite.SQLiteConnection]$Connection,

        [Parameter(Mandatory = $false)]
        [ValidateScript({
            if (Test-Path $_ -PathType Leaf) {
                $true
            } else {
                throw "Schema file not found: $_"
            }
        })]
        [string]$SchemaPath,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$SkipIndexes
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

            Write-ADInventoryLog -Level Debug -Message "Using default schema path" `
                -Context @{ SchemaPath = $SchemaPath }
        }

        # Verify schema file exists
        if (-not (Test-Path $SchemaPath -PathType Leaf)) {
            throw "Schema file not found: $SchemaPath"
        }

        Write-ADInventoryLog -Level Info -Message "Initializing AD Inventory database schema" `
            -Context @{
                SchemaPath = $SchemaPath
                Force = $Force.IsPresent
                DatabasePath = $Connection.DataSource
            }

        try {
            # Drop existing tables if Force specified
            if ($Force) {
                if ($PSCmdlet.ShouldProcess($Connection.DataSource, "Drop all tables and recreate schema")) {
                    Write-ADInventoryLog -Level Warning -Message "Force option specified - dropping existing tables"

                    $dropTables = @(
                        "DROP TABLE IF EXISTS AD_Trust",
                        "DROP TABLE IF EXISTS AD_ForeignSecurityPrincipal",
                        "DROP TABLE IF EXISTS AD_GroupMembership",
                        "DROP TABLE IF EXISTS AD_Object",
                        "DROP TABLE IF EXISTS Schema_Version"
                    )

                    foreach ($dropSql in $dropTables) {
                        Invoke-SqliteQuery -SQLiteConnection $Connection -Query $dropSql
                    }

                    Write-ADInventoryLog -Level Info -Message "Existing tables dropped"
                }
            }

            # Check if schema already exists
            $tableCheck = @"
SELECT COUNT(*) as TableCount
FROM sqlite_master
WHERE type='table' AND name IN ('AD_Object', 'AD_GroupMembership')
"@
            $existingTables = Invoke-SqliteQuery -SQLiteConnection $Connection -Query $tableCheck

            if ($existingTables.TableCount -gt 0 -and -not $Force) {
                Write-ADInventoryLog -Level Warning -Message "Schema tables already exist" `
                    -Context @{ ExistingTableCount = $existingTables.TableCount }

                throw "Database schema already exists. Use -Force to recreate (WARNING: deletes data)"
            }

            # Read schema SQL file
            Write-ADInventoryLog -Level Debug -Message "Reading schema file"
            $schemaSql = Get-Content -Path $SchemaPath -Raw -ErrorAction Stop

            # Filter out CREATE INDEX statements if SkipIndexes is specified
            if ($SkipIndexes) {
                Write-ADInventoryLog -Level Info -Message "Skipping index creation for performance optimization"

                # Split SQL into individual statements
                $sqlStatements = $schemaSql -split ';' | Where-Object { $_.Trim() }

                # Filter out CREATE INDEX statements
                $filteredStatements = $sqlStatements | Where-Object {
                    $_ -notmatch '^\s*CREATE\s+INDEX'
                }

                $schemaSql = ($filteredStatements -join ';') + ';'

                Write-ADInventoryLog -Level Debug -Message "Filtered schema SQL" `
                    -Context @{
                        OriginalStatements = $sqlStatements.Count
                        FilteredStatements = $filteredStatements.Count
                        IndexesSkipped = $sqlStatements.Count - $filteredStatements.Count
                    }
            }

            # Execute schema
            Write-ADInventoryLog -Level Info -Message "Executing schema SQL"
            Invoke-SqliteQuery -SQLiteConnection $Connection -Query $schemaSql -ErrorAction Stop

            # Verify schema creation
            $verifyQuery = @"
SELECT name, type
FROM sqlite_master
WHERE type IN ('table', 'index')
ORDER BY type, name
"@
            $schemaObjects = Invoke-SqliteQuery -SQLiteConnection $Connection -Query $verifyQuery

            $tableCount = ($schemaObjects | Where-Object { $_.type -eq 'table' }).Count
            $indexCount = ($schemaObjects | Where-Object { $_.type -eq 'index' }).Count

            Write-ADInventoryLog -Level Info -Message "Schema created successfully" `
                -Context @{
                    Tables = $tableCount
                    Indexes = $indexCount
                }

            # Get and log schema version
            $versionQuery = "SELECT Version, AppliedDate, Description FROM Schema_Version ORDER BY AppliedDate DESC LIMIT 1"
            $schemaVersion = Invoke-SqliteQuery -SQLiteConnection $Connection -Query $versionQuery

            if ($schemaVersion) {
                Write-ADInventoryLog -Level Info -Message "Schema version applied" `
                    -Context @{
                        Version = $schemaVersion.Version
                        Description = $schemaVersion.Description
                    }
            }

            # Verify PRAGMA settings
            $pragmas = @(
                @{ Name = 'foreign_keys'; Expected = 1 },
                @{ Name = 'journal_mode'; Expected = 'wal' }
            )

            foreach ($pragma in $pragmas) {
                $result = Invoke-SqliteQuery -SQLiteConnection $Connection -Query "PRAGMA $($pragma.Name)"
                $actualValue = $result.$($pragma.Name)

                if ($actualValue -ne $pragma.Expected) {
                    Write-ADInventoryLog -Level Warning -Message "PRAGMA setting unexpected" `
                        -Context @{
                            Setting = $pragma.Name
                            Expected = $pragma.Expected
                            Actual = $actualValue
                        }
                }
                else {
                    Write-ADInventoryLog -Level Debug -Message "PRAGMA verified" `
                        -Context @{
                            Setting = $pragma.Name
                            Value = $actualValue
                        }
                }
            }

            Write-ADInventoryLog -Level Info -Message "Schema initialization completed successfully"
        }
        catch [System.Data.SQLite.SQLiteException] {
            Write-ADInventoryLog -Level Error -Message "Failed to initialize schema: SQLite error" `
                -Context @{
                    ErrorCode = $_.Exception.ErrorCode
                    SQLiteErrorCode = $_.Exception.ResultCode
                } `
                -Exception $_.Exception

            throw "Schema initialization failed: $($_.Exception.Message)"
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to initialize schema" `
                -Context @{
                    SchemaPath = $SchemaPath
                } `
                -Exception $_.Exception

            throw "Schema initialization failed: $_"
        }
    }
}
