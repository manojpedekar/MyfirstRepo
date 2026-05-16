using Hangfire;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Services;
using CLAWS.Jobs.Filters;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for running validation and migration operations in the background.
/// These operations can take 10-30+ minutes for large datasets.
/// </summary>
public interface IValidationMigrationJob
{
    /// <summary>
    /// Validates imported data against production schema.
    /// </summary>
    [JobDisplayName("Validate Upload: {0}")]
    [AutomaticRetry(Attempts = 0)]
    [Queue("validation")]
    [ConfigurableDisableConcurrentExecution] // Timeout configured via AppSettings.JobTimeouts.ValidationMinutes
    Task ValidateAsync(Guid uploadId, string initiatedBy, CancellationToken cancellationToken);

    /// <summary>
    /// Migrates validated data from staging to production schema.
    /// </summary>
    [JobDisplayName("Merge Upload: {0}")]
    [AutomaticRetry(Attempts = 0)]
    [Queue("migration")]
    [ConfigurableDisableConcurrentExecution] // Timeout configured via AppSettings.JobTimeouts.MigrationMinutes
    Task MigrateAsync(Guid uploadId, string initiatedBy, CancellationToken cancellationToken);

    /// <summary>
    /// Validates and then migrates data in one operation.
    /// </summary>
    [JobDisplayName("Validate & Merge Upload: {0}")]
    [AutomaticRetry(Attempts = 0)]
    [Queue("migration")]
    [ConfigurableDisableConcurrentExecution] // Timeout configured via AppSettings.JobTimeouts.ValidateAndMigrateMinutes
    Task ValidateAndMigrateAsync(Guid uploadId, string initiatedBy, CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of validation and migration background job.
/// </summary>
public class ValidationMigrationJob : IValidationMigrationJob
{
    private readonly ILogger<ValidationMigrationJob> _logger;
    private readonly IMigrationService _migrationService;
    private readonly IHubNotifier? _hubNotifier;

    public ValidationMigrationJob(
        ILogger<ValidationMigrationJob> logger,
        IMigrationService migrationService,
        IHubNotifier? hubNotifier = null)
    {
        _logger = logger;
        _migrationService = migrationService;
        _hubNotifier = hubNotifier;
    }

    /// <inheritdoc/>
    public async Task ValidateAsync(Guid uploadId, string initiatedBy, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting validation job for upload {UploadId} initiated by {User}",
            uploadId, initiatedBy);

        await SendProgressAsync(uploadId, "Validating", "", 10, "Starting validation...");

        try
        {
            var result = await _migrationService.ValidateAsync(uploadId, cancellationToken);

            if (result.Success)
            {
                await SendProgressAsync(uploadId, "Completed", "", 100, result.Message);
                _logger.LogInformation("Validation completed successfully for upload {UploadId}: {Message}",
                    uploadId, result.Message);
            }
            else
            {
                await SendProgressAsync(uploadId, "Failed", "", 100, result.Message);
                _logger.LogWarning("Validation failed for upload {UploadId}: {Message}",
                    uploadId, result.Message);
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("Validation job cancelled for upload {UploadId}", uploadId);
            await SendProgressAsync(uploadId, "Failed", "", 0, "Validation cancelled");
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Validation job failed for upload {UploadId}", uploadId);
            await SendProgressAsync(uploadId, "Failed", "", 0, $"Validation error: {ex.Message}");
            throw;
        }
    }

    /// <inheritdoc/>
    public async Task MigrateAsync(Guid uploadId, string initiatedBy, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting migration job for upload {UploadId} initiated by {User}",
            uploadId, initiatedBy);

        await SendProgressAsync(uploadId, "Merging", "", 10, "Starting merge to production...");

        try
        {
            var result = await _migrationService.MigrateAsync(uploadId, cancellationToken);

            if (result.Success)
            {
                await SendProgressAsync(uploadId, "Completed", "", 100, result.Message);
                _logger.LogInformation("Migration completed successfully for upload {UploadId}: {Message}",
                    uploadId, result.Message);
            }
            else
            {
                await SendProgressAsync(uploadId, "Failed", "", 100, result.Message);
                _logger.LogWarning("Migration failed for upload {UploadId}: {Message}",
                    uploadId, result.Message);
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("Migration job cancelled for upload {UploadId}", uploadId);
            await SendProgressAsync(uploadId, "Failed", "", 0, "Migration cancelled");
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Migration job failed for upload {UploadId}", uploadId);
            await SendProgressAsync(uploadId, "Failed", "", 0, $"Migration error: {ex.Message}");
            throw;
        }
    }

    /// <inheritdoc/>
    public async Task ValidateAndMigrateAsync(Guid uploadId, string initiatedBy, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting validate & merge job for upload {UploadId} initiated by {User}",
            uploadId, initiatedBy);

        await SendProgressAsync(uploadId, "Validating", "", 5, "Starting validation...");

        try
        {
            var result = await _migrationService.ValidateAndMigrateAsync(uploadId, cancellationToken);

            if (result.Success)
            {
                await SendProgressAsync(uploadId, "Completed", "", 100, result.Message);
                _logger.LogInformation("Validate & merge completed successfully for upload {UploadId}: {Message}",
                    uploadId, result.Message);
            }
            else
            {
                await SendProgressAsync(uploadId, "Failed", "", 100, result.Message);
                _logger.LogWarning("Validate & merge failed for upload {UploadId}: {Message}",
                    uploadId, result.Message);
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("Validate & merge job cancelled for upload {UploadId}", uploadId);
            await SendProgressAsync(uploadId, "Failed", "", 0, "Operation cancelled");
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Validate & merge job failed for upload {UploadId}", uploadId);
            await SendProgressAsync(uploadId, "Failed", "", 0, $"Error: {ex.Message}");
            throw;
        }
    }

    private async Task SendProgressAsync(Guid uploadId, string phase, string currentTable, int percent, string message)
    {
        if (_hubNotifier != null)
        {
            await _hubNotifier.SendProgressAsync(uploadId, phase, currentTable, percent, message);
        }
    }
}
