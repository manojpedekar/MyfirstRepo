@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'SSNC.ADInventory.psm1'

    # Version number of this module.
    ModuleVersion = '1.10.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID = 'a8f3c5d1-4e2b-4a1c-9d7f-3b5e8a6c2f1d'

    # Author of this module
    Author = 'SSNC'

    # Company or vendor of this module
    CompanyName = 'SSNC'

    # Copyright statement for this module
    Copyright = '(c) SSNC. All rights reserved.'

    # Description of the functionality provided by this module
    Description = @'
Active Directory Inventory Collection Module

Collects comprehensive Active Directory inventory from one or more domains and exports to SQLite database.

Collection Features:
- Resource leak prevention with IDisposable pattern
- Transaction safety with automatic rollback
- LDAP injection prevention
- Large multi-valued attribute support (>1500 values)
- Foreign Security Principal resolution
- Parallel domain processing with runspaces
- Resume capability with checkpoints
- Comprehensive error handling and logging
- Globally unique CollectionID (GUID) for aggregate database support

Ideal for AD auditing, migration planning, security analysis, and compliance reporting.
'@

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Name of the PowerShell host required by this module
    # PowerShellHostName = ''

    # Minimum version of the PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    DotNetFrameworkVersion = '4.7.2'

    # Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # ClrVersion = ''

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    # NOTE: PSSQLite is loaded dynamically by the module with fallback to local copy in ExternalModules
    # This allows the module to work in restricted environments where module installation is not permitted
    # RequiredModules = @(
    #     @{
    #         ModuleName = 'PSSQLite'
    #         ModuleVersion = '1.0.0'
    #     }
    # )
    RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Start-ADInventoryCollection',
        'Test-ADDomainConnectivity'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    FileList = @(
        'SSNC.ADInventory.psd1',
        'SSNC.ADInventory.psm1',
        'README.md',
        # Classes - SQLite collection
        'Classes\ADInventorySession.ps1',
        'Classes\ADQueryConfig.ps1',
        'Classes\SQLiteInventoryWriter.ps1',
        # Private functions
        'Private\Connection\Get-OptimalDomainController.ps1',
        'Private\Connection\New-ADConnection.ps1',
        'Private\Connection\Test-ADConnectivity.ps1',
        'Private\LDAP\ConvertTo-SafeLdapFilter.ps1',
        'Private\LDAP\Get-ADObjectBatch.ps1',
        'Private\LDAP\Get-ADObjects.ps1',
        'Private\LDAP\Get-ForeignSecurityPrincipal.ps1',
        'Private\LDAP\Get-LargeMultiValuedAttribute.ps1',
        'Private\LDAP\New-DirectorySearcher.ps1',
        'Private\SQLite\Add-SQLiteBatch.ps1',
        'Private\SQLite\Initialize-ADInventorySchema.ps1',
        'Private\SQLite\Invoke-SQLiteTransaction.ps1',
        'Private\Transform\ConvertTo-DateTimeFromFileTime.ps1',
        'Private\Transform\ConvertTo-GuidString.ps1',
        'Private\Transform\ConvertTo-SidBytes.ps1',
        'Private\Transform\ConvertTo-SidString.ps1',
        'Private\Utility\Checkpoint-ADInventory.ps1',
        'Private\Utility\Get-ADDomainInfo.ps1',
        'Private\Utility\Get-ADDomainTrust.ps1',
        'Private\Utility\Get-ADForestInfo.ps1',
        'Private\Utility\Get-ADPropertyMultiValue.ps1',
        'Private\Utility\Get-ADPropertyValue.ps1',
        'Private\Utility\Get-TargetDomainList.ps1',
        'Private\Utility\Invoke-ParallelDomainCollection.ps1',
        'Private\Utility\Write-ADInventoryLog.ps1',
        'Private\Utility\Write-ADExecutionTime.ps1',
        # Sites & Services functions
        'Private\SitesAndServices\Get-ADSitesAndServicesInfo.ps1',
        # Domain Health functions
        'Private\DomainHealth\Get-ADDomainHealthInfo.ps1',
        'Private\DomainHealth\Get-ADOptionalFeatureInfo.ps1',
        # KMS Service Discovery functions
        'Private\KMS\Get-KMSServiceRecords.ps1',
        # ADFS Configuration functions
        'Private\ADFS\Get-ADFSConfigurationInfo.ps1',
        # PKI (AD Certificate Services) functions
        'Private\PKI\Get-ADPKIInfo.ps1',
        # Public functions
        'Public\Start-ADInventoryCollection.ps1',
        'Public\Test-ADDomainConnectivity.ps1',
        # Resources - SQLite schema
        'Resources\Schema\ADInventory.sql',
        # Tests
        'Tests\README.md',
        'Tests\Unit\ADAdvancedFeatures.Tests.ps1',
        'Tests\Unit\ADConfiguration.Tests.ps1',
        'Tests\Unit\SQLite.Tests.ps1',
        'Tests\Unit\Transform.Tests.ps1',
        # External modules
        'ExternalModules\PSSQLite\1.1.0\PSSQLite.psd1',
        'ExternalModules\PSSQLite\1.1.0\PSSQLite.psm1',
        'ExternalModules\PSSQLite\1.1.0\Invoke-SqliteQuery.ps1',
        'ExternalModules\PSSQLite\1.1.0\Invoke-SqliteBulkCopy.ps1',
        'ExternalModules\PSSQLite\1.1.0\New-SqliteConnection.ps1',
        'ExternalModules\PSSQLite\1.1.0\Out-DataTable.ps1',
        'ExternalModules\PSSQLite\1.1.0\Update-Sqlite.ps1'
    )

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @(
                'ActiveDirectory',
                'AD',
                'Inventory',
                'Audit',
                'SQLite',
                'LDAP',
                'DirectoryServices',
                'Security',
                'Compliance',
                'Migration',
                'Enterprise',
                'SSNC'
            )

            # A URL to the license for this module.
            # LicenseUri = ''

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/pdemers/CollectNTFSPerms'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
# Version 1.10.0 (2026-01-19)

