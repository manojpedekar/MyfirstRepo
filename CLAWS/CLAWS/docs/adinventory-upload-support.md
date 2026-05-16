# Supporting ADInventory Database Uploads

## Executive Summary

This document outlines the work required to extend NTFSPermsUploader to accept SQLite databases created by the **ADInventory** PowerShell module (`/ADInventory`), in addition to the existing CollectNTFSPerms databases.

**Estimated Effort**: Medium (2-3 weeks development + testing)

**Key Challenges**:
1. Different database schema (10 tables vs 13 tables)
2. Different table naming convention (`AD_*` vs `app__*`)
3. Different metadata structure (`AD_CollectionInfo` vs `app__CollectionInfo`)
4. Multi-domain support with `CollectionID` foreign keys
5. Different data types (text SIDs vs binary SIDs)

**Note**: ADInventory databases will be uploaded as ZIP files (same as CollectNTFSPerms), not as raw `.db` files.

---

## Schema Comparison

### Database Overview

| Aspect | CollectNTFSPerms | ADInventory |
|--------|------------------|-------------|
| **Purpose** | NTFS ACL enumeration | Active Directory inventory |
| **Schema Version** | 1.6.0 | 3.0.0 |
| **Table Prefix** | `app__` | `AD_` |
| **Tables** | 13 data tables + lookups | 10 tables + 8 views |
| **Primary Identifier** | `InventoryID` (GUID in each row) | `CollectionID` (INT FK) + `InventoryID` |
| **Packaging** | ZIP compressed | ZIP compressed |
| **Journal Mode** | Default | WAL (Write-Ahead Logging) |

### Table Structure Comparison

#### CollectNTFSPerms Tables (Current)
```
app__SIDs              - Security principals
app__CollectionInfo    - Collection metadata
app__Disks             - Physical disks
app__Volumes           - Volumes
app__VolumeMounts      - Mount points
app__VolumeExtents     - Volume extents
app__Partitions        - Partitions
app__Folders           - Folder entries (main data)
app__ACL               - Access Control Lists
app__ACE               - Access Control Entries
app__SMBShares         - SMB shares
app__SMBShareAccess    - Share permissions
app__EventLog          - Event log
```

#### ADInventory SQLite Tables
```
AD_CollectionInfo           - Collection metadata (per domain)
AD_Object                   - Users, groups, computers, contacts
AD_GroupMembership          - Direct group memberships
AD_ForeignSecurityPrincipal - Cross-domain principals
AD_Trust                    - Domain trust relationships
AD_Domain                   - Domain information
AD_Forest                   - Forest information
AD_Log                      - Audit trail
AD_ExecutionTime            - Performance metrics
Schema_Version              - Schema tracking
```

> **Note:** `AD_GroupMember_Flat` (recursive/flattened memberships) is NOT collected in SQLite.
> It is computed in SQL Server using a recursive CTE during the transfer process.

### Metadata Structure Differences

#### CollectNTFSPerms: `app__CollectionInfo`
```sql
InventoryID          UNIQUEIDENTIFIER  -- Collection identifier
ApplicationVersion   TEXT              -- Collector version
ComputerName         TEXT              -- Source computer
CollectionDateTime   DATETIME          -- When collected
-- Single row per collection
```

#### ADInventory: `AD_CollectionInfo`
```sql
CollectionID         INTEGER PRIMARY KEY  -- Auto-increment per domain
InventoryID          TEXT                 -- Shared GUID across domains
ComputerName         TEXT                 -- Collector machine
DomainName           TEXT                 -- Individual domain name
CollectionDateTime   TEXT                 -- ISO 8601 format
Who                  TEXT                 -- Running user
StartTime            TEXT                 -- Start timestamp
EndTime              TEXT                 -- End timestamp
-- Multiple rows per collection (one per domain)
```

### Version Tracking Differences

#### CollectNTFSPerms
```sql
-- app__Version table
PropertyName = 'DBVersion'
PropertyValue = '1.6.0'
```

