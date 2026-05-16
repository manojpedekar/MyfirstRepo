using namespace System.Data.SQLite

<#
.SYNOPSIS
    Manages SQLite database connection lifecycle and write operations for AD inventory

.DESCRIPTION
    This class provides a safe, disposable wrapper around SQLite connections for
    AD inventory data. It ensures proper resource cleanup and transaction management.

    CRITICAL FIXES from original script:
    - Line 1647: Connection.Close() only on success path - FIXED with IDisposable
    - Transaction leaks - FIXED with automatic rollback
    - No connection state validation - FIXED with state checks

.NOTES
    Part of SSNC.ADInventory module

    Usage:
        $writer = [SQLiteInventoryWriter]::new("C:\Inventory")
        try {
            $collectionID = $writer.Initialize("contoso.com", "GUID-123", "SERVER01", "DOMAIN\User")
            $writer.WriteObjects($objects)
            $writer.Finalize()
        } catch {
            $writer.Rollback()
            throw
        } finally {
            $writer.Dispose()
        }

    Or use PowerShell 5.0+ using statement:
        using ($writer = [SQLiteInventoryWriter]::new("C:\Inventory")) {
            $writer.Initialize("contoso.com", "GUID-123", "SERVER01", "DOMAIN\User")
            # ... operations ...
        } # Automatically disposed
#>
class SQLiteInventoryWriter : System.IDisposable {
    # Properties
    [SQLiteConnection]$Connection
    [string]$DbPath
    [string]$OutputDirectory
    [bool]$IsInitialized = $false
    [bool]$InTransaction = $false
    [bool]$IsDisposed = $false
    [bool]$IndexesCreated = $false
    [datetime]$CreatedDate

    # Collection metadata (stored after Initialize)
    [hashtable]$DomainCollectionIDs = @{}  # Maps domain name -> CollectionID
    [string]$CurrentDomain = $null         # Currently active domain for writes
    [string]$InventoryID
    [string]$ComputerName
    [string]$Who
    [datetime]$CollectionStartTime         # When the overall collection run started (same for all domains)

    # CollectionID property - returns ID for current domain (GUID string)
    [string] GetCollectionID() {
        if ([string]::IsNullOrEmpty($this.CurrentDomain)) {
            throw "No current domain set. Call SetCurrentDomain() first."
        }
        if (-not $this.DomainCollectionIDs.ContainsKey($this.CurrentDomain)) {
            throw "Domain '$($this.CurrentDomain)' not found in collection. Initialize with this domain first."
        }
        return $this.DomainCollectionIDs[$this.CurrentDomain]
    }

    # Statistics
    [int]$ObjectsWritten = 0
    [int]$MembershipsWritten = 0
    [int]$FSPsWritten = 0
    [int]$TrustsWritten = 0
    [int]$DomainsWritten = 0
    [int]$ForestsWritten = 0

    # Sites & Services Statistics
    [int]$SitesWritten = 0
    [int]$SubnetsWritten = 0
    [int]$SiteLinksWritten = 0
    [int]$SiteSettingsWritten = 0
    [int]$SiteServersWritten = 0
    [int]$DomainControllersWritten = 0
    [int]$SiteSubnetsWritten = 0
    [int]$SiteLinkSitesWritten = 0

    # Optional Features Statistics
    [int]$OptionalFeaturesWritten = 0

    # KMS, ADFS, and PKI Statistics
    [int]$KMSServicesWritten = 0
    [int]$ADFSConfigsWritten = 0
    [int]$EnterpriseCAsWritten = 0
    [int]$CertificateTemplatesWritten = 0
    [int]$TrustedRootCAsWritten = 0
    [int]$NTAuthCAsWritten = 0

    # Constructor
    SQLiteInventoryWriter([string]$outputPath) {
        if ([string]::IsNullOrWhiteSpace($outputPath)) {
            throw [System.ArgumentException]::new("Output path cannot be null or empty")
        }

        if (-not (Test-Path $outputPath -PathType Container)) {
            throw [System.IO.DirectoryNotFoundException]::new("Output directory not found: $outputPath")
        }

        $this.OutputDirectory = $outputPath
        $this.CreatedDate = Get-Date

        Write-ADInventoryLog -Level Debug -Message "SQLiteInventoryWriter instance created" `
            -Context @{ OutputDirectory = $outputPath }
    }

    # Initialize database and schema, create CollectionInfo records for all domains
    # Returns the CollectionID (GUID) for the first domain (for backward compatibility)
    [string] Initialize([string[]]$domainNames, [string]$inventoryID, [string]$computerName, [string]$who) {
        if ($this.IsInitialized) {
            throw "Database is already initialized"
        }

        if ($this.IsDisposed) {
            throw "Cannot initialize disposed object"
        }

        if ($null -eq $domainNames -or $domainNames.Count -eq 0) {
            throw "At least one domain name is required"
        }

        try {
            # Store collection metadata
            $this.InventoryID = $inventoryID
            $this.ComputerName = $computerName
            $this.Who = $who
            $this.CollectionStartTime = Get-Date  # Capture once for all domains

            # Generate database filename with timestamp only (simplified naming)
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $dbFileName = "ADInventory_${timestamp}.db"
            $this.DbPath = Join-Path $this.OutputDirectory $dbFileName

            Write-ADInventoryLog -Level Info -Message "Initializing SQLite database" `
                -Context @{
                    DbPath = $this.DbPath
                    DomainCount = $domainNames.Count
                    Domains = ($domainNames -join ', ')
                    InventoryID = $inventoryID
                }

            # Create connection
            $this.Connection = New-SqliteConnection -DataSource $this.DbPath

            # Initialize schema WITHOUT indexes for bulk insert performance
            # Indexes will be created later in Finalize() after all data is loaded
            Initialize-ADInventorySchema -Connection $this.Connection -SkipIndexes

            # Create AD_CollectionInfo record for each domain
            # NOTE: Use $domainCollID to avoid PS 5.1 class property parsing issue with $collectionID
            $firstCollectionID = $null
            foreach ($domain in $domainNames) {
                $domainCollID = $this.CreateCollectionInfo($domain)
                $this.DomainCollectionIDs[$domain] = $domainCollID

                if ($null -eq $firstCollectionID) {
                    $firstCollectionID = $domainCollID
                }

                Write-ADInventoryLog -Level Debug -Message "Created CollectionInfo for domain" `
                    -Context @{
                        Domain = $domain
                        CollectionID = $domainCollID
                    }
            }

            # Set first domain as current
            $this.CurrentDomain = $domainNames[0]

            $this.IsInitialized = $true

            Write-ADInventoryLog -Level Info -Message "Database initialized successfully (indexes deferred)" `
                -Context @{
                    DbPath = $this.DbPath
                    DomainCount = $domainNames.Count
                    FirstCollectionID = $firstCollectionID
                }

            return $firstCollectionID
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to initialize database" `
                -Exception $_.Exception

            # Clean up on failure
            if ($this.Connection) {
                try { $this.Connection.Close(); $this.Connection.Dispose() } catch { }
                $this.Connection = $null
            }

            throw
        }
    }

    # Overload for single domain (backward compatibility)
    [string] Initialize([string]$domainName, [string]$inventoryID, [string]$computerName, [string]$who) {
        return $this.Initialize(@($domainName), $inventoryID, $computerName, $who)
    }

