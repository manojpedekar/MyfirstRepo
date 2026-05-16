namespace CLAWS.Core.Models;

/// <summary>
/// Represents the progress of an import operation.
/// </summary>
public class ImportProgress
{
    /// <summary>
    /// The upload ID this progress relates to.
    /// </summary>
    public Guid UploadId { get; set; }

    /// <summary>
    /// Current phase of the import.
    /// </summary>
    public string Phase { get; set; } = string.Empty;

    /// <summary>
    /// Current table being processed.
    /// </summary>
    public string? CurrentTable { get; set; }

    /// <summary>
    /// Overall progress percentage (0-100).
    /// </summary>
    public int PercentComplete { get; set; }

    /// <summary>
    /// Number of rows processed so far.
    /// </summary>
    public long RowsProcessed { get; set; }

    /// <summary>
    /// Estimated total rows to process.
    /// </summary>
    public long TotalRows { get; set; }

    /// <summary>
    /// Current status message.
    /// </summary>
    public string Message { get; set; } = string.Empty;

    /// <summary>
    /// When the current phase started.
    /// </summary>
    public DateTime PhaseStartedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Estimated time remaining in seconds.
    /// </summary>
    public int? EstimatedSecondsRemaining { get; set; }
}

/// <summary>
/// Statistics for a completed import.
/// </summary>
public class ImportStatistics
{
    /// <summary>
    /// The upload ID these statistics relate to.
    /// </summary>
    public Guid UploadId { get; set; }

    /// <summary>
    /// When the import started.
    /// </summary>
    public DateTime StartedAt { get; set; }

    /// <summary>
    /// When the import completed.
    /// </summary>
    public DateTime CompletedAt { get; set; }

    /// <summary>
    /// Total duration of the import.
    /// </summary>
    public TimeSpan Duration => CompletedAt - StartedAt;

    /// <summary>
    /// Statistics per table.
    /// </summary>
    public List<TableImportStatistic> TableStatistics { get; set; } = new();

    /// <summary>
    /// Total records imported across all tables.
    /// </summary>
    public long TotalRecordsImported => TableStatistics.Sum(t => t.RecordsImported);
}

/// <summary>
/// Statistics for a single table import.
/// </summary>
public class TableImportStatistic
{
    /// <summary>
    /// Inventory ID for this collection.
    /// </summary>
    public Guid InventoryId { get; set; }

    /// <summary>
    /// Name of the table.
    /// </summary>
    public string TableName { get; set; } = string.Empty;

    /// <summary>
    /// Number of records imported.
    /// </summary>
    public long RecordsImported { get; set; }

    /// <summary>
    /// Duration in milliseconds.
    /// </summary>
    public long DurationMs { get; set; }

    /// <summary>
    /// Records per second.
    /// </summary>
    public double RecordsPerSecond => DurationMs > 0 ? RecordsImported * 1000.0 / DurationMs : 0;
}
