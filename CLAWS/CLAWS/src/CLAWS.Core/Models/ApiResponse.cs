using System.Text.Json.Serialization;

namespace CLAWS.Core.Models;

/// <summary>
/// Standard API response wrapper.
/// </summary>
/// <typeparam name="T">Type of the data payload.</typeparam>
public class ApiResponse<T>
{
    /// <summary>
    /// Indicates whether the request was successful.
    /// </summary>
    [JsonPropertyName("success")]
    public bool Success { get; set; }

    /// <summary>
    /// Response data (present on success).
    /// </summary>
    [JsonPropertyName("data")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public T? Data { get; set; }

    /// <summary>
    /// Error information (present on failure).
    /// </summary>
    [JsonPropertyName("error")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public ApiError? Error { get; set; }

    /// <summary>
    /// UTC timestamp of the response.
    /// </summary>
    [JsonPropertyName("timestamp")]
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Creates a successful response.
    /// </summary>
    public static ApiResponse<T> Ok(T data) => new()
    {
        Success = true,
        Data = data
    };

    /// <summary>
    /// Creates a failure response.
    /// </summary>
    public static ApiResponse<T> Fail(string code, string message, object? details = null) => new()
    {
        Success = false,
        Error = new ApiError
        {
            Code = code,
            Message = message,
            Details = details
        }
    };
}

/// <summary>
/// Non-generic API response for operations with no data.
/// </summary>
public class ApiResponse : ApiResponse<object>
{
    /// <summary>
    /// Creates a successful response with no data.
    /// </summary>
    public static ApiResponse Ok()
    {
        var response = new ApiResponse();
        response.Success = true;
        return response;
    }

    /// <summary>
    /// Creates a failure response.
    /// </summary>
    public new static ApiResponse Fail(string code, string message, object? details = null)
    {
        var response = new ApiResponse();
        response.Success = false;
        response.Error = new ApiError
        {
            Code = code,
            Message = message,
            Details = details
        };
        return response;
    }
}

/// <summary>
/// API error information.
/// </summary>
public class ApiError
{
    /// <summary>
    /// Error code (e.g., "VALIDATION_FAILED").
    /// </summary>
    [JsonPropertyName("code")]
    public string Code { get; set; } = string.Empty;

    /// <summary>
    /// Human-readable error message.
    /// </summary>
    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;

    /// <summary>
    /// Additional error details.
    /// </summary>
    [JsonPropertyName("details")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public object? Details { get; set; }
}

/// <summary>
/// Upload response data.
/// </summary>
public class UploadResponseData
{
    /// <summary>
    /// Unique identifier for the upload.
    /// </summary>
    [JsonPropertyName("uploadId")]
    public Guid UploadId { get; set; }

    /// <summary>
    /// Current status of the upload.
    /// </summary>
    [JsonPropertyName("status")]
    public string Status { get; set; } = string.Empty;

    /// <summary>
    /// Status message.
    /// </summary>
    [JsonPropertyName("message")]
    public string? Message { get; set; }

    /// <summary>
    /// Type of upload (NTFSPermissions, ADInventory, etc.).
    /// </summary>
    [JsonPropertyName("uploadType")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? UploadType { get; set; }

    /// <summary>
    /// Position in the import queue (if queued).
    /// </summary>
    [JsonPropertyName("queuePosition")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? QueuePosition { get; set; }
}

/// <summary>
/// Upload status response data.
/// </summary>
public class UploadStatusData
{
    /// <summary>
    /// Unique identifier for the upload.
    /// </summary>
    [JsonPropertyName("uploadId")]
    public Guid UploadId { get; set; }

    /// <summary>
    /// Original filename.
    /// </summary>
    [JsonPropertyName("originalFilename")]
    public string OriginalFilename { get; set; } = string.Empty;

    /// <summary>
    /// File size in bytes.
    /// </summary>
    [JsonPropertyName("fileSizeBytes")]
    public long FileSizeBytes { get; set; }

    /// <summary>
    /// Current status.
    /// </summary>
    [JsonPropertyName("status")]
    public string Status { get; set; } = string.Empty;

    /// <summary>
    /// Status message.
    /// </summary>
    [JsonPropertyName("statusMessage")]
    public string? StatusMessage { get; set; }

    /// <summary>
    /// Type of upload (NTFSPermissions, ADInventory, etc.).
    /// </summary>
    [JsonPropertyName("uploadType")]
    public string UploadType { get; set; } = "NTFSPermissions";

    /// <summary>
    /// Current phase (if importing).
    /// </summary>
    [JsonPropertyName("currentPhase")]
    public string? CurrentPhase { get; set; }

    /// <summary>
    /// Import progress percentage (0-100).
    /// </summary>
    [JsonPropertyName("importProgress")]
    public int? ImportProgress { get; set; }

    /// <summary>
    /// When the upload was received.
    /// </summary>
    [JsonPropertyName("uploadedAt")]
    public DateTime UploadedAt { get; set; }

    /// <summary>
    /// When processing started.
    /// </summary>
    [JsonPropertyName("startedAt")]
    public DateTime? StartedAt { get; set; }

    /// <summary>
    /// When processing completed.
    /// </summary>
    [JsonPropertyName("completedAt")]
    public DateTime? CompletedAt { get; set; }

    /// <summary>
    /// Who uploaded the file.
    /// </summary>
    [JsonPropertyName("uploadedBy")]
    public string UploadedBy { get; set; } = string.Empty;

    /// <summary>
    /// Error details if failed.
    /// </summary>
    [JsonPropertyName("errorDetails")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? ErrorDetails { get; set; }
}

/// <summary>
/// Real-time progress data for polling.
/// </summary>
public class ProgressData
{
    /// <summary>
    /// Upload ID.
    /// </summary>
    [JsonPropertyName("uploadId")]
    public Guid UploadId { get; set; }

    /// <summary>
    /// Current status.
    /// </summary>
    [JsonPropertyName("status")]
    public string Status { get; set; } = string.Empty;

    /// <summary>
    /// Current phase (e.g., "Importing Folders").
    /// </summary>
    [JsonPropertyName("phase")]
    public string? Phase { get; set; }

    /// <summary>
    /// Progress percentage (0-100).
    /// </summary>
    [JsonPropertyName("progress")]
    public int Progress { get; set; }

    /// <summary>
    /// Rows processed so far.
    /// </summary>
    [JsonPropertyName("rowsProcessed")]
    public long RowsProcessed { get; set; }

    /// <summary>
    /// Total rows to process.
    /// </summary>
    [JsonPropertyName("totalRows")]
    public long TotalRows { get; set; }

    /// <summary>
    /// Status message.
    /// </summary>
    [JsonPropertyName("message")]
    public string? Message { get; set; }

    /// <summary>
    /// When the current phase started.
    /// </summary>
    [JsonPropertyName("phaseStartedAt")]
    public DateTime? PhaseStartedAt { get; set; }

    /// <summary>
    /// When processing started.
    /// </summary>
    [JsonPropertyName("startedAt")]
    public DateTime? StartedAt { get; set; }

    /// <summary>
    /// Records per second (calculated).
    /// </summary>
    [JsonPropertyName("recordsPerSecond")]
    public double RecordsPerSecond { get; set; }

    /// <summary>
    /// Estimated seconds remaining.
    /// </summary>
    [JsonPropertyName("estimatedSecondsRemaining")]
    public int? EstimatedSecondsRemaining { get; set; }

    /// <summary>
    /// Whether the operation is complete.
    /// </summary>
    [JsonPropertyName("isComplete")]
    public bool IsComplete { get; set; }
}

/// <summary>
/// Health check response.
/// </summary>
public class HealthCheckData
{
    /// <summary>
    /// Overall health status.
    /// </summary>
    [JsonPropertyName("status")]
    public string Status { get; set; } = "healthy";

    /// <summary>
    /// Application version.
    /// </summary>
    [JsonPropertyName("version")]
    public string Version { get; set; } = string.Empty;

    /// <summary>
    /// Individual component checks.
    /// </summary>
    [JsonPropertyName("checks")]
    public Dictionary<string, HealthCheckComponent> Checks { get; set; } = new();
}

/// <summary>
/// Individual health check component.
/// </summary>
public class HealthCheckComponent
{
    /// <summary>
    /// Component status.
    /// </summary>
    [JsonPropertyName("status")]
    public string Status { get; set; } = "healthy";

    /// <summary>
    /// Additional details.
    /// </summary>
    [JsonPropertyName("details")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public object? Details { get; set; }
}
