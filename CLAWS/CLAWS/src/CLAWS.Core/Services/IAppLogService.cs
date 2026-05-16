namespace CLAWS.Core.Services;

/// <summary>
/// Service for writing structured log entries to the app.Logs table.
/// </summary>
public interface IAppLogService
{
    /// <summary>
    /// Logs an upload start event.
    /// </summary>
    Task LogUploadStartAsync(Guid uploadId, string filename, long fileSize, string? userId, string? sourceIp, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs an upload completion event.
    /// </summary>
    Task LogUploadCompleteAsync(Guid uploadId, string filename, string? userId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs an upload failure event.
    /// </summary>
    Task LogUploadFailedAsync(Guid uploadId, string filename, string error, string? userId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs an import queued event.
    /// </summary>
    Task LogImportQueuedAsync(Guid uploadId, string filename, string? userId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs an import start event.
    /// </summary>
    Task LogImportStartAsync(Guid uploadId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs an import completion event.
    /// </summary>
    Task LogImportCompleteAsync(Guid uploadId, long recordsImported, TimeSpan duration, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs an import failure event.
    /// </summary>
    Task LogImportFailedAsync(Guid uploadId, string error, string? exception, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs a validation pass event.
    /// </summary>
    Task LogValidationPassAsync(Guid uploadId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs a validation failure event.
    /// </summary>
    Task LogValidationFailAsync(Guid uploadId, string error, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs a merge start event.
    /// </summary>
    Task LogMergeStartAsync(Guid uploadId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs a merge completion event.
    /// </summary>
    Task LogMergeCompleteAsync(Guid uploadId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs a merge failure event.
    /// </summary>
    Task LogMergeFailedAsync(Guid uploadId, string error, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs a disk space warning.
    /// </summary>
    Task LogDiskWarningAsync(string driveName, double freePercent, string freeFormatted, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs a disk space critical alert.
    /// </summary>
    Task LogDiskCriticalAsync(string driveName, double freePercent, string freeFormatted, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs a configuration change event.
    /// </summary>
    Task LogConfigChangeAsync(string setting, string? userId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs an API request event.
    /// </summary>
    Task LogApiRequestAsync(string endpoint, string? apiKeyId, string? sourceIp, bool success, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs an API authentication failure.
    /// </summary>
    Task LogApiAuthFailAsync(string endpoint, string? sourceIp, string reason, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs a security event.
    /// </summary>
    Task LogSecurityEventAsync(string message, string? userId, string? sourceIp, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs a generic event.
    /// </summary>
    Task LogEventAsync(byte facility, byte severity, string messageId, string message, Guid? uploadId = null, string? userId = null, string? sourceIp = null, string? exception = null, object? properties = null, CancellationToken cancellationToken = default);

    /// <summary>
    /// Logs an event with category and severity.
    /// </summary>
    /// <param name="uploadId">Optional upload ID.</param>
    /// <param name="category">Category for filtering (e.g., "AutoProcess", "Import").</param>
    /// <param name="severity">Severity name: "INFO", "WARNING", "ERROR".</param>
    /// <param name="message">Log message.</param>
    /// <param name="userId">Optional user ID.</param>
    /// <param name="exception">Optional exception details.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task LogAsync(Guid? uploadId, string category, string severity, string message, string? userId = null, string? exception = null, CancellationToken cancellationToken = default);
}