#### ADInventory
```sql
-- Schema_Version table
Version       TEXT PRIMARY KEY  -- '3.0.0'
AppliedDate   TEXT             -- ISO 8601
Description   TEXT             -- 'Normalized schema...'
```

---

## SQL Server Schema (Already Created)

The SQL Server database objects for ADInventory already exist in `/ADInventory/SQL/`. This significantly reduces the implementation effort.

### Schemas

Two schemas are defined:

| Schema | Purpose | File |
|--------|---------|------|
| `[ADImport]` | Staging area for imported data | `ADImport.Schema.sql` |
| `[ADData]` | Production data with constraints | `ADData.Schema.sql` |

### ADImport Schema Tables (Staging)

The staging tables have no primary keys or foreign keys for faster bulk loading:

#### ADImport.CollectionInfo
```sql
CREATE TABLE [ADImport].[CollectionInfo] (
    [CollectionID] [int] NOT NULL,
    [InventoryID] [nvarchar](50) NOT NULL,
    [ComputerName] [nvarchar](255) NOT NULL,
    [DomainName] [nvarchar](255) NOT NULL,
    [CollectionDateTime] [datetime2](7) NOT NULL,
    [Who] [nvarchar](255) NOT NULL,
    [StartTime] [datetime2](7) NOT NULL,
    [EndTime] [datetime2](7) NULL,
    [ImportDateTime] [datetime2](7) NOT NULL DEFAULT (sysutcdatetime()),
    [SourceDatabase] [nvarchar](500) NULL
)
```

#### ADImport.AD_Object
```sql
CREATE TABLE [ADImport].[AD_Object] (
    [SID_String] [nvarchar](200) NOT NULL,
    [ObjectType] [int] NOT NULL,
    [SamAccountName] [nvarchar](256) NULL,
    [DisplayName] [nvarchar](500) NULL,
    [UserPrincipalName] [nvarchar](500) NULL,
    [DomainName] [nvarchar](255) NOT NULL,
    [DistinguishedName] [nvarchar](2048) NOT NULL,
    [ObjectGUID] [nvarchar](50) NULL,
    [CanonicalName] [nvarchar](2048) NULL,
    [Description] [nvarchar](max) NULL,
    [WhenCreated] [datetime2](7) NULL,
    [WhenChanged] [datetime2](7) NULL,
    [Enabled] [bit] NULL,
    [LastLogonTimestamp] [datetime2](7) NULL,
    [PasswordLastSet] [datetime2](7) NULL,
    [AccountExpires] [datetime2](7) NULL,
    [PasswordNeverExpires] [bit] NULL,
    [GivenName] [nvarchar](256) NULL,
    [Surname] [nvarchar](256) NULL,
    [Mail] [nvarchar](500) NULL,
    [Department] [nvarchar](256) NULL,
    [Title] [nvarchar](256) NULL,
    [Manager] [nvarchar](2048) NULL,
    [EmployeeID] [nvarchar](100) NULL,
    [GroupType] [int] NULL,
    [GroupScope] [int] NULL,
    [ManagedBy] [nvarchar](2048) NULL,
    [SIDHistory] [nvarchar](max) NULL,
    [IsForeignSecurityPrincipal] [bit] NULL DEFAULT ((0)),
    [CollectionID] [int] NOT NULL
)
```

#### ADImport.AD_GroupMembership
```sql
CREATE TABLE [ADImport].[AD_GroupMembership] (
    [GroupSID] [nvarchar](200) NOT NULL,
    [MemberSID] [nvarchar](200) NOT NULL,
    [CollectionID] [int] NOT NULL
)
```

#### ADImport.AD_GroupMember_Flat (Computed, not imported)
> **Note:** This table is NOT imported from SQLite. It is populated by the
> `usp_ADInventory_TransferData` stored procedure using a recursive CTE.

```sql
CREATE TABLE [ADImport].[AD_GroupMember_Flat] (
    [GroupSID] [nvarchar](200) NOT NULL,
    [MemberSID] [nvarchar](200) NOT NULL,
    [MemberType] [int] NOT NULL,
    [NestingLevel] [int] NOT NULL,
    [PathToMember] [nvarchar](max) NULL,
    [CollectionID] [int] NOT NULL,
    [ComputedDate] [datetime2](7) NOT NULL
)
```

