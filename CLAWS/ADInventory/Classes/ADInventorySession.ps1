using namespace System.Collections.Generic

<#
.SYNOPSIS
    Session orchestrator class for AD inventory collection

.DESCRIPTION
    Main orchestrator that coordinates the entire AD inventory workflow.
    Manages state, connections, and processing across multiple domains.

    REPLACES original script-level state (lines 1441-1448):
    - No more $script: variables
    - Encapsulated state management
    - Proper lifecycle handling
    - Testable design

.NOTES
    Part of SSNC.ADInventory module

    Workflow:
    1. Create session with domains and output path
    2. Initialize database and schema
    3. For each domain:
       - Find optimal DC
       - Collect objects (users, groups, computers, FSPs, trusts)
       - Build lookup maps
       - Stream to database
    4. Process group memberships (direct and recursive)
    5. Finalize and close database

    Usage:
        $session = [ADInventorySession]::new($domains, $outputPath, $config)
        try {
            $session.Initialize()
            $session.CollectInventory()
            $summary = $session.GetSummary()
        } finally {
            $session.Dispose()
        }
#>
class ADInventorySession : System.IDisposable {
    # Core Properties
    [guid]$InventoryID
    [string]$CollectionID = $null  # Database collection ID - GUID string (from AD_CollectionInfo)
    [string[]]$Domains
    [string]$OutputPath
    [ADQueryConfig]$Config
    [SQLiteInventoryWriter]$Writer
    [bool]$IsInitialized = $false
    [bool]$IsDisposed = $false
    [datetime]$StartTime
    [datetime]$EndTime

    # Lookup Maps (for group membership resolution)
    [hashtable]$DNtoSIDMap = @{}
    [hashtable]$SIDtoObjectTypeMap = @{}
    [hashtable]$SIDtoNameMap = @{}

    # Temporary Collections
    [System.Collections.ArrayList]$GroupMembershipDNs = [System.Collections.ArrayList]::new()
    [System.Collections.ArrayList]$AllFSPs = [System.Collections.ArrayList]::new()
    [System.Collections.ArrayList]$AllTrusts = [System.Collections.ArrayList]::new()

    # Statistics
    [hashtable]$Statistics = @{
        DomainsProcessed = 0
        DomainsSkipped = 0
        UsersCollected = 0
        GroupsCollected = 0
        ComputersCollected = 0
        ContactsCollected = 0
        FSPsCollected = 0
        TrustsCollected = 0
        DomainInfoCollected = 0
        ForestInfoCollected = 0
        DirectMemberships = 0
        RecursiveMemberships = 0
        # Sites & Services statistics
        SitesCollected = 0
        SubnetsCollected = 0
        SiteLinksCollected = 0
        SiteSettingsCollected = 0
        SiteServersCollected = 0
        SiteDomainControllersCollected = 0
        # Optional Features statistics
        OptionalFeaturesCollected = 0
        # KMS, ADFS, and PKI statistics
        KMSServicesCollected = 0
        ADFSConfigsCollected = 0
        EnterpriseCAsCollected = 0
        CertificateTemplatesCollected = 0
        TrustedRootCAsCollected = 0
        NTAuthCAsCollected = 0
    }

    # Track skipped domains (unreachable, DNS failures, etc.)
    [System.Collections.ArrayList]$SkippedDomains = [System.Collections.ArrayList]::new()

    # Track collected forests to avoid duplicates (multiple domains may be in same forest)
    [System.Collections.Generic.HashSet[string]]$CollectedForests = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    # Object Types to Collect
    [string[]]$ObjectTypes = @('All')

    # Advanced Features
    [bool]$EnableParallel = $false
    [int]$ParallelThrottleLimit = 4
    [bool]$EnableResume = $false
    [bool]$ResolveForeignSecurityPrincipals = $false
    [hashtable]$TrustMap = @{}  # For FSP resolution

    # Skip Flags for Optional Collections
    [bool]$SkipKMS = $false     # Skip KMS service discovery (DNS SRV queries)
    [bool]$SkipADFS = $false    # Skip ADFS and DRS configuration collection
    [bool]$SkipPKI = $false     # Skip AD Certificate Services (PKI) collection

