function Invoke-SQLiteTransaction {
    <#
    .SYNOPSIS
        Executes a script block within a SQLite transaction with automatic rollback on failure

    .DESCRIPTION
        Wraps database operations in a transaction (BEGIN/COMMIT) with automatic ROLLBACK
        on exceptions. This fixes the critical bug in the original script where transactions
        were not rolled back on errors, leading to partial data commits.

        CRITICAL FIX from original script lines 827-866:
        - Original: No ROLLBACK on exception = partial data committed
        - Fixed: Automatic ROLLBACK ensures all-or-nothing transaction semantics

    .PARAMETER Connection
        The SQLite connection object (from PSSQLite module)

    .PARAMETER ScriptBlock
        The script block containing database operations to execute within transaction

    .PARAMETER IsolationLevel
        Transaction isolation level (default: Deferred)
        - Deferred: Transaction starts on first read/write (recommended)
        - Immediate: Lock acquired immediately
        - Exclusive: Exclusive lock for entire transaction

    .OUTPUTS
        Returns the result of the script block execution

    .EXAMPLE
        $conn = New-SqliteConnection -DataSource "inventory.db"
        try {
            Invoke-SQLiteTransaction -Connection $conn -ScriptBlock {
                Invoke-SqliteQuery -SQLiteConnection $conn -Query "INSERT INTO ..."
                Invoke-SqliteQuery -SQLiteConnection $conn -Query "INSERT INTO ..."
                # Both inserts or neither - atomic transaction
            }
        } finally {
            $conn.Close()
        }

    .EXAMPLE
        # With error handling
        try {
            $result = Invoke-SQLiteTransaction -Connection $conn -ScriptBlock {
                # Database operations here
                Invoke-SqliteQuery -SQLiteConnection $conn -Query $sql -SqlParameters $params
                return $someValue
            }
        }
        catch {
            Write-Error "Transaction failed and was rolled back: $_"
        }

    .NOTES
        Part of SSNC.ADInventory module

        Transaction Safety:
        - Automatically begins transaction
        - Commits on success
        - Rolls back on any exception
        - Provides atomicity guarantee

        Improvements over original script:
        - Automatic rollback on exceptions
        - No partial data commits possible
        - Clean transaction boundary management
        - Supports nested transactions via savepoints (future enhancement)

        Performance Notes:
        - WAL mode (set in schema) allows concurrent reads during write transaction
        - Deferred isolation level provides best performance for most cases
        - Batch multiple operations in single transaction for best performance
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Data.SQLite.SQLiteConnection]$Connection,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Deferred', 'Immediate', 'Exclusive')]
        [string]$IsolationLevel = 'Deferred'
    )

    process {
        # Validate connection state
        if ($Connection.State -ne [System.Data.ConnectionState]::Open) {
            throw "SQLite connection is not open. Current state: $($Connection.State)"
        }

        $inTransaction = $false
        $transactionStartTime = Get-Date

        try {
            # Begin transaction with specified isolation level
            $beginCommand = switch ($IsolationLevel) {
                'Deferred'  { "BEGIN DEFERRED TRANSACTION" }
                'Immediate' { "BEGIN IMMEDIATE TRANSACTION" }
                'Exclusive' { "BEGIN EXCLUSIVE TRANSACTION" }
            }

            Write-ADInventoryLog -Level Debug -Message "Starting SQLite transaction" `
                -Context @{
                    IsolationLevel = $IsolationLevel
                    ConnectionState = $Connection.State.ToString()
                }

            Invoke-SqliteQuery -SQLiteConnection $Connection -Query $beginCommand
            $inTransaction = $true

            # Execute the script block within transaction
            Write-ADInventoryLog -Level Debug -Message "Executing transaction script block"
            $result = & $ScriptBlock

            # Commit transaction
            Write-ADInventoryLog -Level Debug -Message "Committing SQLite transaction"
            Invoke-SqliteQuery -SQLiteConnection $Connection -Query "COMMIT"
            $inTransaction = $false

            $duration = ((Get-Date) - $transactionStartTime).TotalSeconds
            Write-ADInventoryLog -Level Verbose -Message "SQLite transaction completed successfully" `
                -Context @{
                    DurationSeconds = [Math]::Round($duration, 2)
                }

            return $result
        }
        catch [System.Data.SQLite.SQLiteException] {
            $errorContext = @{
                ErrorCode = $_.Exception.ErrorCode
                SQLiteErrorCode = $_.Exception.ResultCode
                Message = $_.Exception.Message
            }

            if ($inTransaction) {
                try {
                    Write-ADInventoryLog -Level Warning -Message "SQLite exception occurred, rolling back transaction" `
                        -Context $errorContext

                    Invoke-SqliteQuery -SQLiteConnection $Connection -Query "ROLLBACK"
                    $inTransaction = $false

                    Write-ADInventoryLog -Level Info -Message "Transaction rolled back successfully"
                }
                catch {
                    Write-ADInventoryLog -Level Error -Message "CRITICAL: Failed to rollback transaction" `
                        -Exception $_.Exception

                    # Connection may be in bad state, recommend closing
                    throw "Transaction rollback failed. Connection may be corrupted: $_"
                }
            }

            Write-ADInventoryLog -Level Error -Message "SQLite transaction failed" `
                -Context $errorContext `
                -Exception $_.Exception

            throw "SQLite transaction failed: $($_.Exception.Message)"
        }
        catch {
            if ($inTransaction) {
                try {
                    Write-ADInventoryLog -Level Warning -Message "Exception occurred in transaction, rolling back" `
                        -Context @{
                            ExceptionType = $_.Exception.GetType().FullName
                            Message = $_.Exception.Message
                        }

                    Invoke-SqliteQuery -SQLiteConnection $Connection -Query "ROLLBACK"
                    $inTransaction = $false

                    Write-ADInventoryLog -Level Info -Message "Transaction rolled back successfully"
                }
                catch {
                    Write-ADInventoryLog -Level Error -Message "CRITICAL: Failed to rollback transaction" `
                        -Exception $_.Exception

                    throw "Transaction rollback failed. Connection may be corrupted: $_"
                }
            }

            Write-ADInventoryLog -Level Error -Message "Transaction script block failed" `
                -Exception $_.Exception

            throw
        }
        finally {
            # Safety net: Ensure transaction is not left open
            if ($inTransaction) {
                try {
                    Write-ADInventoryLog -Level Warning -Message "Transaction still open in finally block, attempting rollback"
                    Invoke-SqliteQuery -SQLiteConnection $Connection -Query "ROLLBACK"
                }
                catch {
                    Write-ADInventoryLog -Level Error -Message "Failed to rollback transaction in finally block" `
                        -Exception $_.Exception
                }
            }
        }
    }
}