#### ADImport.AD_ForeignSecurityPrincipal
```sql
CREATE TABLE [ADImport].[AD_ForeignSecurityPrincipal] (
    [SID_String] [nvarchar](200) NOT NULL,
    [SourceDomainName] [nvarchar](255) NULL,
    [DistinguishedName] [nvarchar](2048) NULL,
    [IsResolved] [bit] NOT NULL DEFAULT ((0)),
    [LastResolveAttempt] [datetime2](7) NULL,
    [CollectionID] [int] NOT NULL
)
```

#### ADImport.AD_Trust
```sql
CREATE TABLE [ADImport].[AD_Trust] (
    [SourceDomain] [nvarchar](255) NOT NULL,
    [TargetDomain] [nvarchar](255) NOT NULL,
    [TrustType] [nvarchar](50) NOT NULL,
    [TrustDirection] [nvarchar](50) NOT NULL,
    [TrustAttributes] [int] NULL,
    [IsTransitive] [bit] NOT NULL,
    [FlatName] [nvarchar](50) NULL,
    [WhenCreated] [datetime2](7) NULL,
    [CollectionID] [int] NOT NULL
)
```

#### ADImport.AD_Domain
```sql
CREATE TABLE [ADImport].[AD_Domain] (
    [DomainName] [nvarchar](255) NOT NULL,
    [DomainSID] [nvarchar](200) NOT NULL,
    [DomainGUID] [nvarchar](50) NULL,
    [NetBIOSName] [nvarchar](50) NULL,
    [DistinguishedName] [nvarchar](2048) NULL,
    [ForestName] [nvarchar](255) NULL,
    [ParentDomain] [nvarchar](255) NULL,
    [DomainMode] [nvarchar](100) NULL,
    [DomainModeLevel] [int] NULL,
    [PDCEmulator] [nvarchar](255) NULL,
    [RIDMaster] [nvarchar](255) NULL,
    [InfrastructureMaster] [nvarchar](255) NULL,
    [ChildDomains] [nvarchar](max) NULL,
    [DomainControllers] [nvarchar](max) NULL,
    [ReadOnlyReplicaDirectoryServers] [nvarchar](max) NULL,
    [WhenCreated] [datetime2](7) NULL,
    [WhenChanged] [datetime2](7) NULL,
    [CollectionID] [int] NOT NULL
)
```

#### ADImport.AD_Forest
```sql
CREATE TABLE [ADImport].[AD_Forest] (
    [ForestName] [nvarchar](255) NOT NULL,
    [ForestGUID] [nvarchar](50) NULL,
    [RootDomain] [nvarchar](255) NULL,
    [ForestMode] [nvarchar](100) NULL,
    [ForestModeLevel] [int] NULL,
    [SchemaMaster] [nvarchar](255) NULL,
    [DomainNamingMaster] [nvarchar](255) NULL,
    [Domains] [nvarchar](max) NULL,
    [GlobalCatalogs] [nvarchar](max) NULL,
    [Sites] [nvarchar](max) NULL,
    [SiteLinks] [nvarchar](max) NULL,
    [SchemaVersion] [int] NULL,
    [ExchangeSchemaVersion] [int] NULL,
    [WhenCreated] [datetime2](7) NULL,
    [CollectionID] [int] NOT NULL
)
```

#### ADImport.AD_Log
```sql
CREATE TABLE [ADImport].[AD_Log] (
    [LogID] [int] NOT NULL,
    [CollectionID] [int] NOT NULL,
    [Timestamp] [datetime2](7) NOT NULL,
    [Level] [nvarchar](20) NOT NULL,
    [Category] [nvarchar](50) NOT NULL,
    [Message] [nvarchar](max) NOT NULL,
    [Context] [nvarchar](max) NULL,
    [ExceptionMessage] [nvarchar](max) NULL,
    [ExceptionType] [nvarchar](500) NULL
)
```

