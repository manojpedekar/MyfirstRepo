-- ============================================================================
-- AD Inventory SQLite Schema
-- ============================================================================
-- Description: Database schema for Active Directory inventory storage
-- Version: 3.4.0
-- Created: 2025-12-01
-- Updated: 2026-01-19
-- Module: SSNC.ADInventory
-- ============================================================================

-- Performance and Safety Settings (optimized for bulk insert)
PRAGMA foreign_keys = ON;              -- Enforce referential integrity
PRAGMA journal_mode = WAL;             -- Write-Ahead Logging for better concurrency
PRAGMA synchronous = OFF;              -- Fastest writes (data recovery not needed for imports)
PRAGMA cache_size = -128000;           -- 128MB cache for better performance
PRAGMA locking_mode = EXCLUSIVE;       -- Single-writer optimization
PRAGMA temp_store = MEMORY;            -- Store temp tables in memory

-- ============================================================================
-- Table: AD_CollectionInfo
-- Description: Collection metadata (one row per domain collected)
-- ============================================================================
CREATE TABLE AD_CollectionInfo (
    CollectionID        TEXT    PRIMARY KEY NOT NULL,  -- GUID string for global uniqueness
    InventoryID         TEXT    NOT NULL,  -- Shared across all domains in a single collection run
    ComputerName        TEXT    NOT NULL,
    DomainName          TEXT    NOT NULL,  -- Individual domain name (not concatenated)
    CollectionDateTime  TEXT    NOT NULL,
    Who                 TEXT    NOT NULL,
    ModuleVersion       TEXT,                -- SSNC.ADInventory module version for troubleshooting
    StartTime           TEXT,                -- NULL until domain collection actually begins
    EndTime             TEXT,

    UNIQUE (InventoryID, DomainName)
);