    # Constructor
    ADInventorySession([string[]]$domains, [string]$outputPath, [ADQueryConfig]$config) {
        if ($null -eq $domains -or $domains.Count -eq 0) {
            throw [System.ArgumentException]::new("Domains array cannot be null or empty")
        }

        if ([string]::IsNullOrWhiteSpace($outputPath)) {
            throw [System.ArgumentException]::new("Output path cannot be null or empty")
        }

        if (-not (Test-Path $outputPath -PathType Container)) {
            throw [System.IO.DirectoryNotFoundException]::new("Output directory not found: $outputPath")
        }

        $this.InventoryID = [guid]::NewGuid()
        $this.Domains = $domains
        $this.OutputPath = $outputPath
        $this.Config = if ($config) { $config } else { [ADQueryConfig]::new() }
        $this.StartTime = Get-Date

        Write-ADInventoryLog -Level Info -Message "ADInventorySession created" `
            -Context @{
                InventoryID = $this.InventoryID.ToString()
                DomainCount = $domains.Count
                Domains = ($domains -join ', ')
            }
    }

    # Initialize database
    [void] Initialize() {
        if ($this.IsInitialized) {
            throw "Session is already initialized"
        }

        if ($this.IsDisposed) {
            throw "Cannot initialize disposed session"
        }

        try {
            Write-ADInventoryLog -Level Info -Message "Initializing inventory session" `
                -Category Initialization `
                -Context @{ InventoryID = $this.InventoryID.ToString() }

            # Validate configuration
            $this.Config.Validate()

            # Create SQLite writer
            $this.Writer = [SQLiteInventoryWriter]::new($this.OutputPath)

            # Initialize database with all domains - creates one CollectionInfo record per domain
            $this.CollectionID = $this.Writer.Initialize(
                $this.Domains,
                $this.InventoryID.ToString(),
                $env:COMPUTERNAME,
                "$env:USERDOMAIN\$env:USERNAME"
            )

            # Initialize logging infrastructure (simplified naming - timestamp only)
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $logFileName = "ADInventory_${timestamp}.log"
            $logFilePath = Join-Path $this.OutputPath $logFileName

            # Set module-scoped variables for logging (CollectionID for normalized schema)
            $Script:ADInventoryLogFilePath = $logFilePath
            $Script:ADInventoryLogConnection = $this.Writer.Connection
            # Use helper function to properly set CollectionID in module scope
            # (PowerShell 5.1 class methods have different scope than module functions)
            Set-ADInventoryCollectionID -CollectionID $this.CollectionID

            # Write header to log file (include module version for troubleshooting)
            $moduleVersion = if ($Script:ModuleVersion) { $Script:ModuleVersion } else { 'Unknown' }
            $logHeader = @"
============================================================================
AD Inventory Collection Log
============================================================================
Module Ver:   SSNC.ADInventory v$moduleVersion
Inventory ID: $($this.InventoryID)
Start Time:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Domains:      $($this.Domains -join ', ')
Output Path:  $($this.OutputPath)
Database:     $($this.Writer.DbPath)
Log File:     $logFilePath
Machine:      $env:COMPUTERNAME
User:         $env:USERNAME
============================================================================

"@
            Add-Content -Path $logFilePath -Value $logHeader -Encoding UTF8

            $this.IsInitialized = $true

            Write-ADInventoryLog -Level Info -Message "Session initialized successfully" `
                -Category Initialization `
                -Context @{
                    InventoryID = $this.InventoryID.ToString()
                    CollectionID = $this.CollectionID
                    DatabasePath = $this.Writer.DbPath
                    LogFilePath = $logFilePath
                } `
                -LogFilePath $logFilePath `
                -DatabaseConnection $this.Writer.Connection `
                -CollectionID $this.CollectionID
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to initialize session" `
                -Category Initialization `
                -Context @{ InventoryID = $this.InventoryID.ToString() } `
                -Exception $_.Exception

            # Cleanup on failure
            if ($this.Writer) {
                try { $this.Writer.Dispose() } catch { }
                $this.Writer = $null
            }

            throw
        }
    }

    # Main inventory collection workflow
    [void] CollectInventory() {
        $this.EnsureInitialized()

        Write-ADInventoryLog -Level Info -Message "Starting inventory collection" `
            -Context @{
                InventoryID = $this.InventoryID.ToString()
                DomainCount = $this.Domains.Count
                ObjectTypes = ($this.ObjectTypes -join ', ')
                EnableParallel = $this.EnableParallel
                EnableResume = $this.EnableResume
            }

        try {
            # Check for existing checkpoint
            $domainsToProcess = $this.Domains
            if ($this.EnableResume) {
                $checkpoint = Get-ADInventoryCheckpoint -InventoryID $this.InventoryID -OutputPath $this.OutputPath

                if ($checkpoint) {
                    Write-ADInventoryLog -Level Info -Message "Resuming from checkpoint" `
                        -Context @{
                            InventoryID = $this.InventoryID.ToString()
                            CompletedDomains = $checkpoint.CompletedDomains.Count
                            SavedAt = $checkpoint.SavedAt
                        }

                    # Resume statistics
                    foreach ($key in $checkpoint.Statistics.Keys) {
                        $this.Statistics[$key] = $checkpoint.Statistics[$key]
                    }

                    # Filter to remaining domains
                    $domainsToProcess = $this.Domains | Where-Object { $_ -notin $checkpoint.CompletedDomains }

                    Write-ADInventoryLog -Level Info -Message "Remaining domains to process" `
                        -Context @{ RemainingDomains = $domainsToProcess.Count }
                }
            }

            # Process domains (parallel or sequential)
            if ($this.EnableParallel -and $domainsToProcess.Count -gt 1) {
                Write-ADInventoryLog -Level Info -Message "Using parallel domain processing" `
                    -Context @{
                        DomainCount = $domainsToProcess.Count
                        ThrottleLimit = $this.ParallelThrottleLimit
                    }

                # Build script block for parallel execution
                # Parameters: domain, domainIndex, totalDomains are passed by Invoke-ParallelDomainCollection
                # Additional parameters (session) come from ArgumentList
                $scriptBlock = {
                    param($domain, $domainIndex, $totalDomains, $session)

                    try {
                        $success = $session.CollectDomain($domain, $domainIndex, $totalDomains)
                        if ($success) {
                            # Export collected data (DNtoSIDMap, GroupMembershipDNs, etc.) for merging
                            $collectedData = $session.ExportCollectedData()
                            return @{
                                Success = $true
                                Skipped = $false
                                Domain = $domain
                                CollectedData = $collectedData
                            }
                        }
                        else {
                            # Domain was skipped (unreachable, DNS failure, etc.)
                            return @{
                                Success = $true
                                Skipped = $true
                                Domain = $domain
                                CollectedData = $null
                            }
                        }
                    }
                    catch {
                        return @{ Success = $false; Skipped = $false; Domain = $domain; Error = $_.Exception.Message }
                    }
                }

                # Execute parallel collection
                $results = Invoke-ParallelDomainCollection `
                    -Domains $domainsToProcess `
                    -ScriptBlock $scriptBlock `
                    -ThrottleLimit $this.ParallelThrottleLimit `
                    -ArgumentList $this

                # Process results and merge collected data from each runspace
                foreach ($result in $results) {
                    if ($result.Success) {
                        if ($result.Skipped) {
                            # Domain was skipped (unreachable) - already logged in CollectDomain
                            # Statistics are updated in CollectDomain
                            Write-ADInventoryLog -Level Info -Message "Domain skipped in parallel mode" `
                                -Context @{ Domain = $result.Domain }
                        }
                        else {
                            $this.Statistics.DomainsProcessed++

                            # Merge collected data (DNtoSIDMap, GroupMembershipDNs, etc.) from this runspace
                            if ($result.CollectedData) {
                                $this.MergeCollectedData($result.CollectedData)
                                Write-ADInventoryLog -Level Debug -Message "Merged collected data from parallel runspace" `
                                    -Context @{
                                        Domain = $result.Domain
                                        DNtoSIDMapEntries = if ($result.CollectedData.DNtoSIDMap) { $result.CollectedData.DNtoSIDMap.Count } else { 0 }
                                        GroupMembershipDNs = if ($result.CollectedData.GroupMembershipDNs) { $result.CollectedData.GroupMembershipDNs.Count } else { 0 }
                                    }
                            }
                        }

                        # Save checkpoint after each domain (processed or skipped)
                        if ($this.EnableResume) {
                            $completedDomains = @($this.Domains | Where-Object { $_ -notin $domainsToProcess -or $_ -eq $result.Domain })
                            Save-ADInventoryCheckpoint `
                                -InventoryID $this.InventoryID `
                                -OutputPath $this.OutputPath `
                                -CompletedDomains $completedDomains `
                                -Statistics $this.Statistics `
                                -Metadata @{ TotalDomains = $this.Domains.Count }
                        }
                    }
                    else {
                        Write-ADInventoryLog -Level Error -Message "Domain collection failed in parallel mode" `
                            -Context @{ Domain = $result.Domain; Error = $result.Error }
                        throw "Failed to collect domain $($result.Domain): $($result.Error)"
                    }
                }

                Write-ADInventoryLog -Level Info -Message "Parallel collection data merged" `
                    -Context @{
                        TotalDNtoSIDMapEntries = $this.DNtoSIDMap.Count
                        TotalGroupMembershipDNs = $this.GroupMembershipDNs.Count
                    }
            }
            else {
                # Sequential processing
                $totalDomains = $domainsToProcess.Count
                for ($i = 0; $i -lt $domainsToProcess.Count; $i++) {
                    $domain = $domainsToProcess[$i]
                    $success = $this.CollectDomain($domain, ($i + 1), $totalDomains)

                    # Only count as processed if collection succeeded (not skipped)
                    if ($success) {
                        $this.Statistics.DomainsProcessed++
                    }

                    # Save checkpoint after each domain (processed or skipped)
                    if ($this.EnableResume) {
                        $completedDomains = @($this.Domains | Where-Object { $_ -notin $domainsToProcess -or $_ -in @($domainsToProcess[0..$domainsToProcess.IndexOf($domain)]) })
                        Save-ADInventoryCheckpoint `
                            -InventoryID $this.InventoryID `
                            -OutputPath $this.OutputPath `
                            -CompletedDomains $completedDomains `
                            -Statistics $this.Statistics `
                            -Metadata @{ TotalDomains = $this.Domains.Count }
                    }
                }

                # DIAGNOSTIC: Log after sequential processing completes
                Write-ADInventoryLog -Level Info -Message "Sequential processing completed" `
                    -Context @{
                        DomainsProcessed = $this.Statistics.DomainsProcessed
                        DomainsSkipped = $this.Statistics.DomainsSkipped
                        GroupMembershipDNsCount = $this.GroupMembershipDNs.Count
                    }
            }

            # DIAGNOSTIC: Log the state of GroupMembershipDNs before processing
            Write-ADInventoryLog -Level Info -Message "Pre-membership processing check" `
                -Context @{
                    GroupMembershipDNsCount = $this.GroupMembershipDNs.Count
                    GroupMembershipDNsType = $this.GroupMembershipDNs.GetType().FullName
                    IsNull = ($null -eq $this.GroupMembershipDNs)
                }

            # Process group memberships (if groups were collected)
            if ($this.GroupMembershipDNs.Count -gt 0) {
                $this.ProcessGroupMemberships()
            }
            else {
                Write-ADInventoryLog -Level Warning -Message "No group memberships to process - GroupMembershipDNs is empty"
            }

            # NOTE: Flattened group memberships (AD_GroupMember_Flat) are computed
            # post-collection in MS SQL using a recursive CTE for better performance.
            # See: database/MSSQL/FlattenGroupMemberships.sql

            # Finalize database
            $this.Writer.Finalize()

            # Remove checkpoint on successful completion
            if ($this.EnableResume) {
                Remove-ADInventoryCheckpoint -InventoryID $this.InventoryID -OutputPath $this.OutputPath
            }

            $this.EndTime = Get-Date

            Write-ADInventoryLog -Level Info -Message "Inventory collection completed" `
                -Context $this.GetSummary()
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Inventory collection failed" `
                -Context @{ InventoryID = $this.InventoryID.ToString() } `
                -Exception $_.Exception

            # Attempt rollback
            try {
                $this.Writer.Rollback()
            }
            catch {
                Write-ADInventoryLog -Level Error -Message "Rollback failed" `
                    -Exception $_.Exception
            }

            throw
        }
    }

    # Collect from a single domain
    # Parameters:
    #   domain - The domain name to collect
    #   domainIndex - 1-based index of this domain in the processing order
    #   totalDomains - Total number of domains being processed
    # Returns:
    #   $true if domain was successfully collected
    #   $false if domain was skipped (unreachable, DNS failure, etc.)
    hidden [bool] CollectDomain([string]$domain, [int]$domainIndex, [int]$totalDomains) {
        Write-ADInventoryLog -Level Info -Message "Processing domain" `
            -Context @{
                Domain = $domain
                Progress = "$domainIndex/$totalDomains"
            }

        # Set the current domain for database writes (each domain has its own CollectionID)
        $this.Writer.SetCurrentDomain($domain)

        # Record when this domain's collection actually starts
        $this.Writer.UpdateDomainStartTime($domain)

        try {
            # Find optimal DC - this is where DNS/connectivity failures occur
            Write-ADInventoryLog -Level Debug -Message "Finding optimal domain controller"
            $dc = Get-OptimalDomainController -DomainName $domain -Config $this.Config

            Write-ADInventoryLog -Level Info -Message "Using domain controller" `
                -Context @{
                    Domain = $domain
                    DC = $dc.IPAddress
                    Latency = "$($dc.Latency)ms"
                }

            # Collect trusts
            $this.CollectTrusts($domain)

            # Collect FSPs
            $this.CollectFSPs($dc.IPAddress, $domain)

            # Collect AD objects based on ObjectTypes
            $collectUsers = ($this.ObjectTypes -contains 'All' -or $this.ObjectTypes -contains 'Users')
            $collectGroups = ($this.ObjectTypes -contains 'All' -or $this.ObjectTypes -contains 'Groups')
            $collectComputers = ($this.ObjectTypes -contains 'All' -or $this.ObjectTypes -contains 'Computers')
            $collectContacts = ($this.ObjectTypes -contains 'All' -or $this.ObjectTypes -contains 'Contacts')

            if ($collectUsers) {
                $this.CollectUsers($dc.IPAddress, $domain)
            }

            if ($collectGroups) {
                $this.CollectGroups($dc.IPAddress, $domain)
            }

            if ($collectComputers) {
                $this.CollectComputers($dc.IPAddress, $domain)
            }

            if ($collectContacts) {
                $this.CollectContacts($dc.IPAddress, $domain)
            }

            # Collect domain and forest information
            $this.CollectDomainInfo($dc.IPAddress, $domain)
            $this.CollectForestInfo($dc.IPAddress, $domain)

            # Collect KMS service records (domain-scoped, via DNS)
            if (-not $this.SkipKMS) {
                $this.CollectKMSServices($domain)
            }

            # Record when this domain's collection completed successfully
            $this.Writer.UpdateDomainEndTime($domain)

            Write-ADInventoryLog -Level Info -Message "Domain processing completed" `
                -Context @{ Domain = $domain }

            return $true
        }
        catch {
            # Check if this is a DNS resolution, DC connectivity, or LDAP operational failure
            # These are common for retired domains, stale trusts, or DCs that become unavailable mid-collection
            $errorMessage = $_.Exception.Message

            # Also check inner exception message (common with LDAP errors)
            $innerMessage = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { '' }
            $fullErrorContext = "$errorMessage $innerMessage"

            $isRecoverableError = (
                # DNS/resolution errors
                $fullErrorContext -match 'DNS' -or
                $fullErrorContext -match 'resolve' -or
                $fullErrorContext -match 'not find' -or
                # DC connectivity errors
                $fullErrorContext -match 'domain controller' -or
                $fullErrorContext -match 'No accessible' -or
                # LDAP operational errors (DC became unavailable mid-collection)
                $fullErrorContext -match 'server is not operational' -or
                $fullErrorContext -match 'server is unavailable' -or
                $fullErrorContext -match 'LDAP server' -or
                $fullErrorContext -match 'connection was forcibly closed' -or
                $fullErrorContext -match 'network path was not found' -or
                $fullErrorContext -match 'RPC server' -or
                # LDAP attribute errors (schema mismatch or restricted domain)
                $fullErrorContext -match 'attribute or value does not exist' -or
                $fullErrorContext -match 'no such object on the server' -or
                $fullErrorContext -match 'local error has occurred' -or
                # Win32 exceptions (network issues)
                $_.Exception.GetType().Name -eq 'Win32Exception'
            )

            if ($isRecoverableError) {
                # Log as warning and skip the domain gracefully
                Write-ADInventoryLog -Level Warning -Message "Domain unreachable or DC failed - skipping" `
                    -Context @{
                        Domain = $domain
                        Reason = $errorMessage
                        InnerException = $innerMessage
                        Note = "This domain may have been retired, have stale trust, or DC became unavailable"
                    }

                # Record the skipped domain for reporting
                [void]$this.SkippedDomains.Add([PSCustomObject]@{
                    Domain = $domain
                    Reason = $errorMessage
                    SkippedAt = (Get-Date).ToString('o')
                })

                $this.Statistics.DomainsSkipped++

                # Display warning to user
                Write-Host "  [WARNING] Domain '$domain' is unreachable and will be skipped" -ForegroundColor Yellow
                Write-Host "            Reason: $errorMessage" -ForegroundColor Yellow
                Write-Host "            (This may indicate a retired domain, stale trust, or unavailable DC)" -ForegroundColor DarkYellow
                Write-Host ""

                # Record when this domain's collection ended (even though it was skipped)
                $this.Writer.UpdateDomainEndTime($domain)

                return $false
            }
            else {
                # For other errors, log and re-throw
                Write-ADInventoryLog -Level Error -Message "Failed to process domain" `
                    -Context @{ Domain = $domain } `
                    -Exception $_.Exception

                throw "Failed to process domain $domain : $_"
            }
        }
    }

    # Helper methods for specific object types
    hidden [void] CollectTrusts([string]$domain) {
        Write-ADInventoryLog -Level Info -Message "Collecting ALL domain trusts (Inbound, Outbound, and Bidirectional)" `
            -Context @{ Domain = $domain }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            # Collect ALL trusts - no direction filtering
            # All trust links are stored in the database for complete trust topology visibility
            $trusts = Get-ADDomainTrust -DomainName $domain -TrustDirection 'All'

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'Trust_Enum' -Target 'Trusts' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount $trusts.Count -Domain $domain

            if ($trusts.Count -gt 0) {
                foreach ($trust in $trusts) {
                    [void]$this.AllTrusts.Add($trust)

                    # Build trust map for FSP resolution (if enabled)
                    if ($this.ResolveForeignSecurityPrincipals -and -not [string]::IsNullOrEmpty($trust.TargetDomain)) {
                        # Would need to query target domain SID here for complete mapping
                        # For now, just store the trust relationship
                    }
                }

                # Write ALL trusts to database (including Outbound for complete trust mapping)
                $this.Writer.AddTrustBatch($trusts)
                $this.Statistics.TrustsCollected += $trusts.Count

                # Calculate trust counts by direction for logging
                $inbound = ($trusts | Where-Object { $_.TrustDirection -eq 'Inbound' }).Count
                $outbound = ($trusts | Where-Object { $_.TrustDirection -eq 'Outbound' }).Count
                $bidirectional = ($trusts | Where-Object { $_.TrustDirection -eq 'Bidirectional' }).Count

                Write-ADInventoryLog -Level Info -Message "All trusts collected and inserted into database" `
                    -Context @{
                        Domain = $domain
                        TotalTrusts = $trusts.Count
                        Inbound = $inbound
                        Outbound = $outbound
                        Bidirectional = $bidirectional
                    }
            }
            else {
                Write-ADInventoryLog -Level Info -Message "No trusts found for domain" `
                    -Context @{ Domain = $domain }
            }
        }
        catch {
            $stopwatch.Stop()
            Write-ADInventoryLog -Level Warning -Message "Failed to collect trusts" `
                -Context @{ Domain = $domain } `
                -Exception $_.Exception
            # Continue with collection even if trusts fail
        }
    }

    hidden [void] CollectFSPs([string]$server, [string]$domain) {
        Write-ADInventoryLog -Level Info -Message "Collecting Foreign Security Principals" `
            -Context @{ Domain = $domain; Server = $server }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $fsps = Get-ForeignSecurityPrincipal `
                -Server $server `
                -DomainName $domain `
                -Config $this.Config `
                -ResolveForeignDomain:$this.ResolveForeignSecurityPrincipals `
                -TrustMap $this.TrustMap

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'FSPs' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount $fsps.Count -Domain $domain

            if ($fsps.Count -gt 0) {
                foreach ($fsp in $fsps) {
                    [void]$this.AllFSPs.Add($fsp)

                    # Add to lookup maps
                    if (-not [string]::IsNullOrEmpty($fsp.SID_String)) {
                        $this.SIDtoObjectTypeMap[$fsp.SID_String] = 'ForeignSecurityPrincipal'
                        $this.SIDtoNameMap[$fsp.SID_String] = if ($fsp.ResolvedName) { $fsp.ResolvedName } else { $fsp.SID_String }
                        $this.DNtoSIDMap[$fsp.DN] = $fsp.SID_String
                    }
                }

                # Write FSPs to database
                $this.Writer.AddFSPBatch($fsps)
                $this.Statistics.FSPsCollected += $fsps.Count

                Write-ADInventoryLog -Level Info -Message "FSPs collected" `
                    -Context @{
                        Domain = $domain
                        FSPCount = $fsps.Count
                        ResolvedCount = ($fsps | Where-Object { $_.ResolvedName }).Count
                    }
            }
        }
        catch {
            $stopwatch.Stop()
            Write-ADInventoryLog -Level Warning -Message "Failed to collect FSPs" `
                -Context @{ Domain = $domain; Server = $server } `
                -Exception $_.Exception
            # Continue with collection even if FSPs fail
        }
    }

    hidden [void] CollectUsers([string]$server, [string]$domain) {
        Write-ADInventoryLog -Level Info -Message "Collecting users" -Context @{ Domain = $domain; Server = $server }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $filter = "(&(objectClass=user)(objectCategory=person))"
            $users = Get-ADObjects `
                -Server $server `
                -SearchBase ("DC=" + ($domain -replace '\.', ',DC=')) `
                -Filter $filter `
                -Config $this.Config

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'Users' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount $users.Count -Domain $domain

            if ($users.Count -gt 0) {
                # Add to lookup maps and stream to database
                foreach ($user in $users) {
                    if (-not [string]::IsNullOrEmpty($user.SID_String)) {
                        $this.SIDtoObjectTypeMap[$user.SID_String] = 'User'
                        $this.SIDtoNameMap[$user.SID_String] = if ($user.DisplayName) { $user.DisplayName } else { $user.SamAccountName }
                        if ($user.DistinguishedName) {
                            $this.DNtoSIDMap[$user.DistinguishedName] = $user.SID_String
                        }
                    }
                }

                # Batch write to database
                $this.Writer.AddObjectBatch($users)
                $this.Statistics.UsersCollected += $users.Count

                Write-ADInventoryLog -Level Info -Message "Users collected" `
                    -Context @{ Domain = $domain; UserCount = $users.Count }
            }
        }
        catch {
            $stopwatch.Stop()
            Write-ADInventoryLog -Level Error -Message "Failed to collect users" `
                -Context @{ Domain = $domain; Server = $server } `
                -Exception $_.Exception
            throw
        }
    }

    hidden [void] CollectGroups([string]$server, [string]$domain) {
        Write-ADInventoryLog -Level Info -Message "Collecting groups" -Context @{ Domain = $domain; Server = $server }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $filter = "(objectClass=group)"
            $groups = Get-ADObjects `
                -Server $server `
                -SearchBase ("DC=" + ($domain -replace '\.', ',DC=')) `
                -Filter $filter `
                -Config $this.Config

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'Groups' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount $groups.Count -Domain $domain

            if ($groups.Count -gt 0) {
                # Process groups and collect membership DNs
                foreach ($group in $groups) {
                    if (-not [string]::IsNullOrEmpty($group.SID_String)) {
                        $this.SIDtoObjectTypeMap[$group.SID_String] = 'Group'
                        $this.SIDtoNameMap[$group.SID_String] = if ($group.DisplayName) { $group.DisplayName } else { $group.SamAccountName }
                        if ($group.DistinguishedName) {
                            $this.DNtoSIDMap[$group.DistinguishedName] = $group.SID_String
                        }
                    }

                    # Collect member DNs for later processing
                    # Check if group has many members (>1500) - use range retrieval
                    if ($group.DistinguishedName -and $group.Member.Count -gt 1500) {
                        Write-ADInventoryLog -Level Debug -Message "Large group detected - using range retrieval" `
                            -Context @{
                                GroupDN = $group.DistinguishedName
                                MemberCount = $group.Member.Count
                            }

                        $members = Get-LargeMultiValuedAttribute `
                            -DistinguishedName $group.DistinguishedName `
                            -AttributeName 'member' `
                            -Server $server `
                            -Config $this.Config

                        # Get CollectionID for this domain NOW while we're processing it
                        $currentCollectionID = $this.Writer.GetCollectionID()
                        foreach ($memberDN in $members) {
                            [void]$this.GroupMembershipDNs.Add(@{
                                GroupSID = $group.SID_String
                                MemberDN = $memberDN
                                CollectionID = $currentCollectionID
                            })
                        }
                    }
                    elseif ($group.Member -and $group.Member.Count -gt 0) {
                        # Standard member collection
                        # Get CollectionID for this domain NOW while we're processing it
                        $currentCollectionID = $this.Writer.GetCollectionID()
                        foreach ($memberDN in $group.Member) {
                            [void]$this.GroupMembershipDNs.Add(@{
                                GroupSID = $group.SID_String
                                MemberDN = $memberDN
                                CollectionID = $currentCollectionID
                            })
                        }
                    }
                }

                # Batch write to database
                $this.Writer.AddObjectBatch($groups)
                $this.Statistics.GroupsCollected += $groups.Count

                Write-ADInventoryLog -Level Info -Message "Groups collected" `
                    -Context @{
                        Domain = $domain
                        GroupCount = $groups.Count
                        MembershipDNsCollected = $this.GroupMembershipDNs.Count
                    }
            }
        }
        catch {
            if ($stopwatch.IsRunning) { $stopwatch.Stop() }
            Write-ADInventoryLog -Level Error -Message "Failed to collect groups" `
                -Context @{ Domain = $domain; Server = $server } `
                -Exception $_.Exception
            throw
        }
    }

    hidden [void] CollectComputers([string]$server, [string]$domain) {
        Write-ADInventoryLog -Level Info -Message "Collecting computers" -Context @{ Domain = $domain; Server = $server }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $filter = "(objectClass=computer)"
            $computers = Get-ADObjects `
                -Server $server `
                -SearchBase ("DC=" + ($domain -replace '\.', ',DC=')) `
                -Filter $filter `
                -Config $this.Config

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'Computers' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount $computers.Count -Domain $domain

            if ($computers.Count -gt 0) {
                # Add to lookup maps and stream to database
                foreach ($computer in $computers) {
                    if (-not [string]::IsNullOrEmpty($computer.SID_String)) {
                        $this.SIDtoObjectTypeMap[$computer.SID_String] = 'Computer'
                        $this.SIDtoNameMap[$computer.SID_String] = if ($computer.DisplayName) { $computer.DisplayName } else { $computer.SamAccountName }
                        if ($computer.DistinguishedName) {
                            $this.DNtoSIDMap[$computer.DistinguishedName] = $computer.SID_String
                        }
                    }
                }

                # Batch write to database
                $this.Writer.AddObjectBatch($computers)
                $this.Statistics.ComputersCollected += $computers.Count

                Write-ADInventoryLog -Level Info -Message "Computers collected" `
                    -Context @{ Domain = $domain; ComputerCount = $computers.Count }
            }
        }
        catch {
            if ($stopwatch.IsRunning) { $stopwatch.Stop() }
            Write-ADInventoryLog -Level Error -Message "Failed to collect computers" `
                -Context @{ Domain = $domain; Server = $server } `
                -Exception $_.Exception
            throw
        }
    }

    hidden [void] CollectContacts([string]$server, [string]$domain) {
        Write-ADInventoryLog -Level Info -Message "Collecting contacts" -Context @{ Domain = $domain; Server = $server }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            # Contacts have objectClass=contact and objectCategory=person
            # They do NOT have objectSid - they are not security principals
            $filter = "(objectClass=contact)"
            $contacts = Get-ADObjects `
                -Server $server `
                -SearchBase ("DC=" + ($domain -replace '\.', ',DC=')) `
                -Filter $filter `
                -Config $this.Config

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'Contacts' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount $contacts.Count -Domain $domain

            if ($contacts.Count -gt 0) {
                # Contacts have a synthetic SID (CN:{ObjectGUID}) generated by Get-ADObjects
                # Add to lookup maps - contacts are not security principals but we track them
                foreach ($contact in $contacts) {
                    if ($contact.DistinguishedName -and $contact.SID_String) {
                        # Store synthetic SID in map for membership tracking
                        $this.DNtoSIDMap[$contact.DistinguishedName] = $contact.SID_String
                        $this.SIDtoObjectTypeMap[$contact.SID_String] = 'Contact'
                        $this.SIDtoNameMap[$contact.SID_String] = if ($contact.DisplayName) { $contact.DisplayName } else { $contact.SamAccountName }
                    }
                    elseif ($contact.DistinguishedName) {
                        # Fallback: mark as known contact with null SID
                        $this.DNtoSIDMap[$contact.DistinguishedName] = $null
                    }
                }

                # Batch write to database (contacts stored with ObjectType=4)
                $this.Writer.AddObjectBatch($contacts)
                $this.Statistics.ContactsCollected += $contacts.Count

                Write-ADInventoryLog -Level Info -Message "Contacts collected" `
                    -Context @{ Domain = $domain; ContactCount = $contacts.Count }
            }
        }
        catch {
            if ($stopwatch.IsRunning) { $stopwatch.Stop() }
            Write-ADInventoryLog -Level Warning -Message "Failed to collect contacts" `
                -Context @{ Domain = $domain; Server = $server } `
                -Exception $_.Exception
            # Continue with collection even if contacts fail (non-critical)
        }
    }

    hidden [void] CollectDomainInfo([string]$server, [string]$domain) {
        Write-ADInventoryLog -Level Info -Message "Collecting domain information" -Context @{ Domain = $domain; Server = $server }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $domainInfo = Get-ADDomainInfo -DomainName $domain -Server $server

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'DomainInfo' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount 1 -Domain $domain

            if ($domainInfo) {
                # Collect domain health info (SYSVOL replication, GPO health)
                $healthStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $healthInfo = Get-ADDomainHealthInfo -Server $server -DomainName $domain -Config $this.Config
                $healthStopwatch.Stop()

                Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'DomainHealth' `
                    -DurationSeconds $healthStopwatch.Elapsed.TotalSeconds `
                    -RecordCount 1 -Domain $domain

                # Merge health info into domain info
                if ($healthInfo) {
                    $domainInfo | Add-Member -NotePropertyName 'SysvolReplicationMethod' -NotePropertyValue $healthInfo.SysvolReplicationMethod -Force
                    $domainInfo | Add-Member -NotePropertyName 'SysvolMigrationState' -NotePropertyValue $healthInfo.SysvolMigrationState -Force
                    $domainInfo | Add-Member -NotePropertyName 'DFSRExists' -NotePropertyValue $healthInfo.DFSRExists -Force
                    $domainInfo | Add-Member -NotePropertyName 'FRSExists' -NotePropertyValue $healthInfo.FRSExists -Force
                    $domainInfo | Add-Member -NotePropertyName 'DFSRFlags' -NotePropertyValue $healthInfo.DFSRFlags -Force
                    $domainInfo | Add-Member -NotePropertyName 'GPOTotalCount' -NotePropertyValue $healthInfo.GPOTotalCount -Force
                    $domainInfo | Add-Member -NotePropertyName 'GPOHealthyCount' -NotePropertyValue $healthInfo.GPOHealthyCount -Force
                    $domainInfo | Add-Member -NotePropertyName 'GPOOrphanedGPCCount' -NotePropertyValue $healthInfo.GPOOrphanedGPCCount -Force
                    $domainInfo | Add-Member -NotePropertyName 'GPOOrphanedGPTCount' -NotePropertyValue $healthInfo.GPOOrphanedGPTCount -Force
                    $domainInfo | Add-Member -NotePropertyName 'GPOVersionMismatchCount' -NotePropertyValue $healthInfo.GPOVersionMismatchCount -Force
                    $domainInfo | Add-Member -NotePropertyName 'GPOOverallHealth' -NotePropertyValue $healthInfo.GPOOverallHealth -Force
                    $domainInfo | Add-Member -NotePropertyName 'SYSVOLAccessible' -NotePropertyValue $healthInfo.SYSVOLAccessible -Force
                    $domainInfo | Add-Member -NotePropertyName 'DefaultDomainPolicyExists' -NotePropertyValue $healthInfo.DefaultDomainPolicyExists -Force
                    $domainInfo | Add-Member -NotePropertyName 'DefaultDCPolicyExists' -NotePropertyValue $healthInfo.DefaultDCPolicyExists -Force
                }

                # Write domain info to database (now includes health columns)
                $this.Writer.AddDomainInfo($domainInfo)
                $this.Statistics.DomainInfoCollected++

                Write-ADInventoryLog -Level Info -Message "Domain information collected" `
                    -Context @{
                        Domain = $domain
                        DomainSID = $domainInfo.DomainSID
                        DomainMode = $domainInfo.DomainMode
                        PDCEmulator = $domainInfo.PDCEmulator
                        SysvolMethod = $healthInfo.SysvolReplicationMethod
                        GPOHealth = $healthInfo.GPOOverallHealth
                    }
            }
        }
        catch {
            if ($stopwatch.IsRunning) { $stopwatch.Stop() }
            Write-ADInventoryLog -Level Warning -Message "Failed to collect domain information" `
                -Context @{ Domain = $domain; Server = $server } `
                -Exception $_.Exception
            # Continue with collection even if domain info fails (non-critical)
        }
    }

    hidden [void] CollectForestInfo([string]$server, [string]$domain) {
        # First, get the forest name for this domain
        try {
            $rootDSE = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$server/RootDSE")
            $forestDN = $rootDSE.Properties['rootDomainNamingContext'][0].ToString()
            $rootDSE.Dispose()

            # Convert DN to DNS name
            $forestName = ($forestDN -replace 'DC=', '' -replace ',', '.').TrimStart('.')

            # Check if we've already collected this forest
            if ($this.CollectedForests.Contains($forestName)) {
                Write-ADInventoryLog -Level Debug -Message "Forest already collected, skipping" `
                    -Context @{ ForestName = $forestName; Domain = $domain }
                return
            }

            Write-ADInventoryLog -Level Info -Message "Collecting forest information" -Context @{ ForestName = $forestName; Server = $server }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $forestInfo = Get-ADForestInfo -ForestName $forestName -Server $server

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'ForestInfo' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount 1

            if ($forestInfo) {
                # Write forest info to database
                $this.Writer.AddForestInfo($forestInfo)
                $this.Statistics.ForestInfoCollected++

                # Mark this forest as collected
                [void]$this.CollectedForests.Add($forestName)

                Write-ADInventoryLog -Level Info -Message "Forest information collected" `
                    -Context @{
                        ForestName = $forestName
                        ForestMode = $forestInfo.ForestMode
                        SchemaMaster = $forestInfo.SchemaMaster
                        DomainCount = if ($forestInfo.Domains) { ($forestInfo.Domains | ConvertFrom-Json).Count } else { 0 }
                        SiteCount = if ($forestInfo.Sites) { ($forestInfo.Sites | ConvertFrom-Json).Count } else { 0 }
                    }

                # Collect Sites & Services data for this forest (forest-scoped, collected once per forest)
                $this.CollectSitesAndServices($server, $forestName)

                # Collect Optional Features for this forest (forest-scoped, collected once per forest)
                $this.CollectOptionalFeatures($server, $forestName)

                # Collect ADFS configuration for this forest (forest-scoped, collected once per forest)
                if (-not $this.SkipADFS) {
                    $this.CollectADFSConfiguration($server, $forestName)
                }

                # Collect PKI (AD CS) information for this forest (forest-scoped, collected once per forest)
                if (-not $this.SkipPKI) {
                    $this.CollectPKIInfo($server, $forestName)
                }
            }
        }
        catch {
            Write-ADInventoryLog -Level Warning -Message "Failed to collect forest information" `
                -Context @{ Domain = $domain; Server = $server } `
                -Exception $_.Exception
            # Continue with collection even if forest info fails (non-critical)
        }
    }

    hidden [void] CollectSitesAndServices([string]$server, [string]$forestName) {
        Write-ADInventoryLog -Level Info -Message "Collecting Sites & Services information" `
            -Context @{ ForestName = $forestName; Server = $server }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            # Collect all Sites & Services data
            $sitesAndServicesData = Get-ADSitesAndServicesInfo `
                -Server $server `
                -ForestName $forestName `
                -Config $this.Config

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'SitesAndServices' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount ($sitesAndServicesData.Sites.Count + $sitesAndServicesData.Subnets.Count + $sitesAndServicesData.SiteLinks.Count)

            if ($sitesAndServicesData) {
                # Write to database
                $this.Writer.AddSitesAndServicesBatch($sitesAndServicesData)

                # Update statistics
                $this.Statistics.SitesCollected += $sitesAndServicesData.Sites.Count
                $this.Statistics.SubnetsCollected += $sitesAndServicesData.Subnets.Count
                $this.Statistics.SiteLinksCollected += $sitesAndServicesData.SiteLinks.Count
                $this.Statistics.SiteSettingsCollected += $sitesAndServicesData.SiteSettings.Count
                $this.Statistics.SiteServersCollected += $sitesAndServicesData.SiteServers.Count
                $this.Statistics.SiteDomainControllersCollected += $sitesAndServicesData.DomainControllers.Count

                Write-ADInventoryLog -Level Info -Message "Sites & Services information collected" `
                    -Context @{
                        ForestName = $forestName
                        Sites = $sitesAndServicesData.Sites.Count
                        Subnets = $sitesAndServicesData.Subnets.Count
                        SiteLinks = $sitesAndServicesData.SiteLinks.Count
                        SiteSettings = $sitesAndServicesData.SiteSettings.Count
                        SiteServers = $sitesAndServicesData.SiteServers.Count
                        DomainControllers = $sitesAndServicesData.DomainControllers.Count
                    }
            }
        }
        catch {
            if ($stopwatch.IsRunning) { $stopwatch.Stop() }
            Write-ADInventoryLog -Level Warning -Message "Failed to collect Sites & Services information" `
                -Context @{ ForestName = $forestName; Server = $server } `
                -Exception $_.Exception
            # Continue with collection even if Sites & Services fails (non-critical)
        }
    }

    hidden [void] CollectOptionalFeatures([string]$server, [string]$forestName) {
        Write-ADInventoryLog -Level Info -Message "Collecting Optional Features information" `
            -Context @{ ForestName = $forestName; Server = $server }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            # Collect all Optional Features data
            # NOTE: Wrap in @() to prevent PowerShell from unwrapping single-element arrays
            $features = @(Get-ADOptionalFeatureInfo `
                -Server $server `
                -ForestName $forestName `
                -Config $this.Config)

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'OptionalFeatures' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount $features.Count

            if ($features.Count -gt 0) {
                # Write to database
                $this.Writer.AddOptionalFeaturesBatch($features)

                # Update statistics
                $this.Statistics.OptionalFeaturesCollected += $features.Count

                # Count enabled features (wrap in @() to handle single-element case)
                $enabledFeatures = @($features | Where-Object { $_.IsEnabled -eq $true })
                $enabledCount = $enabledFeatures.Count

                Write-ADInventoryLog -Level Info -Message "Optional Features information collected" `
                    -Context @{
                        ForestName = $forestName
                        TotalFeatures = $features.Count
                        EnabledFeatures = $enabledCount
                    }
            }
            else {
                Write-ADInventoryLog -Level Info -Message "No Optional Features found" `
                    -Context @{ ForestName = $forestName }
            }
        }
        catch {
            if ($stopwatch.IsRunning) { $stopwatch.Stop() }
            Write-ADInventoryLog -Level Warning -Message "Failed to collect Optional Features information" `
                -Context @{ ForestName = $forestName; Server = $server } `
                -Exception $_.Exception
            # Continue with collection even if Optional Features fails (non-critical)
        }
    }

    hidden [void] CollectKMSServices([string]$domain) {
        Write-ADInventoryLog -Level Info -Message "Collecting KMS service records via DNS" `
            -Context @{ DomainName = $domain }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            # Collect KMS SRV records via DNS query
            $kmsRecords = @(Get-KMSServiceRecords `
                -DomainName $domain `
                -Config $this.Config)

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'DNS_Query' -Target 'KMSService' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount $kmsRecords.Count -Domain $domain

            if ($kmsRecords.Count -gt 0) {
                # Write to database
                $this.Writer.AddKMSServicesBatch($kmsRecords)

                # Update statistics
                $this.Statistics.KMSServicesCollected += $kmsRecords.Count

                Write-ADInventoryLog -Level Info -Message "KMS service records collected" `
                    -Context @{
                        DomainName = $domain
                        RecordCount = $kmsRecords.Count
                    }
            }
            else {
                Write-ADInventoryLog -Level Info -Message "No KMS service records found (common for cloud-activated environments)" `
                    -Context @{ DomainName = $domain }
            }
        }
        catch {
            if ($stopwatch.IsRunning) { $stopwatch.Stop() }
            Write-ADInventoryLog -Level Warning -Message "Failed to collect KMS service records" `
                -Context @{ DomainName = $domain } `
                -Exception $_.Exception
            # Continue with collection even if KMS fails (non-critical)
        }
    }

    hidden [void] CollectADFSConfiguration([string]$server, [string]$forestName) {
        Write-ADInventoryLog -Level Info -Message "Collecting ADFS configuration information" `
            -Context @{ ForestName = $forestName; Server = $server }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            # Collect ADFS and DRS configuration from Configuration partition
            $adfsConfigs = @(Get-ADFSConfigurationInfo `
                -Server $server `
                -ForestName $forestName `
                -Config $this.Config)

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'ADFSConfiguration' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount $adfsConfigs.Count

            if ($adfsConfigs.Count -gt 0) {
                # Write to database
                $this.Writer.AddADFSConfigurationBatch($adfsConfigs)

                # Update statistics
                $this.Statistics.ADFSConfigsCollected += $adfsConfigs.Count

                # Count by service type
                $adfsCount = @($adfsConfigs | Where-Object { $_.ServiceType -eq 'ADFS' }).Count
                $drsCount = @($adfsConfigs | Where-Object { $_.ServiceType -eq 'DRS' }).Count

                Write-ADInventoryLog -Level Info -Message "ADFS configuration collected" `
                    -Context @{
                        ForestName = $forestName
                        TotalRecords = $adfsConfigs.Count
                        ADFSRecords = $adfsCount
                        DRSRecords = $drsCount
                    }
            }
            else {
                Write-ADInventoryLog -Level Info -Message "No ADFS configuration found" `
                    -Context @{ ForestName = $forestName }
            }
        }
        catch {
            if ($stopwatch.IsRunning) { $stopwatch.Stop() }
            Write-ADInventoryLog -Level Warning -Message "Failed to collect ADFS configuration" `
                -Context @{ ForestName = $forestName; Server = $server } `
                -Exception $_.Exception
            # Continue with collection even if ADFS fails (non-critical)
        }
    }

    hidden [void] CollectPKIInfo([string]$server, [string]$forestName) {
        Write-ADInventoryLog -Level Info -Message "Collecting AD Certificate Services (PKI) information" `
            -Context @{ ForestName = $forestName; Server = $server }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            # Collect all PKI data (Enterprise CAs, Templates, Trusted Root CAs, NTAuth CAs)
            $pkiData = Get-ADPKIInfo `
                -Server $server `
                -ForestName $forestName `
                -Config $this.Config

            $stopwatch.Stop()

            $totalRecords = 0
            if ($pkiData) {
                $totalRecords = ($pkiData.EnterpriseCAs.Count) + ($pkiData.CertificateTemplates.Count) + `
                                ($pkiData.TrustedRootCAs.Count) + ($pkiData.NTAuthCAs.Count)
            }

            Write-ADExecutionTime -Operation 'LDAP_Query' -Target 'PKIInfo' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount $totalRecords

            if ($pkiData -and $totalRecords -gt 0) {
                # Write to database
                $this.Writer.AddPKIDataBatch($pkiData)

                # Update statistics
                $this.Statistics.EnterpriseCAsCollected += $pkiData.EnterpriseCAs.Count
                $this.Statistics.CertificateTemplatesCollected += $pkiData.CertificateTemplates.Count
                $this.Statistics.TrustedRootCAsCollected += $pkiData.TrustedRootCAs.Count
                $this.Statistics.NTAuthCAsCollected += $pkiData.NTAuthCAs.Count

                Write-ADInventoryLog -Level Info -Message "AD Certificate Services (PKI) information collected" `
                    -Context @{
                        ForestName = $forestName
                        EnterpriseCAs = $pkiData.EnterpriseCAs.Count
                        CertificateTemplates = $pkiData.CertificateTemplates.Count
                        TrustedRootCAs = $pkiData.TrustedRootCAs.Count
                        NTAuthCAs = $pkiData.NTAuthCAs.Count
                    }
            }
            else {
                Write-ADInventoryLog -Level Info -Message "No PKI configuration found" `
                    -Context @{ ForestName = $forestName }
            }
        }
        catch {
            if ($stopwatch.IsRunning) { $stopwatch.Stop() }
            Write-ADInventoryLog -Level Warning -Message "Failed to collect PKI information" `
                -Context @{ ForestName = $forestName; Server = $server } `
                -Exception $_.Exception
            # Continue with collection even if PKI fails (non-critical)
        }
    }

    hidden [void] ProcessGroupMemberships() {
        Write-ADInventoryLog -Level Info -Message "Processing group memberships" `
            -Context @{ PendingMemberships = $this.GroupMembershipDNs.Count }

        if ($this.GroupMembershipDNs.Count -eq 0) {
            Write-ADInventoryLog -Level Info -Message "No group memberships to process"
            return
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $memberships = [System.Collections.ArrayList]::new()
            $uniqueKeys = [System.Collections.Generic.HashSet[string]]::new()
            $duplicateCount = 0

            $onDemandResolutions = 0
            $unresolvedCount = 0

            foreach ($membership in $this.GroupMembershipDNs) {
                try {
                    # Resolve member DN to SID
                    $memberSID = $null
                    if ($this.DNtoSIDMap.ContainsKey($membership.MemberDN)) {
                        $memberSID = $this.DNtoSIDMap[$membership.MemberDN]
                        # Skip contacts - they have synthetic SIDs (CN:*) and are not security principals
                        if ($null -eq $memberSID -or $memberSID.StartsWith('CN:')) {
                            # Contacts cannot be part of security-based membership tracking
                            $unresolvedCount++
                            continue
                        }
                    }
                    else {
                        # Try on-demand resolution for cross-domain members
                        $memberSID = $this.ResolveUnknownMemberDN($membership.MemberDN)
                        if ($memberSID) {
                            $onDemandResolutions++
                        }
                        else {
                            Write-ADInventoryLog -Level Debug -Message "Member DN not found in lookup and could not be resolved" `
                                -Context @{ MemberDN = $membership.MemberDN }
                            $unresolvedCount++
                            continue
                        }
                    }

                    # Create unique key for deduplication (include CollectionID so same membership
                    # in different domains is preserved - e.g., S-1-5-32-544 Administrators exists in each domain)
                    # NOTE: Use $srcCollectionID to avoid PS 5.1 class property parsing issue with $collectionID
                    $srcCollectionID = $membership.CollectionID
                    $uniqueKey = "$($membership.GroupSID)|$memberSID|$srcCollectionID"

                    # Skip if we've already seen this membership
                    if (-not $uniqueKeys.Add($uniqueKey)) {
                        $duplicateCount++
                        Write-ADInventoryLog -Level Debug -Message "Duplicate membership skipped" `
                            -Context @{
                                GroupSID = $membership.GroupSID
                                MemberSID = $memberSID
                                CollectionID = $srcCollectionID
                            }
                        continue
                    }

                    # Create membership record with SID strings and CollectionID from source domain
                    $membershipRecord = [PSCustomObject]@{
                        GroupSID = $membership.GroupSID
                        MemberSID = $memberSID
                        CollectionID = $srcCollectionID
                    }

                    [void]$memberships.Add($membershipRecord)
                }
                catch {
                    Write-ADInventoryLog -Level Warning -Message "Failed to process membership" `
                        -Context @{
                            GroupSID = $membership.GroupSID
                            MemberDN = $membership.MemberDN
                        } `
                        -Exception $_.Exception
                }
            }

            $stopwatch.Stop()
            Write-ADExecutionTime -Operation 'Processing' -Target 'DirectMemberships' `
                -DurationSeconds $stopwatch.Elapsed.TotalSeconds `
                -RecordCount $memberships.Count

            if ($memberships.Count -gt 0) {
                # Write memberships to database
                $this.Writer.AddMembershipBatch($memberships)
                $this.Statistics.DirectMemberships = $memberships.Count

                Write-ADInventoryLog -Level Info -Message "Group memberships processed" `
                    -Context @{
                        ProcessedMemberships = $memberships.Count
                        DuplicatesSkipped = $duplicateCount
                        OnDemandResolutions = $onDemandResolutions
                        UnresolvedMemberships = $unresolvedCount
                    }
            }
        }
        catch {
            if ($stopwatch.IsRunning) { $stopwatch.Stop() }
            Write-ADInventoryLog -Level Error -Message "Failed to process group memberships" `
                -Exception $_.Exception
            throw
        }
    }

    # Parse domain name from a Distinguished Name
    # Example: CN=User,OU=Users,DC=ad,DC=dstsystems,DC=com -> ad.dstsystems.com
    hidden [string] ParseDomainFromDN([string]$distinguishedName) {
        if ([string]::IsNullOrEmpty($distinguishedName)) {
            return $null
        }

        try {
            # Extract DC components and join them
            $dcComponents = [regex]::Matches($distinguishedName, 'DC=([^,]+)', 'IgnoreCase')
            if ($dcComponents.Count -eq 0) {
                return $null
            }

            $domainParts = $dcComponents | ForEach-Object { $_.Groups[1].Value }
            return ($domainParts -join '.')
        }
        catch {
            Write-ADInventoryLog -Level Debug -Message "Failed to parse domain from DN" `
                -Context @{ DN = $distinguishedName } `
                -Exception $_.Exception
            return $null
        }
    }

    # Resolve an unknown member DN to its SID by querying AD directly
    # Used for cross-domain memberships where the member wasn't collected
    hidden [string] ResolveUnknownMemberDN([string]$memberDN) {
        if ([string]::IsNullOrEmpty($memberDN)) {
            return $null
        }

        # Check cache first (in case we've already resolved this DN)
        if ($this.DNtoSIDMap.ContainsKey($memberDN)) {
            return $this.DNtoSIDMap[$memberDN]
        }

        try {
            # Parse domain from the DN
            $targetDomain = $this.ParseDomainFromDN($memberDN)
            if ([string]::IsNullOrEmpty($targetDomain)) {
                Write-ADInventoryLog -Level Debug -Message "Could not parse domain from member DN" `
                    -Context @{ MemberDN = $memberDN }
                return $null
            }

            Write-ADInventoryLog -Level Debug -Message "Attempting on-demand resolution for cross-domain member" `
                -Context @{ MemberDN = $memberDN; TargetDomain = $targetDomain }

            # Query AD for the object using its DN
            # Use DirectoryEntry to get the objectSid attribute
            $ldapPath = "LDAP://$targetDomain/$memberDN"
            $directoryEntry = $null

            try {
                $directoryEntry = [System.DirectoryServices.DirectoryEntry]::new($ldapPath)

                # Force property load
                $null = $directoryEntry.RefreshCache(@('objectSid'))

                $sidBytes = $directoryEntry.Properties['objectSid'].Value
                if ($null -ne $sidBytes) {
                    $sid = [System.Security.Principal.SecurityIdentifier]::new($sidBytes, 0)
                    $sidString = $sid.Value

                    # Cache the result for future lookups
                    $this.DNtoSIDMap[$memberDN] = $sidString

                    Write-ADInventoryLog -Level Debug -Message "Successfully resolved cross-domain member" `
                        -Context @{
                            MemberDN = $memberDN
                            SID = $sidString
                            TargetDomain = $targetDomain
                        }

                    return $sidString
                }
            }
            finally {
                if ($null -ne $directoryEntry) {
                    $directoryEntry.Dispose()
                }
            }

            return $null
        }
        catch {
            Write-ADInventoryLog -Level Debug -Message "Failed to resolve cross-domain member DN" `
                -Context @{ MemberDN = $memberDN } `
                -Exception $_.Exception
            return $null
        }
    }

    # Export collected data for parallel runspace aggregation
    # Returns a hashtable with all lookup maps and membership data
    # Used when running in parallel mode to merge data back to main session
    [hashtable] ExportCollectedData() {
        return @{
            DNtoSIDMap = @{} + $this.DNtoSIDMap  # Clone as hashtable
            SIDtoObjectTypeMap = @{} + $this.SIDtoObjectTypeMap
            SIDtoNameMap = @{} + $this.SIDtoNameMap
            GroupMembershipDNs = @($this.GroupMembershipDNs)  # Clone as array
        }
    }

    # Merge collected data from a parallel runspace into this session
    # Used to aggregate lookup maps after parallel domain collection
    [void] MergeCollectedData([hashtable]$data) {
        if ($null -eq $data) {
            return
        }

        # Merge DNtoSIDMap
        if ($data.DNtoSIDMap) {
            foreach ($key in $data.DNtoSIDMap.Keys) {
                if (-not $this.DNtoSIDMap.ContainsKey($key)) {
                    $this.DNtoSIDMap[$key] = $data.DNtoSIDMap[$key]
                }
            }
        }

        # Merge SIDtoObjectTypeMap
        if ($data.SIDtoObjectTypeMap) {
            foreach ($key in $data.SIDtoObjectTypeMap.Keys) {
                if (-not $this.SIDtoObjectTypeMap.ContainsKey($key)) {
                    $this.SIDtoObjectTypeMap[$key] = $data.SIDtoObjectTypeMap[$key]
                }
            }
        }

        # Merge SIDtoNameMap
        if ($data.SIDtoNameMap) {
            foreach ($key in $data.SIDtoNameMap.Keys) {
                if (-not $this.SIDtoNameMap.ContainsKey($key)) {
                    $this.SIDtoNameMap[$key] = $data.SIDtoNameMap[$key]
                }
            }
        }

        # Merge GroupMembershipDNs
        if ($data.GroupMembershipDNs) {
            foreach ($membership in $data.GroupMembershipDNs) {
                [void]$this.GroupMembershipDNs.Add($membership)
            }
        }
    }

    # Validation helper
    hidden [void] EnsureInitialized() {
        if ($this.IsDisposed) {
            throw "Session has been disposed"
        }

        if (-not $this.IsInitialized) {
            throw "Session has not been initialized. Call Initialize() first."
        }
    }

    # Get session summary
    [hashtable] GetSummary() {
        $duration = if ($this.EndTime) {
            ($this.EndTime - $this.StartTime).TotalSeconds
        } else {
            ((Get-Date) - $this.StartTime).TotalSeconds
        }

        return @{
            InventoryID = $this.InventoryID.ToString()
            CollectionID = $this.CollectionID
            DatabasePath = if ($this.Writer) { $this.Writer.DbPath } else { $null }
            LogFilePath = $Script:ADInventoryLogFilePath
            DomainsProcessed = $this.Statistics.DomainsProcessed
            DomainsSkipped = $this.Statistics.DomainsSkipped
            SkippedDomains = @($this.SkippedDomains)
            UsersCollected = $this.Statistics.UsersCollected
            GroupsCollected = $this.Statistics.GroupsCollected
            ComputersCollected = $this.Statistics.ComputersCollected
            ContactsCollected = $this.Statistics.ContactsCollected
            TotalObjects = $this.Statistics.UsersCollected + $this.Statistics.GroupsCollected + $this.Statistics.ComputersCollected + $this.Statistics.ContactsCollected
            FSPsCollected = $this.Statistics.FSPsCollected
            TrustsCollected = $this.Statistics.TrustsCollected
            DomainInfoCollected = $this.Statistics.DomainInfoCollected
            ForestInfoCollected = $this.Statistics.ForestInfoCollected
            DirectMemberships = $this.Statistics.DirectMemberships
            RecursiveMemberships = $this.Statistics.RecursiveMemberships
            # Sites & Services statistics
            SitesCollected = $this.Statistics.SitesCollected
            SubnetsCollected = $this.Statistics.SubnetsCollected
            SiteLinksCollected = $this.Statistics.SiteLinksCollected
            SiteSettingsCollected = $this.Statistics.SiteSettingsCollected
            SiteServersCollected = $this.Statistics.SiteServersCollected
            SiteDomainControllersCollected = $this.Statistics.SiteDomainControllersCollected
            # Optional Features statistics
            OptionalFeaturesCollected = $this.Statistics.OptionalFeaturesCollected
            # KMS, ADFS, and PKI statistics
            KMSServicesCollected = $this.Statistics.KMSServicesCollected
            ADFSConfigsCollected = $this.Statistics.ADFSConfigsCollected
            EnterpriseCAsCollected = $this.Statistics.EnterpriseCAsCollected
            CertificateTemplatesCollected = $this.Statistics.CertificateTemplatesCollected
            TrustedRootCAsCollected = $this.Statistics.TrustedRootCAsCollected
            NTAuthCAsCollected = $this.Statistics.NTAuthCAsCollected
            DurationSeconds = [Math]::Round($duration, 2)
        }
    }

    # IDisposable implementation
    [void] Dispose() {
        if ($this.IsDisposed) {
            return
        }

        Write-ADInventoryLog -Level Debug -Message "Disposing ADInventorySession" `
            -Category Completion `
            -Context @{ InventoryID = $this.InventoryID.ToString() }

        try {
            # Write final completion log
            if ($this.IsInitialized) {
                $summary = $this.GetSummary()
                Write-ADInventoryLog -Level Info -Message "Inventory collection completed - Final statistics" `
                    -Category Completion `
                    -Context $summary
            }

            if ($this.Writer) {
                try {
                    $this.Writer.Dispose()
                }
                catch {
                    Write-ADInventoryLog -Level Warning -Message "Error disposing writer" `
                        -Category Completion `
                        -Exception $_.Exception
                }
                finally {
                    $this.Writer = $null
                }
            }

            # Clear collections to free memory
            $this.DNtoSIDMap.Clear()
            $this.SIDtoObjectTypeMap.Clear()
            $this.SIDtoNameMap.Clear()
            $this.GroupMembershipDNs.Clear()
            $this.AllFSPs.Clear()
            $this.AllTrusts.Clear()
            $this.CollectedForests.Clear()

            # Clear module-scoped logging variables
            $Script:ADInventoryLogFilePath = $null
            $Script:ADInventoryLogConnection = $null
            Set-ADInventoryCollectionID -CollectionID $null

            $this.IsDisposed = $true

            Write-ADInventoryLog -Level Verbose -Message "ADInventorySession disposed" `
                -Category Completion `
                -Context @{
                    InventoryID = $this.InventoryID.ToString()
                    Duration = if ($this.EndTime) { ($this.EndTime - $this.StartTime).TotalSeconds } else { 0 }
                }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Error in Dispose method" `
                -Category Completion `
                -Exception $_.Exception
        }
        finally {
            # Force garbage collection to release memory from large collections
            # This runs regardless of how the collection exits (success, error, or cancellation)
            $gcStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            [System.GC]::Collect()

            $gcStopwatch.Stop()
            Write-ADExecutionTime -Operation 'GC_Collect' -Target 'Memory' `
                -DurationSeconds $gcStopwatch.Elapsed.TotalSeconds

            Write-ADInventoryLog -Level Debug -Message "Garbage collection completed" `
                -Category Completion
        }
    }
}