#### ADImport.AD_ExecutionTime
```sql
CREATE TABLE [ADImport].[AD_ExecutionTime] (
    [ExecutionID] [int] NOT NULL,
    [CollectionID] [int] NOT NULL,
    [Timestamp] [datetime2](7) NOT NULL,
    [DurationSeconds] [decimal](18, 6) NOT NULL,
    [Operation] [nvarchar](100) NOT NULL,
    [Target] [nvarchar](255) NULL,
    [Domain] [nvarchar](255) NULL,
    [RecordCount] [int] NULL,
    [RecordsPerSec] [decimal](18, 2) NULL,
    [Details] [nvarchar](max) NULL
)
```

### ADData Schema Tables (Production)

Production tables include primary keys, foreign keys with CASCADE DELETE, and constraints:

#### Key Differences from ADImport
| Feature | ADImport | ADData |
|---------|----------|--------|
| Primary Keys | None | Yes (composite keys) |
| Foreign Keys | None | Yes (CASCADE DELETE) |
| Indexes | None | Clustered on PKs |
| Purpose | Fast bulk insert | Data integrity |

#### Primary Key Structures

| Table | Primary Key |
|-------|-------------|
| CollectionInfo | `(CollectionID)` |
| AD_Object | `(SID_String, CollectionID)` |
| AD_GroupMembership | `(GroupSID, MemberSID, CollectionID)` |
| AD_GroupMember_Flat | `(GroupSID, MemberSID, CollectionID)` |
| AD_ForeignSecurityPrincipal | `(SID_String, CollectionID)` |
| AD_Trust | `(SourceDomain, TargetDomain, CollectionID)` |
| AD_Domain | `(DomainSID, CollectionID)` |
| AD_Forest | `(ForestName, CollectionID)` |
| AD_Log | `(LogID, CollectionID)` |
| AD_ExecutionTime | `(ExecutionID, CollectionID)` |

#### Additional Production Table: AD_FlattenStats
```sql
CREATE TABLE [ADData].[AD_FlattenStats] (
    [FlattenStatsID] [int] IDENTITY(1,1) NOT NULL,
    [CollectionID] [int] NULL,
    [InventoryID] [nvarchar](50) NULL,
    [ComputedDate] [datetime2](7) NOT NULL,
    [DurationSeconds] [decimal](10, 2) NOT NULL,
    [TotalMemberships] [int] NOT NULL,
    [DirectMemberships] [int] NOT NULL,
    [NestedMemberships] [int] NOT NULL,
    [UniqueGroups] [int] NOT NULL,
    [UniqueMembers] [int] NOT NULL,
    [MaxNestingLevel] [int] NOT NULL,
    [UserCount] [int] NULL,
    [GroupCount] [int] NULL,
    [ComputerCount] [int] NULL,
    CONSTRAINT [PK_ADData_FlattenStats] PRIMARY KEY CLUSTERED ([FlattenStatsID])
)
```

### Stored Procedure: usp_ADInventory_TransferData

A comprehensive stored procedure exists to transfer data from staging to production:

**Location**: `dbo.usp_ADInventory_TransferData.StoredProcedure.sql`

**Parameters**:
```sql
@CollectionID INT = NULL,           -- Specific collection or NULL for all
@DeleteFromStaging BIT = 1,         -- Delete from staging after transfer
@ComputeFlatMemberships BIT = 1,    -- Compute recursive group memberships
@MaxRecursionDepth INT = 50         -- Max depth for membership calculation
```

**Key Features**:
1. **Transactional**: All-or-nothing transfer with rollback on error
2. **Idempotent**: Uses `NOT EXISTS` to skip already-transferred records
3. **Flat Membership Computation**: Uses recursive CTE to flatten group memberships
4. **Statistics Tracking**: Records flatten stats to `AD_FlattenStats`
5. **Staging Cleanup**: Optionally deletes from staging after successful transfer

