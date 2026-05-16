using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CLAWS.Data.Entities;

/// <summary>
/// Represents import statistics for a single table.
/// </summary>
[Table("ImportStatistics", Schema = "app")]
public class ImportStatistic
{
    /// <summary>
    /// Unique identifier for the statistic record.
    /// </summary>
    [Key]
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public long StatId { get; set; }

    /// <summary>
    /// Reference to the upload.
    /// </summary>
    public Guid UploadId { get; set; }

    /// <summary>
    /// Inventory ID of the imported collection.
    /// </summary>
    public Guid InventoryId { get; set; }

    /// <summary>
    /// Name of the table.
    /// </summary>
    [Required]
    [MaxLength(128)]
    public string TableName { get; set; } = string.Empty;

    /// <summary>
    /// Number of records imported.
    /// </summary>
    public long RecordsImported { get; set; }

    /// <summary>
    /// Duration of the import in milliseconds.
    /// </summary>
    public long DurationMs { get; set; }

    /// <summary>
    /// Navigation property to the upload.
    /// </summary>
    [ForeignKey(nameof(UploadId))]
    public virtual Upload? Upload { get; set; }
}
