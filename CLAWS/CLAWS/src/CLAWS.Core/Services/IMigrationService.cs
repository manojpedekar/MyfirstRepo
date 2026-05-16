namespace CLAWS.Core.Services;

/// <summary>
/// Result of a migration operation.
/// </summary>
public class MigrationResult
{
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
    public List<InventoryMigrationResult> InventoryResults { get; set; } = new();
    public int TotalErrorCount { get; set; }
}

/// <summary>
/// Result for a single inventory migration.
/// </summary>
public class InventoryMigrationResult
{
    public Guid InventoryId { get; set; }
    public bool ValidationPassed { get; set; }
    public int ValidationErrorCount { get; set; }
    public bool MigrationSuccess { get; set; }
    public string? ErrorMessage { get; set; }

    /// <summary>
    /// Detailed validation errors when validation fails.
    /// </summary>
    public List<ValidationErrorDetail> ValidationErrors { get; set; } = new();
}

/// <summary>
/// Detailed validation error information from stored procedure.
/// </summary>
public class ValidationErrorDetail
{
    public string Category { get; set; } = string.Empty;
    public string Severity { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public string ErrorMessage { get; set; } = string.Empty;
    public int AffectedCount { get; set; }
}

/// <summary>
/// Information about an inventory for display.
/// </summary>
public class InventoryInfo
{
    public Guid InventoryId { get; set; }
    public string? ComputerName { get; set; }
    public string? ScanPath { get; set; }
    public DateTime? CollectionDateTime { get; set; }
    public long TotalRecords { get; set; }
}

/// <summary>
/// Information about an orphaned inventory (in fssimport but no upload record).
/// </summary>
public class OrphanedInventoryInfo
{
    public Guid InventoryId { get; set; }
    public string? ComputerName { get; set; }
    public string? ScanPath { get; set; }
    public DateTime? CollectionDateTime { get; set; }
    public long FoldersCount { get; set; }
    public long FilesCount { get; set; }
    public long PermissionsCount { get; set; }
}

/// <summary>
/// Information about an AD domain from ADInventory upload.
/// </summary>
public class ADInventoryDomainInfo
{
    public Guid InventoryId { get; set; }
    /// <summary>
    /// The CollectionID (UNIQUEIDENTIFIER) for this domain.
    /// </summary>
    public Guid CollectionId { get; set; }
    public string DomainName { get; set; } = string.Empty;
    public DateTime? CollectionDateTime { get; set; }
    public long TotalRecords { get; set; }
}

/// <summary>
/// Service for validating and migrating imported data to fsapp schema.
/// </summary>
public interface IMigrationService
{
    /// <summary>
    /// Gets the inventory IDs associated with an upload.
    /// </summary>
    Task<List<Guid>> GetInventoryIdsAsync(Guid uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets detailed inventory information for an upload.
    /// </summary>
    Task<List<InventoryInfo>> GetInventoryInfoAsync(Guid uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets ADInventory domain information with record counts for an upload.
    /// </summary>
    Task<List<ADInventoryDomainInfo>> GetADInventoryDomainInfoAsync(Guid uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Validates import data for all inventories in an upload.
    /// </summary>
    Task<MigrationResult> ValidateAsync(Guid uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Migrates validated data to fsapp schema for all inventories in an upload.
    /// </summary>
    Task<MigrationResult> MigrateAsync(Guid uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Validates and then migrates data (combined workflow).
    /// </summary>
    Task<MigrationResult> ValidateAndMigrateAsync(Guid uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Cleans up imported data from fssimport schema for all inventories in an upload.
    /// </summary>
    Task<(bool Success, string Message)> CleanupImportDataAsync(Guid uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets orphaned inventories in fssimport schema (no associated upload record).
    /// </summary>
    Task<List<OrphanedInventoryInfo>> GetOrphanedInventoriesAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Cleans up a specific orphaned inventory from fssimport schema.
    /// </summary>
    Task<(bool Success, string Message)> CleanupOrphanedInventoryAsync(Guid inventoryId, CancellationToken cancellationToken);

    /// <summary>
    /// Cleans up all orphaned inventories from fssimport schema.
    /// </summary>
    Task<(int Cleaned, int Failed, string Message)> CleanupAllOrphanedInventoriesAsync(CancellationToken cancellationToken);
}
