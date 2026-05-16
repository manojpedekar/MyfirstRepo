
#include "../database/database.h"

// Database schema version
const char* DB_SCHEMA_VERSION = "1.6.0";   

/*
	Version History:
	1.0.0 --> 1.0.1
	    - Added Disk and Volume tables
	    - Added SMBShares and SMBShareAccess tables
	    - Added EventLog table for logging events
	    - Added Version table for storing version information
	
    1.0.1 --> 1.0.2
	    - Added ACE table for Access Control Entries
	    - Added Folders table for folder information
	    - Added SIDs table for security identifiers
	
    1.0.2 --> 1.0.3
	    - Improved error handling in database operations
	    - Optimized batch insert operations
	    - Updated schema to include new fields in existing tables

    1.0.3 --> 1.0.4
        - Added Lookup tables
		    - lkp__PropagationFlags
		    - lkp__ShareAvailabilityTypes
		    - lkp__ShareCachingModes
		    - lkp__ShareFolderEnumerationModes
		    - lkp__ShareLeasingModes
            - lkp__InheritanceFlags
	    - Split Table and Data statement into different variables

	1.0.4 --> 1.0.5
	    - Changed AccountName and AccountType in app__SIDs table to be nullable

    1.0.5 --> 1.0.6
        - Removed FK constraints from all tables for development purposes
        - Removed FileSystemRights from app__ACE table
		- Added lkp__FileSystemRights table for file system rights
		- Added initial entries to lkp__FileSystemRights
		- Added view vw__ACEWithPermissions to show ACEs with permissions
        - Added table lkp__AceTypes and data
		- Updated lkp__SIDs with more common SIDs, removed unused SIDs
		- Correct lkp__PropagationFlags to include all combinations of flags with actual values

	1.0.6 --> 1.0.7
		- Added lkp__AceTypes table and initial data
		- Added view vw__ACE to show ACEs with permissions and inheritance flags
		- Updated CREATE_SCHEMA_TABLES_SQL to include new tables and views

	1.0.7 --> 1.0.8
		- Added lkp__DriveTypes and data
		- Added app__VolumeMounts table to track volume mount points
		- Added vw__Volumes view to show volume details with drive type
		- Updated app_smbShares table to include new fields for security descriptor, current users, and branch cache
		- Updated app__SMBShareAccess table to include AccessMask and IsInherited fields
    
    1.0.8 --> 1.0.9
        - Added lkp__ShareFolderEnumerationModes and data
        - Added lkp__ShareLeasingModes and data
        - Added lkp__ShareCachingModes and data
        - Updated app__SMBShares to include new fields for enumeration mode, caching mode, and leasing mode
        - Added app__VolumeExtents table to track volume extents
        - Added app__Disks table to track disks
        - Updated app__Volumes to include DiskID
        - Updated app__SMBShares to include VolumeID
        
    1.0.9 --> 1.1.0
        - Refactored disk, volume, extent, and partition tables
        - Added app__Partitions table to track disk partitions
        - Updated foreign key relationships between disk/volume/partition tables
        - Added views for disk, volume, and partition relationships
        - Made DiskID nullable in app__Volumes to support non-disk volumes
		- Updated app__VolumeMounts to support multiple mount points per volume
		- Updated create statements to create if not exists

	1.1.0 --> 1.1.1
		- Added performance indexes for common query patterns:
		  * idx_ACE_LocalFolderID - for ACE to folder joins
		  * idx_ACE_IdentitySID - for ACE SID lookups
		  * idx_ACL_LocalFolderID - for ACL to folder joins
		  * idx_Folders_Path - for folder path lookups
		  * idx_Partitions_DiskID - for partition queries by disk
		  * idx_VolumeExtents_DiskID - for extent queries by disk
		  * idx_VolumeExtents_VolumeID - for extent queries by volume
		  * idx_EventLog_Severity - for event log filtering by severity
		  * idx_EventLog_Timestamp - for event log chronological queries

	1.1.1 --> 1.1.2
		- Optimized lookup tables with WITHOUT ROWID for better performance:
		  * lkp__PropagationFlags
		  * lkp__InheritanceFlags
		  * lkp__FileSystemRights
		  * lkp__AceTypes
		  * lkp__DriveTypes
		- WITHOUT ROWID tables reduce storage and improve query speed for small tables
		  with simple primary keys that are frequently accessed by PK

	1.1.2 --> 1.2.0
		- Enhanced app__SIDs table with SID resolution tracking:
		  * Added IsResolved (BOOLEAN) - tracks whether SID lookup succeeded during collection
		  * Added ResolutionSource (TEXT) - tracks where the account name came from
		    (Local, Domain, WellKnown, Failed)
		- These fields support troubleshooting failed SID resolutions and distinguishing
		  between different resolution sources for security analysis

	1.2.0 --> 1.3.0
		- Enhanced app__Folders table with hierarchical and volume relationship tracking:
		  * Added ParentFolderID (INTEGER) - enables folder hierarchy reconstruction
		  * Added VolumeID (INTEGER) - links folders to their containing volumes
		  * Added foreign key constraints for data integrity
		  * Added indexes idx_Folders_ParentID and idx_Folders_VolumeID for query performance
		- Fixed vw__Volumes view:
		  * Removed references to non-existent columns (Info, LastCheckedTime)
		  * View now only references actual columns in app__Volumes table
		- These changes enable recursive folder tree queries, volume-level analysis,
		  and proper folder-to-volume relationship tracking

	1.3.0 --> 1.4.0
		- PHASE 1 - Critical Fixes:
		  * Removed duplicate app__VolumeMounts table definition (was defined twice)

		- PHASE 2 - Referential Integrity (High Priority):
		  * Added foreign key constraints to app__ACL table:
		    - LocalFolderID references app__Folders
		    - Owner references app__SIDs
		    - Group references app__SIDs
		  * Added foreign key constraints to app__ACE table:
		    - LocalFolderID references app__Folders
		    - IdentitySID references app__SIDs
		    - InheritedFromLocalID references app__Folders
		  * Added foreign key constraint to app__SMBShares table:
		    - Path references app__Folders.LocalFolderID
		  * Added foreign key constraint to app__SMBShareAccess table:
		    - Trustee references app__SIDs (see refactoring below)

		- PHASE 2 - Performance Optimization (High Priority):
		  * Added 13 new performance indexes:
		    - idx_ACE_InheritedFrom - for ACE inheritance lookups
		    - idx_ACL_Owner, idx_ACL_Group - for ACL SID lookups
		    - idx_SIDs_AccountName - for SID name searches
		    - idx_SIDs_IsResolved - for tracking unresolved SIDs
		    - idx_SMBShares_Path, idx_SMBShares_VolumeID, idx_SMBShares_Name - for share queries
		    - idx_SMBShareAccess_ShareID, idx_SMBShareAccess_Trustee - for share permission queries
		    - idx_VolumeMounts_MountPoint - for mount point lookups
		    - idx_EventLog_Source, idx_EventLog_InventoryID - for event log queries

		- PHASE 3 - Data Model Improvements (Medium Priority):
		  * Refactored app__SMBShareAccess.Trustee from TEXT to INTEGER:
		    - Changed Trustee column from SID string to SidID foreign key
		    - Ensures consistency with other tables that reference SIDs
		    - Eliminates duplicate SID strings in database
		    - Updated SMBShare.cpp to use GetOrCreateSidId() before inserting share access
		  * Added CHECK constraints for data validation:
		    - app__Disks.Size >= 0
		    - app__Volumes.Size >= 0
		    - app__Volumes.FreeSpace >= 0 AND FreeSpace <= Size
		    - app__Partitions.StartOffset >= 0
		    - app__Partitions.LengthBytes > 0
		    - app__SMBShares.MaximumAllowed IS NULL OR MaximumAllowed > 0
		  * Improved column documentation:
		    - app__SMBShares.Path now clearly documented as FK to app__Folders
		    - app__SMBShareAccess.Trustee now documented as SidID from app__SIDs

		- These changes significantly improve:
		  * Data integrity through foreign key constraints
		  * Query performance through comprehensive indexing
		  * Data consistency through CHECK constraints
		  * Code maintainability through better documentation
		  * Storage efficiency through normalized SID references

	1.4.0 --> 1.4.1
		- Added new views for Windows Disk Management parity:
		  * vw__DiskPartitionLayout - Shows disk → partitions → volumes with mount points
		    - Ordered by disk then by partition offset
		    - Includes partition and volume size calculations
		    - Shows mount points for each partition's volume
		    - Calculates unallocated space after each partition
		    - Percentage of disk for each partition
		    - Volume percent free
		  * vw__VolumeDiskMap - Shows volume with its backing disk(s)
		    - Includes layout type detection (Simple/Spanned/Striped)
		    - Shows primary disk and all associated disks
		    - Number of extents and disks per volume
		    - Total extent size calculations

		- Enhanced existing views:
		  * vw__PartitionDetails - Added:
		    - DiskModel, DiskSize columns
		    - PercentOfDisk calculation
		    - VolumeSize, VolumeFreeSpace columns
		    - VolumePercentFree calculation
		    - MountPoints aggregated from app__VolumeMounts
		  * vw__VolumeFull - Added:
		    - DiskID, DiskDeviceID, DiskModel columns
		    - PercentFree calculation
		    - LayoutType field (Simple/Spanned/Unknown based on extent count)

		- These views provide equivalent information to Windows Disk Management:
		  * Upper pane (volume list) → vw__VolumeFull, vw__VolumeDiskMap
		  * Lower pane (graphical disk layout) → vw__DiskPartitionLayout
		  * Partition properties → vw__PartitionDetails
		  * Volume properties → vw__VolumeFull, vw__VolumeDiskMap

	1.4.1 --> 1.5.0
		- Enhanced app__Folders table with timestamp and attribute tracking:
		  * Added CreationTime (TEXT) - folder creation timestamp in ISO 8601 format
		  * Added LastWriteTime (TEXT) - folder last modification timestamp
		  * Added LastAccessTime (TEXT) - folder last access timestamp
		  * Added Attributes (INTEGER) - Windows file attributes bitmask
		- These fields enable temporal analysis, change tracking, and attribute-based
		  filtering for security and compliance auditing
		- Updated InsertFolderBatch and related functions to capture folder metadata
		  using GetFileAttributesExW during folder enumeration
		- Added vw__FolderAttributes view:
		  * Expands Attributes bitmask into individual boolean columns
		  * Includes 21 attribute flags (IsReadOnly, IsHidden, IsSystem, IsEncrypted, etc.)
		  * Includes convenience columns for common attribute combinations
		  * Simplifies queries without requiring bitwise operations

	1.5.0 --> 1.6.0
		- Removed problematic foreign key constraints for improved data integrity:
		  * Removed FK constraint from app__SMBShares(InventoryID, VolumeID) to app__Volumes
		    - SMB shares often point to non-volume paths (DFS, cluster, remote, administrative)
		    - Frequently resulted in VolumeID = 0 or NULL entries that violated FK
		    - FK provided no practical referential safety and only caused import failures
		  * Removed FK constraint from app__Partitions(InventoryID, VolID) to app__Volumes
		    - Windows does not guarantee consistent VolID → Partition mapping
		    - GPT/MBR data does not always correlate 1:1 with Windows VolumeID
		    - Logical volumes (Storage Spaces, clustered volumes) often lack matching volume records
		    - Many legitimate system configurations violate this constraint
		  * NOTE: app__SMBShares(InventoryID, Path) to app__Folders FK was never enforced in SQLite
		    - MS SQL schema had this FK which caused import failures
		    - SMB shares often reference paths not yet enumerated or outside scan scope
		    - Removed from MS SQL schema for consistency with SQLite
		- VolumeID and Path columns retained for reference but no longer enforce referential integrity
		- These changes resolve PRAGMA foreign_key_check violations and improve import reliability
*/


