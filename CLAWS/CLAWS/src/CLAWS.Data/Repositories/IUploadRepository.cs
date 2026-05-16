using CLAWS.Data.Entities;

namespace CLAWS.Data.Repositories;

/// <summary>
/// Repository for upload operations.
/// </summary>
public interface IUploadRepository
{
    /// <summary>
    /// Creates a new upload record.
    /// </summary>
    Task<Upload> CreateAsync(Upload upload, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets an upload by ID.
    /// </summary>
    Task<Upload?> GetByIdAsync(Guid uploadId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Updates an upload record.
    /// </summary>
    Task<Upload> UpdateAsync(Upload upload, CancellationToken cancellationToken = default);

    /// <summary>
    /// Updates only the status fields of an upload.
    /// </summary>
    Task UpdateStatusAsync(Guid uploadId, string status, string? message = null, int? progress = null, string? phase = null, CancellationToken cancellationToken = default);

    /// <summary>
    /// Updates detailed progress information for an upload.
    /// </summary>
    Task UpdateProgressAsync(
        Guid uploadId,
        int progress,
        string? phase = null,
        long? rowsProcessed = null,
        long? totalRows = null,
        string? message = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets uploads by user.
    /// </summary>
    Task<List<Upload>> GetByUserAsync(string username, int skip = 0, int take = 50, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all uploads with pagination.
    /// </summary>
    Task<List<Upload>> GetAllAsync(int skip = 0, int take = 50, string? status = null, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the count of uploads matching criteria.
    /// </summary>
    Task<int> GetCountAsync(string? status = null, string? username = null, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets uploads in queue position order.
    /// </summary>
    Task<List<Upload>> GetQueuedUploadsAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes an upload record.
    /// </summary>
    Task<bool> DeleteAsync(Guid uploadId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes old upload records that have been completed, failed, or cancelled before the cutoff date.
    /// </summary>
    /// <param name="cutoffDate">Delete records where CompletedAt is before this date.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The number of records deleted.</returns>
    Task<int> DeleteOldUploadsAsync(DateTime cutoffDate, CancellationToken cancellationToken = default);

    /// <summary>
    /// Adds import statistics for an upload.
    /// </summary>
    Task AddImportStatisticsAsync(Guid uploadId, IEnumerable<ImportStatistic> statistics, CancellationToken cancellationToken = default);
}