## Infrastructure Services Collection

Added collection of KMS, AD FS, and AD Certificate Services (PKI) configuration data.

### New Features

- **KMS Service Discovery**: Queries DNS for `_vlmcs._tcp.{domain}` SRV records to discover KMS activation servers
- **AD FS Configuration**: Collects AD FS Service Connection Points and Device Registration Service configuration from Configuration partition
- **AD Certificate Services (PKI)**: Collects Enterprise CAs, Certificate Templates, Trusted Root CAs, and NTAuth certificates

### New Parameters

- `-SkipKMS`: Skip KMS service discovery
- `-SkipADFS`: Skip AD FS and DRS configuration collection
- `-SkipPKI`: Skip AD Certificate Services collection

### New Tables

- **AD_KMSService**: KMS server records from DNS (domain-scoped)
- **AD_ADFSConfiguration**: AD FS and Device Registration Service configuration (forest-scoped)
- **AD_EnterpriseCA**: Enterprise Certification Authorities (forest-scoped)
- **AD_CertificateTemplate**: Certificate templates with enrollment flags and key usage (forest-scoped)
- **AD_TrustedRootCA**: Trusted Root CAs from CertificationAuthorities, AIA, and CDP containers (forest-scoped)
- **AD_NTAuthCA**: NTAuth certificates for smart card authentication (forest-scoped)

### Database Changes

- Schema version upgraded to 3.4.0
- Added 6 new SQLite tables with indexes
- Added compatibility views for all new tables

### Technical Notes

- KMS collection is domain-scoped (collected per domain via DNS)
- ADFS and PKI collection is forest-scoped (collected once per forest)
- All new collections fail gracefully if data doesn't exist
- Certificate binary data stored as Base64 for portability
- Uses raw LDAP/ADSI and DNS queries (no AD PowerShell module dependency)

---

# Version 1.9.1 (2026-01-10)

## Bug Fix

- **AD_Forest WhenCreated Fix**: Fixed empty WhenCreated column in AD_Forest table by querying the Configuration partition instead of the Partitions container. The Configuration partition's whenCreated reliably reflects the forest creation date.

---

# Version 1.9.0 (2026-01-08)

## Domain Health Collection

Added comprehensive domain health data collection including SYSVOL replication method detection and GPO store health assessment.

### New Features

- **SYSVOL Replication Method**: Detects FRS vs DFSR and migration state (Start, Prepared, Redirected, Eliminated, Native)
- **GPO Store Health**: Validates GPC/GPT synchronization, detects orphaned objects and version mismatches
- **AD Optional Features**: Collects forest-scoped optional features (Recycle Bin, PAM) with enabled status