    # Set the current domain for subsequent write operations
    # Also updates the module-scoped CollectionID so that log entries are correctly
    # associated with the current domain's CollectionID (fixes WalkTrust logging issue)
    [void] SetCurrentDomain([string]$domainName) {
        if (-not $this.DomainCollectionIDs.ContainsKey($domainName)) {
            throw "Domain '$domainName' not found in collection. Available domains: $($this.DomainCollectionIDs.Keys -join ', ')"
        }
        $this.CurrentDomain = $domainName

        # Use helper function to set the module-scoped CollectionID variable
        # This is necessary because PowerShell 5.1 class methods run in a different scope
        # than module functions, so direct $Script: assignment doesn't propagate correctly
        # NOTE: Use $domainCollID to avoid PS 5.1 class property parsing issue with $collectionID
        $domainCollID = $this.DomainCollectionIDs[$domainName]
        Set-ADInventoryCollectionID -CollectionID $domainCollID

        Write-ADInventoryLog -Level Debug -Message "Set current domain" `
            -Context @{ Domain = $domainName; CollectionID = $domainCollID }
    }

    # Create AD_CollectionInfo record for a specific domain and return CollectionID (GUID)
    # CollectionDateTime is set to the overall script start time (same for all domains)
    # StartTime and EndTime are NULL - they will be set when domain collection actually starts/ends
    hidden [string] CreateCollectionInfo([string]$domainName) {
        # Generate a globally unique CollectionID (GUID)
        $newCollectionID = [guid]::NewGuid().ToString()

        # Use the stored CollectionStartTime (captured once during Initialize)
        $collectionDateTime = $this.CollectionStartTime.ToUniversalTime().ToString('o')

        # Get module version for troubleshooting (use helper function to access module scope)
        $moduleVersion = Get-ADInventoryModuleVersion

        # Execute INSERT with the generated GUID as CollectionID
        $insertQuery = @"
INSERT INTO AD_CollectionInfo (CollectionID, InventoryID, ComputerName, DomainName, CollectionDateTime, Who, ModuleVersion, StartTime, EndTime)
VALUES (@CollectionID, @InventoryID, @ComputerName, @DomainName, @CollectionDateTime, @Who, @ModuleVersion, NULL, NULL)
"@

        # Execute INSERT with ErrorAction Stop to ensure failures are caught
        Invoke-SqliteQuery -SQLiteConnection $this.Connection -Query $insertQuery -SqlParameters @{
            CollectionID = $newCollectionID
            InventoryID = $this.InventoryID
            ComputerName = $this.ComputerName
            DomainName = $domainName
            CollectionDateTime = $collectionDateTime
            Who = $this.Who
            ModuleVersion = $moduleVersion
        } -ErrorAction Stop

        Write-ADInventoryLog -Level Debug -Message "Created AD_CollectionInfo record" `
            -Context @{
                CollectionID = $newCollectionID
                InventoryID = $this.InventoryID
                DomainName = $domainName
                CollectionDateTime = $collectionDateTime
            }

        return $newCollectionID
    }

    # Update AD_CollectionInfo with EndTime for domains that don't have one yet (fallback)
    hidden [void] UpdateCollectionEndTime() {
        if ($this.DomainCollectionIDs.Count -eq 0) {
            return
        }

        $endTime = (Get-Date).ToUniversalTime().ToString('o')

        # Only update records that don't already have an EndTime (fallback for any missed domains)
        $updateQuery = "UPDATE AD_CollectionInfo SET EndTime = @EndTime WHERE InventoryID = @InventoryID AND EndTime IS NULL"

        Invoke-SqliteQuery -SQLiteConnection $this.Connection -Query $updateQuery -SqlParameters @{
            EndTime = $endTime
            InventoryID = $this.InventoryID
        }

        Write-ADInventoryLog -Level Debug -Message "Updated AD_CollectionInfo EndTime for remaining domains" `
            -Context @{
                InventoryID = $this.InventoryID
                EndTime = $endTime
            }
    }

    # Update StartTime for a specific domain when collection actually begins
    # NOTE: Use $domainCollID to avoid PS 5.1 class property parsing issue with $collectionID
    [void] UpdateDomainStartTime([string]$domainName) {
        if (-not $this.DomainCollectionIDs.ContainsKey($domainName)) {
            Write-ADInventoryLog -Level Warning -Message "Cannot update StartTime - domain not found" `
                -Context @{ DomainName = $domainName }
            return
        }

        $startTime = (Get-Date).ToUniversalTime().ToString('o')
        $domainCollID = $this.DomainCollectionIDs[$domainName]

        $updateQuery = "UPDATE AD_CollectionInfo SET StartTime = @StartTime WHERE CollectionID = @CollectionID"

        Invoke-SqliteQuery -SQLiteConnection $this.Connection -Query $updateQuery -SqlParameters @{
            StartTime = $startTime
            CollectionID = $domainCollID
        }

