namespace CLAWS.Core.Models;

/// <summary>
/// Type of database upload.
/// </summary>
public enum UploadType
{
    /// <summary>
    /// Unknown or undetected database type.
    /// </summary>
    Unknown = 0,

    /// <summary>
    /// NTFS Permissions database from CollectNTFSPerms.
    /// Uses app__ table prefix and fssimport schema.
    /// </summary>
    NTFSPermissions = 1,

    /// <summary>
    /// Active Directory Inventory database from ADInventory module.
    /// Uses AD_ table prefix and ADImport schema.
    /// </summary>
    ADInventory = 2
}

/// <summary>
/// Extension methods for UploadType.
/// </summary>
public static class UploadTypeExtensions
{
    /// <summary>
    /// Gets a display-friendly name for the upload type.
    /// </summary>
    public static string GetDisplayName(this UploadType type) => type switch
    {
        UploadType.NTFSPermissions => "NTFS Permissions",
        UploadType.ADInventory => "AD Inventory",
        _ => "Unknown"
    };

    /// <summary>
    /// Gets the staging schema name for this upload type.
    /// </summary>
    public static string GetStagingSchema(this UploadType type) => type switch
    {
        UploadType.NTFSPermissions => "fssimport",
        UploadType.ADInventory => "ADImport",
        _ => throw new ArgumentException($"Unknown upload type: {type}")
    };

    /// <summary>
    /// Gets the production schema name for this upload type.
    /// </summary>
    public static string GetProductionSchema(this UploadType type) => type switch
    {
        UploadType.NTFSPermissions => "fsapp",
        UploadType.ADInventory => "ADData",
        _ => throw new ArgumentException($"Unknown upload type: {type}")
    };

    /// <summary>
    /// Gets the version schema name used in fsapp.SchemaVersion.
    /// </summary>
    public static string GetVersionSchemaName(this UploadType type) => type switch
    {
        UploadType.NTFSPermissions => "CollectNTFSPerm",
        UploadType.ADInventory => "ADInventory",
        _ => throw new ArgumentException($"Unknown upload type: {type}")
    };

    /// <summary>
    /// Gets the migration stored procedure name for this upload type.
    /// </summary>
    public static string GetMigrationProcedure(this UploadType type) => type switch
    {
        UploadType.NTFSPermissions => "dbo.usp_MigrateCollection",
        UploadType.ADInventory => "dbo.usp_ADInventory_TransferData",
        _ => throw new ArgumentException($"Unknown upload type: {type}")
    };

    /// <summary>
    /// Gets the validation stored procedure name for this upload type.
    /// </summary>
    public static string GetValidationProcedure(this UploadType type) => type switch
    {
        UploadType.NTFSPermissions => "dbo.usp_ValidateImportData",
        UploadType.ADInventory => "dbo.usp_ADInventory_ValidateData",
        _ => throw new ArgumentException($"Unknown upload type: {type}")
    };
}
