#Requires -Modules Pester, PSSQLite

<#
.SYNOPSIS
    Unit tests for SQLite helper functions

.DESCRIPTION
    Pester tests for AD Inventory SQLite operations.
    These tests use in-memory SQLite databases for isolated testing.

.NOTES
    Run with: Invoke-Pester -Path .\SQLite.Tests.ps1
    Requires: Pester 5.0+, PSSQLite module
#>

BeforeAll {
    # Import functions to test
    $sqlitePath = Join-Path $PSScriptRoot "../../Private/SQLite"
    $utilityPath = Join-Path $PSScriptRoot "../../Private/Utility"

    . (Join-Path $sqlitePath "Invoke-SQLiteTransaction.ps1")
    . (Join-Path $sqlitePath "Initialize-ADInventorySchema.ps1")
    . (Join-Path $sqlitePath "Add-SQLiteBatch.ps1")

    # Import dependencies
    . (Join-Path $utilityPath "Write-ADInventoryLog.ps1")

    # Check if PSSQLite is available
    $psSqliteAvailable = $null -ne (Get-Module -Name PSSQLite -ListAvailable)
    if (-not $psSqliteAvailable) {
        Write-Warning "PSSQLite module not found. Some tests will be skipped. Install with: Install-Module PSSQLite"
    }
}

Describe "Invoke-SQLiteTransaction" -Skip:(-not $psSqliteAvailable) {
    BeforeEach {
        # Create in-memory database for each test
        $script:conn = New-SqliteConnection -DataSource ":memory:"
        Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "CREATE TABLE test (id INTEGER, value TEXT)"
    }

    AfterEach {
        if ($script:conn) {
            $script:conn.Close()
            $script:conn.Dispose()
        }
    }

    Context "Successful Transactions" {
        It "Commits transaction on success" {
            $result = Invoke-SQLiteTransaction -Connection $script:conn -ScriptBlock {
                Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "INSERT INTO test VALUES (1, 'test')"
                return "success"
            }

            $result | Should -Be "success"

            $data = Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "SELECT * FROM test"
            $data.Count | Should -Be 1
            $data.id | Should -Be 1
        }

        It "Supports return values from script block" {
            $result = Invoke-SQLiteTransaction -Connection $script:conn -ScriptBlock {
                Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "INSERT INTO test VALUES (1, 'test')"
                return 42
            }

            $result | Should -Be 42
        }

        It "Allows multiple operations in one transaction" {
            Invoke-SQLiteTransaction -Connection $script:conn -ScriptBlock {
                Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "INSERT INTO test VALUES (1, 'one')"
                Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "INSERT INTO test VALUES (2, 'two')"
                Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "INSERT INTO test VALUES (3, 'three')"
            }

            $data = Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "SELECT * FROM test"
            $data.Count | Should -Be 3
        }
    }

    Context "Failed Transactions" {
        It "Rolls back transaction on exception" {
            {
                Invoke-SQLiteTransaction -Connection $script:conn -ScriptBlock {
                    Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "INSERT INTO test VALUES (1, 'test')"
                    throw "Simulated error"
                }
            } | Should -Throw

            # Verify rollback - no data should be inserted
            $data = Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "SELECT * FROM test"
            $data.Count | Should -Be 0
        }

        It "Rolls back on SQL error" {
            {
                Invoke-SQLiteTransaction -Connection $script:conn -ScriptBlock {
                    Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "INSERT INTO test VALUES (1, 'test')"
                    # Invalid SQL - should cause rollback
                    Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "INSERT INTO nonexistent_table VALUES (1)"
                }
            } | Should -Throw

            # Verify rollback - first insert should also be rolled back
            $data = Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "SELECT * FROM test"
            $data.Count | Should -Be 0
        }

        It "Provides meaningful error messages" {
            {
                Invoke-SQLiteTransaction -Connection $script:conn -ScriptBlock {
                    throw "Custom error message"
                }
            } | Should -Throw "*Custom error message*"
        }
    }

    Context "Isolation Levels" {
        It "Supports Deferred isolation level" {
            { Invoke-SQLiteTransaction -Connection $script:conn -IsolationLevel Deferred -ScriptBlock {} } | Should -Not -Throw
        }

        It "Supports Immediate isolation level" {
            { Invoke-SQLiteTransaction -Connection $script:conn -IsolationLevel Immediate -ScriptBlock {} } | Should -Not -Throw
        }

        It "Supports Exclusive isolation level" {
            { Invoke-SQLiteTransaction -Connection $script:conn -IsolationLevel Exclusive -ScriptBlock {} } | Should -Not -Throw
        }
    }

    Context "Connection Validation" {
        It "Throws if connection is not open" {
            $closedConn = New-SqliteConnection -DataSource ":memory:"
            $closedConn.Close()

            { Invoke-SQLiteTransaction -Connection $closedConn -ScriptBlock {} } | Should -Throw "*not open*"

            $closedConn.Dispose()
        }
    }
}