        Write-ADInventoryLog -Level Debug -Message "Updated domain StartTime" `
            -Context @{
                DomainName = $domainName
                CollectionID = $domainCollID
                StartTime = $startTime
            }
    }

    # Update EndTime for a specific domain when collection completes (success or skip)
    # NOTE: Use $domainCollID to avoid PS 5.1 class property parsing issue with $collectionID
    [void] UpdateDomainEndTime([string]$domainName) {
        if (-not $this.DomainCollectionIDs.ContainsKey($domainName)) {
            Write-ADInventoryLog -Level Warning -Message "Cannot update EndTime - domain not found" `
                -Context @{ DomainName = $domainName }
            return
        }

        $endTime = (Get-Date).ToUniversalTime().ToString('o')
        $domainCollID = $this.DomainCollectionIDs[$domainName]

        $updateQuery = "UPDATE AD_CollectionInfo SET EndTime = @EndTime WHERE CollectionID = @CollectionID"

        Invoke-SqliteQuery -SQLiteConnection $this.Connection -Query $updateQuery -SqlParameters @{
            EndTime = $endTime
            CollectionID = $domainCollID
        }

        Write-ADInventoryLog -Level Debug -Message "Updated domain EndTime" `
            -Context @{
                DomainName = $domainName
                CollectionID = $domainCollID
                EndTime = $endTime
            }
    }

    # Validate connection state (helper method)
    hidden [void] EnsureConnectionReady() {
        if ($this.IsDisposed) {
            throw "Object has been disposed"
        }

        if (-not $this.IsInitialized) {
            throw "Database has not been initialized. Call Initialize() first."
        }

        if ($null -eq $this.Connection) {
            throw "Connection is null"
        }

        if ($this.Connection.State -ne [System.Data.ConnectionState]::Open) {
            throw "Connection is not open. State: $($this.Connection.State)"
        }
    }

    # Get object count statistics
    [hashtable] GetStatistics() {
        $sitesServicesTotal = $this.SitesWritten + $this.SubnetsWritten + $this.SiteLinksWritten +
                              $this.SiteSettingsWritten + $this.SiteServersWritten + $this.DomainControllersWritten +
                              $this.SiteSubnetsWritten + $this.SiteLinkSitesWritten

        $pkiTotal = $this.EnterpriseCAsWritten + $this.CertificateTemplatesWritten +
                    $this.TrustedRootCAsWritten + $this.NTAuthCAsWritten

        return @{
            ObjectsWritten = $this.ObjectsWritten
            MembershipsWritten = $this.MembershipsWritten
            FSPsWritten = $this.FSPsWritten
            TrustsWritten = $this.TrustsWritten
            DomainsWritten = $this.DomainsWritten
            ForestsWritten = $this.ForestsWritten
            SitesWritten = $this.SitesWritten
            SubnetsWritten = $this.SubnetsWritten
            SiteLinksWritten = $this.SiteLinksWritten
            SiteSettingsWritten = $this.SiteSettingsWritten
            SiteServersWritten = $this.SiteServersWritten
            DomainControllersWritten = $this.DomainControllersWritten
            SiteSubnetsWritten = $this.SiteSubnetsWritten
            SiteLinkSitesWritten = $this.SiteLinkSitesWritten
            OptionalFeaturesWritten = $this.OptionalFeaturesWritten
            KMSServicesWritten = $this.KMSServicesWritten
            ADFSConfigsWritten = $this.ADFSConfigsWritten
            EnterpriseCAsWritten = $this.EnterpriseCAsWritten
            CertificateTemplatesWritten = $this.CertificateTemplatesWritten
            TrustedRootCAsWritten = $this.TrustedRootCAsWritten
            NTAuthCAsWritten = $this.NTAuthCAsWritten
            TotalRecords = $this.ObjectsWritten + $this.MembershipsWritten + $this.FSPsWritten + $this.TrustsWritten + $this.DomainsWritten + $this.ForestsWritten + $sitesServicesTotal + $this.OptionalFeaturesWritten + $this.KMSServicesWritten + $this.ADFSConfigsWritten + $pkiTotal
        }
    }

    # Add batch of AD objects to database
    [void] AddObjectBatch([array]$objects) {
        $this.EnsureConnectionReady()

        if ($null -eq $objects -or $objects.Count -eq 0) {
            Write-ADInventoryLog -Level Verbose -Message "No objects to add to database"
            return
        }

        try {
            # Determine table name from object type
            # All objects (users, groups, computers) go to AD_Object table
            $tableName = 'AD_Object'

            # Transform objects to include CollectionID
            $objectsWithCollection = $objects | ForEach-Object {
                # Add CollectionID to each object
                $_ | Add-Member -NotePropertyName 'CollectionID' -NotePropertyValue $this.GetCollectionID() -PassThru -Force
            }

            Write-ADInventoryLog -Level Info -Message "Adding objects to database" `
                -Context @{
                    Count = $objects.Count
                    TableName = $tableName
                    CollectionID = $this.GetCollectionID()
                }

            # Call Add-SQLiteBatch to perform the insert with single large transaction
            $inserted = Add-SQLiteBatch `
                -Connection $this.Connection `
                -Objects $objectsWithCollection `
                -TableName $tableName `
                -ShowProgress $false `
                -UseSingleTransaction

            $this.ObjectsWritten += $inserted

            Write-ADInventoryLog -Level Info -Message "Objects added to database" `
                -Context @{
                    Inserted = $inserted
                    TableName = $tableName
                }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add objects to database" `
                -Context @{ Count = $objects.Count } `
                -Exception $_.Exception
            throw
        }
    }

    # Add Foreign Security Principals to database
    [void] AddFSPBatch([array]$fsps) {
        $this.EnsureConnectionReady()

        if ($null -eq $fsps -or $fsps.Count -eq 0) {
            Write-ADInventoryLog -Level Verbose -Message "No FSPs to add to database"
            return
        }

        try {
            # Transform FSPs to match AD_ForeignSecurityPrincipal schema
            $fspRecords = $fsps | ForEach-Object {
                [PSCustomObject]@{
                    SID_String = $_.SID_String
                    SourceDomainName = $_.SourceDomain
                    DistinguishedName = $_.DN
                    IsResolved = if ($_.ResolvedName) { 1 } else { 0 }
                    LastResolveAttempt = Get-Date -Format 'o'
                    CollectionID = $this.GetCollectionID()
                }
            }

            Write-ADInventoryLog -Level Info -Message "Adding FSPs to database" `
                -Context @{
                    Count = $fspRecords.Count
                    CollectionID = $this.GetCollectionID()
                }

            $inserted = Add-SQLiteBatch `
                -Connection $this.Connection `
                -Objects $fspRecords `
                -TableName 'AD_ForeignSecurityPrincipal' `
                -ShowProgress $false `
                -UseSingleTransaction

            $this.FSPsWritten += $inserted

            Write-ADInventoryLog -Level Info -Message "FSPs added to database" `
                -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add FSPs to database" `
                -Context @{ Count = $fsps.Count } `
                -Exception $_.Exception
            throw
        }
    }

    # Add Trust relationships to database
    [void] AddTrustBatch([array]$trusts) {
        $this.EnsureConnectionReady()

        if ($null -eq $trusts -or $trusts.Count -eq 0) {
            Write-ADInventoryLog -Level Verbose -Message "No trusts to add to database"
            return
        }

        try {
            # Transform trusts to match AD_Trust schema
            $trustRecords = $trusts | ForEach-Object {
                [PSCustomObject]@{
                    SourceDomain    = $_.SourceDomain
                    TargetDomain    = $_.TargetDomain
                    TrustType       = $_.TrustType
                    TrustDirection  = $_.TrustDirection
                    TrustAttributes = $_.TrustAttributes
                    IsTransitive    = if ($_.IsTransitive) { 1 } else { 0 }
                    FlatName        = $_.FlatName
                    WhenCreated     = if ($_.WhenCreated) { $_.WhenCreated.ToString('o') } else { $null }
                    CollectionID    = $this.GetCollectionID()
                }
            }

            Write-ADInventoryLog -Level Info -Message "Adding trusts to database" `
                -Context @{
                    Count = $trustRecords.Count
                    CollectionID = $this.GetCollectionID()
                }

            $inserted = Add-SQLiteBatch `
                -Connection $this.Connection `
                -Objects $trustRecords `
                -TableName 'AD_Trust' `
                -ShowProgress $false `
                -UseSingleTransaction

            $this.TrustsWritten += $inserted

            Write-ADInventoryLog -Level Info -Message "Trusts added to database" `
                -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add trusts to database" `
                -Context @{ Count = $trusts.Count } `
                -Exception $_.Exception
            throw
        }
    }

    # Add Domain Information to database
    [void] AddDomainInfo([PSCustomObject]$domainInfo) {
        $this.EnsureConnectionReady()

        if ($null -eq $domainInfo) {
            Write-ADInventoryLog -Level Verbose -Message "No domain info to add to database"
            return
        }

        try {
            # Transform domain info to match AD_Domain schema
            $domainRecord = [PSCustomObject]@{
                DomainName                      = $domainInfo.DomainName
                DomainSID                       = $domainInfo.DomainSID
                DomainGUID                      = $domainInfo.DomainGUID
                NetBIOSName                     = $domainInfo.NetBIOSName
                DistinguishedName               = $domainInfo.DistinguishedName
                ForestName                      = $domainInfo.ForestName
                ParentDomain                    = $domainInfo.ParentDomain
                DomainMode                      = $domainInfo.DomainMode
                DomainModeLevel                 = $domainInfo.DomainModeLevel
                PDCEmulator                     = $domainInfo.PDCEmulator
                RIDMaster                       = $domainInfo.RIDMaster
                InfrastructureMaster            = $domainInfo.InfrastructureMaster
                ChildDomains                    = $domainInfo.ChildDomains
                DomainControllers               = $domainInfo.DomainControllers
                ReadOnlyReplicaDirectoryServers = $domainInfo.ReadOnlyReplicaDirectoryServers
                # SYSVOL Replication Method columns
                SysvolReplicationMethod         = $domainInfo.SysvolReplicationMethod
                SysvolMigrationState            = $domainInfo.SysvolMigrationState
                DFSRExists                      = if ($null -ne $domainInfo.DFSRExists) { if ($domainInfo.DFSRExists) { 1 } else { 0 } } else { $null }
                FRSExists                       = if ($null -ne $domainInfo.FRSExists) { if ($domainInfo.FRSExists) { 1 } else { 0 } } else { $null }
                DFSRFlags                       = $domainInfo.DFSRFlags
                # GPO Store Health columns
                GPOTotalCount                   = $domainInfo.GPOTotalCount
                GPOHealthyCount                 = $domainInfo.GPOHealthyCount
                GPOOrphanedGPCCount             = $domainInfo.GPOOrphanedGPCCount
                GPOOrphanedGPTCount             = $domainInfo.GPOOrphanedGPTCount
                GPOVersionMismatchCount         = $domainInfo.GPOVersionMismatchCount
                GPOOverallHealth                = $domainInfo.GPOOverallHealth
                SYSVOLAccessible                = if ($null -ne $domainInfo.SYSVOLAccessible) { if ($domainInfo.SYSVOLAccessible) { 1 } else { 0 } } else { $null }
                DefaultDomainPolicyExists       = if ($null -ne $domainInfo.DefaultDomainPolicyExists) { if ($domainInfo.DefaultDomainPolicyExists) { 1 } else { 0 } } else { $null }
                DefaultDCPolicyExists           = if ($null -ne $domainInfo.DefaultDCPolicyExists) { if ($domainInfo.DefaultDCPolicyExists) { 1 } else { 0 } } else { $null }
                # Timestamps
                WhenCreated                     = if ($domainInfo.WhenCreated) { $domainInfo.WhenCreated.ToString('o') } else { $null }
                WhenChanged                     = if ($domainInfo.WhenChanged) { $domainInfo.WhenChanged.ToString('o') } else { $null }
                CollectionID                    = $this.GetCollectionID()
            }

            Write-ADInventoryLog -Level Info -Message "Adding domain info to database" `
                -Context @{
                    DomainName = $domainInfo.DomainName
                    CollectionID = $this.GetCollectionID()
                }

            $inserted = Add-SQLiteBatch `
                -Connection $this.Connection `
                -Objects @($domainRecord) `
                -TableName 'AD_Domain' `
                -ShowProgress $false `
                -UseSingleTransaction

            $this.DomainsWritten += $inserted

            Write-ADInventoryLog -Level Info -Message "Domain info added to database" `
                -Context @{ DomainName = $domainInfo.DomainName }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add domain info to database" `
                -Context @{ DomainName = $domainInfo.DomainName } `
                -Exception $_.Exception
            throw
        }
    }

    # Add Forest Information to database
    [void] AddForestInfo([PSCustomObject]$forestInfo) {
        $this.EnsureConnectionReady()

        if ($null -eq $forestInfo) {
            Write-ADInventoryLog -Level Verbose -Message "No forest info to add to database"
            return
        }

        try {
            # Transform forest info to match AD_Forest schema
            $forestRecord = [PSCustomObject]@{
                ForestName            = $forestInfo.ForestName
                ForestGUID            = $forestInfo.ForestGUID
                RootDomain            = $forestInfo.RootDomain
                ForestMode            = $forestInfo.ForestMode
                ForestModeLevel       = $forestInfo.ForestModeLevel
                SchemaMaster          = $forestInfo.SchemaMaster
                DomainNamingMaster    = $forestInfo.DomainNamingMaster
                Domains               = $forestInfo.Domains
                GlobalCatalogs        = $forestInfo.GlobalCatalogs
                Sites                 = $forestInfo.Sites
                SiteLinks             = $forestInfo.SiteLinks
                SchemaVersion         = $forestInfo.SchemaVersion
                ExchangeSchemaVersion = $forestInfo.ExchangeSchemaVersion
                WhenCreated           = if ($forestInfo.WhenCreated) { $forestInfo.WhenCreated.ToString('o') } else { $null }
                CollectionID          = $this.GetCollectionID()
            }

            Write-ADInventoryLog -Level Info -Message "Adding forest info to database" `
                -Context @{
                    ForestName = $forestInfo.ForestName
                    CollectionID = $this.GetCollectionID()
                }

            $inserted = Add-SQLiteBatch `
                -Connection $this.Connection `
                -Objects @($forestRecord) `
                -TableName 'AD_Forest' `
                -ShowProgress $false `
                -UseSingleTransaction

            $this.ForestsWritten += $inserted

            Write-ADInventoryLog -Level Info -Message "Forest info added to database" `
                -Context @{ ForestName = $forestInfo.ForestName }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add forest info to database" `
                -Context @{ ForestName = $forestInfo.ForestName } `
                -Exception $_.Exception
            throw
        }
    }

    # Add Group Memberships to database
    # NOTE: Each membership record must include CollectionID (set during collection, not here)
    [void] AddMembershipBatch([array]$memberships) {
        $this.EnsureConnectionReady()

        if ($null -eq $memberships -or $memberships.Count -eq 0) {
            Write-ADInventoryLog -Level Verbose -Message "No memberships to add to database"
            return
        }

        try {
            $totalCount = $memberships.Count

            # Count unique CollectionIDs for logging
            $collectionIDs = $memberships | ForEach-Object { $_.CollectionID } | Sort-Object -Unique

            Write-ADInventoryLog -Level Info -Message "Adding memberships to database" `
                -Context @{
                    Count = $totalCount
                    CollectionIDs = ($collectionIDs -join ', ')
                    UniqueCollections = $collectionIDs.Count
                }

            # Enable progress for large inserts (>10K records)
            $showProgress = $totalCount -gt 10000

            # Memberships already have CollectionID set per-record from collection time
            # No transformation needed - pass directly to batch insert
            $inserted = Add-SQLiteBatch `
                -Connection $this.Connection `
                -Objects $memberships `
                -TableName 'AD_GroupMembership' `
                -ShowProgress $showProgress `
                -UseSingleTransaction

            $this.MembershipsWritten += $inserted

            Write-ADInventoryLog -Level Info -Message "Group memberships added to database" `
                -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add memberships to database" `
                -Context @{ Count = $memberships.Count } `
                -Exception $_.Exception
            throw
        }
    }

    # NOTE: AD_GroupMember_Flat table has been removed from SQLite collection.
    # Flattened group memberships are computed post-collection in MS SQL using a recursive CTE.
    # See: database/MSSQL/FlattenGroupMemberships.sql

    #region Sites & Services Batch Methods

    # Add Sites & Services data to database
    # This method writes all Sites & Services data types in a single call
    [void] AddSitesAndServicesBatch([PSCustomObject]$sitesAndServicesData) {
        $this.EnsureConnectionReady()

        if ($null -eq $sitesAndServicesData) {
            Write-ADInventoryLog -Level Verbose -Message "No Sites & Services data to add to database"
            return
        }

        try {
            Write-ADInventoryLog -Level Info -Message "Adding Sites & Services data to database" `
                -Context @{
                    CollectionID = $this.GetCollectionID()
                }

            # Add sites
            if ($sitesAndServicesData.Sites -and $sitesAndServicesData.Sites.Count -gt 0) {
                $this.AddSitesBatch($sitesAndServicesData.Sites)
            }

            # Add subnets
            if ($sitesAndServicesData.Subnets -and $sitesAndServicesData.Subnets.Count -gt 0) {
                $this.AddSubnetsBatch($sitesAndServicesData.Subnets)
            }

            # Add site links (without SiteListDNs property which is for junction building only)
            if ($sitesAndServicesData.SiteLinks -and $sitesAndServicesData.SiteLinks.Count -gt 0) {
                $this.AddSiteLinksBatch($sitesAndServicesData.SiteLinks)
            }

            # Add site settings
            if ($sitesAndServicesData.SiteSettings -and $sitesAndServicesData.SiteSettings.Count -gt 0) {
                $this.AddSiteSettingsBatch($sitesAndServicesData.SiteSettings)
            }

            # Add site servers
            if ($sitesAndServicesData.SiteServers -and $sitesAndServicesData.SiteServers.Count -gt 0) {
                $this.AddSiteServersBatch($sitesAndServicesData.SiteServers)
            }

            # Add domain controllers
            if ($sitesAndServicesData.DomainControllers -and $sitesAndServicesData.DomainControllers.Count -gt 0) {
                $this.AddDomainControllersBatch($sitesAndServicesData.DomainControllers)
            }

            # Add site-subnet junctions
            if ($sitesAndServicesData.SiteSubnets -and $sitesAndServicesData.SiteSubnets.Count -gt 0) {
                $this.AddSiteSubnetsBatch($sitesAndServicesData.SiteSubnets)
            }

            # Add site link-site junctions
            if ($sitesAndServicesData.SiteLinkSites -and $sitesAndServicesData.SiteLinkSites.Count -gt 0) {
                $this.AddSiteLinkSitesBatch($sitesAndServicesData.SiteLinkSites)
            }

            Write-ADInventoryLog -Level Info -Message "Sites & Services data added to database"
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add Sites & Services data to database" `
                -Exception $_.Exception
            throw
        }
    }

    # Add Sites batch
    [void] AddSitesBatch([array]$sites) {
        $this.EnsureConnectionReady()

        if ($null -eq $sites -or $sites.Count -eq 0) { return }

        try {
            $siteRecords = $sites | ForEach-Object {
                [PSCustomObject]@{
                    SiteName          = $_.SiteName
                    Description       = $_.Description
                    Location          = $_.Location
                    DistinguishedName = $_.DistinguishedName
                    ObjectGUID        = $_.ObjectGUID
                    WhenCreated       = if ($_.WhenCreated) { $_.WhenCreated.ToString('o') } else { $null }
                    WhenChanged       = if ($_.WhenChanged) { $_.WhenChanged.ToString('o') } else { $null }
                    CollectionID      = $this.GetCollectionID()
                }
            }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $siteRecords `
                -TableName 'AD_Site' -ShowProgress $false -UseSingleTransaction

            $this.SitesWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "Sites added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add sites to database" -Exception $_.Exception
            throw
        }
    }

    # Add Subnets batch
    [void] AddSubnetsBatch([array]$subnets) {
        $this.EnsureConnectionReady()

        if ($null -eq $subnets -or $subnets.Count -eq 0) { return }

        try {
            $subnetRecords = $subnets | ForEach-Object {
                [PSCustomObject]@{
                    SubnetName        = $_.SubnetName
                    Description       = $_.Description
                    Location          = $_.Location
                    SiteName          = $_.SiteName
                    SiteObjectDN      = $_.SiteObjectDN
                    DistinguishedName = $_.DistinguishedName
                    ObjectGUID        = $_.ObjectGUID
                    WhenCreated       = if ($_.WhenCreated) { $_.WhenCreated.ToString('o') } else { $null }
                    WhenChanged       = if ($_.WhenChanged) { $_.WhenChanged.ToString('o') } else { $null }
                    CollectionID      = $this.GetCollectionID()
                }
            }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $subnetRecords `
                -TableName 'AD_Subnet' -ShowProgress $false -UseSingleTransaction

            $this.SubnetsWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "Subnets added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add subnets to database" -Exception $_.Exception
            throw
        }
    }

    # Add Site Links batch
    [void] AddSiteLinksBatch([array]$siteLinks) {
        $this.EnsureConnectionReady()

        if ($null -eq $siteLinks -or $siteLinks.Count -eq 0) { return }

        try {
            $siteLinkRecords = $siteLinks | ForEach-Object {
                [PSCustomObject]@{
                    SiteLinkName        = $_.SiteLinkName
                    Cost                = $_.Cost
                    ReplicationInterval = $_.ReplicationInterval
                    Options             = $_.Options
                    UseNotification     = if ($_.UseNotification) { 1 } else { 0 }
                    TwoWaySync          = if ($_.TwoWaySync) { 1 } else { 0 }
                    CompressionDisabled = if ($_.CompressionDisabled) { 1 } else { 0 }
                    SiteCount           = $_.SiteCount
                    SiteList            = $_.SiteList
                    Schedule            = $_.Schedule
                    Description         = $_.Description
                    TransportType       = $_.TransportType
                    DistinguishedName   = $_.DistinguishedName
                    ObjectGUID          = $_.ObjectGUID
                    WhenCreated         = if ($_.WhenCreated) { $_.WhenCreated.ToString('o') } else { $null }
                    WhenChanged         = if ($_.WhenChanged) { $_.WhenChanged.ToString('o') } else { $null }
                    CollectionID        = $this.GetCollectionID()
                }
            }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $siteLinkRecords `
                -TableName 'AD_SiteLink' -ShowProgress $false -UseSingleTransaction

            $this.SiteLinksWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "Site links added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add site links to database" -Exception $_.Exception
            throw
        }
    }

    # Add Site Settings batch
    [void] AddSiteSettingsBatch([array]$siteSettings) {
        $this.EnsureConnectionReady()

        if ($null -eq $siteSettings -or $siteSettings.Count -eq 0) { return }

        try {
            $settingsRecords = $siteSettings | ForEach-Object {
                [PSCustomObject]@{
                    SiteName                        = $_.SiteName
                    InterSiteTopologyGenerator      = $_.InterSiteTopologyGenerator
                    InterSiteTopologyGeneratorName  = $_.InterSiteTopologyGeneratorName
                    Options                         = $_.Options
                    IsAutoTopologyDisabled          = if ($_.IsAutoTopologyDisabled) { 1 } else { 0 }
                    IsTopologyCleanupDisabled       = if ($_.IsTopologyCleanupDisabled) { 1 } else { 0 }
                    IsMinHopsDisabled               = if ($_.IsMinHopsDisabled) { 1 } else { 0 }
                    IsDetectStaleDisabled           = if ($_.IsDetectStaleDisabled) { 1 } else { 0 }
                    IsInterSiteAutoTopologyDisabled = if ($_.IsInterSiteAutoTopologyDisabled) { 1 } else { 0 }
                    IsGroupCachingEnabled           = if ($_.IsGroupCachingEnabled) { 1 } else { 0 }
                    Schedule                        = $_.Schedule
                    DistinguishedName               = $_.DistinguishedName
                    ObjectGUID                      = $_.ObjectGUID
                    WhenCreated                     = if ($_.WhenCreated) { $_.WhenCreated.ToString('o') } else { $null }
                    WhenChanged                     = if ($_.WhenChanged) { $_.WhenChanged.ToString('o') } else { $null }
                    CollectionID                    = $this.GetCollectionID()
                }
            }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $settingsRecords `
                -TableName 'AD_SiteSettings' -ShowProgress $false -UseSingleTransaction

            $this.SiteSettingsWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "Site settings added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add site settings to database" -Exception $_.Exception
            throw
        }
    }

    # Add Site Servers batch
    [void] AddSiteServersBatch([array]$siteServers) {
        $this.EnsureConnectionReady()

        if ($null -eq $siteServers -or $siteServers.Count -eq 0) { return }

        try {
            $serverRecords = $siteServers | ForEach-Object {
                [PSCustomObject]@{
                    ServerName        = $_.ServerName
                    SiteName          = $_.SiteName
                    DNSHostName       = $_.DNSHostName
                    ServerReference   = $_.ServerReference
                    DistinguishedName = $_.DistinguishedName
                    ObjectGUID        = $_.ObjectGUID
                    WhenCreated       = if ($_.WhenCreated) { $_.WhenCreated.ToString('o') } else { $null }
                    WhenChanged       = if ($_.WhenChanged) { $_.WhenChanged.ToString('o') } else { $null }
                    CollectionID      = $this.GetCollectionID()
                }
            }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $serverRecords `
                -TableName 'AD_SiteServer' -ShowProgress $false -UseSingleTransaction

            $this.SiteServersWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "Site servers added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add site servers to database" -Exception $_.Exception
            throw
        }
    }

    # Add Domain Controllers batch
    [void] AddDomainControllersBatch([array]$domainControllers) {
        $this.EnsureConnectionReady()

        if ($null -eq $domainControllers -or $domainControllers.Count -eq 0) { return }

        try {
            $dcRecords = $domainControllers | ForEach-Object {
                [PSCustomObject]@{
                    ServerName                   = $_.ServerName
                    SiteName                     = $_.SiteName
                    Options                      = $_.Options
                    IsGlobalCatalog              = if ($_.IsGlobalCatalog) { 1 } else { 0 }
                    DisableInboundReplication    = if ($_.DisableInboundReplication) { 1 } else { 0 }
                    DisableOutboundReplication   = if ($_.DisableOutboundReplication) { 1 } else { 0 }
                    DisableNTDSConnTranslation   = if ($_.DisableNTDSConnTranslation) { 1 } else { 0 }
                    IsRODC                       = if ($_.IsRODC) { 1 } else { 0 }
                    InvocationId                 = $_.InvocationId
                    MasterNCs                    = $_.MasterNCs
                    DistinguishedName            = $_.DistinguishedName
                    ObjectGUID                   = $_.ObjectGUID
                    WhenCreated                  = if ($_.WhenCreated) { $_.WhenCreated.ToString('o') } else { $null }
                    WhenChanged                  = if ($_.WhenChanged) { $_.WhenChanged.ToString('o') } else { $null }
                    CollectionID                 = $this.GetCollectionID()
                }
            }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $dcRecords `
                -TableName 'AD_DomainController' -ShowProgress $false -UseSingleTransaction

            $this.DomainControllersWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "Domain controllers added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add domain controllers to database" -Exception $_.Exception
            throw
        }
    }

    # Add Site-Subnet junction records batch
    [void] AddSiteSubnetsBatch([array]$siteSubnets) {
        $this.EnsureConnectionReady()

        if ($null -eq $siteSubnets -or $siteSubnets.Count -eq 0) { return }

        try {
            $junctionRecords = $siteSubnets | ForEach-Object {
                [PSCustomObject]@{
                    SiteName     = $_.SiteName
                    SubnetName   = $_.SubnetName
                    CollectionID = $this.GetCollectionID()
                }
            }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $junctionRecords `
                -TableName 'AD_SiteSubnet' -ShowProgress $false -UseSingleTransaction

            $this.SiteSubnetsWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "Site-subnet junctions added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add site-subnet junctions to database" -Exception $_.Exception
            throw
        }
    }

    # Add SiteLink-Site junction records batch
    [void] AddSiteLinkSitesBatch([array]$siteLinkSites) {
        $this.EnsureConnectionReady()

        if ($null -eq $siteLinkSites -or $siteLinkSites.Count -eq 0) { return }

        try {
            $junctionRecords = $siteLinkSites | ForEach-Object {
                [PSCustomObject]@{
                    SiteLinkName = $_.SiteLinkName
                    SiteName     = $_.SiteName
                    CollectionID = $this.GetCollectionID()
                }
            }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $junctionRecords `
                -TableName 'AD_SiteLinkSite' -ShowProgress $false -UseSingleTransaction

            $this.SiteLinkSitesWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "Site link-site junctions added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add site link-site junctions to database" -Exception $_.Exception
            throw
        }
    }

    #endregion Sites & Services Batch Methods

    #region Optional Features Batch Method

    # Add Optional Features batch
    [void] AddOptionalFeaturesBatch([array]$features) {
        $this.EnsureConnectionReady()

        if ($null -eq $features -or $features.Count -eq 0) {
            Write-ADInventoryLog -Level Verbose -Message "No optional features to add to database"
            return
        }

        try {
            $featureRecords = $features | ForEach-Object {
                [PSCustomObject]@{
                    ForestName              = $_.ForestName
                    FeatureName             = $_.FeatureName
                    FeatureGUID             = $_.FeatureGUID
                    IsEnabled               = if ($_.IsEnabled) { 1 } else { 0 }
                    RequiredForestLevel     = $_.RequiredForestLevel
                    RequiredForestLevelName = $_.RequiredForestLevelName
                    RequiredDomainLevel     = $_.RequiredDomainLevel
                    Description             = $_.Description
                    DistinguishedName       = $_.DistinguishedName
                    CollectionID            = $this.GetCollectionID()
                }
            }

            Write-ADInventoryLog -Level Info -Message "Adding optional features to database" `
                -Context @{
                    Count = $featureRecords.Count
                    CollectionID = $this.GetCollectionID()
                }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $featureRecords `
                -TableName 'AD_OptionalFeature' -ShowProgress $false -UseSingleTransaction

            $this.OptionalFeaturesWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "Optional features added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add optional features to database" -Exception $_.Exception
            throw
        }
    }

    #endregion Optional Features Batch Method

    #region KMS, ADFS, and PKI Batch Methods

    # Add KMS Service records batch (DNS SRV records)
    [void] AddKMSServicesBatch([array]$kmsServices) {
        $this.EnsureConnectionReady()

        if ($null -eq $kmsServices -or $kmsServices.Count -eq 0) {
            Write-ADInventoryLog -Level Verbose -Message "No KMS service records to add to database"
            return
        }

        try {
            $kmsRecords = $kmsServices | ForEach-Object {
                [PSCustomObject]@{
                    DomainName     = $_.DomainName
                    TargetHostname = $_.TargetHostname
                    Port           = $_.Port
                    Priority       = $_.Priority
                    Weight         = $_.Weight
                    TTL            = $_.TTL
                    ResolvedIP     = $_.ResolvedIP
                    RecordSource   = $_.RecordSource
                    CollectionID   = $this.GetCollectionID()
                }
            }

            Write-ADInventoryLog -Level Info -Message "Adding KMS service records to database" `
                -Context @{
                    Count = $kmsRecords.Count
                    CollectionID = $this.GetCollectionID()
                }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $kmsRecords `
                -TableName 'AD_KMSService' -ShowProgress $false -UseSingleTransaction

            $this.KMSServicesWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "KMS service records added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add KMS service records to database" -Exception $_.Exception
            throw
        }
    }

    # Add ADFS Configuration records batch (ADFS and DRS Service Connection Points)
    [void] AddADFSConfigurationBatch([array]$adfsConfigs) {
        $this.EnsureConnectionReady()

        if ($null -eq $adfsConfigs -or $adfsConfigs.Count -eq 0) {
            Write-ADInventoryLog -Level Verbose -Message "No ADFS configuration records to add to database"
            return
        }

        try {
            $adfsRecords = $adfsConfigs | ForEach-Object {
                [PSCustomObject]@{
                    ForestName            = $_.ForestName
                    ServiceType           = $_.ServiceType
                    ServiceName           = $_.ServiceName
                    FederationServiceName = $_.FederationServiceName
                    AzureTenantId         = $_.AzureTenantId
                    AzureObjectId         = $_.AzureObjectId
                    DomainName            = $_.DomainName
                    ServiceBindingInfo    = $_.ServiceBindingInfo
                    Keywords              = $_.Keywords
                    DistinguishedName     = $_.DistinguishedName
                    ObjectGUID            = $_.ObjectGUID
                    WhenCreated           = if ($_.WhenCreated) { $_.WhenCreated.ToString('o') } else { $null }
                    WhenChanged           = if ($_.WhenChanged) { $_.WhenChanged.ToString('o') } else { $null }
                    CollectionID          = $this.GetCollectionID()
                }
            }

            Write-ADInventoryLog -Level Info -Message "Adding ADFS configuration records to database" `
                -Context @{
                    Count = $adfsRecords.Count
                    CollectionID = $this.GetCollectionID()
                }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $adfsRecords `
                -TableName 'AD_ADFSConfiguration' -ShowProgress $false -UseSingleTransaction

            $this.ADFSConfigsWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "ADFS configuration records added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add ADFS configuration records to database" -Exception $_.Exception
            throw
        }
    }

    # Add PKI data batch (Enterprise CAs, Certificate Templates, Trusted Root CAs, NTAuth CAs)
    [void] AddPKIDataBatch([PSCustomObject]$pkiData) {
        $this.EnsureConnectionReady()

        if ($null -eq $pkiData) {
            Write-ADInventoryLog -Level Verbose -Message "No PKI data to add to database"
            return
        }

        try {
            Write-ADInventoryLog -Level Info -Message "Adding PKI data to database" `
                -Context @{ CollectionID = $this.GetCollectionID() }

            # Add Enterprise CAs
            if ($pkiData.EnterpriseCAs -and $pkiData.EnterpriseCAs.Count -gt 0) {
                $this.AddEnterpriseCAs($pkiData.EnterpriseCAs)
            }

            # Add Certificate Templates
            if ($pkiData.CertificateTemplates -and $pkiData.CertificateTemplates.Count -gt 0) {
                $this.AddCertificateTemplates($pkiData.CertificateTemplates)
            }

            # Add Trusted Root CAs
            if ($pkiData.TrustedRootCAs -and $pkiData.TrustedRootCAs.Count -gt 0) {
                $this.AddTrustedRootCAs($pkiData.TrustedRootCAs)
            }

            # Add NTAuth CAs
            if ($pkiData.NTAuthCAs -and $pkiData.NTAuthCAs.Count -gt 0) {
                $this.AddNTAuthCAs($pkiData.NTAuthCAs)
            }

            Write-ADInventoryLog -Level Info -Message "PKI data added to database"
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add PKI data to database" -Exception $_.Exception
            throw
        }
    }

    # Add Enterprise CAs (internal helper)
    hidden [void] AddEnterpriseCAs([array]$enterpriseCAs) {
        if ($null -eq $enterpriseCAs -or $enterpriseCAs.Count -eq 0) { return }

        try {
            $caRecords = $enterpriseCAs | ForEach-Object {
                [PSCustomObject]@{
                    ForestName           = $_.ForestName
                    CAName               = $_.CAName
                    DNSHostName          = $_.DNSHostName
                    CAType               = $_.CAType
                    CACertificate        = $_.CACertificate
                    CACertificateDN      = $_.CACertificateDN
                    CertificateTemplates = $_.CertificateTemplates
                    Flags                = $_.Flags
                    DistinguishedName    = $_.DistinguishedName
                    ObjectGUID           = $_.ObjectGUID
                    WhenCreated          = if ($_.WhenCreated) { $_.WhenCreated.ToString('o') } else { $null }
                    WhenChanged          = if ($_.WhenChanged) { $_.WhenChanged.ToString('o') } else { $null }
                    CollectionID         = $this.GetCollectionID()
                }
            }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $caRecords `
                -TableName 'AD_EnterpriseCA' -ShowProgress $false -UseSingleTransaction

            $this.EnterpriseCAsWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "Enterprise CAs added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add Enterprise CAs to database" -Exception $_.Exception
            throw
        }
    }

    # Add Certificate Templates (internal helper)
    hidden [void] AddCertificateTemplates([array]$templates) {
        if ($null -eq $templates -or $templates.Count -eq 0) { return }

        try {
            $templateRecords = $templates | ForEach-Object {
                [PSCustomObject]@{
                    ForestName           = $_.ForestName
                    TemplateName         = $_.TemplateName
                    DisplayName          = $_.DisplayName
                    TemplateOID          = $_.TemplateOID
                    SchemaVersion        = $_.SchemaVersion
                    MinorRevision        = $_.MinorRevision
                    MajorRevision        = $_.MajorRevision
                    RASignaturesRequired = $_.RASignaturesRequired
                    MinKeySize           = $_.MinKeySize
                    EnrollmentFlags      = $_.EnrollmentFlags
                    PrivateKeyFlags      = $_.PrivateKeyFlags
                    CertificateNameFlags = $_.CertificateNameFlags
                    ValidityPeriod       = $_.ValidityPeriod
                    RenewalPeriod        = $_.RenewalPeriod
                    ExtendedKeyUsage     = $_.ExtendedKeyUsage
                    DistinguishedName    = $_.DistinguishedName
                    ObjectGUID           = $_.ObjectGUID
                    WhenCreated          = if ($_.WhenCreated) { $_.WhenCreated.ToString('o') } else { $null }
                    WhenChanged          = if ($_.WhenChanged) { $_.WhenChanged.ToString('o') } else { $null }
                    CollectionID         = $this.GetCollectionID()
                }
            }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $templateRecords `
                -TableName 'AD_CertificateTemplate' -ShowProgress $false -UseSingleTransaction

            $this.CertificateTemplatesWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "Certificate templates added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add certificate templates to database" -Exception $_.Exception
            throw
        }
    }

    # Add Trusted Root CAs (internal helper)
    hidden [void] AddTrustedRootCAs([array]$trustedRootCAs) {
        if ($null -eq $trustedRootCAs -or $trustedRootCAs.Count -eq 0) { return }

        try {
            $rootCARecords = $trustedRootCAs | ForEach-Object {
                [PSCustomObject]@{
                    ForestName            = $_.ForestName
                    CAName                = $_.CAName
                    CACertificate         = $_.CACertificate
                    CertificateSubject    = $_.CertificateSubject
                    CertificateThumbprint = $_.CertificateThumbprint
                    CertificateNotBefore  = $_.CertificateNotBefore
                    CertificateNotAfter   = $_.CertificateNotAfter
                    ContainerType         = $_.ContainerType
                    DistinguishedName     = $_.DistinguishedName
                    ObjectGUID            = $_.ObjectGUID
                    WhenCreated           = if ($_.WhenCreated) { $_.WhenCreated.ToString('o') } else { $null }
                    WhenChanged           = if ($_.WhenChanged) { $_.WhenChanged.ToString('o') } else { $null }
                    CollectionID          = $this.GetCollectionID()
                }
            }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $rootCARecords `
                -TableName 'AD_TrustedRootCA' -ShowProgress $false -UseSingleTransaction

            $this.TrustedRootCAsWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "Trusted Root CAs added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add Trusted Root CAs to database" -Exception $_.Exception
            throw
        }
    }

    # Add NTAuth CAs (internal helper)
    hidden [void] AddNTAuthCAs([array]$ntAuthCAs) {
        if ($null -eq $ntAuthCAs -or $ntAuthCAs.Count -eq 0) { return }

        try {
            $ntAuthRecords = $ntAuthCAs | ForEach-Object {
                [PSCustomObject]@{
                    ForestName            = $_.ForestName
                    CertificateSubject    = $_.CertificateSubject
                    CACertificate         = $_.CACertificate
                    CertificateThumbprint = $_.CertificateThumbprint
                    CertificateNotBefore  = $_.CertificateNotBefore
                    CertificateNotAfter   = $_.CertificateNotAfter
                    CertificateIndex      = $_.CertificateIndex
                    DistinguishedName     = $_.DistinguishedName
                    CollectionID          = $this.GetCollectionID()
                }
            }

            $inserted = Add-SQLiteBatch -Connection $this.Connection -Objects $ntAuthRecords `
                -TableName 'AD_NTAuthCA' -ShowProgress $false -UseSingleTransaction

            $this.NTAuthCAsWritten += $inserted
            Write-ADInventoryLog -Level Info -Message "NTAuth CAs added to database" -Context @{ Inserted = $inserted }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to add NTAuth CAs to database" -Exception $_.Exception
            throw
        }
    }

    #endregion KMS, ADFS, and PKI Batch Methods

    # Finalize - perform any cleanup operations
    [void] Finalize() {
        $this.EnsureConnectionReady()

        try {
            Write-ADInventoryLog -Level Info -Message "Finalizing database" `
                -Context $this.GetStatistics()

            # Update CollectionInfo with EndTime
            $this.UpdateCollectionEndTime()

            # Create indexes now that all data is loaded (major performance benefit)
            if (-not $this.IndexesCreated) {
                Write-ADInventoryLog -Level Info -Message "Creating database indexes (this may take several minutes)..."

                $indexStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $indexCount = Add-ADInventoryIndexes -Connection $this.Connection
                $indexStopwatch.Stop()

                Write-ADExecutionTime -Operation 'Index' -Target 'AllTables' `
                    -DurationSeconds $indexStopwatch.Elapsed.TotalSeconds `
                    -RecordCount $indexCount

                $this.IndexesCreated = $true

                Write-ADInventoryLog -Level Info -Message "Database indexes created" `
                    -Context @{
                        IndexCount = $indexCount
                    }
            }

            # Run ANALYZE to update statistics for query optimizer
            Write-ADInventoryLog -Level Info -Message "Analyzing database statistics"
            $analyzeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-SqliteQuery -SQLiteConnection $this.Connection -Query "ANALYZE"
            $analyzeStopwatch.Stop()

            Write-ADExecutionTime -Operation 'Finalize' -Target 'ANALYZE' `
                -DurationSeconds $analyzeStopwatch.Elapsed.TotalSeconds

            Write-ADInventoryLog -Level Info -Message "Database finalized successfully"
        }
        catch {
            Write-ADInventoryLog -Level Warning -Message "Error during database finalization" `
                -Exception $_.Exception
            # Don't throw - finalization is optional optimization
        }
    }

    # Rollback any pending transaction
    [void] Rollback() {
        if ($this.IsDisposed) {
            return
        }

        if ($this.InTransaction) {
            try {
                Write-ADInventoryLog -Level Warning -Message "Rolling back transaction"
                Invoke-SqliteQuery -SQLiteConnection $this.Connection -Query "ROLLBACK"
                $this.InTransaction = $false
                Write-ADInventoryLog -Level Info -Message "Transaction rolled back"
            }
            catch {
                Write-ADInventoryLog -Level Error -Message "Failed to rollback transaction" `
                    -Exception $_.Exception
            }
        }
    }

    # IDisposable implementation
    [void] Dispose() {
        if ($this.IsDisposed) {
            return
        }

        Write-ADInventoryLog -Level Debug -Message "Disposing SQLiteInventoryWriter"

        try {
            # Rollback any pending transaction
            $this.Rollback()

            # Close and dispose connection
            if ($null -ne $this.Connection) {
                try {
                    if ($this.Connection.State -eq [System.Data.ConnectionState]::Open) {
                        # Checkpoint WAL to merge .wal file into main database and remove .wal/.shm files
                        # TRUNCATE mode: checkpoint and truncate the WAL file to zero bytes
                        Write-ADInventoryLog -Level Debug -Message "Running WAL checkpoint before close"
                        try {
                            $cmd = $this.Connection.CreateCommand()
                            $cmd.CommandText = "PRAGMA wal_checkpoint(TRUNCATE)"
                            $null = $cmd.ExecuteNonQuery()
                            $cmd.Dispose()
                            Write-ADInventoryLog -Level Debug -Message "WAL checkpoint completed"
                        }
                        catch {
                            Write-ADInventoryLog -Level Warning -Message "WAL checkpoint failed (non-critical)" `
                                -Exception $_.Exception
                        }

                        Write-ADInventoryLog -Level Debug -Message "Closing SQLite connection"
                        $this.Connection.Close()
                    }

                    $this.Connection.Dispose()
                    Write-ADInventoryLog -Level Debug -Message "SQLite connection disposed"
                }
                catch {
                    Write-ADInventoryLog -Level Warning -Message "Error disposing connection" `
                        -Exception $_.Exception
                }
                finally {
                    $this.Connection = $null
                }
            }

            $this.IsDisposed = $true

            Write-ADInventoryLog -Level Verbose -Message "SQLiteInventoryWriter disposed" `
                -Context $this.GetStatistics()
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Error in Dispose method" `
                -Exception $_.Exception
        }
    }
}
