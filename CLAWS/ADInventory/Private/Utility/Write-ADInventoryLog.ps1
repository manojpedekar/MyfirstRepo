function Write-ADInventoryLog {
    <#
    .SYNOPSIS
        Centralized logging function for AD Inventory operations

    .DESCRIPTION
        Provides consistent logging across all AD Inventory module functions.
        Supports multiple log levels (Error, Warning, Info, Verbose, Debug) and
        structured context information for troubleshooting.

        Writes to three destinations:
        1. PowerShell streams (console output)
        2. Local log file (if configured)
        3. SQLite database (if configured)

        Replaces inconsistent Write-Host/Write-Warning/Write-Error usage in original script.

    .PARAMETER Level
        Log level: Error, Warning, Info, Verbose, or Debug

    .PARAMETER Message
        The log message to write

    .PARAMETER Category
        Optional log category: Initialization, Connection, Collection, Database, Checkpoint, Parallel, Completion

    .PARAMETER Context
        Optional hashtable of contextual information (domain, server, objectType, etc.)
        Will be formatted as key=value pairs in the log output

    .PARAMETER Exception
        Optional exception object for error logging

    .PARAMETER LogFilePath
        Optional explicit log file path. If not provided, uses module-scoped $Script:LogFilePath

    .PARAMETER DatabaseConnection
        Optional SQLite connection for database logging. If not provided, uses module-scoped $Script:LogDatabaseConnection

    .OUTPUTS
        None. Writes to PowerShell streams, log file, and database.

    .EXAMPLE
        Write-ADInventoryLog -Level Info -Message "Starting inventory collection" -Category Initialization

    .EXAMPLE
        Write-ADInventoryLog -Level Error -Message "Connection failed" `
            -Category Connection `
            -Context @{ Domain = "contoso.com"; Server = "DC01" } `
            -Exception $_.Exception

    .EXAMPLE
        Write-ADInventoryLog -Level Verbose -Message "Processing object" `
            -Category Collection `
            -Context @{ DN = $dn; ObjectType = "User" }

    .NOTES
        Part of SSNC.ADInventory module

        Log Levels:
        - Error: Critical failures that stop processing
        - Warning: Non-critical issues that may need attention
        - Info: Important informational messages (uses Write-Information)
        - Verbose: Detailed progress information (requires -Verbose)
        - Debug: Diagnostic information for troubleshooting (requires -Debug)

        Thread Safety:
        - File logging uses mutex for thread-safe writes in parallel scenarios
        - Database logging uses transactions for atomicity
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Error', 'Warning', 'Info', 'Verbose', 'Debug')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Initialization', 'Connection', 'Collection', 'Database', 'Checkpoint', 'Parallel', 'Completion', 'General')]
        [string]$Category = 'General',

        [Parameter(Mandatory = $false)]
        [hashtable]$Context = @{},

        [Parameter(Mandatory = $false)]
        [System.Exception]$Exception,

        [Parameter(Mandatory = $false)]
        [string]$LogFilePath,

        [Parameter(Mandatory = $false)]
        [object]$DatabaseConnection,

        [Parameter(Mandatory = $false)]
        [string]$CollectionID = $null  # GUID string for global uniqueness
    )

    process {
        # Format timestamp
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $timestampUtc = (Get-Date).ToUniversalTime()

        # Format context as key=value pairs
        $contextStr = ''
        $contextJson = $null
        if ($Context.Count -gt 0) {
            $contextPairs = $Context.GetEnumerator() | ForEach-Object {
                "$($_.Key)=$($_.Value)"
            }
            $contextStr = " | $($contextPairs -join ', ')"
            $contextJson = ($Context | ConvertTo-Json -Compress -Depth 3)
        }

        # Build log message
        $logMessage = "[$timestamp] [$Category] $Message$contextStr"

        # Add exception details if provided
        if ($Exception) {
            $logMessage += " | Exception: $($Exception.Message)"
            if ($Exception.StackTrace) {
                $logMessage += " | Stack: $($Exception.StackTrace -replace "`r`n", ' ' -replace "`n", ' ')"
            }
        }

        # Write to PowerShell streams based on level
        switch ($Level) {
            'Error' {
                if ($Exception) {
                    Write-Error -Message $logMessage -Exception $Exception -ErrorAction Continue
                }
                else {
                    Write-Error -Message $logMessage -ErrorAction Continue
                }
            }

            'Warning' {
                Write-Warning -Message $logMessage
            }

            'Info' {
                Write-Information -MessageData $logMessage -InformationAction Continue
            }

            'Verbose' {
                Write-Verbose -Message $logMessage
            }

            'Debug' {
                Write-Debug -Message $logMessage
            }
        }

        # Write to log file if configured
        $fileToUse = if ($LogFilePath) { $LogFilePath } else { $Script:ADInventoryLogFilePath }
        if ($fileToUse -and (Test-Path (Split-Path $fileToUse -Parent))) {
            try {
                # Thread-safe file writing using mutex
                $mutexName = "Global\ADInventoryLog_" + ([System.IO.Path]::GetFileName($fileToUse) -replace '[^a-zA-Z0-9]', '_')
                $mutex = $null
                $acquired = $false

                try {
                    $mutex = [System.Threading.Mutex]::new($false, $mutexName)
                    $acquired = $mutex.WaitOne(5000) # 5 second timeout

                    if ($acquired) {
                        # Build file log entry
                        $fileLogEntry = "[$timestamp] [$Level] [$Category] $Message"
                        if ($Context.Count -gt 0) {
                            $fileLogEntry += " | Context: $contextJson"
                        }
                        if ($Exception) {
                            $fileLogEntry += " | Exception: $($Exception.Message)"
                            if ($Exception.InnerException) {
                                $fileLogEntry += " | InnerException: $($Exception.InnerException.Message)"
                            }
                        }

                        # Append to log file
                        Add-Content -Path $fileToUse -Value $fileLogEntry -Encoding UTF8 -ErrorAction Stop
                    }
                }
                finally {
                    if ($acquired -and $mutex) {
                        $mutex.ReleaseMutex()
                    }
                    if ($mutex) {
                        $mutex.Dispose()
                    }
                }
            }
            catch {
                # Silently ignore file logging errors to not break execution
                Write-Debug "Failed to write to log file: $_"
            }
        }

        # Write to database if configured
        # CollectionID is now a GUID string for global uniqueness
        # MachineName and UserName are stored in AD_CollectionInfo, not in each log entry
        $dbToUse = if ($DatabaseConnection) { $DatabaseConnection } else { $Script:ADInventoryLogConnection }
        $collIdToUse = if (-not [string]::IsNullOrEmpty($CollectionID)) { $CollectionID } else { $Script:ADInventoryCollectionID }

        if ($dbToUse -and -not [string]::IsNullOrEmpty($collIdToUse)) {
            try {
                # Build database log entry (MachineName/UserName now in AD_CollectionInfo)
                $query = @"
INSERT INTO AD_Log (
    CollectionID,
    Timestamp,
    Level,
    Category,
    Message,
    Context,
    ExceptionMessage,
    ExceptionType
) VALUES (
    @CollectionID,
    @Timestamp,
    @Level,
    @Category,
    @Message,
    @Context,
    @ExceptionMessage,
    @ExceptionType
)
"@

                $params = @{
                    CollectionID = $collIdToUse
                    Timestamp = $timestampUtc.ToString('o')
                    Level = $Level
                    Category = $Category
                    Message = $Message
                    Context = $contextJson
                    ExceptionMessage = if ($Exception) { $Exception.Message } else { $null }
                    ExceptionType = if ($Exception) { $Exception.GetType().FullName } else { $null }
                }

                # Use PSSQLite with parameters
                Invoke-SqliteQuery -SQLiteConnection $dbToUse -Query $query -SqlParameters $params -ErrorAction Stop | Out-Null
            }
            catch {
                # Silently ignore database logging errors to not break execution
                Write-Debug "Failed to write to database log: $_"
            }
        }
    }
}

