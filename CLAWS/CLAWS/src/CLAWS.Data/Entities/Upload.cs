using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CLAWS.Data.Entities;

/// <summary>
/// Represents an upload record in the database.
/// </summary>
[Table("Uploads", Schema = "app")]
public class Upload
{
    /// <summary>
    /// Unique identifier for the upload.
    /// </summary>
    [Key]
    public Guid UploadId { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Original filename of the uploaded file.
    /// </summary>
    [Required]
    [MaxLength(500)]
    public string OriginalFilename { get; set; } = string.Empty;

    /// <summary>
    /// Size of the uploaded file in bytes.
    /// </summary>
    public long FileSizeBytes { get; set; }

    /// <summary>
    /// Username of the person who uploaded the file.
    /// </summary>
    [Required]
    [MaxLength(256)]
    public string UploadedBy { get; set; } = string.Empty;

    /// <summary>
    /// When the file was uploaded.
    /// </summary>
    public DateTime UploadedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Source IP address of the upload.
    /// </summary>
    [MaxLength(45)]
    public string? SourceIP { get; set; }

    /// <summary>
    /// Current status of the upload.
    /// </summary>
    [Required]
    [MaxLength(50)]
    public string Status { get; set; } = "Uploading";

    /// <summary>
    /// Status message or description.
    /// </summary>
    public string? StatusMessage { get; set; }

    /// <summary>
    /// JSON-serialized validation result details.
    /// </summary>
    public string? ValidationResult { get; set; }

    /// <summary>
    /// Import progress percentage (0-100).
    /// </summary>
    public int? ImportProgress { get; set; }

    /// <summary>
    /// Current phase of processing.
    /// </summary>
    [MaxLength(100)]
    public string? CurrentPhase { get; set; }

    /// <summary>
    /// Number of rows processed so far.
    /// </summary>
    public long? RowsProcessed { get; set; }

    /// <summary>
    /// Total estimated rows to process.
    /// </summary>
    public long? TotalRows { get; set; }

    /// <summary>
    /// When the current phase started.
    /// </summary>
    public DateTime? PhaseStartedAt { get; set; }

    /// <summary>
    /// When processing started.
    /// </summary>
    public DateTime? StartedAt { get; set; }

    /// <summary>
    /// When processing completed.
    /// </summary>
    public DateTime? CompletedAt { get; set; }

    /// <summary>
    /// Current file path.
    /// </summary>
    [MaxLength(1000)]
    public string? FilePath { get; set; }

    /// <summary>
    /// Error details if failed.
    /// </summary>
    public string? ErrorDetails { get; set; }

    /// <summary>
    /// Hangfire job ID for tracking.
    /// </summary>
    [MaxLength(100)]
    public string? HangfireJobId { get; set; }

    /// <summary>
    /// Validation status: NotValidated, Passed, Failed.
    /// </summary>
    [MaxLength(20)]
    public string ValidationStatus { get; set; } = "NotValidated";

    /// <summary>
    /// Validation result message.
    /// </summary>
    public string? ValidationMessage { get; set; }

    /// <summary>
    /// When validation was completed.
    /// </summary>
    public DateTime? ValidationCompletedAt { get; set; }

    /// <summary>
    /// Merge status: NotMerged, Merged, PartiallyMerged, Failed.
    /// </summary>
    [MaxLength(20)]
    public string MergeStatus { get; set; } = "NotMerged";

    /// <summary>
    /// Merge result message.
    /// </summary>
    public string? MergeMessage { get; set; }

    /// <summary>
    /// When merge was completed.
    /// </summary>
    public DateTime? MergeCompletedAt { get; set; }

    /// <summary>
    /// Per-upload override for automatic processing behavior.
    /// Values: null (use global settings), "ValidateOnly", "ValidateAndMerge", "Manual".
    /// </summary>
    [MaxLength(20)]
    public string? AutoProcessingOverride { get; set; }

    /// <summary>
    /// Type of upload (NTFSPermissions, ADInventory, etc.).
    /// Stored as string for readability and database compatibility.
    /// Default is "NTFSPermissions" for backward compatibility.
    /// </summary>
    [MaxLength(30)]
    public string UploadType { get; set; } = "NTFSPermissions";

    /// <summary>
    /// Import statistics for this upload.
    /// </summary>
    public virtual ICollection<ImportStatistic> ImportStatistics { get; set; } = new List<ImportStatistic>();
}