// SQL schema for the database
// Split into two parts to avoid MSVC 16KB string literal limit
const char* CREATE_SCHEMA_TABLES_SQL_PART1 = R"(
CREATE TABLE IF NOT EXISTS "app__CollectionInfo" (
    "InventoryID" TEXT,
    "ComputerName" TEXT NOT NULL,
    "DomainName" TEXT NOT NULL,
    "CollectionDateTime" TEXT NOT NULL,
    "ApplicationVersion" TEXT NOT NULL,
    "ApplicationBuild" TEXT NOT NULL,
    "IsAdmin" BOOLEAN NOT NULL,
    "Who" TEXT NOT NULL,
    "HardwareConcurrency" INTEGER NOT NULL,
    "ThreadCount" INTEGER NOT NULL,
    "StartTime" TEXT NOT NULL,
    "EndTime" TEXT,
    "TotalRuntime" INTEGER,
    "FoldersProcessed" INTEGER,
    "FoldersWithErrors" INTEGER,
    "PeakQueueSize" INTEGER,
    "MemoryUsageMB" INTEGER,
    "OutputPath" TEXT,
    "ScanPath" TEXT NOT NULL,
    "RemoteComputer" BOOLEAN NOT NULL DEFAULT 0,
    "ExplicitOnly" BOOLEAN NOT NULL DEFAULT 0,
    PRIMARY KEY("InventoryID","ComputerName")
);

CREATE TABLE IF NOT EXISTS app__Folders (
    InventoryID TEXT NOT NULL,
    LocalFolderID INTEGER NOT NULL,
    ParentFolderID INTEGER,
    Path TEXT NOT NULL,
    VolumeID INTEGER,
    CreationTime TEXT,
    LastWriteTime TEXT,
    LastAccessTime TEXT,
    Attributes INTEGER,
    PRIMARY KEY (InventoryID, LocalFolderID),
    FOREIGN KEY (InventoryID, ParentFolderID)
        REFERENCES app__Folders(InventoryID, LocalFolderID),
    FOREIGN KEY (InventoryID, VolumeID)
        REFERENCES app__Volumes(InventoryID, VolumeID)
);

CREATE TABLE IF NOT EXISTS "app__SIDs" (
	"SidID" INTEGER PRIMARY KEY,
    "InventoryID" TEXT NOT NULL,
	"Sid" TEXT NOT NULL,
	"AccountName" TEXT,
	"AccountType" TEXT CHECK("AccountType" IS NULL OR "AccountType" IN ('User','Group','Other')),
	"Description" TEXT,
	"IsResolved" BOOLEAN NOT NULL DEFAULT 0,
	"ResolutionSource" TEXT CHECK("ResolutionSource" IS NULL OR "ResolutionSource" IN ('Local','Domain','WellKnown','Failed'))
);

CREATE UNIQUE INDEX idx_appSIDs_inv_sid ON app__SIDs(InventoryID, Sid);

CREATE TABLE IF NOT EXISTS "app__ACL" (
    "InventoryID" TEXT NOT NULL,
    "LocalACLID" INTEGER NOT NULL,
    "LocalFolderID" INTEGER NOT NULL,
    "Owner" INTEGER,
    "Group" INTEGER,
    "AreAccessRulesProtected" BOOLEAN NOT NULL,
    "AreAuditRulesProtected" BOOLEAN NOT NULL,
    "AreAccessRulesCanonical" BOOLEAN NOT NULL,
    "AreAuditRulesCanonical" BOOLEAN NOT NULL,
    PRIMARY KEY("InventoryID","LocalACLID"),
    FOREIGN KEY (InventoryID, LocalFolderID)
        REFERENCES app__Folders(InventoryID, LocalFolderID),
    FOREIGN KEY (Owner)
        REFERENCES app__SIDs(SidID),
    FOREIGN KEY ("Group")
        REFERENCES app__SIDs(SidID)
);

CREATE TABLE IF NOT EXISTS app__ACE (
    InventoryID TEXT NOT NULL,
    LocalACEID INTEGER NOT NULL,
    LocalFolderID INTEGER NOT NULL,
    FileSystemRightsMask INTEGER NOT NULL,
    AccessControlType INTEGER NOT NULL,
    IdentitySID INTEGER NOT NULL,
    IsInherited BOOLEAN NOT NULL,
    InheritanceFlags INTEGER NOT NULL,
    PropagationFlags INTEGER NOT NULL,
    InheritedFromLocalID INTEGER,
    PRIMARY KEY (InventoryID, LocalACEID),
    FOREIGN KEY (InventoryID, LocalFolderID)
        REFERENCES app__Folders(InventoryID, LocalFolderID),
    FOREIGN KEY (IdentitySID)
        REFERENCES app__SIDs(SidID),
    FOREIGN KEY (InventoryID, InheritedFromLocalID)
        REFERENCES app__Folders(InventoryID, LocalFolderID)
);

CREATE TABLE IF NOT EXISTS app__Disks (
    InventoryID     TEXT    NOT NULL,
    DiskID          INTEGER NOT NULL,
    DeviceID        TEXT    NOT NULL,
    Model           TEXT,
    InterfaceType   TEXT,
    Size            BIGINT  NOT NULL CHECK (Size >= 0),
    PartitionStyle  TEXT,
    IsBoot          BOOLEAN NOT NULL,
    IsSystem        BOOLEAN NOT NULL,
    IsReadOnly      BOOLEAN NOT NULL,
    Status          TEXT    NOT NULL,
    PRIMARY KEY (InventoryID, DiskID)
);