**Transfer Order**:
1. CollectionInfo
2. AD_Object
3. AD_GroupMembership
4. AD_ForeignSecurityPrincipal
5. AD_Trust
6. AD_Domain
7. AD_Forest
8. AD_Log
9. AD_ExecutionTime
10. Compute AD_GroupMember_Flat (if enabled)

### Views

#### Reporting Views
| View | Purpose |
|------|---------|
| `v_CollectionSummary` | Collection statistics with object counts |
| `v_AD_Object` | Objects with InventoryID from CollectionInfo |
| `v_AD_Users` | Filtered view for users (ObjectType=1) |
| `v_AD_Groups` | Filtered view for groups (ObjectType=2) |
| `v_AD_Computers` | Filtered view for computers (ObjectType=3) |
| `v_AD_GroupMembership` | Memberships with group/member names |
| `v_AD_GroupMember_Flat` | Flattened memberships with path names |
| `v_AD_Domain` | Domain info with InventoryID |
| `v_AD_Forest` | Forest info with InventoryID |
| `v_AD_Trust` | Trust relationships with InventoryID |
| `v_AD_ForeignSecurityPrincipal` | FSPs with InventoryID |
| `v_AD_Log` | Logs with InventoryID |
| `v_AD_ExecutionTime` | Execution times with InventoryID |

#### Diagnostic Views
| View | Purpose |
|------|---------|
| `v_DiagValidationSummary` | Overall validation status per inventory |
| `v_DiagObjectsNullSID` | Objects with NULL SID (errors) |
| `v_DiagOrphanedMemberships` | Memberships without matching objects |
| `v_DiagUnresolvedFSPs` | Foreign Security Principals not resolved |
| `v_DiagSkippedDomains` | Domains in collection but missing AD_Domain record |

### User-Defined Functions

#### fn_ConvertSIDPathToNames
Converts SID paths (e.g., `S-1-5-21-... -> S-1-5-21-...`) to friendly names:
```sql
ADData.fn_ConvertSIDPathToNames(@SIDPath NVARCHAR(MAX), @CollectionID UNIQUEIDENTIFIER)
-- Returns: 'Domain Admins -> Enterprise Admins -> John Smith'
```

---

## Required Changes

### 1. Upload Type Detection

**New Component**: `UploadTypeDetector`

```csharp
public enum UploadType
{
    Unknown,
    NTFSPermissions,    // CollectNTFSPerms database
    ADInventory         // ADInventory database
}

public interface IUploadTypeDetector
{
    Task<UploadType> DetectTypeAsync(string sqlitePath, CancellationToken ct);
}
```

**Detection Logic**:
1. Check for `app__Version` table → `NTFSPermissions`
2. Check for `Schema_Version` table → `ADInventory`
3. Verify expected tables exist for detected type

**File**: `NTFSPermsUploader.Core/Validation/UploadTypeDetector.cs` (NEW)

---

### 2. DatabaseValidator Refactoring

**Current Hardcoding**:
```csharp
// Line 116: Hardcoded table name
var hasVersionTable = await TableExistsAsync(connection, "app__Version", ct);
```

**Required Changes**:

```csharp
public interface IDatabaseValidator
{
    Task<DatabaseValidationResult> ValidateAsync(
        string sqlitePath,
        UploadType uploadType,           // NEW: Type-aware validation
        string requiredDbVersion,
        string requiredAppVersion,
        CancellationToken ct);
}
```

**Type-Specific Validation**:

| Validation | NTFSPermissions | ADInventory |
|------------|-----------------|-------------|
| Version Table | `app__Version` | `Schema_Version` |
| Version Column | `PropertyValue WHERE PropertyName='DBVersion'` | `Version` (single column) |
| Metadata Table | `app__CollectionInfo` | `AD_CollectionInfo` |
| Metadata Columns | `InventoryID, ApplicationVersion, ComputerName, CollectionDateTime` | `CollectionID, InventoryID, DomainName, ComputerName, Who, StartTime, EndTime` |

**File**: `NTFSPermsUploader.Core/Validation/DatabaseValidator.cs`

---

### 3. Table Mapping System Extension

**Current Design**: Static `TableMappings.AllMappings` list

