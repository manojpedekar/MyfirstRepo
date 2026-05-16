using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CLAWS.Data.Entities;

/// <summary>
/// Represents a log entry in the database.
/// </summary>
[Table("Logs", Schema = "app")]
public class LogEntry
{
    /// <summary>
    /// Unique identifier for the log entry.
    /// </summary>
    [Key]
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public long LogId { get; set; }

    /// <summary>
    /// When the log entry was created.
    /// </summary>
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Syslog facility code.
    /// </summary>
    public byte Facility { get; set; }

    /// <summary>
    /// Syslog severity level.
    /// </summary>
    public byte Severity { get; set; }

    /// <summary>
    /// Severity name (DEBUG, INFO, WARNING, ERROR, CRITICAL).
    /// </summary>
    [Required]
    [MaxLength(15)]
    public string SeverityName { get; set; } = string.Empty;

    /// <summary>
    /// Server hostname.
    /// </summary>
    [Required]
    [MaxLength(255)]
    public string Hostname { get; set; } = string.Empty;

    /// <summary>
    /// Application name.
    /// </summary>
    [Required]
    [MaxLength(100)]
    public string AppName { get; set; } = "CLAWS";

    /// <summary>
    /// Process ID.
    /// </summary>
    public int? ProcessId { get; set; }

    /// <summary>
    /// Structured message type.
    /// </summary>
    [MaxLength(50)]
    public string? MessageId { get; set; }

    /// <summary>
    /// Correlation ID for linking related log entries.
    /// </summary>
    public Guid? CorrelationId { get; set; }

    /// <summary>
    /// Reference to an upload (if applicable).
    /// </summary>
    public Guid? UploadId { get; set; }

    /// <summary>
    /// Windows username or API key ID.
    /// </summary>
    [MaxLength(256)]
    public string? UserId { get; set; }

    /// <summary>
    /// Client IP address.
    /// </summary>
    [MaxLength(45)]
    public string? SourceIP { get; set; }

    /// <summary>
    /// Logger category/class name.
    /// </summary>
    [MaxLength(100)]
    public string? Category { get; set; }

    /// <summary>
    /// Log message.
    /// </summary>
    [Required]
    public string Message { get; set; } = string.Empty;

    /// <summary>
    /// Exception details if applicable.
    /// </summary>
    public string? Exception { get; set; }

    /// <summary>
    /// JSON-serialized structured data.
    /// </summary>
    public string? Properties { get; set; }
}

/// <summary>
/// Syslog facility codes for the application.
/// </summary>
public static class LogFacility
{
    public const byte Upload = 16;        // local0
    public const byte Validation = 17;    // local1
    public const byte Import = 18;        // local2
    public const byte Api = 19;           // local3
    public const byte ScheduledTask = 20; // local4
    public const byte Security = 21;      // local5
    public const byte Configuration = 22; // local6
    public const byte System = 23;        // local7
}

/// <summary>
/// Syslog severity levels.
/// </summary>
public static class LogSeverity
{
    public const byte Emergency = 0;
    public const byte Alert = 1;
    public const byte Critical = 2;
    public const byte Error = 3;
    public const byte Warning = 4;
    public const byte Notice = 5;
    public const byte Info = 6;
    public const byte Debug = 7;
}

/// <summary>
/// Standard message IDs for structured logging.
/// </summary>
public static class MessageIds
{
    public const string UploadStart = "UPLOAD_START";
    public const string UploadComplete = "UPLOAD_COMPLETE";
    public const string UploadFailed = "UPLOAD_FAILED";
    public const string ValidationStart = "VALIDATION_START";
    public const string ValidationPass = "VALIDATION_PASS";
    public const string ValidationFail = "VALIDATION_FAIL";
    public const string ImportQueued = "IMPORT_QUEUED";
    public const string ImportStart = "IMPORT_START";
    public const string ImportProgress = "IMPORT_PROGRESS";
    public const string ImportComplete = "IMPORT_COMPLETE";
    public const string ImportFailed = "IMPORT_FAILED";
    public const string ApiRequest = "API_REQUEST";
    public const string ApiAuthFail = "API_AUTH_FAIL";
    public const string ConfigChange = "CONFIG_CHANGE";
    public const string TaskRun = "TASK_RUN";
    public const string SecurityEvent = "SECURITY_EVENT";
    public const string DiskWarning = "DISK_WARNING";
    public const string DiskCritical = "DISK_CRITICAL";
}