### New Columns on AD_Domain

- SysvolReplicationMethod, SysvolMigrationState, DFSRExists, FRSExists, DFSRFlags
- GPOTotalCount, GPOHealthyCount, GPOOrphanedGPCCount, GPOOrphanedGPTCount, GPOVersionMismatchCount
- GPOOverallHealth, SYSVOLAccessible, DefaultDomainPolicyExists, DefaultDCPolicyExists

### New Table: AD_OptionalFeature

Forest-scoped table storing optional features with:
- FeatureName, FeatureGUID, IsEnabled
- RequiredForestLevel, RequiredForestLevelName, RequiredDomainLevel
- Description, DistinguishedName

### Database Changes

- Schema version upgraded to 3.3.0
- Added 14 new columns to AD_Domain table
- Added AD_OptionalFeature table with indexes

### Technical Notes

- Domain health data collected during domain info phase
- Optional features collected during forest info phase (once per forest)
- Uses raw LDAP/ADSI queries (no AD PowerShell module dependency)
- Non-critical: failures won't interrupt object collection

---

# Version 1.8.0 (2026-01-08)

## Sites & Services Collection

Added comprehensive collection of AD Sites and Services configuration data.

### New Features

- **AD Sites Collection**: Collects all AD sites with description, location, and metadata
- **AD Subnets Collection**: Collects IP subnets and their site assignments
- **AD Site Links Collection**: Collects inter-site replication links with cost, interval, and options
- **AD Site Settings Collection**: Collects NTDS Site Settings including ISTG and site options
- **AD Site Servers Collection**: Collects server objects in each site
- **AD Domain Controllers Collection**: Collects NTDSDSA objects with GC, RODC, and replication flags
- **Junction Tables**: Normalized site-subnet and site link-site relationships

### Database Changes

- Schema version upgraded to 3.2.0
- Added 8 new SQLite tables: AD_Site, AD_Subnet, AD_SiteLink, AD_SiteSettings, AD_SiteServer, AD_DomainController, AD_SiteSubnet, AD_SiteLinkSite
- Added indexes for efficient querying

### Technical Notes

- Sites & Services data is forest-scoped and collected once per forest
- Collection happens during the forest info collection phase
- Uses raw LDAP/ADSI queries (no AD PowerShell module dependency)
- Non-critical: failures won't interrupt domain object collection

---

# Version 1.0.0 (2025-12-01)

## Initial Release - Complete Refactoring

This is the first release of the refactored SSNC.ADInventory module, replacing the monolithic Get-SSNCADInventory.ps1 script.

### New Features

- **Parallel Domain Processing**: Process multiple domains concurrently using PowerShell runspaces (up to 32 concurrent)
- **Resume Capability**: Checkpoint-based recovery for interrupted long-running collections
- **FSP Resolution**: Resolve Foreign Security Principals to their actual objects in trusted domains
- **Large Group Support**: Automatic range retrieval for groups with >1500 members
- **LDAP Injection Prevention**: Input validation and escaping for all LDAP filters
- **Transaction Safety**: Automatic rollback on database errors
- **Resource Leak Prevention**: IDisposable pattern throughout with try/finally blocks

### Architecture Improvements

- Session-based orchestration with ADInventorySession class
- Centralized configuration with ADQueryConfig class
- Database lifecycle management with SQLiteInventoryWriter class
- Dependency injection for testability
- Externalized schema to ADInventory.sql
- Comprehensive unit test coverage (100+ tests)

### Critical Fixes

- Connection leak fixes (original script lines 512, 331-333, 1647)
- Missing transaction rollback (original script lines 827-866)
- Multi-valued attribute truncation (>1500 values)
- Script-scoped state elimination
- Proper timeout configuration
- Enhanced error handling with structured logging

### Performance

- 10,000-50,000 objects/minute collection rate
- Configurable page sizes (100-5000)
- Optimized memory usage
- Parallel processing: 4x speedup for 4-domain forests

### Testing

- Transform.Tests.ps1: Conversion functions
- SQLite.Tests.ps1: Database operations
- ADConfiguration.Tests.ps1: Configuration and security
- ADAdvancedFeatures.Tests.ps1: Checkpoints and advanced features
'@

            # Prerelease string of this module
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        }
    }

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
}