**Required Changes**:

```csharp
public static class TableMappings
{
    public static IReadOnlyList<TableMapping> NTFSPermissionsMappings { get; }
    public static IReadOnlyList<TableMapping> ADInventoryMappings { get; }

    public static IReadOnlyList<TableMapping> GetMappings(UploadType type) =>
        type switch
        {
            UploadType.NTFSPermissions => NTFSPermissionsMappings,
            UploadType.ADInventory => ADInventoryMappings,
            _ => throw new ArgumentException($"Unknown upload type: {type}")
        };
}
```

#### ADInventory Table Mappings

```csharp
new List<TableMapping>
{
    // SQLiteTable, MssqlTable, Schema, DisplayName, ImportOrder, hasInventoryId
    new("AD_CollectionInfo", "CollectionInfo", "ADImport", "Collection Info", 1, hasInventoryId: true),
    new("AD_Object", "AD_Object", "ADImport", "AD Objects", 2, hasInventoryId: false),
    new("AD_GroupMembership", "AD_GroupMembership", "ADImport", "Group Memberships", 3, hasInventoryId: false),
    new("AD_ForeignSecurityPrincipal", "AD_ForeignSecurityPrincipal", "ADImport", "Foreign Principals", 4, hasInventoryId: false),
    new("AD_Trust", "AD_Trust", "ADImport", "Domain Trusts", 5, hasInventoryId: false),
    new("AD_Domain", "AD_Domain", "ADImport", "Domains", 6, hasInventoryId: false),
    new("AD_Forest", "AD_Forest", "ADImport", "Forests", 7, hasInventoryId: false),
    new("AD_Log", "AD_Log", "ADImport", "Audit Log", 8, hasInventoryId: false, allowMigrationDelta: true),
    new("AD_ExecutionTime", "AD_ExecutionTime", "ADImport", "Execution Times", 9, hasInventoryId: false),
};
```

**Note**: ADInventory tables do NOT use a prefix - the table names in SQLite are already `AD_*`.

**File**: `NTFSPermsUploader.Core/Import/TableMapping.cs`

---

### 4. SqliteImporter Refactoring

**Current Hardcoding Issues**:

#### Issue 1: Table Name Prefix
```csharp
// TableMapping.cs:67 - Hardcoded app__ prefix
public string GetSqliteTableName() => $"app__{SqliteTable}";
```

**Fix**: Add prefix to TableMapping class or use direct table names:
```csharp
public class TableMapping
{
    public string SqliteTableName { get; }  // Direct name or with prefix
    public string GetSqliteTableName() => SqliteTableName;
}
```

#### Issue 2: Value Conversion (ConvertValue method)

**Current NTFS-Specific Conversions**:
```csharp
// SID string to binary (Windows-specific)
if (column.Name.Equals("Sid"))
    return new SecurityIdentifier(sidString).GetBinaryForm();

// FileSystemRights bit preservation
if (column.Name.Contains("Mask") || Contains("Rights") || Contains("Flags"))
    return unchecked((int)int64Value);
```

**ADInventory Requirements**:
- SID stored as `SID_String` (TEXT) - **no conversion needed**
- No FileSystemRights columns
- JSON columns (`SIDHistory`, `PathToMember`, `Context`) - pass through as TEXT
- GUID columns (`ObjectGUID`) - keep as TEXT

**Solution**: Type-based converter strategy

```csharp
public interface IValueConverter
{
    object? Convert(object value, ColumnInfo column);
}

public class NTFSPermissionsValueConverter : IValueConverter { ... }
public class ADInventoryValueConverter : IValueConverter { ... }  // Mostly pass-through
```

**File**: `NTFSPermsUploader.Core/Import/SqliteImporter.cs`

---

### 5. Version Service Extension

**Current Hardcoding**:
```csharp
// VersionService.cs:59
versions.TryGetValue("CollectNTFSPerm", out var version)
```