Describe "Initialize-ADInventorySchema" -Skip:(-not $psSqliteAvailable) {
    BeforeEach {
        $script:conn = New-SqliteConnection -DataSource ":memory:"
    }

    AfterEach {
        if ($script:conn) {
            $script:conn.Close()
            $script:conn.Dispose()
        }
    }

    Context "Schema Creation" {
        It "Creates schema successfully" {
            { Initialize-ADInventorySchema -Connection $script:conn } | Should -Not -Throw

            # Verify tables exist
            $tables = Invoke-SqliteQuery -SQLiteConnection $script:conn -Query @"
SELECT name FROM sqlite_master WHERE type='table' AND name IN ('AD_Object', 'AD_GroupMembership', 'AD_ForeignSecurityPrincipal', 'AD_Trust')
"@
            $tables.Count | Should -BeGreaterThan 3
        }

        It "Creates indexes" {
            Initialize-ADInventorySchema -Connection $script:conn

            $indexes = Invoke-SqliteQuery -SQLiteConnection $script:conn -Query @"
SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'IX_%'
"@
            $indexes.Count | Should -BeGreaterThan 0
        }

        It "Sets PRAGMA options correctly" {
            Initialize-ADInventorySchema -Connection $script:conn

            $foreignKeys = Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "PRAGMA foreign_keys"
            $foreignKeys.foreign_keys | Should -Be 1

            $journalMode = Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "PRAGMA journal_mode"
            $journalMode.journal_mode.ToLower() | Should -Be 'wal'
        }

        It "Creates Schema_Version table" {
            Initialize-ADInventorySchema -Connection $script:conn

            $version = Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "SELECT Version FROM Schema_Version"
            $version | Should -Not -BeNullOrEmpty
            $version.Version | Should -Match '^\d+\.\d+\.\d+$'
        }
    }

    Context "Schema Validation" {
        It "Prevents duplicate schema creation" {
            Initialize-ADInventorySchema -Connection $script:conn

            # Second attempt should fail
            { Initialize-ADInventorySchema -Connection $script:conn } | Should -Throw "*already exists*"
        }

        It "Allows recreation with Force parameter" {
            Initialize-ADInventorySchema -Connection $script:conn

            # Should succeed with Force
            { Initialize-ADInventorySchema -Connection $script:conn -Force -Confirm:$false } | Should -Not -Throw
        }
    }

    Context "Connection Validation" {
        It "Throws if connection is not open" {
            $closedConn = New-SqliteConnection -DataSource ":memory:"
            $closedConn.Close()

            { Initialize-ADInventorySchema -Connection $closedConn } | Should -Throw "*not open*"

            $closedConn.Dispose()
        }
    }
}

