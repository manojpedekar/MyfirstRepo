function Write-ADExecutionTime {
    <#
    .SYNOPSIS
        Records execution timing for performance monitoring

    .DESCRIPTION
        Logs the duration of operations (LDAP queries, inserts, processing, etc.)
        to the AD_ExecutionTime table for performance analysis.

        Also writes an info log message for console visibility.

    .PARAMETER Operation
        The type of operation: LDAP_Query, Insert, Processing, Index, Finalize, etc.

    .PARAMETER Target
        What was operated on: Users, Groups, Computers, Trusts, FSPs, Memberships, etc.

    .PARAMETER DurationSeconds
        The duration of the operation in seconds (supports millisecond precision)

    .PARAMETER RecordCount
        Optional number of records processed/inserted

    .PARAMETER Domain
        Optional domain name if the operation is domain-specific

    .PARAMETER Details
        Optional hashtable with additional details (will be stored as JSON)

    .PARAMETER StartTime
        Optional start time of the operation (defaults to now minus duration)

    .PARAMETER Connection
        Optional SQLite connection. If not provided, uses module-scoped connection.

    .PARAMETER CollectionID
        Optional collection ID (GUID string). If not provided, uses module-scoped ID.

    .EXAMPLE
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $users = Get-ADObjects -Filter "(objectClass=user)" ...
        $stopwatch.Stop()

        Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'Users' `
            -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
            -RecordCount $users.Count -Domain 'contoso.com'

    .EXAMPLE
        # Using Measure-Command
        $result = Measure-Command { $inserted = Add-SQLiteBatch ... }

        Write-ADExecutionTime -Operation 'Insert' -Target 'AD_Object' `
            -DurationSeconds $result.TotalSeconds `
            -RecordCount $inserted

    .NOTES
        Part of SSNC.ADInventory module

        Operations:
        - LDAP_Query: Active Directory LDAP queries
        - DNS_Query: DNS SRV record queries (e.g., KMS discovery)
        - Insert: Database insert operations
        - Processing: Data transformation/processing
        - Index: Index creation
        - Finalize: Database finalization (ANALYZE, VACUUM)
        - Membership_Flatten: Recursive membership expansion
        - Trust_Enum: Trust enumeration
        - DC_Discovery: Domain controller discovery
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('LDAP_Query', 'DNS_Query', 'Insert', 'Processing', 'Index', 'Finalize', 'Membership_Flatten', 'Trust_Enum', 'DC_Discovery', 'GC_Collect', 'Total')]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [double]$DurationSeconds,

        [Parameter(Mandatory = $false)]
        [int]$RecordCount = 0,

        [Parameter(Mandatory = $false)]
        [string]$Domain,

        [Parameter(Mandatory = $false)]
        [hashtable]$Details,

        [Parameter(Mandatory = $false)]
        [datetime]$StartTime,

        [Parameter(Mandatory = $false)]
        [object]$Connection,

        [Parameter(Mandatory = $false)]
        [string]$CollectionID = $null  # GUID string for global uniqueness
    )

    process {
        # Calculate throughput
        $recordsPerSec = if ($RecordCount -gt 0 -and $DurationSeconds -gt 0) {
            [Math]::Round($RecordCount / $DurationSeconds, 2)
        } else { $null }

        # Determine start time
        $operationStartTime = if ($StartTime) {
            $StartTime.ToUniversalTime()
        } else {
            (Get-Date).AddSeconds(-$DurationSeconds).ToUniversalTime()
        }

        # Format duration for display
        $durationFormatted = if ($DurationSeconds -ge 60) {
            "{0:N1} min" -f ($DurationSeconds / 60)
        } elseif ($DurationSeconds -ge 1) {
            "{0:N2} sec" -f $DurationSeconds
        } else {
            "{0:N0} ms" -f ($DurationSeconds * 1000)
        }

        # Build log context
        $logContext = @{
            Operation = $Operation
            Target    = $Target
            Duration  = $durationFormatted
        }
        if ($RecordCount -gt 0) {
            $logContext['RecordCount'] = $RecordCount
        }
        if ($recordsPerSec) {
            $logContext['RecordsPerSec'] = $recordsPerSec
        }
        if ($Domain) {
            $logContext['Domain'] = $Domain
        }

        # Write info log for visibility
        Write-ADInventoryLog -Level Info -Message "Execution time: $Operation - $Target" `
            -Category 'Database' `
            -Context $logContext

        # Get connection and collection ID (CollectionID is now a GUID string)
        $dbToUse = if ($Connection) { $Connection } else { $Script:ADInventoryLogConnection }
        $collIdToUse = if (-not [string]::IsNullOrEmpty($CollectionID)) { $CollectionID } else { $Script:ADInventoryCollectionID }

        # Write to database if configured
        if ($dbToUse -and -not [string]::IsNullOrEmpty($collIdToUse)) {
            try {
                # Convert details to JSON
                $detailsJson = if ($Details -and $Details.Count -gt 0) {
                    $Details | ConvertTo-Json -Compress -Depth 3
                } else { $null }

                $query = @"
INSERT INTO AD_ExecutionTime (
    CollectionID,
    Timestamp,
    DurationSeconds,
    Operation,
    Target,
    Domain,
    RecordCount,
    RecordsPerSec,
    Details
) VALUES (
    @CollectionID,
    @Timestamp,
    @DurationSeconds,
    @Operation,
    @Target,
    @Domain,
    @RecordCount,
    @RecordsPerSec,
    @Details
)
"@

                $params = @{
                    CollectionID    = $collIdToUse
                    Timestamp       = $operationStartTime.ToString('o')
                    DurationSeconds = [Math]::Round($DurationSeconds, 4)
                    Operation       = $Operation
                    Target          = $Target
                    Domain          = $Domain
                    RecordCount     = if ($RecordCount -gt 0) { $RecordCount } else { $null }
                    RecordsPerSec   = $recordsPerSec
                    Details         = $detailsJson
                }

                Invoke-SqliteQuery -SQLiteConnection $dbToUse -Query $query -SqlParameters $params -ErrorAction Stop | Out-Null
            }
            catch {
                # Log error but don't break execution
                Write-Debug "Failed to write execution time to database: $_"
            }
        }
    }
}