**Required Changes**:
```csharp
public async Task<VersionRequirements> GetRequiredVersionsAsync(
    UploadType uploadType,
    CancellationToken ct)
{
    var schemaName = uploadType switch
    {
        UploadType.NTFSPermissions => "CollectNTFSPerm",
        UploadType.ADInventory => "ADInventory",
        _ => throw new ArgumentException()
    };

    // Query fsapp.SchemaVersion for the appropriate schema
}
```

**New fsapp.SchemaVersion Row**:
```sql
INSERT INTO fsapp.SchemaVersion (SchemaName, Version)
VALUES ('ADInventory', '3.0.0');
```

**File**: `NTFSPermsUploader.Core/Services/VersionService.cs`

---

### 6. Migration Service Changes

**Current**: Calls `dbo.usp_MigrateCollection` for NTFS data

**Required**: Call `dbo.usp_ADInventory_TransferData` for ADInventory data

```csharp
public async Task<MigrationResult> MigrateAsync(
    Guid uploadId,
    UploadType uploadType,
    CancellationToken ct)
{
    var procName = uploadType switch
    {
        UploadType.NTFSPermissions => "dbo.usp_MigrateCollection",
        UploadType.ADInventory => "dbo.usp_ADInventory_TransferData",
        _ => throw new ArgumentException()
    };

    // Execute appropriate stored procedure
}
```

**File**: `NTFSPermsUploader.Core/Services/MigrationService.cs`

---

### 7. Upload Service Orchestration

**Changes to UploadService.ProcessUploadAsync()**:

```csharp
public async Task<ProcessResult> ProcessUploadAsync(...)
{
    // 1. Extract from ZIP (same as current)
    var sqlitePath = await _zipValidator.ValidateAndExtractAsync(filePath, ct);

    // 2. Detect upload type (NEW)
    var uploadType = await _uploadTypeDetector.DetectTypeAsync(sqlitePath, ct);

    // 3. Get version requirements for this type
    var versionReqs = await _versionService.GetRequiredVersionsAsync(uploadType, ct);

    // 4. Validate database with type-specific logic
    var validationResult = await _dbValidator.ValidateAsync(
        sqlitePath, uploadType, versionReqs.DbVersion, versionReqs.AppVersion, ct);

    // 5. Queue import job with upload type
    await _importJob.EnqueueAsync(uploadId, sqlitePath, uploadType, ct);
}
```

**File**: `NTFSPermsUploader.Web/Services/UploadService.cs`

---

### 8. ImportJob Changes

**Add Upload Type to Job Parameters**:

```csharp
public interface IImportJob
{
    [JobDisplayName("Import {1}: {0}")]  // Shows "Import ADInventory: {guid}"
    Task ExecuteAsync(
        Guid uploadId,
        string sqlitePath,
        UploadType uploadType,           // NEW
        CancellationToken ct);
}
```

**File**: `NTFSPermsUploader.Jobs/ImportJob.cs`

---

### 9. UI Changes

**Status Page Updates**:
- Display upload type (NTFS Permissions / AD Inventory)
- Show type-specific statistics

**Upload Page Updates**:
- Display guidance for each upload type