-- ============================================================================
-- Table: AD_Object
-- Description: Core AD objects (users, groups, computers)
-- ============================================================================
CREATE TABLE AD_Object (
    -- Identity
    SID_String                 TEXT    NOT NULL,  -- Real SID for security principals, synthetic "CN:{GUID}" for contacts
    ObjectType                 INTEGER NOT NULL,  -- 1=User, 2=Group, 3=Computer, 4=Contact

    -- Core Attributes
    SamAccountName             TEXT,
    DisplayName                TEXT,
    UserPrincipalName          TEXT,
    DomainName                 TEXT    NOT NULL,  -- Object's domain (may differ from collection domain)
    DistinguishedName          TEXT    NOT NULL,
    ObjectGUID                 TEXT,
    CanonicalName              TEXT,
    Description                TEXT,

    -- Timestamps
    WhenCreated                TEXT,
    WhenChanged                TEXT,

    -- Status
    Enabled                    INTEGER,

    -- Account Security (Users and Computers only)
    LastLogonTimestamp         TEXT,     -- ISO 8601 DateTime
    PasswordLastSet            TEXT,     -- ISO 8601 DateTime
    AccountExpires             TEXT,     -- ISO 8601 DateTime (NULL = never)
    PasswordNeverExpires       INTEGER,  -- 1=true, 0=false

    -- User Attributes
    GivenName                  TEXT,
    Surname                    TEXT,
    Mail                       TEXT,
    Department                 TEXT,
    Title                      TEXT,
    Manager                    TEXT,
    EmployeeID                 TEXT,
    EmployeeNumber             TEXT,
    EmployeeType               TEXT,

    -- Group Attributes
    GroupType                  INTEGER,
    GroupScope                 INTEGER,
    ManagedBy                  TEXT,

    -- Computer Attributes
    DNSHostName                TEXT,
    OperatingSystem            TEXT,
    OperatingSystemVersion     TEXT,
    OperatingSystemServicePack TEXT,
    OperatingSystemHotfix      TEXT,

    -- Security Attributes
    SIDHistory                 TEXT,   -- JSON array of historical SIDs
    IsCriticalSystemObject     INTEGER,  -- 1=critical (DCs, built-in), 0=normal
    ServicePrincipalName       TEXT,     -- JSON array of SPNs
    UserAccountControl         INTEGER,  -- Raw UAC bitmask value
    PasswordExpired            INTEGER,  -- 1=expired, 0=valid (computed from msDS-UserPasswordExpired)

    -- Foreign Security Principal Support
    IsForeignSecurityPrincipal INTEGER DEFAULT 0,

    -- Collection Reference
    CollectionID               INTEGER NOT NULL,

    PRIMARY KEY (SID_String, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_GroupMembership
-- Description: Direct group membership relationships (one-level)
-- ============================================================================
CREATE TABLE AD_GroupMembership (
    GroupSID     TEXT    NOT NULL,
    MemberSID    TEXT    NOT NULL,
    CollectionID INTEGER NOT NULL,

    PRIMARY KEY (GroupSID, MemberSID, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- NOTE: AD_GroupMember_Flat table has been removed from SQLite.
-- Flattened memberships are computed in MS SQL using a recursive CTE.
-- See: database/MSSQL/FlattenGroupMemberships.sql

-- ============================================================================
-- Table: AD_ForeignSecurityPrincipal
-- Description: Foreign Security Principals from trusted domains
-- ============================================================================
CREATE TABLE AD_ForeignSecurityPrincipal (
    SID_String         TEXT    NOT NULL,
    SourceDomainName   TEXT,
    DistinguishedName  TEXT,
    IsResolved         INTEGER NOT NULL DEFAULT 0,
    LastResolveAttempt TEXT,
    CollectionID       INTEGER NOT NULL,

    PRIMARY KEY (SID_String, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_Trust
-- Description: Domain trust relationships
-- ============================================================================
CREATE TABLE AD_Trust (
    SourceDomain    TEXT    NOT NULL,  -- Domain that defines this trust relationship
    TargetDomain    TEXT    NOT NULL,
    TrustType       TEXT    NOT NULL,  -- ParentChild, External, Forest, Downlevel, Kerberos, etc.
    TrustDirection  TEXT    NOT NULL,  -- Inbound, Outbound, Bidirectional
    TrustAttributes INTEGER,           -- Bitmask of trust attributes
    IsTransitive    INTEGER NOT NULL,
    FlatName        TEXT,              -- NetBIOS name of trusted domain
    WhenCreated     TEXT,
    CollectionID    INTEGER NOT NULL,

    PRIMARY KEY (SourceDomain, TargetDomain, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_Domain
-- Description: Domain information and FSMO role holders
-- ============================================================================
CREATE TABLE AD_Domain (
    -- Identity
    DomainName              TEXT    NOT NULL,  -- DNS name (e.g., contoso.com)
    DomainSID               TEXT    NOT NULL,  -- Domain SID string
    DomainGUID              TEXT,              -- Domain GUID
    NetBIOSName             TEXT,              -- NetBIOS name (e.g., CONTOSO)
    DistinguishedName       TEXT,              -- Domain DN (DC=contoso,DC=com)

    -- Forest relationship
    ForestName              TEXT,              -- Parent forest DNS name
    ParentDomain            TEXT,              -- Parent domain if child domain

    -- Functional level
    DomainMode              TEXT,              -- Functional level name (e.g., Windows2016Domain)
    DomainModeLevel         INTEGER,           -- Functional level number

    -- FSMO Role Holders
    PDCEmulator             TEXT,              -- PDC Emulator role holder
    RIDMaster               TEXT,              -- RID Master role holder
    InfrastructureMaster    TEXT,              -- Infrastructure Master role holder

    -- Additional info
    ChildDomains            TEXT,              -- JSON array of child domain names
    DomainControllers       TEXT,              -- JSON array of DC names
    ReadOnlyReplicaDirectoryServers TEXT,     -- JSON array of RODC names

    -- SYSVOL Replication Method
    SysvolReplicationMethod TEXT,              -- FRS, DFSR, or Unknown
    SysvolMigrationState    TEXT,              -- Not Started, Start, Prepared, Redirected, Eliminated, Native
    DFSRExists              INTEGER,           -- 1=true, 0=false
    FRSExists               INTEGER,           -- 1=true, 0=false
    DFSRFlags               INTEGER,           -- Raw msDFSR-Flags value

    -- GPO Store Health
    GPOTotalCount           INTEGER,           -- Total number of GPOs in AD
    GPOHealthyCount         INTEGER,           -- Number of GPOs with no issues
    GPOOrphanedGPCCount     INTEGER,           -- GPCs with missing SYSVOL folders
    GPOOrphanedGPTCount     INTEGER,           -- SYSVOL folders with missing AD objects
    GPOVersionMismatchCount INTEGER,           -- GPOs with AD/SYSVOL version mismatch
    GPOOverallHealth        TEXT,              -- Healthy, Warning, or Critical
    SYSVOLAccessible        INTEGER,           -- 1=true, 0=false
    DefaultDomainPolicyExists INTEGER,         -- 1=true, 0=false
    DefaultDCPolicyExists   INTEGER,           -- 1=true, 0=false

    -- Timestamps
    WhenCreated             TEXT,
    WhenChanged             TEXT,

    -- Collection Reference
    CollectionID            INTEGER NOT NULL,

    PRIMARY KEY (DomainSID, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_Forest
-- Description: Forest information and FSMO role holders
-- ============================================================================
CREATE TABLE AD_Forest (
    -- Identity
    ForestName              TEXT    NOT NULL,  -- Forest root domain DNS name
    ForestGUID              TEXT,              -- Forest GUID (from Configuration NC)
    RootDomain              TEXT,              -- Forest root domain name

    -- Functional level
    ForestMode              TEXT,              -- Functional level name (e.g., Windows2016Forest)
    ForestModeLevel         INTEGER,           -- Functional level number

    -- FSMO Role Holders
    SchemaMaster            TEXT,              -- Schema Master role holder
    DomainNamingMaster      TEXT,              -- Domain Naming Master role holder

    -- Forest structure
    Domains                 TEXT,              -- JSON array of all domain names in forest
    GlobalCatalogs          TEXT,              -- JSON array of Global Catalog servers
    Sites                   TEXT,              -- JSON array of AD site names
    SiteLinks               TEXT,              -- JSON array of site link names

    -- Schema info
    SchemaVersion           INTEGER,           -- AD Schema version number
    ExchangeSchemaVersion   INTEGER,           -- Exchange schema version (if present)

    -- Timestamps
    WhenCreated             TEXT,

    -- Collection Reference
    CollectionID            INTEGER NOT NULL,

    PRIMARY KEY (ForestName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- SITES & SERVICES TABLES
-- ============================================================================
-- These tables store forest-wide Sites & Services configuration data.
-- Data is collected once per forest from the Configuration partition.
-- ============================================================================

-- ============================================================================
-- Table: AD_Site
-- Description: Active Directory sites
-- ============================================================================
CREATE TABLE AD_Site (
    SiteName          TEXT    NOT NULL,
    Description       TEXT,
    Location          TEXT,
    DistinguishedName TEXT    NOT NULL,
    ObjectGUID        TEXT,
    WhenCreated       TEXT,
    WhenChanged       TEXT,
    CollectionID      TEXT    NOT NULL,

    PRIMARY KEY (SiteName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_Subnet
-- Description: Active Directory subnets
-- ============================================================================
CREATE TABLE AD_Subnet (
    SubnetName        TEXT    NOT NULL,
    Description       TEXT,
    Location          TEXT,
    SiteName          TEXT,              -- FK to site this subnet is assigned to
    SiteObjectDN      TEXT,              -- Full DN of the site object
    DistinguishedName TEXT    NOT NULL,
    ObjectGUID        TEXT,
    WhenCreated       TEXT,
    WhenChanged       TEXT,
    CollectionID      TEXT    NOT NULL,

    PRIMARY KEY (SubnetName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_SiteLink
-- Description: Active Directory site links
-- ============================================================================
CREATE TABLE AD_SiteLink (
    SiteLinkName        TEXT    NOT NULL,
    Cost                INTEGER DEFAULT 100,
    ReplicationInterval INTEGER DEFAULT 180,
    Options             INTEGER DEFAULT 0,
    UseNotification     INTEGER DEFAULT 0,
    TwoWaySync          INTEGER DEFAULT 0,
    CompressionDisabled INTEGER DEFAULT 0,
    SiteCount           INTEGER,
    SiteList            TEXT,              -- JSON array of site names
    Schedule            TEXT,              -- Base64-encoded schedule
    Description         TEXT,
    TransportType       TEXT    DEFAULT 'IP',
    DistinguishedName   TEXT    NOT NULL,
    ObjectGUID          TEXT,
    WhenCreated         TEXT,
    WhenChanged         TEXT,
    CollectionID        TEXT    NOT NULL,

    PRIMARY KEY (SiteLinkName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_SiteSettings
-- Description: NTDS Site Settings for each site
-- ============================================================================
CREATE TABLE AD_SiteSettings (
    SiteName                        TEXT    NOT NULL,
    InterSiteTopologyGenerator      TEXT,              -- Full DN of ISTG
    InterSiteTopologyGeneratorName  TEXT,              -- Server name of ISTG
    Options                         INTEGER DEFAULT 0,
    IsAutoTopologyDisabled          INTEGER DEFAULT 0,
    IsTopologyCleanupDisabled       INTEGER DEFAULT 0,
    IsMinHopsDisabled               INTEGER DEFAULT 0,
    IsDetectStaleDisabled           INTEGER DEFAULT 0,
    IsInterSiteAutoTopologyDisabled INTEGER DEFAULT 0,
    IsGroupCachingEnabled           INTEGER DEFAULT 0,
    Schedule                        TEXT,              -- Base64-encoded schedule
    DistinguishedName               TEXT    NOT NULL,
    ObjectGUID                      TEXT,
    WhenCreated                     TEXT,
    WhenChanged                     TEXT,
    CollectionID                    TEXT    NOT NULL,

    PRIMARY KEY (SiteName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_SiteServer
-- Description: Servers in AD sites
-- ============================================================================
CREATE TABLE AD_SiteServer (
    ServerName        TEXT    NOT NULL,
    SiteName          TEXT    NOT NULL,
    DNSHostName       TEXT,
    ServerReference   TEXT,              -- DN of the computer object in AD
    DistinguishedName TEXT    NOT NULL,
    ObjectGUID        TEXT,
    WhenCreated       TEXT,
    WhenChanged       TEXT,
    CollectionID      TEXT    NOT NULL,

    PRIMARY KEY (ServerName, SiteName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_DomainController
-- Description: Domain Controller NTDS Settings objects
-- ============================================================================
CREATE TABLE AD_DomainController (
    ServerName                   TEXT    NOT NULL,
    SiteName                     TEXT    NOT NULL,
    Options                      INTEGER DEFAULT 0,
    IsGlobalCatalog              INTEGER DEFAULT 0,
    DisableInboundReplication    INTEGER DEFAULT 0,
    DisableOutboundReplication   INTEGER DEFAULT 0,
    DisableNTDSConnTranslation   INTEGER DEFAULT 0,
    IsRODC                       INTEGER DEFAULT 0,
    InvocationId                 TEXT,
    MasterNCs                    TEXT,              -- JSON array of naming contexts
    DistinguishedName            TEXT    NOT NULL,
    ObjectGUID                   TEXT,
    WhenCreated                  TEXT,
    WhenChanged                  TEXT,
    CollectionID                 TEXT    NOT NULL,

    PRIMARY KEY (ServerName, SiteName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_SiteSubnet (Junction Table)
-- Description: Normalized site-to-subnet relationships
-- ============================================================================
CREATE TABLE AD_SiteSubnet (
    SiteName     TEXT    NOT NULL,
    SubnetName   TEXT    NOT NULL,
    CollectionID TEXT    NOT NULL,

    PRIMARY KEY (SiteName, SubnetName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_SiteLinkSite (Junction Table)
-- Description: Normalized site link-to-site relationships
-- ============================================================================
CREATE TABLE AD_SiteLinkSite (
    SiteLinkName TEXT    NOT NULL,
    SiteName     TEXT    NOT NULL,
    CollectionID TEXT    NOT NULL,

    PRIMARY KEY (SiteLinkName, SiteName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_OptionalFeature
-- Description: Forest-scoped optional features (Recycle Bin, PAM, etc.)
-- ============================================================================
CREATE TABLE AD_OptionalFeature (
    -- Identity (composite key: ForestName + FeatureName + CollectionID)
    ForestName              TEXT    NOT NULL,
    FeatureName             TEXT    NOT NULL,

    -- Feature Properties
    FeatureGUID             TEXT,              -- GUID of the optional feature
    IsEnabled               INTEGER NOT NULL DEFAULT 0,  -- 1=enabled, 0=not enabled
    RequiredForestLevel     INTEGER,           -- Minimum forest functional level required
    RequiredForestLevelName TEXT,              -- Friendly name (e.g., "Windows Server 2008 R2")
    RequiredDomainLevel     INTEGER,           -- Minimum domain functional level required
    Description             TEXT,              -- Human-readable description

    -- Reference
    DistinguishedName       TEXT,              -- Full DN of the feature object

    -- Collection Reference
    CollectionID            TEXT    NOT NULL,

    PRIMARY KEY (ForestName, FeatureName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- KMS SERVICE DISCOVERY
-- ============================================================================
-- Domain-scoped: Collected once per domain via DNS SRV query
-- ============================================================================

-- ============================================================================
-- Table: AD_KMSService
-- Description: KMS Service records discovered via DNS SRV queries
-- ============================================================================
CREATE TABLE AD_KMSService (
    DomainName        TEXT    NOT NULL,
    TargetHostname    TEXT    NOT NULL,
    Port              INTEGER NOT NULL DEFAULT 1688,
    Priority          INTEGER,
    Weight            INTEGER,
    TTL               INTEGER,
    ResolvedIP        TEXT,              -- Optional IP resolution
    RecordSource      TEXT    DEFAULT 'DNS',  -- DNS or Manual
    CollectionID      TEXT    NOT NULL,

    PRIMARY KEY (DomainName, TargetHostname, Port, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- AD FS CONFIGURATION
-- ============================================================================
-- Forest-scoped: Collected from Configuration partition
-- ============================================================================

-- ============================================================================
-- Table: AD_ADFSConfiguration
-- Description: AD FS Service Connection Points and Device Registration Service
-- ============================================================================
CREATE TABLE AD_ADFSConfiguration (
    ForestName              TEXT    NOT NULL,
    ServiceType             TEXT    NOT NULL,  -- 'ADFS' or 'DRS' (Device Registration)
    ServiceName             TEXT,
    FederationServiceName   TEXT,              -- For ADFS
    AzureTenantId           TEXT,              -- From keywords
    AzureObjectId           TEXT,              -- From keywords
    DomainName              TEXT,              -- Associated domain
    ServiceBindingInfo      TEXT,              -- URL or binding
    Keywords                TEXT,              -- JSON array of all keywords
    DistinguishedName       TEXT    NOT NULL,
    ObjectGUID              TEXT,
    WhenCreated             TEXT,
    WhenChanged             TEXT,
    CollectionID            TEXT    NOT NULL,

    PRIMARY KEY (ForestName, ServiceType, DistinguishedName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- AD CERTIFICATE SERVICES (PKI) TABLES
-- ============================================================================
-- Forest-scoped: Collected from Configuration partition
-- ============================================================================

-- ============================================================================
-- Table: AD_EnterpriseCA
-- Description: Enterprise Certification Authorities (from pKIEnrollmentService)
-- ============================================================================
CREATE TABLE AD_EnterpriseCA (
    ForestName              TEXT    NOT NULL,
    CAName                  TEXT    NOT NULL,
    DNSHostName             TEXT,
    CAType                  TEXT,              -- Enterprise Root, Enterprise Subordinate
    CACertificate           TEXT,              -- Base64-encoded certificate
    CACertificateDN         TEXT,              -- Certificate subject DN
    CertificateTemplates    TEXT,              -- JSON array of template names
    Flags                   INTEGER,
    DistinguishedName       TEXT    NOT NULL,
    ObjectGUID              TEXT,
    WhenCreated             TEXT,
    WhenChanged             TEXT,
    CollectionID            TEXT    NOT NULL,

    PRIMARY KEY (ForestName, CAName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_CertificateTemplate
-- Description: Certificate Templates (from pKICertificateTemplate)
-- ============================================================================
CREATE TABLE AD_CertificateTemplate (
    ForestName              TEXT    NOT NULL,
    TemplateName            TEXT    NOT NULL,
    DisplayName             TEXT,
    TemplateOID             TEXT,              -- msPKI-Cert-Template-OID
    SchemaVersion           INTEGER,           -- msPKI-Template-Schema-Version
    MinorRevision           INTEGER,           -- msPKI-Template-Minor-Revision
    MajorRevision           INTEGER,           -- revision attribute
    RASignaturesRequired    INTEGER,           -- msPKI-RA-Signature
    MinKeySize              INTEGER,           -- msPKI-Minimal-Key-Size
    EnrollmentFlags         INTEGER,           -- msPKI-Enrollment-Flag
    PrivateKeyFlags         INTEGER,           -- msPKI-Private-Key-Flag
    CertificateNameFlags    INTEGER,           -- msPKI-Certificate-Name-Flag
    ValidityPeriod          TEXT,              -- pKIExpirationPeriod (parsed)
    RenewalPeriod           TEXT,              -- pKIOverlapPeriod (parsed)
    ExtendedKeyUsage        TEXT,              -- JSON array of EKU OIDs
    DistinguishedName       TEXT    NOT NULL,
    ObjectGUID              TEXT,
    WhenCreated             TEXT,
    WhenChanged             TEXT,
    CollectionID            TEXT    NOT NULL,

    PRIMARY KEY (ForestName, TemplateName, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_TrustedRootCA
-- Description: Trusted Root Certification Authorities
-- ============================================================================
CREATE TABLE AD_TrustedRootCA (
    ForestName              TEXT    NOT NULL,
    CAName                  TEXT    NOT NULL,
    CACertificate           TEXT,              -- Base64-encoded certificate
    CertificateSubject      TEXT,              -- Certificate subject DN
    CertificateThumbprint   TEXT,
    CertificateNotBefore    TEXT,
    CertificateNotAfter     TEXT,
    ContainerType           TEXT    NOT NULL,  -- 'CertificationAuthorities', 'AIA', 'CDP'
    DistinguishedName       TEXT    NOT NULL,
    ObjectGUID              TEXT,
    WhenCreated             TEXT,
    WhenChanged             TEXT,
    CollectionID            TEXT    NOT NULL,

    PRIMARY KEY (ForestName, CAName, ContainerType, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_NTAuthCA
-- Description: NTAuth Certificates (for smart card authentication)
-- ============================================================================
CREATE TABLE AD_NTAuthCA (
    ForestName              TEXT    NOT NULL,
    CertificateSubject      TEXT    NOT NULL,
    CACertificate           TEXT,              -- Base64-encoded certificate
    CertificateThumbprint   TEXT,
    CertificateNotBefore    TEXT,
    CertificateNotAfter     TEXT,
    CertificateIndex        INTEGER,           -- Index in cACertificate array
    DistinguishedName       TEXT    NOT NULL,  -- NTAuthCertificates container DN
    CollectionID            TEXT    NOT NULL,

    PRIMARY KEY (ForestName, CertificateThumbprint, CollectionID),
    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_Log
-- Description: Consolidated logging for audit trail and troubleshooting
-- ============================================================================
CREATE TABLE AD_Log (
    -- Identity
    LogID              INTEGER PRIMARY KEY AUTOINCREMENT,
    CollectionID       INTEGER NOT NULL,

    -- Timestamp
    Timestamp          TEXT    NOT NULL,  -- ISO 8601 UTC timestamp

    -- Log Details
    Level              TEXT    NOT NULL,  -- Error, Warning, Info, Verbose, Debug
    Category           TEXT    NOT NULL,  -- Initialization, Connection, Collection, Database, Checkpoint, Parallel, Completion, General
    Message            TEXT    NOT NULL,
    Context            TEXT,               -- JSON context information

    -- Exception Details
    ExceptionMessage   TEXT,
    ExceptionType      TEXT,

    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Table: AD_ExecutionTime
-- Description: Execution timing for performance monitoring
-- ============================================================================
CREATE TABLE AD_ExecutionTime (
    -- Identity
    ExecutionID     INTEGER PRIMARY KEY AUTOINCREMENT,
    CollectionID    INTEGER NOT NULL,

    -- Timing
    Timestamp       TEXT    NOT NULL,  -- ISO 8601 UTC timestamp when operation started
    DurationSeconds REAL    NOT NULL,  -- Duration in seconds (with millisecond precision)

    -- Operation Details
    Operation       TEXT    NOT NULL,  -- Category: LDAP_Query, Insert, Processing, Index, etc.
    Target          TEXT,              -- What was operated on: Users, Groups, Trusts, etc.
    Domain          TEXT,              -- Domain name if applicable

    -- Metrics
    RecordCount     INTEGER,           -- Number of records processed/inserted
    RecordsPerSec   REAL,              -- Throughput: records per second

    -- Additional Context
    Details         TEXT,              -- JSON with additional details

    FOREIGN KEY (CollectionID) REFERENCES AD_CollectionInfo(CollectionID)
);

-- ============================================================================
-- Performance Indexes
-- ============================================================================

-- AD_CollectionInfo indexes
CREATE INDEX IX_CollectionInfo_InventoryID
    ON AD_CollectionInfo(InventoryID);

CREATE INDEX IX_CollectionInfo_DomainName
    ON AD_CollectionInfo(DomainName);

-- AD_Object indexes
CREATE INDEX IX_AD_Object_Type
    ON AD_Object(ObjectType);

CREATE INDEX IX_AD_Object_Domain
    ON AD_Object(DomainName);

CREATE INDEX IX_AD_Object_SamAccount
    ON AD_Object(SamAccountName);

CREATE INDEX IX_AD_Object_CollectionID
    ON AD_Object(CollectionID);

-- Group membership indexes
CREATE INDEX IX_GroupMembership_Member
    ON AD_GroupMembership(MemberSID);

CREATE INDEX IX_GroupMembership_CollectionID
    ON AD_GroupMembership(CollectionID);

-- FSP indexes
CREATE INDEX IX_FSP_SourceDomain
    ON AD_ForeignSecurityPrincipal(SourceDomainName);

CREATE INDEX IX_FSP_CollectionID
    ON AD_ForeignSecurityPrincipal(CollectionID);

-- Trust indexes
CREATE INDEX IX_Trust_Source
    ON AD_Trust(SourceDomain);

CREATE INDEX IX_Trust_Target
    ON AD_Trust(TargetDomain);

CREATE INDEX IX_Trust_CollectionID
    ON AD_Trust(CollectionID);

-- Domain indexes
CREATE INDEX IX_Domain_Name
    ON AD_Domain(DomainName);

CREATE INDEX IX_Domain_Forest
    ON AD_Domain(ForestName);

CREATE INDEX IX_Domain_CollectionID
    ON AD_Domain(CollectionID);

-- Forest indexes
CREATE INDEX IX_Forest_Name
    ON AD_Forest(ForestName);

CREATE INDEX IX_Forest_CollectionID
    ON AD_Forest(CollectionID);

-- Log indexes
CREATE INDEX IX_Log_CollectionID
    ON AD_Log(CollectionID);

CREATE INDEX IX_Log_Timestamp
    ON AD_Log(Timestamp);

CREATE INDEX IX_Log_Level
    ON AD_Log(Level);

CREATE INDEX IX_Log_Category
    ON AD_Log(Category);

-- ExecutionTime indexes
CREATE INDEX IX_ExecutionTime_CollectionID
    ON AD_ExecutionTime(CollectionID);

CREATE INDEX IX_ExecutionTime_Operation
    ON AD_ExecutionTime(Operation);

CREATE INDEX IX_ExecutionTime_Timestamp
    ON AD_ExecutionTime(Timestamp);

-- Sites & Services indexes
CREATE INDEX IX_Site_CollectionID
    ON AD_Site(CollectionID);

CREATE INDEX IX_Subnet_CollectionID
    ON AD_Subnet(CollectionID);

CREATE INDEX IX_Subnet_SiteName
    ON AD_Subnet(SiteName);

CREATE INDEX IX_SiteLink_CollectionID
    ON AD_SiteLink(CollectionID);

CREATE INDEX IX_SiteSettings_CollectionID
    ON AD_SiteSettings(CollectionID);

CREATE INDEX IX_SiteServer_CollectionID
    ON AD_SiteServer(CollectionID);

CREATE INDEX IX_SiteServer_SiteName
    ON AD_SiteServer(SiteName);

CREATE INDEX IX_DomainController_CollectionID
    ON AD_DomainController(CollectionID);

CREATE INDEX IX_DomainController_SiteName
    ON AD_DomainController(SiteName);

CREATE INDEX IX_SiteSubnet_CollectionID
    ON AD_SiteSubnet(CollectionID);

CREATE INDEX IX_SiteLinkSite_CollectionID
    ON AD_SiteLinkSite(CollectionID);

-- Optional Feature indexes
CREATE INDEX IX_OptionalFeature_CollectionID
    ON AD_OptionalFeature(CollectionID);

CREATE INDEX IX_OptionalFeature_ForestName
    ON AD_OptionalFeature(ForestName);

CREATE INDEX IX_OptionalFeature_IsEnabled
    ON AD_OptionalFeature(IsEnabled);

-- KMS Service indexes
CREATE INDEX IX_KMSService_CollectionID
    ON AD_KMSService(CollectionID);

CREATE INDEX IX_KMSService_DomainName
    ON AD_KMSService(DomainName);

CREATE INDEX IX_KMSService_TargetHostname
    ON AD_KMSService(TargetHostname);

-- ADFS Configuration indexes
CREATE INDEX IX_ADFSConfiguration_CollectionID
    ON AD_ADFSConfiguration(CollectionID);

CREATE INDEX IX_ADFSConfiguration_ForestName
    ON AD_ADFSConfiguration(ForestName);

CREATE INDEX IX_ADFSConfiguration_ServiceType
    ON AD_ADFSConfiguration(ServiceType);

-- Enterprise CA indexes
CREATE INDEX IX_EnterpriseCA_CollectionID
    ON AD_EnterpriseCA(CollectionID);

CREATE INDEX IX_EnterpriseCA_ForestName
    ON AD_EnterpriseCA(ForestName);

-- Certificate Template indexes
CREATE INDEX IX_CertificateTemplate_CollectionID
    ON AD_CertificateTemplate(CollectionID);

CREATE INDEX IX_CertificateTemplate_ForestName
    ON AD_CertificateTemplate(ForestName);

-- Trusted Root CA indexes
CREATE INDEX IX_TrustedRootCA_CollectionID
    ON AD_TrustedRootCA(CollectionID);

CREATE INDEX IX_TrustedRootCA_ForestName
    ON AD_TrustedRootCA(ForestName);

CREATE INDEX IX_TrustedRootCA_ContainerType
    ON AD_TrustedRootCA(ContainerType);

-- NTAuth CA indexes
CREATE INDEX IX_NTAuthCA_CollectionID
    ON AD_NTAuthCA(CollectionID);

CREATE INDEX IX_NTAuthCA_ForestName
    ON AD_NTAuthCA(ForestName);

-- ============================================================================
-- Compatibility Views (provide legacy column names)
-- ============================================================================

-- View: v_AD_Object (adds InventoryID for backward compatibility)
CREATE VIEW v_AD_Object AS
SELECT
    o.SID_String,
    o.ObjectType,
    o.SamAccountName,
    o.DisplayName,
    o.UserPrincipalName,
    o.DomainName,
    o.DistinguishedName,
    o.ObjectGUID,
    o.CanonicalName,
    o.Description,
    o.WhenCreated,
    o.WhenChanged,
    o.Enabled,
    o.LastLogonTimestamp,
    o.PasswordLastSet,
    o.AccountExpires,
    o.PasswordNeverExpires,
    o.GivenName,
    o.Surname,
    o.Mail,
    o.Department,
    o.Title,
    o.Manager,
    o.EmployeeID,
    o.EmployeeNumber,
    o.EmployeeType,
    o.GroupType,
    o.GroupScope,
    o.ManagedBy,
    o.DNSHostName,
    o.OperatingSystem,
    o.OperatingSystemVersion,
    o.OperatingSystemServicePack,
    o.OperatingSystemHotfix,
    o.SIDHistory,
    o.IsCriticalSystemObject,
    o.ServicePrincipalName,
    o.UserAccountControl,
    o.PasswordExpired,
    o.IsForeignSecurityPrincipal,
    c.InventoryID
FROM AD_Object o
JOIN AD_CollectionInfo c ON o.CollectionID = c.CollectionID;

-- View: v_AD_GroupMembership (adds InventoryID for backward compatibility)
CREATE VIEW v_AD_GroupMembership AS
SELECT
    gm.GroupSID,
    gm.MemberSID,
    c.InventoryID
FROM AD_GroupMembership gm
JOIN AD_CollectionInfo c ON gm.CollectionID = c.CollectionID;

-- View: v_AD_ForeignSecurityPrincipal (adds InventoryID and CollectedDate)
CREATE VIEW v_AD_ForeignSecurityPrincipal AS
SELECT
    fsp.SID_String,
    fsp.SourceDomainName,
    fsp.DistinguishedName,
    fsp.IsResolved,
    fsp.LastResolveAttempt,
    c.InventoryID,
    c.CollectionDateTime AS CollectedDate
FROM AD_ForeignSecurityPrincipal fsp
JOIN AD_CollectionInfo c ON fsp.CollectionID = c.CollectionID;

-- View: v_AD_Trust (adds InventoryID)
CREATE VIEW v_AD_Trust AS
SELECT
    t.SourceDomain,
    t.TargetDomain,
    t.TrustType,
    t.TrustDirection,
    t.TrustAttributes,
    t.IsTransitive,
    t.FlatName,
    t.WhenCreated,
    c.InventoryID
FROM AD_Trust t
JOIN AD_CollectionInfo c ON t.CollectionID = c.CollectionID;

-- View: v_AD_Domain (adds InventoryID)
CREATE VIEW v_AD_Domain AS
SELECT
    d.DomainName,
    d.DomainSID,
    d.DomainGUID,
    d.NetBIOSName,
    d.DistinguishedName,
    d.ForestName,
    d.ParentDomain,
    d.DomainMode,
    d.DomainModeLevel,
    d.PDCEmulator,
    d.RIDMaster,
    d.InfrastructureMaster,
    d.ChildDomains,
    d.DomainControllers,
    d.ReadOnlyReplicaDirectoryServers,
    d.SysvolReplicationMethod,
    d.SysvolMigrationState,
    d.DFSRExists,
    d.FRSExists,
    d.DFSRFlags,
    d.GPOTotalCount,
    d.GPOHealthyCount,
    d.GPOOrphanedGPCCount,
    d.GPOOrphanedGPTCount,
    d.GPOVersionMismatchCount,
    d.GPOOverallHealth,
    d.SYSVOLAccessible,
    d.DefaultDomainPolicyExists,
    d.DefaultDCPolicyExists,
    d.WhenCreated,
    d.WhenChanged,
    c.InventoryID
FROM AD_Domain d
JOIN AD_CollectionInfo c ON d.CollectionID = c.CollectionID;

-- View: v_AD_Forest (adds InventoryID)
CREATE VIEW v_AD_Forest AS
SELECT
    f.ForestName,
    f.ForestGUID,
    f.RootDomain,
    f.ForestMode,
    f.ForestModeLevel,
    f.SchemaMaster,
    f.DomainNamingMaster,
    f.Domains,
    f.GlobalCatalogs,
    f.Sites,
    f.SiteLinks,
    f.SchemaVersion,
    f.ExchangeSchemaVersion,
    f.WhenCreated,
    c.InventoryID
FROM AD_Forest f
JOIN AD_CollectionInfo c ON f.CollectionID = c.CollectionID;

-- View: v_AD_OptionalFeature (adds InventoryID)
CREATE VIEW v_AD_OptionalFeature AS
SELECT
    of.ForestName,
    of.FeatureName,
    of.FeatureGUID,
    of.IsEnabled,
    of.RequiredForestLevel,
    of.RequiredForestLevelName,
    of.RequiredDomainLevel,
    of.Description,
    of.DistinguishedName,
    c.InventoryID
FROM AD_OptionalFeature of
JOIN AD_CollectionInfo c ON of.CollectionID = c.CollectionID;

-- View: v_AD_Log (adds InventoryID, MachineName, UserName)
CREATE VIEW v_AD_Log AS
SELECT
    l.LogID,
    l.Timestamp,
    l.Level,
    l.Category,
    l.Message,
    l.Context,
    l.ExceptionMessage,
    l.ExceptionType,
    c.InventoryID,
    c.ComputerName AS MachineName,
    c.Who AS UserName
FROM AD_Log l
JOIN AD_CollectionInfo c ON l.CollectionID = c.CollectionID;

-- View: v_AD_ExecutionTime (adds InventoryID)
CREATE VIEW v_AD_ExecutionTime AS
SELECT
    et.ExecutionID,
    et.Timestamp,
    et.DurationSeconds,
    et.Operation,
    et.Target,
    et.Domain,
    et.RecordCount,
    et.RecordsPerSec,
    et.Details,
    c.InventoryID
FROM AD_ExecutionTime et
JOIN AD_CollectionInfo c ON et.CollectionID = c.CollectionID;

-- View: v_AD_KMSService (adds InventoryID)
CREATE VIEW v_AD_KMSService AS
SELECT
    kms.DomainName,
    kms.TargetHostname,
    kms.Port,
    kms.Priority,
    kms.Weight,
    kms.TTL,
    kms.ResolvedIP,
    kms.RecordSource,
    c.InventoryID
FROM AD_KMSService kms
JOIN AD_CollectionInfo c ON kms.CollectionID = c.CollectionID;

-- View: v_AD_ADFSConfiguration (adds InventoryID)
CREATE VIEW v_AD_ADFSConfiguration AS
SELECT
    adfs.ForestName,
    adfs.ServiceType,
    adfs.ServiceName,
    adfs.FederationServiceName,
    adfs.AzureTenantId,
    adfs.AzureObjectId,
    adfs.DomainName,
    adfs.ServiceBindingInfo,
    adfs.Keywords,
    adfs.DistinguishedName,
    adfs.ObjectGUID,
    adfs.WhenCreated,
    adfs.WhenChanged,
    c.InventoryID
FROM AD_ADFSConfiguration adfs
JOIN AD_CollectionInfo c ON adfs.CollectionID = c.CollectionID;

-- View: v_AD_EnterpriseCA (adds InventoryID)
CREATE VIEW v_AD_EnterpriseCA AS
SELECT
    ca.ForestName,
    ca.CAName,
    ca.DNSHostName,
    ca.CAType,
    ca.CACertificate,
    ca.CACertificateDN,
    ca.CertificateTemplates,
    ca.Flags,
    ca.DistinguishedName,
    ca.ObjectGUID,
    ca.WhenCreated,
    ca.WhenChanged,
    c.InventoryID
FROM AD_EnterpriseCA ca
JOIN AD_CollectionInfo c ON ca.CollectionID = c.CollectionID;

-- View: v_AD_CertificateTemplate (adds InventoryID)
CREATE VIEW v_AD_CertificateTemplate AS
SELECT
    ct.ForestName,
    ct.TemplateName,
    ct.DisplayName,
    ct.TemplateOID,
    ct.SchemaVersion,
    ct.MinorRevision,
    ct.MajorRevision,
    ct.RASignaturesRequired,
    ct.MinKeySize,
    ct.EnrollmentFlags,
    ct.PrivateKeyFlags,
    ct.CertificateNameFlags,
    ct.ValidityPeriod,
    ct.RenewalPeriod,
    ct.ExtendedKeyUsage,
    ct.DistinguishedName,
    ct.ObjectGUID,
    ct.WhenCreated,
    ct.WhenChanged,
    c.InventoryID
FROM AD_CertificateTemplate ct
JOIN AD_CollectionInfo c ON ct.CollectionID = c.CollectionID;

-- View: v_AD_TrustedRootCA (adds InventoryID)
CREATE VIEW v_AD_TrustedRootCA AS
SELECT
    tca.ForestName,
    tca.CAName,
    tca.CACertificate,
    tca.CertificateSubject,
    tca.CertificateThumbprint,
    tca.CertificateNotBefore,
    tca.CertificateNotAfter,
    tca.ContainerType,
    tca.DistinguishedName,
    tca.ObjectGUID,
    tca.WhenCreated,
    tca.WhenChanged,
    c.InventoryID
FROM AD_TrustedRootCA tca
JOIN AD_CollectionInfo c ON tca.CollectionID = c.CollectionID;

-- View: v_AD_NTAuthCA (adds InventoryID)
CREATE VIEW v_AD_NTAuthCA AS
SELECT
    nta.ForestName,
    nta.CertificateSubject,
    nta.CACertificate,
    nta.CertificateThumbprint,
    nta.CertificateNotBefore,
    nta.CertificateNotAfter,
    nta.CertificateIndex,
    nta.DistinguishedName,
    c.InventoryID
FROM AD_NTAuthCA nta
JOIN AD_CollectionInfo c ON nta.CollectionID = c.CollectionID;

-- ============================================================================
-- Schema Version Tracking
-- ============================================================================
CREATE TABLE Schema_Version (
    Version     TEXT NOT NULL PRIMARY KEY,
    AppliedDate TEXT NOT NULL,
    Description TEXT
);

INSERT INTO Schema_Version (Version, AppliedDate, Description)
VALUES ('3.4.0', datetime('now'), 'Added KMS, ADFS, and PKI collection tables (AD_KMSService, AD_ADFSConfiguration, AD_EnterpriseCA, AD_CertificateTemplate, AD_TrustedRootCA, AD_NTAuthCA)');

-- ============================================================================
-- End of Schema
-- ============================================================================
