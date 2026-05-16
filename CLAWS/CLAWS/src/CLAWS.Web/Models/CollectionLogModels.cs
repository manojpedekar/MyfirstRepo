namespace CLAWS.Web.Models;

/// <summary>
/// Filter options for collection log queries.
/// </summary>
public class CollectionLogFilter
{
    /// <summary>
    /// Filter by severity level (ERROR, WARNING, INFO, SUCCESS).
    /// </summary>
    public string? Severity { get; set; }

    /// <summary>
    /// Free text search in Message and Path fields.
    /// </summary>
    public string? SearchText { get; set; }

    /// <summary>
    /// Filter by source component.
    /// </summary>
    public string? Source { get; set; }

    /// <summary>
    /// Filter logs from this date onwards.
    /// </summary>
    public DateTime? FromDate { get; set; }

    /// <summary>
    /// Filter logs up to this date.
    /// </summary>
    public DateTime? ToDate { get; set; }

    /// <summary>
    /// Column to sort by (default: Timestamp).
    /// </summary>
    public string SortBy { get; set; } = "Timestamp";

    /// <summary>
    /// Sort in descending order (default: false for oldest to newest).
    /// </summary>
    public bool Descending { get; set; } = false;
}

/// <summary>
/// Represents a single collection log entry from EventLog table.
/// </summary>
public class CollectionLogEntry
{
    /// <summary>
    /// Unique event identifier.
    /// </summary>
    public int EventId { get; set; }

    /// <summary>
    /// Inventory ID this log belongs to.
    /// </summary>
    public Guid InventoryId { get; set; }

    /// <summary>
    /// When the event occurred.
    /// </summary>
    public DateTimeOffset Timestamp { get; set; }

    /// <summary>
    /// Log severity level.
    /// </summary>
    public string Severity { get; set; } = string.Empty;

    /// <summary>
    /// Component that generated the log.
    /// </summary>
    public string Source { get; set; } = string.Empty;

    /// <summary>
    /// Log message content.
    /// </summary>
    public string Message { get; set; } = string.Empty;

    /// <summary>
    /// File/folder path related to the event.
    /// </summary>
    public string? Path { get; set; }

    /// <summary>
    /// Windows error code if applicable.
    /// </summary>
    public int? ErrorCode { get; set; }

    /// <summary>
    /// Additional context information for the log entry (AD logs only).
    /// </summary>
    public string? Context { get; set; }

    /// <summary>
    /// Exception message if an exception occurred (AD logs only).
    /// </summary>
    public string? ExceptionMessage { get; set; }

    /// <summary>
    /// Exception type if an exception occurred (AD logs only).
    /// </summary>
    public string? ExceptionType { get; set; }

    /// <summary>
    /// Gets the Bootstrap badge CSS class for the severity level.
    /// </summary>
    public string SeverityBadgeClass => Severity?.ToUpperInvariant() switch
    {
        "ERROR" => "bg-danger",
        "WARNING" => "bg-warning text-dark",
        "INFO" => "bg-info",
        "SUCCESS" => "bg-success",
        "DEBUG" => "bg-secondary",
        _ => "bg-secondary"
    };

    /// <summary>
    /// Gets the Bootstrap icon class for the severity level.
    /// </summary>
    public string SeverityIcon => Severity?.ToUpperInvariant() switch
    {
        "ERROR" => "bi-x-circle-fill",
        "WARNING" => "bi-exclamation-triangle-fill",
        "INFO" => "bi-info-circle-fill",
        "SUCCESS" => "bi-check-circle-fill",
        "DEBUG" => "bi-bug-fill",
        _ => "bi-circle-fill"
    };
}

/// <summary>
/// Paginated result container for collection logs.
/// </summary>
public class PagedCollectionLogs
{
    /// <summary>
    /// Upload ID these logs belong to.
    /// </summary>
    public Guid UploadId { get; set; }

    /// <summary>
    /// Specific inventory ID if filtered, null for all inventories.
    /// </summary>
    public Guid? InventoryId { get; set; }

    /// <summary>
    /// Human-readable label for the inventory/upload.
    /// </summary>
    public string? InventoryLabel { get; set; }

    /// <summary>
    /// Schema the data was retrieved from (fssimport or fsapp).
    /// </summary>
    public string DataSource { get; set; } = "fssimport";

    /// <summary>
    /// Whether the upload has been merged to production schema.
    /// </summary>
    public bool IsMerged { get; set; }

    /// <summary>
    /// The log entries for the current page.
    /// </summary>
    public List<CollectionLogEntry> Logs { get; set; } = new();

    /// <summary>
    /// Current page number (1-based).
    /// </summary>
    public int Page { get; set; } = 1;

    /// <summary>
    /// Number of items per page.
    /// </summary>
    public int PageSize { get; set; } = 50;

    /// <summary>
    /// Total number of items matching the filter.
    /// </summary>
    public int TotalItems { get; set; }

    /// <summary>
    /// Total number of pages.
    /// </summary>
    public int TotalPages => PageSize > 0 ? (int)Math.Ceiling(TotalItems / (double)PageSize) : 0;

    /// <summary>
    /// Whether there's a previous page.
    /// </summary>
    public bool HasPreviousPage => Page > 1;

    /// <summary>
    /// Whether there's a next page.
    /// </summary>
    public bool HasNextPage => Page < TotalPages;

    /// <summary>
    /// Applied filters for display.
    /// </summary>
    public CollectionLogFilter? AppliedFilter { get; set; }

    /// <summary>
    /// List of distinct severity values available for filtering.
    /// </summary>
    public List<string> AvailableSeverities { get; set; } = new() { "ERROR", "WARNING", "INFO", "SUCCESS", "DEBUG" };

    /// <summary>
    /// List of distinct source values available for filtering.
    /// </summary>
    public List<string> AvailableSources { get; set; } = new();
}

/// <summary>
/// API response for collection logs endpoint.
/// </summary>
public class CollectionLogsApiResponse
{
    public bool Success { get; set; }
    public string? Error { get; set; }
    public PagedCollectionLogs? Data { get; set; }

    public static CollectionLogsApiResponse Ok(PagedCollectionLogs data) => new()
    {
        Success = true,
        Data = data
    };

    public static CollectionLogsApiResponse Fail(string error) => new()
    {
        Success = false,
        Error = error
    };
}