CREATE TABLE IF NOT EXISTS app__Volumes (
    InventoryID        TEXT    NOT NULL,
    VolumeID           INTEGER NOT NULL,
    DiskID             INTEGER NULL,
    Label              TEXT    NULL,
    FileSystem         TEXT    NULL,
    Size               BIGINT  NOT NULL CHECK (Size >= 0),
    FreeSpace          BIGINT  NOT NULL CHECK (FreeSpace >= 0 AND FreeSpace <= Size),
    IsSystem           BOOLEAN NOT NULL,
    IsReadOnly         BOOLEAN NOT NULL,
    Status             TEXT    NULL,
    UniqueID           TEXT    NULL,
    AllocationUnitSize BIGINT  NULL,
    DriveType          INTEGER NULL,
    IsEncrypted        BOOLEAN NOT NULL DEFAULT 0,
    IsCompressed       BOOLEAN NOT NULL DEFAULT 0,
    ShadowCopyEnabled  BOOLEAN NOT NULL DEFAULT 0,
    ShadowCopyStorageMax BIGINT NULL,
    PRIMARY KEY (InventoryID, VolumeID),
    FOREIGN KEY (InventoryID, DiskID)
        REFERENCES app__Disks (InventoryID, DiskID),
    FOREIGN KEY (DriveType)
        REFERENCES lkp__DriveTypes (DriveType)
);

