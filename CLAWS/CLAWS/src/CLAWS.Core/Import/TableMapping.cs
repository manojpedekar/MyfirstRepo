using CLAWS.Core.Models;

namespace CLAWS.Core.Import;

/// <summary>
/// Mapping between SQLite and SQL Server tables.
/// </summary>
public class TableMapping
{
    /// <summary>
    /// Name of the table in SQLite (without prefix for NTFS, with AD_ prefix for ADInventory).
    /// </summary>
    public string SqliteTable { get; }

    /// <summary>
    /// Name of the table in SQL Server.
    /// </summary>
    public string MssqlTable { get; }

    /// <summary>
    /// SQL Server schema.
    /// </summary>
    public string MssqlSchema { get; }

    /// <summary>
    /// Display name for progress reporting.
    /// </summary>
    public string DisplayName { get; }

    /// <summary>
    /// Whether the table has an InventoryID column.
    /// </summary>
    public bool HasInventoryId { get; }

    /// <summary>
    /// Whether the table allows migration delta (rows added during migration).
    /// </summary>
    public bool AllowMigrationDelta { get; }

    /// <summary>
    /// Order in which this table should be imported (lower = earlier).
    /// </summary>
    public int ImportOrder { get; }

    /// <summary>
    /// Prefix for SQLite table names (e.g., "app__" for NTFS, "" for ADInventory).
    /// </summary>
    public string SqlitePrefix { get; }

    /// <summary>
    /// Creates a new table mapping.
    /// </summary>
    public TableMapping(
        string sqliteTable,
        string mssqlTable,
        string mssqlSchema,
        string displayName,
        int importOrder,
        bool hasInventoryId = true,
        bool allowMigrationDelta = false,
        string sqlitePrefix = "app__")
    {
        SqliteTable = sqliteTable;
        MssqlTable = mssqlTable;
        MssqlSchema = mssqlSchema;
        DisplayName = displayName;
        ImportOrder = importOrder;
        HasInventoryId = hasInventoryId;
        AllowMigrationDelta = allowMigrationDelta;
        SqlitePrefix = sqlitePrefix;
    }

    /// <summary>
    /// Gets the full SQLite table name with prefix.
    /// </summary>
    public string GetSqliteTableName() => $"{SqlitePrefix}{SqliteTable}";

    /// <summary>
    /// Gets the full SQL Server table name with schema.
    /// </summary>
    public string GetMssqlTableName() => $"[{MssqlSchema}].[{MssqlTable}]";
}

/// <summary>
/// Provides the standard table mappings for NTFS permissions and ADInventory data.
/// </summary>
public static class TableMappings
{
    /// <summary>
    /// NTFS Permissions table mappings (legacy - use NTFSPermissionsMappings instead).
    /// </summary>
    public static IReadOnlyList<TableMapping> AllMappings => NTFSPermissionsMappings;

    /// <summary>
    /// NTFS Permissions table mappings.
    /// </summary>
    public static IReadOnlyList<TableMapping> NTFSPermissionsMappings { get; } = new List<TableMapping>
    {
        new("SIDs", "SIDs", "fssimport", "Security Identifiers", 1),
        new("CollectionInfo", "CollectionInfo", "fssimport", "Collection Info", 2),
        new("Disks", "Disks", "fssimport", "Disks", 3),
        new("Volumes", "Volumes", "fssimport", "Volumes", 4, allowMigrationDelta: true),
        new("VolumeMounts", "VolumeMounts", "fssimport", "Volume Mounts", 5),
        new("VolumeExtents", "VolumeExtents", "fssimport", "Volume Extents", 6),
        new("Partitions", "Partitions", "fssimport", "Partitions", 7),
        new("Folders", "Folders", "fssimport", "Folders", 8),
        new("ACL", "ACL", "fssimport", "Access Control Lists", 9),
        new("ACE", "ACE", "fssimport", "Access Control Entries", 10),
        new("SMBShares", "SMBShares", "fssimport", "SMB Shares", 11),
        new("SMBShareAccess", "SMBShareAccess", "fssimport", "SMB Share Access", 12),
        new("EventLog", "EventLog", "fssimport", "Event Log", 13, allowMigrationDelta: true),
    };