<#
.SYNOPSIS
    Helper function to set the current CollectionID for logging

.DESCRIPTION
    This function sets the module-scoped $Script:ADInventoryCollectionID variable.
    It exists because PowerShell 5.1 class methods run in a different scope than
    module functions, so setting $Script: from a class method doesn't propagate
    to functions that read $Script: variables.

    This function bridges the scope gap - class methods call this function,
    which runs in the module's script scope and properly sets the variable.

.PARAMETER CollectionID
    The CollectionID (GUID string) to set as the current active collection for logging

.NOTES
    Part of SSNC.ADInventory module
    Called by SQLiteInventoryWriter.SetCurrentDomain()
#>
function Set-ADInventoryCollectionID {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$CollectionID  # GUID string for global uniqueness
    )

    $Script:ADInventoryCollectionID = $CollectionID
}

<#
.SYNOPSIS
    Helper function to get the module version

.DESCRIPTION
    This function returns the module-scoped $Script:ModuleVersion variable.
    It exists because PowerShell 5.1 class methods run in a different scope than
    module functions, so reading $Script: from a class method doesn't work correctly.

    This function bridges the scope gap - class methods call this function,
    which runs in the module's script scope and properly reads the variable.

.OUTPUTS
    [string] The module version, or 'Unknown' if not available

.NOTES
    Part of SSNC.ADInventory module
    Called by SQLiteInventoryWriter.CreateCollectionInfo()
#>
function Get-ADInventoryModuleVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($Script:ModuleVersion) {
        return $Script:ModuleVersion
    }
    return 'Unknown'
}