CREATE TABLE IF NOT EXISTS app__VolumeMounts (
    InventoryID   TEXT    NOT NULL,
    VolumeID      INTEGER NOT NULL,
    MountPoint    TEXT    NOT NULL,
    PRIMARY KEY (InventoryID, VolumeID, MountPoint),
    FOREIGN KEY (InventoryID, VolumeID)
        REFERENCES app__Volumes (InventoryID, VolumeID)
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS app__VolumeExtents (
    InventoryID     TEXT    NOT NULL,
    VolumeID        INTEGER NOT NULL,
    DiskID          INTEGER NOT NULL,
    ExtentIndex     INTEGER NOT NULL,
    StartingOffset  BIGINT  NOT NULL,
    ExtentLength    BIGINT  NOT NULL,
    PRIMARY KEY (InventoryID, VolumeID, ExtentIndex),
    FOREIGN KEY (InventoryID, VolumeID)
        REFERENCES app__Volumes (InventoryID, VolumeID)
        ON DELETE CASCADE,
    FOREIGN KEY (InventoryID, DiskID)
        REFERENCES app__Disks (InventoryID, DiskID)
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS app__Partitions (
    InventoryID      TEXT    NOT NULL,
    PartitionID      INTEGER NOT NULL,
    DiskID           INTEGER NOT NULL,
    PartitionIndex   INTEGER NOT NULL,
    StartOffset      BIGINT  NOT NULL CHECK (StartOffset >= 0),
    LengthBytes      BIGINT  NOT NULL CHECK (LengthBytes > 0),
    PartitionType    TEXT    NULL,
    GPT_GUID         TEXT    NULL,
    MBR_Type         INTEGER NULL,  -- MBR partition type code (0x00-0xFF), NULL for GPT partitions
    VolID            INTEGER NULL,
    PRIMARY KEY (InventoryID, PartitionID),
    FOREIGN KEY (InventoryID, DiskID)
        REFERENCES app__Disks (InventoryID, DiskID)
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS app__SMBShares (
    InventoryID          TEXT    NOT NULL,
    ShareID              INTEGER NOT NULL,
    Name                 TEXT    NOT NULL,
    Path                 INTEGER    NOT NULL, -- Foreign key to app__Folders.LocalFolderID (folder path)
    Description          TEXT,
    Type                 TEXT    NOT NULL,      -- e.g. "DiskShare" vs "PrintQueue" (STYPE_DISKTREE vs STYPE_PRINTQ)
    AllowMaximum         BOOLEAN NOT NULL,      -- PowerShell: AllowMaximum
    MaximumAllowed       INTEGER CHECK (MaximumAllowed IS NULL OR MaximumAllowed > 0), -- PowerShell: Concurrent user limit
    IsHidden             BOOLEAN NOT NULL,      -- Name ends with '$' or via --Hidden
    IsSpecial            BOOLEAN NOT NULL,      -- ADMIN$, IPC$ etc.
    Status               TEXT    NOT NULL,      -- "Online", "Offline", "Disabled"
    IsEncrypted          BOOLEAN DEFAULT NULL,  -- SMB 3.x encryption (NULL = unknown, requires PowerShell Get-SmbShare)
    IsContinuous         BOOLEAN DEFAULT NULL,  -- Continuously Available (NULL = unknown, cluster feature)
    ScopeName            TEXT,                    -- DFS namespace scope, if any
    OwningNode           TEXT,                    -- Cluster/FSSO node name
    FolderEnumerationMode TEXT,                   -- "AccessBased" vs "None" (NULL = unknown)
    CachingMode          TEXT,                    -- "Manual", "Auto", etc. (NULL = unknown)
    BranchCacheEnabled   BOOLEAN DEFAULT NULL,   -- NULL = unknown, requires Get-SmbShare
    LeasingMode          TEXT,                    -- "None", "Hash", "Local", etc. (NULL = unknown)
    VolumeID             INTEGER,                 -- FK --> app__Volumes(VolumeID)
    CreatedDate          TEXT,                    -- "YYYY-MM-DD HH:MM:SS" or CIM_DATE_TIME
    ModifiedDate         TEXT,                    -- "YYYY-MM-DD HH:MM:SS" or CIM_DATE_TIME
    SecurityDescriptor   TEXT,                    -- SDDL string (e.g. "O:BAG:SYD:...") or BLOB
    CurrentUsers         INTEGER DEFAULT NULL,        -- snapshot from Get-SmbSession (NULL = unknown)
    IsBranchCacheEnabled BOOLEAN DEFAULT NULL,        -- if BranchCache is actually configured (NULL = unknown)

    PRIMARY KEY (InventoryID, ShareID)
);

CREATE TABLE IF NOT EXISTS app__SMBShareAccess (
    InventoryID          TEXT    NOT NULL,
    ShareID              INTEGER NOT NULL,
    AccessID             INTEGER NOT NULL,
    Trustee              INTEGER NOT NULL,  -- SidID from app__SIDs
    AccessType           TEXT    NOT NULL,  -- "Allow", "Deny", etc.
    AccessMask           INTEGER NOT NULL,  -- Access rights mask
    IsInherited          BOOLEAN NOT NULL DEFAULT 0,
    PRIMARY KEY (InventoryID, ShareID, AccessID),
    FOREIGN KEY (InventoryID, ShareID)
        REFERENCES app__SMBShares(InventoryID, ShareID)
        ON DELETE CASCADE,
    FOREIGN KEY (Trustee)
        REFERENCES app__SIDs(SidID)
);
)";

const char* CREATE_SCHEMA_TABLES_SQL_PART2 = R"(
CREATE TABLE IF NOT EXISTS app__EventLog (
    EventID INTEGER PRIMARY KEY AUTOINCREMENT,
    InventoryID TEXT NOT NULL,
    Timestamp TEXT NOT NULL,
    Severity TEXT NOT NULL,
    Source TEXT NOT NULL,
    Message TEXT NOT NULL,
    Path TEXT,
    ErrorCode INTEGER,
    ThreadID INTEGER,
    AdditionalData TEXT
);

CREATE TABLE IF NOT EXISTS app__Version (
    PropertyName TEXT NOT NULL,
    PropertyValue TEXT NOT NULL,
    PRIMARY KEY (PropertyName)
);

CREATE TABLE IF NOT EXISTS lkp__PropagationFlags (
    FlagValue INTEGER PRIMARY KEY,
    Description TEXT NOT NULL,
    IsNoPropagate BOOLEAN NOT NULL,
    IsInheritOnly BOOLEAN NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS "lkp__ShareAvailabilityTypes" (
	"TypeID"	INTEGER,
	"TypeValue"	TEXT,
	"Description"	TEXT NOT NULL,
	PRIMARY KEY("TypeID" AUTOINCREMENT)
);

CREATE TABLE IF NOT EXISTS lkp__ShareCachingModes (
    "CacheID"	INTEGER,
    ModeValue TEXT,
    Description TEXT NOT NULL,
    PRIMARY KEY("CacheID" AUTOINCREMENT)
);

CREATE TABLE IF NOT EXISTS lkp__ShareFolderEnumerationModes (
    "FolderEnumID"	INTEGER,
    ModeValue TEXT,
    Description TEXT NOT NULL,
    PRIMARY KEY("FolderEnumID" AUTOINCREMENT)
);

CREATE TABLE IF NOT EXISTS lkp__ShareLeasingModes (
    "LeaseID"	INTEGER,
    ModeValue TEXT,
    Description TEXT NOT NULL,
    PRIMARY KEY("LeaseID" AUTOINCREMENT)
);

CREATE TABLE IF NOT EXISTS lkp__InheritanceFlags (
    FlagValue INTEGER PRIMARY KEY,
    Description TEXT NOT NULL,
    IsObjectInherit BOOLEAN NOT NULL,
    IsContainerInherit BOOLEAN NOT NULL,
    IsNoPropagate BOOLEAN NOT NULL,
    IsInheritOnly BOOLEAN NOT NULL,
    IsInherited BOOLEAN NOT NULL
) WITHOUT ROWID;

CREATE VIEW vw__ACL AS
Select 
acl.InventoryID,
acl.LocalACLID,
f.Path,
s1.AccountName as OwnerName,
s1.Sid as OwnerSID,
s2.AccountName as GroupName,
s2.Sid as GroupSID,
acl.AreAccessRulesProtected,
acl.AreAuditRulesProtected,
acl.AreAccessRulesCanonical,
acl.AreAuditRulesCanonical
from app__ACL as acl
LEFT JOIN app__Folders AS f ON acl.LocalFolderID = f.LocalFolderID AND acl.InventoryID = f.InventoryID
LEFT JOIN app__SIDs as S1 on acl.Owner = s1.SidID AND acl.InventoryID = s1.InventoryID 
LEFT JOIN app__SIDs as S2 on acl.[group] = s2.SidID AND acl.InventoryID = s2.InventoryID;

CREATE VIEW vw__ACE AS
SELECT
  ace.InventoryID,
  ace.LocalACEID,
  f.LocalFolderID,
  f.Path AS FolderPath,
  CASE
    WHEN ace.InheritedFromLocalID = 0 THEN 'Self'
    ELSE f2.Path
  END AS InheritedFromPath,
  COALESCE((
    SELECT group_concat(fsr.Permission, ', ')
    FROM lkp__FileSystemRights AS fsr
    WHERE (ace.FileSystemRightsMask & fsr.MaskValue) = fsr.MaskValue
  ), '') AS FileSystemRights,
  ace.AccessControlType,
  at.TypeName AS Access,
  sids.Sid,
  sids.AccountName,
  ace.IsInherited,
  CASE ace.InheritanceFlags
    WHEN 0 THEN 'None'
    WHEN 1 THEN 'OBJECT_INHERIT_ACE'
    WHEN 2 THEN 'CONTAINER_INHERIT_ACE'
    WHEN 3 THEN 'OBJECT_INHERIT_ACE, CONTAINER_INHERIT_ACE'
  END AS InheritanceFlags,
  pf.Description AS PropagationFlags,
  ace.InheritedFromLocalID
FROM app__ACE AS ace
LEFT JOIN app__Folders AS f ON ace.LocalFolderID = f.LocalFolderID AND ace.InventoryID = f.InventoryID 
LEFT JOIN app__Folders AS f2 ON ace.InheritedFromLocalID = f2.LocalFolderID AND ace.InventoryID = f2.InventoryID
LEFT JOIN app__SIDs AS sids ON ace.IdentitySID = sids.SidID AND ace.InventoryID = sids.InventoryID
LEFT JOIN lkp__AceTypes AS at ON ace.AccessControlType = at.TypeValue
LEFT JOIN lkp__InheritanceFlags AS ihf ON ace.InheritanceFlags = ihf.FlagValue
LEFT JOIN lkp__PropagationFlags AS pf ON ace.PropagationFlags = pf.FlagValue;

CREATE VIEW vw__Volumes AS
SELECT
  v.InventoryID,
  v.VolumeID,
  v.Label,
  v.FileSystem,
  v.Size,
  v.FreeSpace,
  v.IsSystem,
  v.IsReadOnly,
  v.Status,
  v.UniqueID,
  v.AllocationUnitSize,
  v.DriveType,
  dt.TypeName   AS DriveTypeName,
  dt.Description AS DriveTypeDesc,
  v.IsEncrypted,
  v.IsCompressed,
  v.ShadowCopyEnabled,
  v.ShadowCopyStorageMax
FROM app__Volumes AS v
LEFT JOIN lkp__DriveTypes AS dt
  ON v.DriveType = dt.DriveType;

CREATE TABLE IF NOT EXISTS lkp__FileSystemRights (
  MaskValue   INTEGER NOT NULL PRIMARY KEY,
  Permission  TEXT    NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS lkp__AceTypes (
    TypeValue INTEGER PRIMARY KEY,
    TypeName TEXT NOT NULL,
    Description TEXT NOT NULL,
    IsSupported BOOLEAN NOT NULL DEFAULT 0
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS lkp__DriveTypes (
    DriveType   INTEGER   NOT NULL PRIMARY KEY,
    TypeName    TEXT      NOT NULL,
    Description TEXT
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS lkp__MBR_Type (
    MBR_Type    INTEGER   NOT NULL PRIMARY KEY,
    TypeName    TEXT      NOT NULL,
    Description TEXT      NOT NULL,
    FileSystem  TEXT      NULL      -- Common file system for this type (if applicable)
) WITHOUT ROWID;

-- Performance indexes for common query patterns (created after tables)
CREATE INDEX IF NOT EXISTS idx_ACE_LocalFolderID ON app__ACE(InventoryID, LocalFolderID);
CREATE INDEX IF NOT EXISTS idx_ACE_IdentitySID ON app__ACE(InventoryID, IdentitySID);
CREATE INDEX IF NOT EXISTS idx_ACE_InheritedFrom ON app__ACE(InventoryID, InheritedFromLocalID);
CREATE INDEX IF NOT EXISTS idx_ACE_FileSystemRightsMask ON app__ACE(InventoryID, FileSystemRightsMask);
CREATE INDEX IF NOT EXISTS idx_ACL_LocalFolderID ON app__ACL(InventoryID, LocalFolderID);
CREATE INDEX IF NOT EXISTS idx_ACL_Owner ON app__ACL(Owner);
CREATE INDEX IF NOT EXISTS idx_ACL_Group ON app__ACL("Group");
CREATE INDEX IF NOT EXISTS idx_Folders_Path ON app__Folders(InventoryID, Path);
CREATE INDEX IF NOT EXISTS idx_Folders_ParentID ON app__Folders(InventoryID, ParentFolderID);
CREATE INDEX IF NOT EXISTS idx_Folders_VolumeID ON app__Folders(InventoryID, VolumeID);
CREATE INDEX IF NOT EXISTS idx_SIDs_AccountName ON app__SIDs(AccountName);
CREATE INDEX IF NOT EXISTS idx_SIDs_IsResolved ON app__SIDs(InventoryID, IsResolved);
CREATE INDEX IF NOT EXISTS idx_SMBShares_Path ON app__SMBShares(InventoryID, Path);
CREATE INDEX IF NOT EXISTS idx_SMBShares_VolumeID ON app__SMBShares(InventoryID, VolumeID);
CREATE INDEX IF NOT EXISTS idx_SMBShares_Name ON app__SMBShares(InventoryID, Name);
CREATE INDEX IF NOT EXISTS idx_SMBShareAccess_ShareID ON app__SMBShareAccess(InventoryID, ShareID);
CREATE INDEX IF NOT EXISTS idx_SMBShareAccess_Trustee ON app__SMBShareAccess(Trustee);
CREATE INDEX IF NOT EXISTS idx_VolumeMounts_MountPoint ON app__VolumeMounts(InventoryID, MountPoint);
CREATE INDEX IF NOT EXISTS idx_Partitions_DiskID ON app__Partitions(InventoryID, DiskID);
CREATE INDEX IF NOT EXISTS idx_VolumeExtents_DiskID ON app__VolumeExtents(InventoryID, DiskID);
CREATE INDEX IF NOT EXISTS idx_VolumeExtents_VolumeID ON app__VolumeExtents(InventoryID, VolumeID);
CREATE INDEX IF NOT EXISTS idx_EventLog_Severity ON app__EventLog(InventoryID, Severity);
CREATE INDEX IF NOT EXISTS idx_EventLog_Timestamp ON app__EventLog(Timestamp);
CREATE INDEX IF NOT EXISTS idx_EventLog_Source ON app__EventLog(Source);
CREATE INDEX IF NOT EXISTS idx_EventLog_InventoryID ON app__EventLog(InventoryID);
)";

const char* CREATE_SCHEMA_VIEWS_SQL = R"(
CREATE VIEW vw__DiskSummary AS
SELECT
  d.InventoryID,
  d.DiskID,
  d.DeviceID,
  d.Model,
  d.InterfaceType,
  d.Size,
  d.PartitionStyle,
  d.IsBoot,
  d.IsSystem,
  d.IsReadOnly,
  d.Status,
  COUNT(DISTINCT p.PartitionID)   AS PartitionCount,
  COUNT(DISTINCT v.VolumeID)      AS DirectVolumeCount
FROM app__Disks AS d
LEFT JOIN app__Partitions AS p
  ON p.InventoryID = d.InventoryID
 AND p.DiskID       = d.DiskID
LEFT JOIN app__Volumes AS v
  ON v.InventoryID = d.InventoryID
 AND v.DiskID       = d.DiskID
GROUP BY
  d.InventoryID,
  d.DiskID;

CREATE VIEW vw__PartitionDetails AS
SELECT
  p.InventoryID,
  p.PartitionID,
  p.DiskID,
  d.DeviceID           AS DiskDeviceID,
  d.Model              AS DiskModel,
  d.Size               AS DiskSize,
  p.PartitionIndex,
  p.StartOffset,
  p.LengthBytes,
  ROUND(CAST(p.LengthBytes AS REAL) / d.Size * 100, 2) AS PercentOfDisk,
  p.PartitionType,
  p.GPT_GUID,
  p.MBR_Type,
  mbr.TypeName         AS MBR_TypeName,
  mbr.Description      AS MBR_TypeDescription,
  mbr.FileSystem       AS MBR_TypeFileSystem,
  p.VolID              AS BackingVolumeID,
  v.UniqueID           AS VolumeUniqueID,
  v.Label              AS VolumeLabel,
  v.FileSystem         AS VolumeFileSystem,
  v.Size               AS VolumeSize,
  v.FreeSpace          AS VolumeFreeSpace,
  CASE WHEN v.Size > 0
       THEN ROUND(CAST(v.FreeSpace AS REAL) / v.Size * 100, 2)
       ELSE 0
  END AS VolumePercentFree,
  vm.MountPoints
FROM app__Partitions AS p
LEFT JOIN app__Disks AS d
  ON p.InventoryID = d.InventoryID
 AND p.DiskID       = d.DiskID
LEFT JOIN app__Volumes AS v
  ON p.InventoryID = v.InventoryID
 AND p.VolID        = v.VolumeID
LEFT JOIN (
    SELECT InventoryID, VolumeID, GROUP_CONCAT(MountPoint, ';') AS MountPoints
    FROM app__VolumeMounts
    GROUP BY InventoryID, VolumeID
) AS vm
  ON v.InventoryID = vm.InventoryID
 AND v.VolumeID    = vm.VolumeID
LEFT JOIN lkp__MBR_Type AS mbr
  ON p.MBR_Type = mbr.MBR_Type;

CREATE VIEW vw__VolumeMounts AS
SELECT
  v.InventoryID,
  v.VolumeID,
  v.Label             AS VolumeLabel,
  v.FileSystem,
  v.Size,
  v.FreeSpace,
  v.IsSystem,
  v.IsReadOnly,
  v.Status            AS VolumeStatus,
  v.UniqueID          AS VolumeUniqueID,
  m.MountPoint
FROM app__Volumes      AS v
LEFT JOIN app__VolumeMounts AS m
  ON v.InventoryID = m.InventoryID
 AND v.VolumeID    = m.VolumeID;

CREATE VIEW vw__VolumeExtents AS
SELECT
  e.InventoryID,
  e.VolumeID,
  v.Label               AS VolumeLabel,
  v.FileSystem          AS VolumeFileSystem,
  v.UniqueID            AS VolumeUniqueID,
  e.DiskID              AS ExtentDiskID,
  d.DeviceID            AS ExtentDiskDeviceID, 
  e.ExtentIndex,
  e.StartingOffset,
  e.ExtentLength
FROM app__VolumeExtents AS e
LEFT JOIN app__Volumes AS v
  ON e.InventoryID = v.InventoryID
 AND e.VolumeID    = v.VolumeID
LEFT JOIN app__Disks   AS d
  ON e.InventoryID = d.InventoryID
 AND e.DiskID      = d.DiskID;

CREATE VIEW vw__VolumeFull AS
SELECT
  v.InventoryID,
  v.VolumeID,
  v.DiskID,
  d.DeviceID         AS DiskDeviceID,
  d.Model            AS DiskModel,
  v.Label,
  v.FileSystem,
  v.Size,
  v.FreeSpace,
  CASE WHEN v.Size > 0
       THEN ROUND(CAST(v.FreeSpace AS REAL) / v.Size * 100, 2)
       ELSE 0
  END AS PercentFree,
  v.IsSystem,
  v.IsReadOnly,
  v.Status           AS VolumeStatus,
  v.UniqueID         AS VolumeUniqueID,
  v.AllocationUnitSize,
  v.DriveType,
  dt.TypeName        AS DriveTypeName,
  dt.Description     AS DriveTypeDesc,
  v.IsEncrypted,
  v.IsCompressed,
  v.ShadowCopyEnabled,
  v.ShadowCopyStorageMax,
  vm.MountPoints,
  COALESCE(cnt.NumExtents, 0) AS ExtentCount,
  CASE
    WHEN COALESCE(cnt.NumExtents, 0) = 0 THEN 'Unknown'
    WHEN COALESCE(cnt.NumExtents, 0) = 1 THEN 'Simple'
    WHEN COALESCE(cnt.NumExtents, 0) > 1 THEN 'Spanned'
    ELSE 'Unknown'
  END AS LayoutType
FROM app__Volumes AS v
LEFT JOIN app__Disks AS d
  ON v.InventoryID = d.InventoryID
 AND v.DiskID       = d.DiskID
LEFT JOIN lkp__DriveTypes AS dt
  ON v.DriveType = dt.DriveType
LEFT JOIN (
    SELECT
      InventoryID,
      VolumeID,
      GROUP_CONCAT(MountPoint, ';') AS MountPoints
    FROM app__VolumeMounts
    GROUP BY
      InventoryID,
      VolumeID
) AS vm
  ON v.InventoryID = vm.InventoryID
 AND v.VolumeID    = vm.VolumeID
LEFT JOIN (
    SELECT
      InventoryID,
      VolumeID,
      COUNT(*) AS NumExtents
    FROM app__VolumeExtents
    GROUP BY
      InventoryID,
      VolumeID
) AS cnt
  ON v.InventoryID = cnt.InventoryID
 AND v.VolumeID    = cnt.VolumeID;

CREATE VIEW vw__DiskPartitionLayout AS
SELECT
  d.InventoryID,
  d.DiskID,
  d.DeviceID,
  d.Model              AS DiskModel,
  d.InterfaceType,
  d.Size               AS DiskSize,
  d.PartitionStyle,
  d.IsBoot             AS DiskIsBoot,
  d.IsSystem           AS DiskIsSystem,
  d.Status             AS DiskStatus,
  p.PartitionID,
  p.PartitionIndex,
  p.StartOffset,
  p.LengthBytes        AS PartitionSize,
  ROUND(CAST(p.LengthBytes AS REAL) / d.Size * 100, 2) AS PartitionPercentOfDisk,
  p.PartitionType,
  p.GPT_GUID,
  p.MBR_Type,
  p.VolID              AS VolumeID,
  v.Label              AS VolumeLabel,
  v.FileSystem,
  v.Size               AS VolumeSize,
  v.FreeSpace,
  CASE WHEN v.Size > 0
       THEN ROUND(CAST(v.FreeSpace AS REAL) / v.Size * 100, 2)
       ELSE NULL
  END AS VolumePercentFree,
  v.Status             AS VolumeStatus,
  vm.MountPoints,
  -- Calculate unallocated space after this partition (simplified)
  CASE
    WHEN lead_offset.NextStartOffset IS NOT NULL
    THEN lead_offset.NextStartOffset - (p.StartOffset + p.LengthBytes)
    ELSE d.Size - (p.StartOffset + p.LengthBytes)
  END AS UnallocatedAfter
FROM app__Disks AS d
LEFT JOIN app__Partitions AS p
  ON d.InventoryID = p.InventoryID
 AND d.DiskID       = p.DiskID
LEFT JOIN app__Volumes AS v
  ON p.InventoryID = v.InventoryID
 AND p.VolID        = v.VolumeID
LEFT JOIN (
    SELECT InventoryID, VolumeID, GROUP_CONCAT(MountPoint, ';') AS MountPoints
    FROM app__VolumeMounts
    GROUP BY InventoryID, VolumeID
) AS vm
  ON v.InventoryID = vm.InventoryID
 AND v.VolumeID    = vm.VolumeID
LEFT JOIN (
    SELECT
      p1.InventoryID,
      p1.DiskID,
      p1.PartitionID,
      MIN(p2.StartOffset) AS NextStartOffset
    FROM app__Partitions AS p1
    LEFT JOIN app__Partitions AS p2
      ON p1.InventoryID = p2.InventoryID
     AND p1.DiskID = p2.DiskID
     AND p2.StartOffset > p1.StartOffset
    GROUP BY p1.InventoryID, p1.DiskID, p1.PartitionID
) AS lead_offset
  ON p.InventoryID = lead_offset.InventoryID
 AND p.DiskID       = lead_offset.DiskID
 AND p.PartitionID  = lead_offset.PartitionID
ORDER BY d.InventoryID, d.DiskID, p.StartOffset;

CREATE VIEW vw__VolumeDiskMap AS
SELECT
  v.InventoryID,
  v.VolumeID,
  v.Label              AS VolumeLabel,
  v.FileSystem,
  v.Size               AS VolumeSize,
  v.FreeSpace,
  CASE WHEN v.Size > 0
       THEN ROUND(CAST(v.FreeSpace AS REAL) / v.Size * 100, 2)
       ELSE 0
  END AS PercentFree,
  v.Status             AS VolumeStatus,
  v.UniqueID           AS VolumeUniqueID,
  vm.MountPoints,
  COALESCE(v.DiskID, ext.PrimaryDiskID) AS PrimaryDiskID,
  COALESCE(d.DeviceID, ext.PrimaryDeviceID) AS PrimaryDeviceID,
  COALESCE(d.Model, ext.PrimaryModel) AS PrimaryDiskModel,
  ext.NumExtents,
  ext.NumDisks,
  CASE
    WHEN ext.NumExtents IS NULL OR ext.NumExtents = 0 THEN 'Unknown'
    WHEN ext.NumDisks = 1 AND ext.NumExtents = 1 THEN 'Simple'
    WHEN ext.NumDisks = 1 AND ext.NumExtents > 1 THEN 'Spanned'
    WHEN ext.NumDisks > 1 THEN 'Spanned/Striped'
    ELSE 'Simple'
  END AS LayoutType,
  ext.AllDiskIDs,
  ext.TotalExtentSize
FROM app__Volumes AS v
LEFT JOIN app__Disks AS d
  ON v.InventoryID = d.InventoryID
 AND v.DiskID       = d.DiskID
LEFT JOIN (
    SELECT InventoryID, VolumeID, GROUP_CONCAT(MountPoint, ';') AS MountPoints
    FROM app__VolumeMounts
    GROUP BY InventoryID, VolumeID
) AS vm
  ON v.InventoryID = vm.InventoryID
 AND v.VolumeID    = vm.VolumeID
LEFT JOIN (
    SELECT
      e.InventoryID,
      e.VolumeID,
      COUNT(*) AS NumExtents,
      COUNT(DISTINCT e.DiskID) AS NumDisks,
      MIN(e.DiskID) AS PrimaryDiskID,
      MIN(d2.DeviceID) AS PrimaryDeviceID,
      MIN(d2.Model) AS PrimaryModel,
      GROUP_CONCAT(DISTINCT e.DiskID) AS AllDiskIDs,
      SUM(e.ExtentLength) AS TotalExtentSize
    FROM app__VolumeExtents AS e
    LEFT JOIN app__Disks AS d2
      ON e.InventoryID = d2.InventoryID
     AND e.DiskID = d2.DiskID
    GROUP BY e.InventoryID, e.VolumeID
) AS ext
  ON v.InventoryID = ext.InventoryID
 AND v.VolumeID    = ext.VolumeID;

CREATE VIEW vw__FolderAttributes AS
SELECT
  f.InventoryID,
  f.LocalFolderID,
  f.ParentFolderID,
  f.Path,
  f.VolumeID,
  f.CreationTime,
  f.LastWriteTime,
  f.LastAccessTime,
  f.Attributes,
  -- Boolean flags for each attribute (using bitwise AND)
  CASE WHEN (f.Attributes & 1) = 1 THEN 1 ELSE 0 END AS IsReadOnly,
  CASE WHEN (f.Attributes & 2) = 2 THEN 1 ELSE 0 END AS IsHidden,
  CASE WHEN (f.Attributes & 4) = 4 THEN 1 ELSE 0 END AS IsSystem,
  CASE WHEN (f.Attributes & 16) = 16 THEN 1 ELSE 0 END AS IsDirectory,
  CASE WHEN (f.Attributes & 32) = 32 THEN 1 ELSE 0 END AS IsArchive,
  CASE WHEN (f.Attributes & 64) = 64 THEN 1 ELSE 0 END AS IsDevice,
  CASE WHEN (f.Attributes & 128) = 128 THEN 1 ELSE 0 END AS IsNormal,
  CASE WHEN (f.Attributes & 256) = 256 THEN 1 ELSE 0 END AS IsTemporary,
  CASE WHEN (f.Attributes & 512) = 512 THEN 1 ELSE 0 END AS IsSparseFile,
  CASE WHEN (f.Attributes & 1024) = 1024 THEN 1 ELSE 0 END AS IsReparsePoint,
  CASE WHEN (f.Attributes & 2048) = 2048 THEN 1 ELSE 0 END AS IsCompressed,
  CASE WHEN (f.Attributes & 4096) = 4096 THEN 1 ELSE 0 END AS IsOffline,
  CASE WHEN (f.Attributes & 8192) = 8192 THEN 1 ELSE 0 END AS IsNotContentIndexed,
  CASE WHEN (f.Attributes & 16384) = 16384 THEN 1 ELSE 0 END AS IsEncrypted,
  CASE WHEN (f.Attributes & 32768) = 32768 THEN 1 ELSE 0 END AS IsIntegrityStream,
  CASE WHEN (f.Attributes & 65536) = 65536 THEN 1 ELSE 0 END AS IsVirtual,
  CASE WHEN (f.Attributes & 131072) = 131072 THEN 1 ELSE 0 END AS IsNoScrubData,
  CASE WHEN (f.Attributes & 262144) = 262144 THEN 1 ELSE 0 END AS IsRecallOnOpen,
  CASE WHEN (f.Attributes & 524288) = 524288 THEN 1 ELSE 0 END AS IsPinned,
  CASE WHEN (f.Attributes & 1048576) = 1048576 THEN 1 ELSE 0 END AS IsUnpinned,
  CASE WHEN (f.Attributes & 4194304) = 4194304 THEN 1 ELSE 0 END AS IsRecallOnDataAccess,
  -- Commonly useful attribute combinations
  CASE WHEN (f.Attributes & 6) = 6 THEN 1 ELSE 0 END AS IsHiddenSystem,
  CASE WHEN (f.Attributes & 18432) = 18432 THEN 1 ELSE 0 END AS IsCompressedAndEncrypted
FROM app__Folders AS f;
)";

// Split into two parts to avoid MSVC 16KB string literal limit
const char* CREATE_SCHEMA_INSERTS_SQL_PART1 = R"(
INSERT OR IGNORE INTO app__CollectionInfo(
  InventoryID, ComputerName, DomainName, CollectionDateTime,
  ApplicationVersion, ApplicationBuild, IsAdmin, Who, HardwareConcurrency,
  ThreadCount, StartTime
)
VALUES(
  '00000000-0000-0000-0000-000000000000',
  'GLOBAL','GLOBAL', datetime('now'),
  '0','0', 0,'', 0,
  0, datetime('now')
);

INSERT OR IGNORE INTO lkp__PropagationFlags (FlagValue,Description,IsNoPropagate,IsInheritOnly) VALUES
(0, 'None', 0, 0),
(4, 'No propagate inherit', 1, 0),
(8, 'Inherit only', 0, 1),
(12, 'No propagate inherit + Inherit only', 1, 1);

INSERT OR IGNORE INTO lkp__ShareAvailabilityTypes(TypeValue, Description) VALUES
('NonClustered','Standard non-clustered share'),
('Clustered','Clustered share for failover clustering'),
('ScaleOut','Scale-out file server share'),
('CSV','Cluster Shared Volume share'),
('DFS','Distributed File System share');

INSERT OR IGNORE INTO lkp__ShareCachingModes(ModeValue, Description) VALUES
('Manual','Manual caching'),
('Documents','Document caching'),
('Programs','Program caching'),
('None','No caching');

INSERT OR IGNORE INTO lkp__ShareFolderEnumerationModes(ModeValue, Description) VALUES
('AccessBased','Only show folders the user has access to'),
('Unrestricted','Show all folders regardless of access');

INSERT OR IGNORE INTO lkp__ShareLeasingModes(ModeValue, Description) VALUES
('None','No leasing'),
('Basic','Basic leasing'),
('Advanced','Advanced leasing');

INSERT OR IGNORE INTO lkp__InheritanceFlags (FlagValue,Description,IsObjectInherit,IsContainerInherit,IsNoPropagate,IsInheritOnly,IsInherited) VALUES
('0','No inheritance','0','0','0','0','0'),
('1','Inherit to files only','1','0','0','0','0'),
('2','Inherit to folders only','0','1','0','0','0'),
('3','Inherit to both files and folders','1','1','0','0','0'),
('4','No propagate inherit','0','0','1','0','0'),
('8','Inherit only','0','0','0','1','0'),
('11','Inherit to files only, no propagate','1','0','1','0','0'),
('12','Inherit to folders only, no propagate','0','1','1','0','0'),
('15','Inherit to both, no propagate','1','1','1','0','0'),
('16','Inherited from parent','0','0','0','0','1'),
('17','Inherit to files only, inherited','1','0','0','0','1'),
('18','Inherit to folders only, inherited','0','1','0','0','1'),
('19','Inherit to both, inherited','1','1','0','0','1');

INSERT INTO lkp__FileSystemRights (MaskValue, Permission) VALUES 
  (0x00000001, 'FILE_READ_DATA'),
  (0x00000002, 'FILE_WRITE_DATA'),
  (0x00000004, 'FILE_APPEND_DATA'),
  (0x00000008, 'FILE_READ_EA'),
  (0x00000010, 'FILE_WRITE_EA'),
  (0x00000020, 'FILE_EXECUTE'),
  (0x00000040, 'FILE_DELETE_CHILD'),
  (0x00000080, 'FILE_READ_ATTRIBUTES'),
  (0x00000100, 'FILE_WRITE_ATTRIBUTES'),
  (0x00010000, 'DELETE'),
  (0x00020000, 'READ_CONTROL'),
  (0x00040000, 'WRITE_DAC'),
  (0x00080000, 'WRITE_OWNER'),
  (0x00100000, 'SYNCHRONIZE');
)";

const char* CREATE_SCHEMA_INSERTS_SQL_PART2 = R"(
INSERT OR IGNORE INTO lkp__AceTypes (TypeValue, TypeName, Description, IsSupported) VALUES
(0, 'ACCESS_ALLOWED_ACE_TYPE', 'Standard access allowed ACE', 1),
(1, 'ACCESS_DENIED_ACE_TYPE', 'Standard access denied ACE', 1),
(2, 'SYSTEM_AUDIT_ACE_TYPE', 'System audit ACE', 0),
(3, 'SYSTEM_ALARM_ACE_TYPE', 'System alarm ACE (reserved for future use)', 0),
(4, 'ACCESS_ALLOWED_COMPOUND_ACE_TYPE', 'Reserved for future use', 0),
(5, 'ACCESS_ALLOWED_OBJECT_ACE_TYPE', 'Object-specific access allowed ACE', 0),
(6, 'ACCESS_DENIED_OBJECT_ACE_TYPE', 'Object-specific access denied ACE', 0),
(7, 'SYSTEM_AUDIT_OBJECT_ACE_TYPE', 'Object-specific system audit ACE', 0),
(8, 'SYSTEM_ALARM_OBJECT_ACE_TYPE', 'Object-specific system alarm ACE (reserved for future use)', 0),
(9, 'ACCESS_ALLOWED_CALLBACK_ACE_TYPE', 'Callback access allowed ACE', 1),
(10, 'ACCESS_DENIED_CALLBACK_ACE_TYPE', 'Callback access denied ACE', 0),
(11, 'ACCESS_ALLOWED_CALLBACK_OBJECT_ACE_TYPE', 'Object-specific callback access allowed ACE', 0),
(12, 'ACCESS_DENIED_CALLBACK_OBJECT_ACE_TYPE', 'Object-specific callback access denied ACE', 0),
(13, 'SYSTEM_AUDIT_CALLBACK_ACE_TYPE', 'Callback system audit ACE', 0),
(14, 'SYSTEM_ALARM_CALLBACK_ACE_TYPE', 'Callback system alarm ACE (reserved for future use)', 0),
(15, 'SYSTEM_AUDIT_CALLBACK_OBJECT_ACE_TYPE', 'Object-specific callback system audit ACE', 0),
(16, 'SYSTEM_ALARM_CALLBACK_OBJECT_ACE_TYPE', 'Object-specific callback system alarm ACE (reserved for future use)', 0),
(17, 'SYSTEM_MANDATORY_LABEL_ACE_TYPE', 'Mandatory integrity label ACE', 0),
(18, 'SYSTEM_RESOURCE_ATTRIBUTE_ACE_TYPE', 'Resource attribute ACE', 0),
(19, 'SYSTEM_SCOPED_POLICY_ID_ACE_TYPE', 'Scoped policy ID ACE', 0),
(20, 'SYSTEM_PROCESS_TRUST_LABEL_ACE_TYPE', 'Process trust label ACE', 0),
(21, 'SYSTEM_ACCESS_FILTER_ACE_TYPE', 'Access filter ACE', 0);

INSERT OR IGNORE INTO lkp__DriveTypes (DriveType, TypeName, Description) VALUES
    (0, 'DRIVE_UNKNOWN',      'Unknown drive type'),
    (1, 'DRIVE_NO_ROOT_DIR',  'No root directory (invalid)'),
    (2, 'DRIVE_REMOVABLE',    'Removable media (USB, etc.)'),
    (3, 'DRIVE_FIXED',        'Fixed disk (local HDD/SSD)'),
    (4, 'DRIVE_REMOTE',       'Network drive'),
    (5, 'DRIVE_CDROM',        'CD/DVD-ROM'),
    (6, 'DRIVE_RAMDISK',      'RAM disk or virtual disk');

INSERT OR IGNORE INTO lkp__MBR_Type (MBR_Type, TypeName, Description, FileSystem) VALUES
    (0x00, 'Empty',                    'Empty partition slot or unused partition table entry', NULL),
    (0x01, 'FAT12',                    'FAT12 filesystem (< 16 MB, very old DOS)', 'FAT12'),
    (0x04, 'FAT16 <32MB',              'FAT16 filesystem (< 32 MB)', 'FAT16'),
    (0x05, 'Extended',                 'Extended partition (CHS addressing)', NULL),
    (0x06, 'FAT16',                    'FAT16 filesystem (>= 32 MB, < 2 GB)', 'FAT16'),
    (0x07, 'NTFS/exFAT',               'NTFS or exFAT filesystem (Windows)', 'NTFS'),
    (0x0B, 'FAT32 (CHS)',              'FAT32 filesystem with CHS addressing', 'FAT32'),
    (0x0C, 'FAT32 (LBA)',              'FAT32 filesystem with LBA addressing', 'FAT32'),
    (0x0E, 'FAT16 (LBA)',              'FAT16 filesystem with LBA addressing', 'FAT16'),
    (0x0F, 'Extended (LBA)',           'Extended partition with LBA addressing', NULL),
    (0x11, 'Hidden FAT12',             'Hidden FAT12 partition', 'FAT12'),
    (0x14, 'Hidden FAT16 <32MB',       'Hidden FAT16 partition (< 32 MB)', 'FAT16'),
    (0x16, 'Hidden FAT16',             'Hidden FAT16 partition (>= 32 MB)', 'FAT16'),
    (0x17, 'Hidden NTFS/exFAT',        'Hidden NTFS or exFAT partition', 'NTFS'),
    (0x1B, 'Hidden FAT32 (CHS)',       'Hidden FAT32 with CHS addressing', 'FAT32'),
    (0x1C, 'Hidden FAT32 (LBA)',       'Hidden FAT32 with LBA addressing', 'FAT32'),
    (0x1E, 'Hidden FAT16 (LBA)',       'Hidden FAT16 with LBA addressing', 'FAT16'),
    (0x27, 'Windows RE',               'Windows Recovery Environment partition', NULL),
    (0x42, 'Dynamic Disk',             'Windows dynamic disk / Logical Disk Manager', NULL),
    (0x82, 'Linux Swap',               'Linux swap partition', 'swap'),
    (0x83, 'Linux',                    'Linux native filesystem (ext2/3/4, XFS, etc.)', 'ext4'),
    (0x85, 'Linux Extended',           'Linux extended partition', NULL),
    (0x8E, 'Linux LVM',                'Linux Logical Volume Manager', 'LVM'),
    (0xA5, 'FreeBSD',                  'FreeBSD partition', 'UFS'),
    (0xA6, 'OpenBSD',                  'OpenBSD partition', 'FFS'),
    (0xA8, 'macOS (Darwin)',           'macOS / Darwin UFS partition', 'UFS'),
    (0xA9, 'NetBSD',                   'NetBSD partition', 'FFS'),
    (0xAF, 'macOS HFS/HFS+',           'macOS HFS or HFS+ partition', 'HFS+'),
    (0xEB, 'BFS',                      'BeOS filesystem', 'BFS'),
    (0xEE, 'GPT Protective',           'GPT protective MBR (indicates GPT disk)', NULL),
    (0xEF, 'EFI System',               'EFI System Partition (ESP)', 'FAT32'),
    (0xFB, 'VMware VMFS',              'VMware filesystem', 'VMFS'),
    (0xFC, 'VMware Swap',              'VMware swap partition', NULL),
    (0xFD, 'Linux RAID',               'Linux software RAID partition', NULL),
    (0xFE, 'LANstep',                  'LANstep / SpeedStor partition', NULL);
)";

const char* CREATE_SCHEMA_INSERTS_Not_Used_SQL = R"(

INSERT OR IGNORE INTO app__SIDs(SidID, InventoryID, Sid, AccountName, AccountType, Description) VALUES
(1,'00000000-0000-0000-0000-000000000000','S-1-0-0','NULL SID','Other','No security principal; unknown SID'),
(2,'00000000-0000-0000-0000-000000000000','S-1-1-0','Everyone','Group','All users'),
(3,'00000000-0000-0000-0000-000000000000','S-1-2-0','LOCAL','Group','Users who log on locally'),
(4,'00000000-0000-0000-0000-000000000000','S-1-2-1','CONSOLE LOGON','Group','Users logged on at the physical console'),
(5,'00000000-0000-0000-0000-000000000000','S-1-3-0','CREATOR OWNER','Other','Placeholder replaced by object creator'),
(6,'00000000-0000-0000-0000-000000000000','S-1-3-1','CREATOR GROUP','Other','Placeholder replaced by object creators group'),
(7,'00000000-0000-0000-0000-000000000000','S-1-3-2','CREATOR OWNER SERVER','Other','Placeholder replaced by owner server'),
(8,'00000000-0000-0000-0000-000000000000','S-1-3-3','CREATOR GROUP SERVER','Other','Placeholder replaced by group server'),
(9,'00000000-0000-0000-0000-000000000000','S-1-3-4','OWNER RIGHTS','Other','Represents the current owner of the object'),
(10,'00000000-0000-0000-0000-000000000000','S-1-5-1','NT AUTHORITY\DIALUP','Group','Users who log on via dial-up'),
(11,'00000000-0000-0000-0000-000000000000','S-1-5-10','NT AUTHORITY\SELF','Other','Placeholder for the object itself'),
(12,'00000000-0000-0000-0000-000000000000','S-1-5-11','NT AUTHORITY\Authenticated Users','Group','All authenticated users'),
(13,'00000000-0000-0000-0000-000000000000','S-1-5-12','NT AUTHORITY\RESTRICTED','Group','Processes running in a restricted context'),
(14,'00000000-0000-0000-0000-000000000000','S-1-5-13','NT AUTHORITY\TERMINAL SERVER USER','Group','Users logged on to Remote Desktop Services'),
(15,'00000000-0000-0000-0000-000000000000','S-1-5-14','NT AUTHORITY\REMOTE INTERACTIVE LOGON','Group','Users logged on via Remote Desktop/Terminal Services'),
(16,'00000000-0000-0000-0000-000000000000','S-1-5-15','NT AUTHORITY\This Organization','Group','Users from the same AD forest'),
(17,'00000000-0000-0000-0000-000000000000','S-1-5-17','NT AUTHORITY\IUSR','User','Default IIS anonymous-access account'),
(18,'00000000-0000-0000-0000-000000000000','S-1-5-18','NT AUTHORITY\SYSTEM','User','NT AUTHORITY\SYSTEM'),
(19,'00000000-0000-0000-0000-000000000000','S-1-5-19','NT AUTHORITY\LOCAL SERVICE','User','NT AUTHORITY\LOCAL SERVICE'),
(20,'00000000-0000-0000-0000-000000000000','S-1-5-2','NT AUTHORITY\NETWORK','Group','Users who log on across a network'),
(21,'00000000-0000-0000-0000-000000000000','S-1-5-20','NT AUTHORITY\NETWORK SERVICE','User','NT AUTHORITY\NETWORK SERVICE'),
(22,'00000000-0000-0000-0000-000000000000','S-1-5-3','NT AUTHORITY\BATCH','Group','Scheduled-job (batch) logon'),
(23,'00000000-0000-0000-0000-000000000000','S-1-5-32-544','BUILTIN\Administrators','Group','Local administrators group'),
(24,'00000000-0000-0000-0000-000000000000','S-1-5-32-545','BUILTIN\Users','Group','Local users group'),
(25,'00000000-0000-0000-0000-000000000000','S-1-5-32-546','BUILTIN\Guests','Group','Local guests group'),
(26,'00000000-0000-0000-0000-000000000000','S-1-5-32-547','BUILTIN\Power Users','Group','Legacy elevated-rights group'),
(27,'00000000-0000-0000-0000-000000000000','S-1-5-32-550','BUILTIN\Print Operators','Group','Local print operators'),
(28,'00000000-0000-0000-0000-000000000000','S-1-5-32-551','BUILTIN\Backup Operators','Group','Backup and restore privileges'),
(29,'00000000-0000-0000-0000-000000000000','S-1-5-32-552','BUILTIN\Replicator','Group','Replication services'),
(30,'00000000-0000-0000-0000-000000000000','S-1-5-32-555','BUILTIN\Remote Desktop Users','Group','Allowed to sign in via RDP'),
(31,'00000000-0000-0000-0000-000000000000','S-1-5-32-556','BUILTIN\Network Configuration Operators','Group','Network configuration operators'),
(32,'00000000-0000-0000-0000-000000000000','S-1-5-32-558','BUILTIN\Performance Monitor Users','Group','Performance monitor users'),
(33,'00000000-0000-0000-0000-000000000000','S-1-5-32-559','BUILTIN\Performance Log Users','Group','Performance log users'),
(34,'00000000-0000-0000-0000-000000000000','S-1-5-32-562','BUILTIN\Distributed COM Users','Group','DCOM users'),
(35,'00000000-0000-0000-0000-000000000000','S-1-5-32-568','BUILTIN\IIS_IUSRS','Group','IIS users'),
(36,'00000000-0000-0000-0000-000000000000','S-1-5-32-569','BUILTIN\Cryptographic Operators','Group','Cryptographic operators'),
(37,'00000000-0000-0000-0000-000000000000','S-1-5-32-573','BUILTIN\Event Log Readers','Group','Read event logs'),
(38,'00000000-0000-0000-0000-000000000000','S-1-5-32-574','BUILTIN\Certificate Service DCOM Access','Group','Certificate Services DCOM access'),
(39,'00000000-0000-0000-0000-000000000000','S-1-5-32-575','BUILTIN\RDS Remote Access Servers','Group','RDS remote access servers'),
(40,'00000000-0000-0000-0000-000000000000','S-1-5-32-576','BUILTIN\RDS Endpoint Servers','Group','RDS endpoint servers'),
(41,'00000000-0000-0000-0000-000000000000','S-1-5-32-577','BUILTIN\RDS Management Servers','Group','RDS management servers'),
(42,'00000000-0000-0000-0000-000000000000','S-1-5-32-578','BUILTIN\Hyper-V Administrators','Group','Full access to Hyper-V'),
(43,'00000000-0000-0000-0000-000000000000','S-1-5-32-579','BUILTIN\Access Control Assistance Operators','Group','Access Control Assistance Operators'),
(44,'00000000-0000-0000-0000-000000000000','S-1-5-32-580','BUILTIN\Remote Management Users','Group','WS-Management/WinRM users'),
(45,'00000000-0000-0000-0000-000000000000','S-1-5-32-581','BUILTIN\System Managed Accounts Group','User','System-managed default local account'),
(46,'00000000-0000-0000-0000-000000000000','S-1-5-32-582','BUILTIN\Storage Replica Administrators','Group','Storage Replica management'),
(47,'00000000-0000-0000-0000-000000000000','S-1-5-32-583','BUILTIN\Device Owners','Group','Device Owners group'),
(48,'00000000-0000-0000-0000-000000000000','S-1-5-32-584','BUILTIN\User Mode Hardware Operators','Group','User-mode hardware access'),
(49,'00000000-0000-0000-0000-000000000000','S-1-5-32-585','BUILTIN\OpenSSH Users','Group','Users permitted to log on via OpenSSH'),
(50,'00000000-0000-0000-0000-000000000000','S-1-5-4','NT AUTHORITY\INTERACTIVE','Group','Users who log on interactively'),
(51,'00000000-0000-0000-0000-000000000000','S-1-5-6','NT AUTHORITY\SERVICE','Group','Accounts authorized to log on as a service'),
(52,'00000000-0000-0000-0000-000000000000','S-1-5-64-10','NT AUTHORITY\NTLM Authentication','Other','Used for NTLM authentication'),
(53,'00000000-0000-0000-0000-000000000000','S-1-5-64-14','NT AUTHORITY\SChannel Authentication','Other','Used for SChannel authentication'),
(54,'00000000-0000-0000-0000-000000000000','S-1-5-64-21','NT AUTHORITY\Digest Authentication','Other','Used for Digest authentication'),
(55,'00000000-0000-0000-0000-000000000000','S-1-5-7','NT AUTHORITY\ANONYMOUS LOGON','User','Anonymous or null-session logon'),
(56,'00000000-0000-0000-0000-000000000000','S-1-5-8','NT AUTHORITY\PROXY','Group','Reserved'),
(57,'00000000-0000-0000-0000-000000000000','S-1-5-80-0','NT SERVICE\ALL SERVICES','Group','Used for all services'),
(58,'00000000-0000-0000-0000-000000000000','S-1-5-9','NT AUTHORITY\ENTERPRISE DOMAIN CONTROLLERS','Group','All DCs in the forest'),
(59,'00000000-0000-0000-0000-000000000000','S-1-5-90-0','Window Manager\Window Manager Group','Group','Windows Manager group');
)";
