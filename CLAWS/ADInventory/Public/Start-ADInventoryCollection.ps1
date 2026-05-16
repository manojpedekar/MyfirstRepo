function Start-ADInventoryCollection {
    <#
    .SYNOPSIS
        Main entry point for AD inventory collection

    .DESCRIPTION
        Collects Active Directory inventory from one or more domains and exports
        to SQLite database. This is the main public function that users interact with.

        REPLACES original script Get-SSNCADInventory.ps1 with improved:
        - Proper resource management (IDisposable pattern)
        - Transaction safety with automatic rollback
        - Better error handling and logging
        - Configurable timeouts
        - Progress reporting
        - Statistics tracking

    .PARAMETER CurrentDomain
        Collect inventory from current computer's domain only

    .PARAMETER WalkTrust
        Collect inventory from current domain and all trusted domains (inbound/bidirectional).
        Can be combined with -Domains to walk trusts starting from a specified remote domain
        instead of the computer's current domain.

    .PARAMETER Domains
        Explicit array of domain names to collect from.
        When combined with -WalkTrust, trusts will be enumerated from each specified domain
        and all trusted domains (inbound/bidirectional) will be included in the collection.

    .PARAMETER OutputPath
        Directory where SQLite database will be created (default: current directory)

    .PARAMETER ObjectTypes
        Which object types to collect: Users, Groups, Computers, Contacts, All (default: All)
        Note: Contacts are mail-enabled objects without SIDs (not security principals)

    .PARAMETER PageSize
        LDAP query page size (default: 1000, range: 100-5000)

    .PARAMETER Credential
        Optional PSCredential for authentication

    .PARAMETER EnableVerboseLogging
        Enable verbose logging output

    .PARAMETER EnableParallel
        Enable parallel domain processing using runspaces (recommended for 3+ domains)

    .PARAMETER ParallelThrottleLimit
        Maximum number of concurrent domain collections (default: 4, range: 1-32)
        Only used when -EnableParallel is specified

    .PARAMETER EnableResume
        Enable checkpoint-based resume capability for interrupted collections

    .PARAMETER ResolveForeignSecurityPrincipals
        Attempt to resolve Foreign Security Principals to their source domain objects
        Requires connectivity to trusted domains

    .PARAMETER SkipKMS
        Skip KMS (Key Management Service) discovery via DNS SRV queries.
        By default, KMS servers are discovered from _vlmcs._tcp.{domain} DNS records.

    .PARAMETER SkipADFS
        Skip AD FS (Active Directory Federation Services) and Device Registration Service
        configuration collection from the Configuration partition.

    .PARAMETER SkipPKI
        Skip AD Certificate Services (PKI) collection including Enterprise CAs,
        Certificate Templates, Trusted Root CAs, and NTAuth certificates.

    .OUTPUTS
        PSCustomObject with summary:
        - InventoryID: Unique GUID for this collection
        - DatabasePath: Path to created SQLite database
        - DomainsProcessed: Number of domains processed
        - TotalObjects: Total AD objects collected
        - DurationSeconds: Time taken
        - Statistics: Detailed counts

    .EXAMPLE
        Start-ADInventoryCollection -CurrentDomain -OutputPath "C:\ADInventory"
        Collects inventory from current domain

    .EXAMPLE
        Start-ADInventoryCollection -WalkTrust -ObjectTypes Users,Groups
        Collects only users and groups from current domain and trusted domains

    .EXAMPLE
        $cred = Get-Credential
        Start-ADInventoryCollection -Domains "contoso.com","fabrikam.com" -Credential $cred -OutputPath "C:\Inventory"
        Collects from specific domains with credentials

    .EXAMPLE
        Start-ADInventoryCollection -WalkTrust -EnableParallel -ParallelThrottleLimit 6 -EnableResume
        Collects from current domain and trusts using parallel processing with resume capability

    .EXAMPLE
        Start-ADInventoryCollection -Domains "contoso.com","fabrikam.com" -ResolveForeignSecurityPrincipals
        Collects inventory and resolves Foreign Security Principals to their source objects

    .EXAMPLE
        Start-ADInventoryCollection -Domains "admgmt.ssncad.global" -WalkTrust -OutputPath "C:\temp\Inventory"
        Collects from the specified remote domain AND all its trusted domains (inbound/bidirectional).
        Useful when running from a computer in a different domain than the one being scanned.

    .NOTES
        Part of SSNC.ADInventory module

        Requirements:
        - PowerShell 5.1+
        - PSSQLite module
        - Domain-joined computer or explicit credentials
        - Network access to domain controllers (LDAPS port 636 or LDAP port 389)

        Performance:
        - Typical speed: 10,000-50,000 objects/minute
        - Memory usage: ~500MB-2GB depending on domain size
        - Database size: ~1KB per object

        Output Database:
        - Format: SQLite 3.x
        - Schema version: 2.1.0
        - Tables: AD_Object, AD_GroupMembership, AD_ForeignSecurityPrincipal, AD_Trust, AD_Domain, AD_Forest
    #>
    [CmdletBinding(DefaultParameterSetName = 'CurrentDomain', SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'CurrentDomain', Mandatory = $true)]
        [switch]$CurrentDomain,

        [Parameter(ParameterSetName = 'WalkTrust', Mandatory = $true)]
        [Parameter(ParameterSetName = 'Domains')]
        [switch]$WalkTrust,

        [Parameter(ParameterSetName = 'Domains', Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Domains,

        [Parameter(Mandatory = $false)]
        [ValidateScript({
            if (Test-Path $_ -PathType Container) {
                $true
            } else {
                throw "Output path does not exist or is not a directory: $_"
            }
        })]
        [string]$OutputPath = (Get-Location).Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Users', 'Groups', 'Computers', 'Contacts', 'All')]
        [string[]]$ObjectTypes = @('All'),

        [Parameter(Mandatory = $false)]
        [ValidateRange(100, 5000)]
        [int]$PageSize = 1000,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [switch]$EnableVerboseLogging,

        [Parameter(Mandatory = $false)]
        [switch]$EnableParallel,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 32)]
        [int]$ParallelThrottleLimit = 4,

        [Parameter(Mandatory = $false)]
        [switch]$EnableResume,

        [Parameter(Mandatory = $false)]
        [switch]$ResolveForeignSecurityPrincipals,

        [Parameter(Mandatory = $false)]
        [switch]$SkipKMS,

        [Parameter(Mandatory = $false)]
        [switch]$SkipADFS,

        [Parameter(Mandatory = $false)]
        [switch]$SkipPKI
    )

    begin {
        # Set error handling
        $ErrorActionPreference = 'Stop'

        # Enable verbose if requested
        if ($EnableVerboseLogging) {
            $VerbosePreference = 'Continue'
        }

        Write-ADInventoryLog -Level Info -Message "Starting AD inventory collection" `
            -Context @{
                ParameterSet = $PSCmdlet.ParameterSetName
                ObjectTypes = ($ObjectTypes -join ', ')
                OutputPath = $OutputPath
            }
    }

    process {
        try {
            # Determine target domains
            Write-Host "`nResolving target domains..." -ForegroundColor Cyan

            $domainList = switch ($PSCmdlet.ParameterSetName) {
                'CurrentDomain' {
                    Get-TargetDomainList -CurrentDomain
                }
                'WalkTrust' {
                    Get-TargetDomainList -WalkTrust
                }
                'Domains' {
                    if ($WalkTrust) {
                        # Walk trusts starting from the specified domain(s)
                        Get-TargetDomainList -Domains $Domains -WalkTrust
                    }
                    else {
                        Get-TargetDomainList -Domains $Domains
                    }
                }
            }

            Write-Host "Domains to process: $($domainList -join ', ')" -ForegroundColor Green
            Write-Host ""

            # Create configuration
            $config = [ADQueryConfig]::new()
            $config.PageSize = $PageSize
            $config.Credential = $Credential

            if ($EnableVerboseLogging) {
                $config.EnableVerboseLogging = $true
            }

            # Validate configuration
            $config.Validate()

            # Confirm action if -WhatIf or -Confirm
            if ($PSCmdlet.ShouldProcess(
                "Collect inventory from $($domainList.Count) domain(s) to $OutputPath",
                "Collect AD Inventory",
                "AD Inventory Collection"
            )) {
                # Create and execute session
                $session = [ADInventorySession]::new($domainList, $OutputPath, $config)
                $session.ObjectTypes = $ObjectTypes

                # Configure advanced features
                $session.EnableParallel = $EnableParallel.IsPresent
                $session.ParallelThrottleLimit = $ParallelThrottleLimit
                $session.EnableResume = $EnableResume.IsPresent
                $session.ResolveForeignSecurityPrincipals = $ResolveForeignSecurityPrincipals.IsPresent

                # Configure skip flags for optional collections
                $session.SkipKMS = $SkipKMS.IsPresent
                $session.SkipADFS = $SkipADFS.IsPresent
                $session.SkipPKI = $SkipPKI.IsPresent

                try {
                    # Initialize database
                    Write-Host "Initializing database..." -ForegroundColor Cyan
                    $session.Initialize()
                    Write-Host "  Database: $($session.Writer.DbPath)" -ForegroundColor Gray
                    Write-Host ""

                    # Collect inventory
                    Write-Host "Collecting inventory..." -ForegroundColor Cyan
                    $session.CollectInventory()

                    # Get summary
                    $summary = $session.GetSummary()

                    # Display results
                    Write-Host ""
                    Write-Host "================================" -ForegroundColor Green
                    Write-Host "Collection Complete!" -ForegroundColor Green
                    Write-Host "================================" -ForegroundColor Green
                    Write-Host "Inventory ID:       $($summary.InventoryID)" -ForegroundColor Gray
                    Write-Host "Database:           $($summary.DatabasePath)" -ForegroundColor Gray
                    Write-Host "Log File:           $($summary.LogFilePath)" -ForegroundColor Gray
                    Write-Host "Duration:           $($summary.DurationSeconds) seconds" -ForegroundColor Gray
                    Write-Host ""
                    Write-Host "Summary:" -ForegroundColor Cyan
                    Write-Host "  Domains Processed:      $($summary.DomainsProcessed)" -ForegroundColor Gray
                    if ($summary.DomainsSkipped -gt 0) {
                        Write-Host "  Domains Skipped:        $($summary.DomainsSkipped)" -ForegroundColor Yellow
                    }
                    Write-Host "  Total Objects:          $($summary.TotalObjects)" -ForegroundColor Gray
                    Write-Host "    Users:                $($summary.UsersCollected)" -ForegroundColor Gray
                    Write-Host "    Groups:               $($summary.GroupsCollected)" -ForegroundColor Gray
                    Write-Host "    Computers:            $($summary.ComputersCollected)" -ForegroundColor Gray
                    Write-Host "    Contacts:             $($summary.ContactsCollected)" -ForegroundColor Gray
                    Write-Host "  Foreign Security Principals: $($summary.FSPsCollected)" -ForegroundColor Gray
                    Write-Host "  Trust Relationships:    $($summary.TrustsCollected)" -ForegroundColor Gray
                    Write-Host "  Domain Info Records:    $($summary.DomainInfoCollected)" -ForegroundColor Gray
                    Write-Host "  Forest Info Records:    $($summary.ForestInfoCollected)" -ForegroundColor Gray
                    Write-Host "  Direct Memberships:     $($summary.DirectMemberships)" -ForegroundColor Gray
                    Write-Host "  Recursive Memberships:  $($summary.RecursiveMemberships)" -ForegroundColor Gray
                    # KMS, ADFS, and PKI statistics
                    if ($summary.KMSServicesCollected -gt 0 -or $summary.ADFSConfigsCollected -gt 0 -or
                        $summary.EnterpriseCAsCollected -gt 0 -or $summary.CertificateTemplatesCollected -gt 0) {
                        Write-Host ""
                        Write-Host "  Infrastructure Services:" -ForegroundColor Cyan
                        if ($summary.KMSServicesCollected -gt 0) {
                            Write-Host "    KMS Servers:          $($summary.KMSServicesCollected)" -ForegroundColor Gray
                        }
                        if ($summary.ADFSConfigsCollected -gt 0) {
                            Write-Host "    ADFS Configurations:  $($summary.ADFSConfigsCollected)" -ForegroundColor Gray
                        }
                        if ($summary.EnterpriseCAsCollected -gt 0) {
                            Write-Host "    Enterprise CAs:       $($summary.EnterpriseCAsCollected)" -ForegroundColor Gray
                        }
                        if ($summary.CertificateTemplatesCollected -gt 0) {
                            Write-Host "    Cert Templates:       $($summary.CertificateTemplatesCollected)" -ForegroundColor Gray
                        }
                        if ($summary.TrustedRootCAsCollected -gt 0) {
                            Write-Host "    Trusted Root CAs:     $($summary.TrustedRootCAsCollected)" -ForegroundColor Gray
                        }
                        if ($summary.NTAuthCAsCollected -gt 0) {
                            Write-Host "    NTAuth CAs:           $($summary.NTAuthCAsCollected)" -ForegroundColor Gray
                        }
                    }
                    Write-Host ""

                    # Display skipped domains if any
                    if ($summary.SkippedDomains -and $summary.SkippedDomains.Count -gt 0) {
                        Write-Host "Skipped Domains (Unreachable):" -ForegroundColor Yellow
                        foreach ($skipped in $summary.SkippedDomains) {
                            Write-Host "  - $($skipped.Domain)" -ForegroundColor Yellow
                            Write-Host "      Reason: $($skipped.Reason)" -ForegroundColor DarkYellow
                        }
                        Write-Host ""
                        Write-Host "Note: These domains may have been retired with stale trust relationships." -ForegroundColor DarkYellow
                        Write-Host "      Consider cleaning up these trust relationships in Active Directory." -ForegroundColor DarkYellow
                        Write-Host ""
                    }

                    Write-Host "Output Files:" -ForegroundColor Cyan
                    Write-Host "  Database: $($summary.DatabasePath)" -ForegroundColor Gray
                    Write-Host "  Log File: $($summary.LogFilePath)" -ForegroundColor Gray
                    Write-Host ""
                    Write-Host "Next Steps:" -ForegroundColor Cyan
                    Write-Host "  1. Review the SQLite database and log file" -ForegroundColor Gray
                    Write-Host "  2. Import into SQL Server or analyze locally" -ForegroundColor Gray
                    Write-Host "  3. Query AD_Log table for detailed execution history" -ForegroundColor Gray
                    Write-Host ""

                    # Return summary object
                    return [PSCustomObject]$summary
                }
                finally {
                    # Ensure session is disposed
                    if ($session) {
                        $session.Dispose()
                    }
                }
            }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "AD inventory collection failed" `
                -Exception $_.Exception

            Write-Host ""
            Write-Host "================================" -ForegroundColor Red
            Write-Host "Collection Failed" -ForegroundColor Red
            Write-Host "================================" -ForegroundColor Red
            Write-Host "Error: $_" -ForegroundColor Red
            Write-Host ""
            Write-Host "Press Enter to exit..." -ForegroundColor Yellow
            Read-Host

            throw
        }
    }
}
