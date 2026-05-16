using Hangfire.Common;
using Hangfire.Server;
using Hangfire.Storage;
using CLAWS.Core.Configuration;

namespace CLAWS.Jobs.Filters;

/// <summary>
/// Hangfire filter that provides configurable job timeout and concurrent execution lock.
/// Replaces compile-time [DisableConcurrentExecution] attributes with runtime-configurable values.
/// </summary>
/// <remarks>
/// This filter implements a distributed lock similar to Hangfire's built-in
/// DisableConcurrentExecutionAttribute, but reads timeout values from AppSettings
/// at runtime, allowing administrators to configure job timeouts without recompilation.
///
/// The filter uses a naming convention to determine which timeout setting to apply:
/// - Methods containing "Upload" or "Process" use UploadProcessingMinutes
/// - Methods containing "Validate" (but not "Migrate") use ValidationMinutes
/// - Methods containing "Migrate" (but not "Validate") use MigrationMinutes
/// - Methods containing both "Validate" and "Migrate" use ValidateAndMigrateMinutes
/// - Methods containing "Delete" or "Deletion" use DeletionMinutes
/// - Methods containing "Orphan" or "Cleanup" use OrphanedCleanupMinutes
/// - Methods containing "Truncate" use SchemaTruncateMinutes
/// </remarks>
public class ConfigurableJobTimeoutFilter : JobFilterAttribute, IServerFilter
{
    private static readonly object Lock = new();
    private static Func<JobTimeoutSettings>? _settingsAccessor;

    /// <summary>
    /// Registers the settings accessor function. Must be called during application startup.
    /// </summary>
    /// <param name="settingsAccessor">Function that returns the current JobTimeoutSettings.</param>
    public static void RegisterSettingsAccessor(Func<JobTimeoutSettings> settingsAccessor)
    {
        lock (Lock)
        {
            _settingsAccessor = settingsAccessor;
        }
    }

    /// <summary>
    /// Gets the current job timeout settings.
    /// </summary>
    private static JobTimeoutSettings GetSettings()
    {
        lock (Lock)
        {
            return _settingsAccessor?.Invoke() ?? new JobTimeoutSettings();
        }
    }

    /// <summary>
    /// Called before the job method is executed. Acquires a distributed lock.
    /// </summary>
    public void OnPerforming(PerformingContext context)
    {
        var settings = GetSettings();
        var timeoutSeconds = GetTimeoutForJob(context.BackgroundJob.Job, settings);

        // Create a unique resource identifier for this job type
        var resource = $"{context.BackgroundJob.Job.Type.FullName}.{context.BackgroundJob.Job.Method.Name}";
        var lockKey = $"locks:job:{resource}";

        // Acquire distributed lock with configurable timeout
        var timeout = TimeSpan.FromSeconds(timeoutSeconds);
        var distributedLock = context.Connection.AcquireDistributedLock(lockKey, timeout);

        // Store the lock in context items so we can release it in OnPerformed
        context.Items["ConfigurableJobTimeoutFilter:Lock"] = distributedLock;
    }

    /// <summary>
    /// Called after the job method completes. Releases the distributed lock.
    /// </summary>
    public void OnPerformed(PerformedContext context)
    {
        if (context.Items.TryGetValue("ConfigurableJobTimeoutFilter:Lock", out var lockObj) &&
            lockObj is IDisposable distributedLock)
        {
            distributedLock.Dispose();
        }
    }

    /// <summary>
    /// Determines the appropriate timeout for a job based on its method name.
    /// </summary>
    private static int GetTimeoutForJob(Job job, JobTimeoutSettings settings)
    {
        var methodName = job.Method.Name;
        var typeName = job.Type.Name;
        var fullIdentifier = $"{typeName}.{methodName}";

        // Check for specific patterns in order of specificity

        // Combined validate and migrate
        if (methodName.Contains("ValidateAndMigrate", StringComparison.OrdinalIgnoreCase))
        {
            return settings.ValidateAndMigrateSeconds;
        }

        // Upload processing
        if (methodName.Contains("Execute", StringComparison.OrdinalIgnoreCase) &&
            typeName.Contains("UploadProcessing", StringComparison.OrdinalIgnoreCase))
        {
            return settings.UploadProcessingSeconds;
        }

        // Validation only
        if (methodName.Contains("Validate", StringComparison.OrdinalIgnoreCase) &&
            !methodName.Contains("Migrate", StringComparison.OrdinalIgnoreCase))
        {
            return settings.ValidationSeconds;
        }

        // Migration only
        if (methodName.Contains("Migrate", StringComparison.OrdinalIgnoreCase) &&
            !methodName.Contains("Validate", StringComparison.OrdinalIgnoreCase))
        {
            return settings.MigrationSeconds;
        }

        // Deletion jobs
        if (methodName.Contains("Delete", StringComparison.OrdinalIgnoreCase) ||
            typeName.Contains("Deletion", StringComparison.OrdinalIgnoreCase))
        {
            return settings.DeletionSeconds;
        }

        // Orphaned cleanup
        if (methodName.Contains("Orphan", StringComparison.OrdinalIgnoreCase) ||
            methodName.Contains("Cleanup", StringComparison.OrdinalIgnoreCase) &&
            typeName.Contains("Orphan", StringComparison.OrdinalIgnoreCase))
        {
            return settings.OrphanedCleanupSeconds;
        }

        // Schema truncate
        if (methodName.Contains("Truncate", StringComparison.OrdinalIgnoreCase) ||
            typeName.Contains("Truncate", StringComparison.OrdinalIgnoreCase))
        {
            return settings.SchemaTruncateSeconds;
        }

        // Default to upload processing timeout (2 hours) for unmatched jobs
        return settings.UploadProcessingSeconds;
    }
}

/// <summary>
/// Attribute to mark jobs that should use configurable timeout from AppSettings.
/// Apply this attribute to job interface methods instead of [DisableConcurrentExecution].
/// </summary>
/// <remarks>
/// Usage:
/// <code>
/// [ConfigurableDisableConcurrentExecution]
/// Task ExecuteAsync(Guid uploadId, CancellationToken cancellationToken);
/// </code>
///
/// The actual timeout value is determined at runtime based on the job type
/// and the current JobTimeoutSettings configuration.
/// </remarks>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class, AllowMultiple = false)]
public class ConfigurableDisableConcurrentExecutionAttribute : JobFilterAttribute, IServerFilter
{
    /// <summary>
    /// Gets or sets the job type hint for timeout selection.
    /// </summary>
    public string? JobTypeHint { get; set; }

    /// <inheritdoc/>
    public void OnPerforming(PerformingContext context)
    {
        // Delegate to the static filter implementation
        var filter = new ConfigurableJobTimeoutFilter();
        filter.OnPerforming(context);

        // Transfer the lock to this attribute's context tracking
        if (context.Items.TryGetValue("ConfigurableJobTimeoutFilter:Lock", out var lockObj))
        {
            context.Items["ConfigurableDisableConcurrentExecution:Lock"] = lockObj;
            context.Items.Remove("ConfigurableJobTimeoutFilter:Lock");
        }
    }

    /// <inheritdoc/>
    public void OnPerformed(PerformedContext context)
    {
        if (context.Items.TryGetValue("ConfigurableDisableConcurrentExecution:Lock", out var lockObj) &&
            lockObj is IDisposable distributedLock)
        {
            distributedLock.Dispose();
        }
    }
}
