function Add-SQLiteBatch {
    <#
    .SYNOPSIS
        Performs high-performance batch insert of objects into SQLite database

    .DESCRIPTION
        Executes batch INSERT operations using ADO.NET prepared statements for
        maximum performance. Uses a single transaction and reuses the prepared
        statement, only updating parameter values between executions.

        PERFORMANCE: 10-100x faster than row-by-row Invoke-SqliteQuery calls.

    .PARAMETER Connection
        The SQLite connection object (must be open)

    .PARAMETER Objects
        Array of objects to insert. Each object's properties must match table columns.

    .PARAMETER TableName
        Target table name (AD_Object, AD_GroupMembership, etc.)

    .PARAMETER BatchSize
        Number of objects between progress updates (default: 5000)

    .PARAMETER ProgressActivity
        Activity name for progress bar (default: "Inserting {TableName} records")

    .PARAMETER ShowProgress
        Show progress bar during insertion (default: $true)

    .PARAMETER UseSingleTransaction
        Use a single transaction for all records (default behavior, kept for compatibility)

    .OUTPUTS
        Returns the number of records inserted

    .EXAMPLE
        $inserted = Add-SQLiteBatch -Connection $conn -Objects $adObjects -TableName "AD_Object"

    .NOTES
        Part of SSNC.ADInventory module
        Uses ADO.NET prepared statements for maximum insert performance
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Data.SQLite.SQLiteConnection]$Connection,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [array]$Objects,

        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'AD_Object', 'AD_GroupMembership', 'AD_ForeignSecurityPrincipal', 'AD_Trust', 'AD_Domain', 'AD_Forest',
            'AD_Site', 'AD_Subnet', 'AD_SiteLink', 'AD_SiteSettings', 'AD_SiteServer', 'AD_DomainController',
            'AD_SiteSubnet', 'AD_SiteLinkSite', 'AD_OptionalFeature',
            'AD_KMSService', 'AD_ADFSConfiguration', 'AD_EnterpriseCA', 'AD_CertificateTemplate',
            'AD_TrustedRootCA', 'AD_NTAuthCA'
        )]
        [string]$TableName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(100, 50000)]
        [int]$BatchSize = 5000,

        [Parameter(Mandatory = $false)]
        [string]$ProgressActivity,

        [Parameter(Mandatory = $false)]
        [bool]$ShowProgress = $true,

        [Parameter(Mandatory = $false)]
        [switch]$UseSingleTransaction
    )

    process {
        if ($Objects.Count -eq 0) {
            Write-ADInventoryLog -Level Verbose -Message "No objects to insert" `
                -Context @{ TableName = $TableName }
            return 0
        }

        # Set default progress activity
        if (-not $ProgressActivity) {
            $ProgressActivity = "Inserting $TableName records"
        }

        Write-ADInventoryLog -Level Info -Message "Starting batch insert" `
            -Context @{
                TableName = $TableName
                ObjectCount = $Objects.Count
                BatchSize = $BatchSize
                SingleTransaction = $true
            }

        # Start timing
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Get INSERT statement and column info for table
        $tableInfo = Get-TableInsertInfo -TableName $TableName
        $insertSql = $tableInfo.Sql
        $columnNames = $tableInfo.Columns

        $totalInserted = 0
        $progressId = Get-Random -Minimum 1000 -Maximum 9999
        $transaction = $null
        $command = $null

        try {
            # Start transaction
            $transaction = $Connection.BeginTransaction()

            # Create and prepare command ONCE
            $command = $Connection.CreateCommand()
            $command.Transaction = $transaction
            $command.CommandText = $insertSql

            # Add parameters ONCE (we'll update values in the loop)
            $parameterMap = @{}
            foreach ($colName in $columnNames) {
                $param = $command.CreateParameter()
                $param.ParameterName = "@$colName"
                [void]$command.Parameters.Add($param)
                $parameterMap[$colName] = $param
            }

            # Process each object
            for ($i = 0; $i -lt $Objects.Count; $i++) {
                $obj = $Objects[$i]

                # Update parameter values (much faster than recreating parameters)
                foreach ($colName in $columnNames) {
                    $value = $obj.$colName
                    if ($null -eq $value) {
                        $parameterMap[$colName].Value = [DBNull]::Value
                    }
                    elseif ($value -is [DateTime]) {
                        # Convert DateTime to ISO 8601 string for SQLite
                        $parameterMap[$colName].Value = $value.ToString('o')
                    }
                    else {
                        $parameterMap[$colName].Value = $value
                    }
                }

                # Execute prepared statement
                try {
                    [void]$command.ExecuteNonQuery()
                    $totalInserted++
                }
                catch {
                    # Log but continue on constraint violations (duplicates)
                    if ($_.Exception.Message -match 'UNIQUE constraint|PRIMARY KEY constraint') {
                        Write-ADInventoryLog -Level Debug -Message "Duplicate key skipped" `
                            -Context @{ Table = $TableName; Index = $i }
                    }
                    else {
                        throw
                    }
                }

                # Update progress periodically
                if ($totalInserted % $BatchSize -eq 0) {
                    $percentComplete = [int](($i / $Objects.Count) * 100)

                    if ($ShowProgress) {
                        Write-Progress -Id $progressId `
                            -Activity $ProgressActivity `
                            -Status "$totalInserted of $($Objects.Count) records" `
                            -PercentComplete $percentComplete
                    }

                    # Also log to file for large inserts (every 50K records)
                    if ($totalInserted % 50000 -eq 0) {
                        Write-ADInventoryLog -Level Info -Message "Batch insert progress" `
                            -Context @{
                                TableName = $TableName
                                Inserted = $totalInserted
                                Total = $Objects.Count
                                PercentComplete = $percentComplete
                            }
                    }
                }
            }

            Write-ADInventoryLog -Level Info -Message "Insert loop complete, committing transaction" `
                -Context @{
                    TableName = $TableName
                    RecordsInserted = $totalInserted
                }

            # Commit transaction
            $transaction.Commit()

            # Final progress update
            if ($ShowProgress) {
                Write-Progress -Id $progressId -Activity $ProgressActivity -Completed
            }

            # Stop timing and record
            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'Insert' -Target $TableName `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount $totalInserted

            Write-ADInventoryLog -Level Info -Message "Batch insert completed" `
                -Context @{
                    TableName = $TableName
                    RecordsInserted = $totalInserted
                    RecordsAttempted = $Objects.Count
                }

            return $totalInserted
        }
        catch {
            # Rollback on error
            if ($null -ne $transaction) {
                try { $transaction.Rollback() } catch { }
            }

            # Clear progress on error
            if ($ShowProgress) {
                Write-Progress -Id $progressId -Activity $ProgressActivity -Completed
            }

            Write-ADInventoryLog -Level Error -Message "Batch insert failed" `
                -Context @{
                    TableName = $TableName
                    RecordsInserted = $totalInserted
                    RecordsAttempted = $Objects.Count
                } `
                -Exception $_.Exception

            throw "Batch insert failed at record $totalInserted : $_"
        }
        finally {
            # Cleanup
            if ($null -ne $command) {
                $command.Dispose()
            }
            # Don't dispose transaction - it's already committed or rolled back
        }
    }
}

function Get-TableInsertInfo {
    <#
    .SYNOPSIS
        Gets the INSERT statement and column list for a table

    .DESCRIPTION
        Returns a hashtable with the INSERT SQL and ordered column names.
        Used by Add-SQLiteBatch for prepared statement setup.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'AD_Object', 'AD_GroupMembership', 'AD_ForeignSecurityPrincipal', 'AD_Trust', 'AD_Domain', 'AD_Forest',
            'AD_Site', 'AD_Subnet', 'AD_SiteLink', 'AD_SiteSettings', 'AD_SiteServer', 'AD_DomainController',
            'AD_SiteSubnet', 'AD_SiteLinkSite', 'AD_OptionalFeature',
            'AD_KMSService', 'AD_ADFSConfiguration', 'AD_EnterpriseCA', 'AD_CertificateTemplate',
            'AD_TrustedRootCA', 'AD_NTAuthCA'
        )]
        [string]$TableName
    )

    switch ($TableName) {
        'AD_Object' {
            # CollectionID replaces InventoryID (normalized to AD_CollectionInfo)
            $columns = @(
                'SID_String', 'ObjectType', 'SamAccountName', 'DisplayName', 'UserPrincipalName',
                'DomainName', 'DistinguishedName', 'WhenCreated', 'WhenChanged', 'Enabled',
                'LastLogonTimestamp', 'PasswordLastSet', 'AccountExpires', 'PasswordNeverExpires',
                'GivenName', 'Surname', 'Mail', 'Department', 'Title', 'Manager', 'EmployeeID',
                'EmployeeNumber', 'EmployeeType',
                'GroupType', 'GroupScope', 'ManagedBy',
                'DNSHostName', 'OperatingSystem', 'OperatingSystemVersion', 'OperatingSystemServicePack', 'OperatingSystemHotfix',
                'ObjectGUID', 'CanonicalName', 'Description',
                'SIDHistory', 'IsCriticalSystemObject', 'ServicePrincipalName', 'UserAccountControl', 'PasswordExpired',
                'IsForeignSecurityPrincipal', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_Object ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_GroupMembership' {
            # CollectionID replaces InventoryID (normalized to AD_CollectionInfo)
            $columns = @('GroupSID', 'MemberSID', 'CollectionID')
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT OR IGNORE INTO AD_GroupMembership ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_ForeignSecurityPrincipal' {
            # CollectionID replaces InventoryID; CollectedDate removed (now in AD_CollectionInfo)
            $columns = @('SID_String', 'SourceDomainName', 'DistinguishedName', 'IsResolved', 'LastResolveAttempt', 'CollectionID')
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_ForeignSecurityPrincipal ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_Trust' {
            # SourceDomain is stored per-trust to correctly track trust relationships across multiple domains
            $columns = @('SourceDomain', 'TargetDomain', 'TrustType', 'TrustDirection', 'TrustAttributes', 'IsTransitive', 'FlatName', 'WhenCreated', 'CollectionID')
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_Trust ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_Domain' {
            # Domain information including FSMO roles and domain health
            $columns = @(
                'DomainName', 'DomainSID', 'DomainGUID', 'NetBIOSName', 'DistinguishedName',
                'ForestName', 'ParentDomain', 'DomainMode', 'DomainModeLevel',
                'PDCEmulator', 'RIDMaster', 'InfrastructureMaster',
                'ChildDomains', 'DomainControllers', 'ReadOnlyReplicaDirectoryServers',
                # SYSVOL Replication columns
                'SysvolReplicationMethod', 'SysvolMigrationState', 'DFSRExists', 'FRSExists', 'DFSRFlags',
                # GPO Health columns
                'GPOTotalCount', 'GPOHealthyCount', 'GPOOrphanedGPCCount', 'GPOOrphanedGPTCount',
                'GPOVersionMismatchCount', 'GPOOverallHealth', 'SYSVOLAccessible',
                'DefaultDomainPolicyExists', 'DefaultDCPolicyExists',
                'WhenCreated', 'WhenChanged', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_Domain ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_Forest' {
            # Forest information including FSMO roles
            $columns = @(
                'ForestName', 'ForestGUID', 'RootDomain', 'ForestMode', 'ForestModeLevel',
                'SchemaMaster', 'DomainNamingMaster',
                'Domains', 'GlobalCatalogs', 'Sites', 'SiteLinks',
                'SchemaVersion', 'ExchangeSchemaVersion', 'WhenCreated', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_Forest ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        # Sites & Services tables
        'AD_Site' {
            $columns = @(
                'SiteName', 'Description', 'Location', 'DistinguishedName',
                'ObjectGUID', 'WhenCreated', 'WhenChanged', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_Site ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_Subnet' {
            $columns = @(
                'SubnetName', 'Description', 'Location', 'SiteName', 'SiteObjectDN',
                'DistinguishedName', 'ObjectGUID', 'WhenCreated', 'WhenChanged', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_Subnet ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_SiteLink' {
            $columns = @(
                'SiteLinkName', 'Cost', 'ReplicationInterval', 'Options',
                'UseNotification', 'TwoWaySync', 'CompressionDisabled',
                'SiteCount', 'SiteList', 'Schedule', 'Description', 'TransportType',
                'DistinguishedName', 'ObjectGUID', 'WhenCreated', 'WhenChanged', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_SiteLink ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_SiteSettings' {
            $columns = @(
                'SiteName', 'InterSiteTopologyGenerator', 'InterSiteTopologyGeneratorName',
                'Options', 'IsAutoTopologyDisabled', 'IsTopologyCleanupDisabled',
                'IsMinHopsDisabled', 'IsDetectStaleDisabled', 'IsInterSiteAutoTopologyDisabled',
                'IsGroupCachingEnabled', 'Schedule', 'DistinguishedName',
                'ObjectGUID', 'WhenCreated', 'WhenChanged', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_SiteSettings ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_SiteServer' {
            $columns = @(
                'ServerName', 'SiteName', 'DNSHostName', 'ServerReference',
                'DistinguishedName', 'ObjectGUID', 'WhenCreated', 'WhenChanged', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_SiteServer ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_DomainController' {
            $columns = @(
                'ServerName', 'SiteName', 'Options', 'IsGlobalCatalog',
                'DisableInboundReplication', 'DisableOutboundReplication',
                'DisableNTDSConnTranslation', 'IsRODC', 'InvocationId', 'MasterNCs',
                'DistinguishedName', 'ObjectGUID', 'WhenCreated', 'WhenChanged', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_DomainController ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_SiteSubnet' {
            $columns = @('SiteName', 'SubnetName', 'CollectionID')
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT OR IGNORE INTO AD_SiteSubnet ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_SiteLinkSite' {
            $columns = @('SiteLinkName', 'SiteName', 'CollectionID')
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT OR IGNORE INTO AD_SiteLinkSite ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_OptionalFeature' {
            # Optional Features (forest-scoped)
            $columns = @(
                'ForestName', 'FeatureName', 'FeatureGUID', 'IsEnabled',
                'RequiredForestLevel', 'RequiredForestLevelName', 'RequiredDomainLevel',
                'Description', 'DistinguishedName', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_OptionalFeature ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_KMSService' {
            # KMS Service records (domain-scoped, from DNS SRV queries)
            $columns = @(
                'DomainName', 'TargetHostname', 'Port', 'Priority', 'Weight',
                'TTL', 'ResolvedIP', 'RecordSource', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_KMSService ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_ADFSConfiguration' {
            # ADFS and DRS configuration (forest-scoped)
            $columns = @(
                'ForestName', 'ServiceType', 'ServiceName', 'FederationServiceName',
                'AzureTenantId', 'AzureObjectId', 'DomainName', 'ServiceBindingInfo',
                'Keywords', 'DistinguishedName', 'ObjectGUID', 'WhenCreated', 'WhenChanged',
                'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_ADFSConfiguration ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_EnterpriseCA' {
            # Enterprise Certification Authorities (forest-scoped)
            $columns = @(
                'ForestName', 'CAName', 'DNSHostName', 'CAType', 'CACertificate',
                'CACertificateDN', 'CertificateTemplates', 'Flags', 'DistinguishedName',
                'ObjectGUID', 'WhenCreated', 'WhenChanged', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_EnterpriseCA ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_CertificateTemplate' {
            # Certificate Templates (forest-scoped)
            $columns = @(
                'ForestName', 'TemplateName', 'DisplayName', 'TemplateOID',
                'SchemaVersion', 'MinorRevision', 'MajorRevision', 'RASignaturesRequired',
                'MinKeySize', 'EnrollmentFlags', 'PrivateKeyFlags', 'CertificateNameFlags',
                'ValidityPeriod', 'RenewalPeriod', 'ExtendedKeyUsage', 'DistinguishedName',
                'ObjectGUID', 'WhenCreated', 'WhenChanged', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_CertificateTemplate ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_TrustedRootCA' {
            # Trusted Root CAs (forest-scoped)
            $columns = @(
                'ForestName', 'CAName', 'CACertificate', 'CertificateSubject',
                'CertificateThumbprint', 'CertificateNotBefore', 'CertificateNotAfter',
                'ContainerType', 'DistinguishedName', 'ObjectGUID', 'WhenCreated',
                'WhenChanged', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_TrustedRootCA ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        'AD_NTAuthCA' {
            # NTAuth certificates (forest-scoped)
            $columns = @(
                'ForestName', 'CertificateSubject', 'CACertificate', 'CertificateThumbprint',
                'CertificateNotBefore', 'CertificateNotAfter', 'CertificateIndex',
                'DistinguishedName', 'CollectionID'
            )
            $paramList = ($columns | ForEach-Object { "@$_" }) -join ', '
            return @{
                Columns = $columns
                Sql = "INSERT INTO AD_NTAuthCA ($($columns -join ', ')) VALUES ($paramList)"
            }
        }

        default {
            throw "Unknown table name: $TableName"
        }
    }
}