    /// <summary>
    /// ADInventory table mappings.
    /// Note: ADInventory tables use AD_ prefix in SQLite and no prefix for SQL Server.
    /// </summary>
    public static IReadOnlyList<TableMapping> ADInventoryMappings { get; } = new List<TableMapping>
    {
        // CollectionInfo has InventoryID column
        new("AD_CollectionInfo", "CollectionInfo", "ADImport", "Collection Info", 1, hasInventoryId: true, sqlitePrefix: ""),
        // AD_Object and other tables use CollectionID foreign key, not InventoryID directly
        new("AD_Object", "AD_Object", "ADImport", "AD Objects", 2, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_GroupMembership", "AD_GroupMembership", "ADImport", "Group Memberships", 3, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_ForeignSecurityPrincipal", "AD_ForeignSecurityPrincipal", "ADImport", "Foreign Principals", 4, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_Trust", "AD_Trust", "ADImport", "Domain Trusts", 5, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_Domain", "AD_Domain", "ADImport", "Domains", 6, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_Forest", "AD_Forest", "ADImport", "Forests", 7, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_Log", "AD_Log", "ADImport", "Audit Log", 8, hasInventoryId: false, allowMigrationDelta: true, sqlitePrefix: ""),
        new("AD_ExecutionTime", "AD_ExecutionTime", "ADImport", "Execution Times", 9, hasInventoryId: false, sqlitePrefix: ""),
        // Sites & Services tables (base tables first)
        new("AD_Site", "AD_Site", "ADImport", "Sites", 10, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_Subnet", "AD_Subnet", "ADImport", "Subnets", 11, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_SiteLink", "AD_SiteLink", "ADImport", "Site Links", 12, hasInventoryId: false, sqlitePrefix: ""),
        // Sites & Services dependent tables
        new("AD_SiteSettings", "AD_SiteSettings", "ADImport", "Site Settings", 13, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_SiteServer", "AD_SiteServer", "ADImport", "Site Servers", 14, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_DomainController", "AD_DomainController", "ADImport", "Domain Controllers", 15, hasInventoryId: false, sqlitePrefix: ""),
        // Sites & Services junction tables (last due to FK dependencies)
        new("AD_SiteSubnet", "AD_SiteSubnet", "ADImport", "Site-Subnet Links", 16, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_SiteLinkSite", "AD_SiteLinkSite", "ADImport", "SiteLink-Site Links", 17, hasInventoryId: false, sqlitePrefix: ""),
        // Optional Features (forest-level)
        new("AD_OptionalFeature", "AD_OptionalFeature", "ADImport", "Optional Features", 18, hasInventoryId: false, sqlitePrefix: ""),
        // KMS, ADFS, and PKI tables (forest/domain configuration)
        new("AD_KMSService", "AD_KMSService", "ADImport", "KMS Services", 19, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_ADFSConfiguration", "AD_ADFSConfiguration", "ADImport", "ADFS Configuration", 20, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_EnterpriseCA", "AD_EnterpriseCA", "ADImport", "Enterprise CAs", 21, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_CertificateTemplate", "AD_CertificateTemplate", "ADImport", "Certificate Templates", 22, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_TrustedRootCA", "AD_TrustedRootCA", "ADImport", "Trusted Root CAs", 23, hasInventoryId: false, sqlitePrefix: ""),
        new("AD_NTAuthCA", "AD_NTAuthCA", "ADImport", "NTAuth CAs", 24, hasInventoryId: false, sqlitePrefix: ""),
    };

    /// <summary>
    /// Gets table mappings for the specified upload type.
    /// </summary>
    /// <param name="uploadType">The type of upload.</param>
    /// <returns>List of table mappings for that type.</returns>
    public static IReadOnlyList<TableMapping> GetMappings(UploadType uploadType) =>
        uploadType switch
        {
            UploadType.NTFSPermissions => NTFSPermissionsMappings,
            UploadType.ADInventory => ADInventoryMappings,
            _ => throw new ArgumentException($"Unknown upload type: {uploadType}")
        };

    /// <summary>
    /// Gets a table mapping by SQLite table name (NTFS Permissions only - legacy).
    /// </summary>
    public static TableMapping? GetBySqliteTable(string tableName)
    {
        var cleanName = tableName.StartsWith("app__", StringComparison.OrdinalIgnoreCase)
            ? tableName[5..]
            : tableName;
        return AllMappings.FirstOrDefault(m =>
            m.SqliteTable.Equals(cleanName, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Gets a table mapping by SQLite table name for a specific upload type.
    /// </summary>
    public static TableMapping? GetBySqliteTable(string tableName, UploadType uploadType)
    {
        var mappings = GetMappings(uploadType);

        // For NTFS, strip the app__ prefix if present
        if (uploadType == UploadType.NTFSPermissions)
        {
            var cleanName = tableName.StartsWith("app__", StringComparison.OrdinalIgnoreCase)
                ? tableName[5..]
                : tableName;
            return mappings.FirstOrDefault(m =>
                m.SqliteTable.Equals(cleanName, StringComparison.OrdinalIgnoreCase));
        }

        // For ADInventory, match the full table name (with AD_ prefix)
        return mappings.FirstOrDefault(m =>
            m.SqliteTable.Equals(tableName, StringComparison.OrdinalIgnoreCase) ||
            m.GetSqliteTableName().Equals(tableName, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Gets table mappings in import order (NTFS Permissions only - legacy).
    /// </summary>
    public static IEnumerable<TableMapping> GetImportOrder() =>
        AllMappings.OrderBy(m => m.ImportOrder);

    /// <summary>
    /// Gets table mappings in import order for a specific upload type.
    /// </summary>
    public static IEnumerable<TableMapping> GetImportOrder(UploadType uploadType) =>
        GetMappings(uploadType).OrderBy(m => m.ImportOrder);
}
