namespace CLAWS.Core.Models;

/// <summary>
/// Result of a validation operation.
/// </summary>
public class ValidationResult
{
    /// <summary>
    /// Indicates whether validation was successful.
    /// </summary>
    public bool IsValid { get; set; }

    /// <summary>
    /// Error code if validation failed.
    /// </summary>
    public string? ErrorCode { get; set; }

    /// <summary>
    /// Human-readable error message.
    /// </summary>
    public string? ErrorMessage { get; set; }

    /// <summary>
    /// Additional details about the validation result.
    /// </summary>
    public Dictionary<string, object>? Details { get; set; }

    /// <summary>
    /// Creates a successful validation result.
    /// </summary>
    public static ValidationResult Success() => new() { IsValid = true };

    /// <summary>
    /// Creates a failed validation result.
    /// </summary>
    public static ValidationResult Failure(string errorCode, string message, Dictionary<string, object>? details = null)
        => new()
        {
            IsValid = false,
            ErrorCode = errorCode,
            ErrorMessage = message,
            Details = details
        };
}

/// <summary>
/// Result of ZIP file validation.
/// </summary>
public class ZipValidationResult : ValidationResult
{
    /// <summary>
    /// Name of the single file inside the ZIP.
    /// </summary>
    public string? EntryFileName { get; set; }

    /// <summary>
    /// Uncompressed size of the entry in bytes.
    /// </summary>
    public long UncompressedSize { get; set; }

    /// <summary>
    /// Compressed size in bytes.
    /// </summary>
    public long CompressedSize { get; set; }

    /// <summary>
    /// Compression ratio (compressed/uncompressed).
    /// </summary>
    public double CompressionRatio { get; set; }
}

/// <summary>
/// Result of SQLite database validation.
/// </summary>
public class DatabaseValidationResult : ValidationResult
{
    /// <summary>
    /// Schema version found in the database.
    /// </summary>
    public string? DbVersion { get; set; }

    /// <summary>
    /// Minimum required schema version.
    /// </summary>
    public string? RequiredDbVersion { get; set; }

    /// <summary>
    /// Collection information found in the database.
    /// </summary>
    public List<CollectionInfo> Collections { get; set; } = new();

    /// <summary>
    /// Collections that failed version validation.
    /// </summary>
    public List<CollectionVersionError> VersionErrors { get; set; } = new();
}

/// <summary>
/// Information about a collection in the SQLite database.
/// </summary>
public class CollectionInfo
{
    /// <summary>
    /// Unique identifier for the collection.
    /// </summary>
    public Guid InventoryId { get; set; }

    /// <summary>
    /// Application version that created this collection.
    /// </summary>
    public string ApplicationVersion { get; set; } = string.Empty;

    /// <summary>
    /// Name of the computer where collection was performed.
    /// </summary>
    public string? ComputerName { get; set; }

    /// <summary>
    /// Timestamp when collection was performed.
    /// </summary>
    public DateTime? CollectionDate { get; set; }
}

/// <summary>
/// Details about a collection that failed version validation.
/// </summary>
public class CollectionVersionError
{
    /// <summary>
    /// The collection that failed validation.
    /// </summary>
    public Guid InventoryId { get; set; }

    /// <summary>
    /// The application version found.
    /// </summary>
    public string FoundVersion { get; set; } = string.Empty;

    /// <summary>
    /// The minimum required version.
    /// </summary>
    public string RequiredVersion { get; set; } = string.Empty;
}

/// <summary>
/// Result of duplicate inventory check.
/// </summary>
public class DuplicateCheckResult : ValidationResult
{
    /// <summary>
    /// List of duplicate inventories found.
    /// </summary>
    public List<DuplicateInventoryInfo> Duplicates { get; set; } = new();

    /// <summary>
    /// Creates a successful result (no duplicates found).
    /// </summary>
    public static new DuplicateCheckResult Success() => new() { IsValid = true };

    /// <summary>
    /// Creates a failure result with duplicate information.
    /// </summary>
    public static DuplicateCheckResult DuplicatesFound(List<DuplicateInventoryInfo> duplicates)
    {
        var locations = duplicates.Select(d => d.Location).Distinct().ToList();
        var locationDesc = locations.Count == 1
            ? (locations[0] == DuplicateLocation.Production ? "production (already merged)" : "staging (pending merge)")
            : "production and staging";

        return new DuplicateCheckResult
        {
            IsValid = false,
            ErrorCode = "DUPLICATE_INVENTORY",
            ErrorMessage = $"Found {duplicates.Count} duplicate inventory ID(s) already in {locationDesc}. " +
                          "This data has already been imported. Delete the existing import before re-uploading.",
            Duplicates = duplicates
        };
    }
}

/// <summary>
/// Information about a duplicate inventory.
/// </summary>
public class DuplicateInventoryInfo
{
    /// <summary>
    /// The duplicate inventory ID.
    /// </summary>
    public Guid InventoryId { get; set; }

    /// <summary>
    /// Computer name from the duplicate collection.
    /// </summary>
    public string? ComputerName { get; set; }

    /// <summary>
    /// Where the duplicate was found.
    /// </summary>
    public DuplicateLocation Location { get; set; }

    /// <summary>
    /// When the existing data was imported (if available).
    /// </summary>
    public DateTime? ExistingImportDate { get; set; }
}

/// <summary>
/// Location where duplicate was found.
/// </summary>
public enum DuplicateLocation
{
    /// <summary>
    /// Found in fssimport schema (imported but not merged).
    /// </summary>
    Staging,

    /// <summary>
    /// Found in fsapp schema (already merged to production).
    /// </summary>
    Production
}