```html
<!-- Upload type indicator -->
<div class="upload-types">
    <div class="upload-type">
        <h4>NTFS Permissions</h4>
        <p>ZIP files from CollectNTFSPerms</p>
    </div>
    <div class="upload-type">
        <h4>AD Inventory</h4>
        <p>ZIP files from ADInventory module</p>
    </div>
</div>
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Create `UploadTypeDetector` class
- [ ] Refactor `TableMapping` to support multiple schemas
- [ ] Create ADInventory table mappings
- [ ] Deploy SQL Server schemas (already exist in /ADInventory/SQL)

### Phase 2: Import Pipeline (Week 1-2)
- [ ] Create `ADInventoryValueConverter` class
- [ ] Refactor `SqliteImporter` for converter injection
- [ ] Update `ImportJob` to pass upload type
- [ ] Extend `VersionService` for ADInventory version checking
- [ ] Refactor `DatabaseValidator` for type-specific validation

### Phase 3: Migration & Integration (Week 2)
- [ ] Update `MigrationService` to call correct stored procedure
- [ ] Update `UploadService` orchestration
- [ ] Update progress tracking for AD-specific tables

### Phase 4: UI & Testing (Week 2-3)
- [ ] Update UI to display upload types
- [ ] Add configuration options in appsettings.json
- [ ] Unit tests for type detection
- [ ] Integration tests for AD import
- [ ] End-to-end upload tests
- [ ] Performance testing with large AD databases

---

## Configuration Changes

### appsettings.json Additions

```json
{
  "TableMappings": {
    "NTFSPermissions": {
      "Prefix": "app__",
      "Schema": "fssimport"
    },
    "ADInventory": {
      "Prefix": "",
      "Schema": "ADImport"
    }
  },

  "Versions": {
    "NTFSPermissions": {
      "MinimumDbVersion": "1.5.0",
      "MinimumAppVersion": "2.0.0"
    },
    "ADInventory": {
      "MinimumDbVersion": "3.0.0",
      "MinimumAppVersion": "1.0.0"
    }
  }
}
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Schema changes in ADInventory | Medium | High | Version gating, schema validation |
| Performance with large AD datasets | Medium | Medium | Batch size tuning |
| Multi-domain complexity | Low | Medium | Test with multi-domain collections |
| Breaking existing NTFS imports | Low | High | Extensive regression testing |
| WAL mode conflicts | Low | Low | Handle checkpoint on close |

---

## Dependencies

### SQL Server Requirements (Already Met)
The following objects already exist in `/ADInventory/SQL/`:
- ✅ Schema: `[ADImport]`
- ✅ Schema: `[ADData]`
- ✅ 10 staging tables in `ADImport`
- ✅ 11 production tables in `ADData`
- ✅ Stored procedure: `dbo.usp_ADInventory_TransferData`
- ✅ 13 views for reporting
- ✅ 5 diagnostic views
- ✅ User-defined function: `fn_ConvertSIDPathToNames`

### Remaining SQL Server Tasks
- [ ] Add version entry to `fsapp.SchemaVersion`
- [ ] Deploy SQL scripts to target database

---

## Files to Create/Modify

### New Files
```
NTFSPermsUploader.Core/
  Validation/
    UploadTypeDetector.cs           (NEW)
  Import/
    IValueConverter.cs              (NEW)
    NTFSPermissionsValueConverter.cs (NEW - extract from SqliteImporter)
    ADInventoryValueConverter.cs    (NEW)
```

### Modified Files
```
NTFSPermsUploader.Core/
  Configuration/AppSettings.cs      - Add UploadType settings
  Validation/DatabaseValidator.cs   - Type-specific validation
  Import/TableMapping.cs            - Add prefix, multiple mappings
  Import/SqliteImporter.cs          - Inject value converter
  Services/VersionService.cs        - Multi-schema version lookup
  Services/MigrationService.cs      - Type-specific stored procedure

NTFSPermsUploader.Jobs/
  ImportJob.cs                      - Add uploadType parameter

NTFSPermsUploader.Web/
  Services/UploadService.cs         - Type detection orchestration
  Views/Status/*.cshtml             - Display upload type
```

---

## Conclusion

Supporting ADInventory uploads requires moderate refactoring to make the system type-aware. The significant advantage is that **all SQL Server database objects already exist** in `/ADInventory/SQL/`, including the transfer stored procedure with recursive group membership computation.

**Key Implementation Points**:
1. **Upload Type Detection**: Simple table existence check
2. **Table Mappings**: Different prefix (`AD_` vs `app__`) and target schema (`ADImport` vs `fssimport`)
3. **Value Conversion**: ADInventory is simpler (no SID binary conversion needed)
4. **Migration**: Use existing `usp_ADInventory_TransferData` stored procedure

**Recommended Approach**: Implement as a pluggable architecture using strategy pattern for:
- Table mappings (per upload type)
- Value conversion (per upload type)
- Version validation (per upload type)
- Database validation (per upload type)
- Migration procedure (per upload type)

This will also make it easier to add future upload types without major refactoring.