Describe "Get-TableInsertStatement" -Skip:(-not $psSqliteAvailable) {
    Context "INSERT Statement Generation" {
        It "Generates valid INSERT for AD_Object" {
            $sql = Get-TableInsertStatement -TableName "AD_Object"
            $sql | Should -Match "INSERT INTO AD_Object"
            $sql | Should -Match "@SID"
            $sql | Should -Match "@ObjectType"
        }

        It "Generates valid INSERT for AD_GroupMembership" {
            $sql = Get-TableInsertStatement -TableName "AD_GroupMembership"
            $sql | Should -Match "INSERT INTO AD_GroupMembership"
            $sql | Should -Match "@GroupSID"
            $sql | Should -Match "@MemberSID"
        }

        It "Throws for unknown table" {
            { Get-TableInsertStatement -TableName "UnknownTable" } | Should -Throw
        }
    }
}

Describe "Add-SQLiteBatch" -Skip:(-not $psSqliteAvailable) {
    BeforeEach {
        $script:conn = New-SqliteConnection -DataSource ":memory:"
        Initialize-ADInventorySchema -Connection $script:conn
    }

    AfterEach {
        if ($script:conn) {
            $script:conn.Close()
            $script:conn.Dispose()
        }
    }

    Context "Batch Insertion" {
        It "Inserts group memberships successfully" {
            $memberships = @(
                [PSCustomObject]@{
                    GroupSID = [byte[]](1,2,3,4)
                    MemberSID = [byte[]](5,6,7,8)
                    InventoryID = "test-123"
                },
                [PSCustomObject]@{
                    GroupSID = [byte[]](1,2,3,4)
                    MemberSID = [byte[]](9,10,11,12)
                    InventoryID = "test-123"
                }
            )

            $count = Add-SQLiteBatch -Connection $script:conn `
                -Objects $memberships `
                -TableName "AD_GroupMembership" `
                -ShowProgress $false

            $count | Should -Be 2

            # Verify data
            $data = Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "SELECT COUNT(*) as cnt FROM AD_GroupMembership"
            $data.cnt | Should -Be 2
        }

        It "Returns 0 for empty array" {
            $count = Add-SQLiteBatch -Connection $script:conn `
                -Objects @() `
                -TableName "AD_GroupMembership" `
                -ShowProgress $false

            $count | Should -Be 0
        }

        It "Handles large batches" {
            # Create 100 test memberships
            $memberships = 1..100 | ForEach-Object {
                [PSCustomObject]@{
                    GroupSID = [byte[]](1,2,3,4)
                    MemberSID = [byte[]]($_,2,3,4)
                    InventoryID = "test-123"
                }
            }

            $count = Add-SQLiteBatch -Connection $script:conn `
                -Objects $memberships `
                -TableName "AD_GroupMembership" `
                -BatchSize 25 `
                -ShowProgress $false

            $count | Should -Be 100

            # Verify all inserted
            $data = Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "SELECT COUNT(*) as cnt FROM AD_GroupMembership"
            $data.cnt | Should -Be 100
        }
    }

    Context "Transaction Safety" {
        It "Rolls back entire batch on error" {
            # Create objects with one that will fail
            $trusts = @(
                [PSCustomObject]@{
                    SourceDomain = "domain1.com"
                    TargetDomain = "domain2.com"
                    TrustType = "External"
                    TrustDirection = "Inbound"
                    TrustAttributes = 0
                    IsTransitive = 0
                    WhenCreated = $null
                    InventoryID = "test-123"
                }
            )

            # Insert first batch successfully
            Add-SQLiteBatch -Connection $script:conn -Objects $trusts -TableName "AD_Trust" -ShowProgress $false

            # Try to insert same (will fail on primary key)
            { Add-SQLiteBatch -Connection $script:conn -Objects $trusts -TableName "AD_Trust" -ShowProgress $false } | Should -Throw

            # Verify only first batch exists
            $data = Invoke-SqliteQuery -SQLiteConnection $script:conn -Query "SELECT COUNT(*) as cnt FROM AD_Trust"
            $data.cnt | Should -Be 1
        }
    }
}
