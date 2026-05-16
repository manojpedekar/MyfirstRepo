using Hangfire;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Data.Context;
using Microsoft.EntityFrameworkCore;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for pruning old database logs.
/// </summary>
public interface ILogPruningJob
{
    /// <summary>
    /// Prunes database log entries older than retention period.
    /// </summary>
    [JobDisplayName("Cleanup: Database Logs")]
    Task PruneLogsAsync(CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of the log pruning job.
/// </summary>
public class LogPruningJob : ILogPruningJob
{
    private readonly ILogger<LogPruningJob> _logger;
    private readonly ApplicationDbContext _context;
    private readonly LoggingSettings _loggingSettings;

    public LogPruningJob(
        ILogger<LogPruningJob> logger,
        ApplicationDbContext context,
        LoggingSettings loggingSettings)
    {
        _logger = logger;
        _context = context;
        _loggingSettings = loggingSettings;
    }

    /// <inheritdoc/>
    public async Task PruneLogsAsync(CancellationToken cancellationToken)
    {
        if (_loggingSettings.DatabaseLogRetentionDays <= 0)
        {
            _logger.LogInformation("Database log pruning is disabled (retention = 0)");
            return;
        }

        var cutoffDate = DateTime.UtcNow.AddDays(-_loggingSettings.DatabaseLogRetentionDays);

        _logger.LogInformation("Pruning database logs older than {CutoffDate}", cutoffDate);

        try
        {
            // Use raw SQL for efficient bulk delete
            var deletedCount = await _context.Database.ExecuteSqlRawAsync(
                "DELETE FROM [app].[Logs] WHERE Timestamp < {0}",
                new object[] { cutoffDate },
                cancellationToken);

            _logger.LogInformation("Pruned {Count} log entries from database", deletedCount);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error pruning database logs");
            throw;
        }
    }
}
