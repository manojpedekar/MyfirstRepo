using Microsoft.EntityFrameworkCore;
using CLAWS.Data.Context;
using CLAWS.Data.Entities;

namespace CLAWS.Data.Repositories;

/// <summary>
/// Implementation of upload repository.
/// </summary>
public class UploadRepository : IUploadRepository
{
    private readonly ApplicationDbContext _context;

    public UploadRepository(ApplicationDbContext context)
    {
        _context = context;
    }

    /// <inheritdoc/>
    public async Task<Upload> CreateAsync(Upload upload, CancellationToken cancellationToken = default)
    {
        _context.Uploads.Add(upload);
        await _context.SaveChangesAsync(cancellationToken);
        return upload;
    }

    /// <inheritdoc/>
    public async Task<Upload?> GetByIdAsync(Guid uploadId, CancellationToken cancellationToken = default)
    {
        return await _context.Uploads
            .Include(u => u.ImportStatistics)
            .FirstOrDefaultAsync(u => u.UploadId == uploadId, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<Upload> UpdateAsync(Upload upload, CancellationToken cancellationToken = default)
    {
        _context.Uploads.Update(upload);
        await _context.SaveChangesAsync(cancellationToken);
        return upload;
    }

    /// <inheritdoc/>
    public async Task UpdateStatusAsync(
        Guid uploadId,
        string status,
        string? message = null,
        int? progress = null,
        string? phase = null,
        CancellationToken cancellationToken = default)
    {
        var upload = await _context.Uploads.FindAsync(new object[] { uploadId }, cancellationToken);
        if (upload != null)
        {
            upload.Status = status;
            if (message != null) upload.StatusMessage = message;
            if (progress.HasValue) upload.ImportProgress = progress;
            if (phase != null) upload.CurrentPhase = phase;

            if (status == "Importing" && !upload.StartedAt.HasValue)
            {
                upload.StartedAt = DateTime.UtcNow;
            }
            else if (status is "Completed" or "Failed" or "Cancelled")
            {
                upload.CompletedAt = DateTime.UtcNow;
            }

            await _context.SaveChangesAsync(cancellationToken);
        }
    }

    /// <inheritdoc/>
    public async Task UpdateProgressAsync(
        Guid uploadId,
        int progress,
        string? phase = null,
        long? rowsProcessed = null,
        long? totalRows = null,
        string? message = null,
        CancellationToken cancellationToken = default)
    {
        var upload = await _context.Uploads.FindAsync(new object[] { uploadId }, cancellationToken);
        if (upload != null)
        {
            upload.ImportProgress = progress;
            if (phase != null)
            {
                // Track when phase changes
                if (upload.CurrentPhase != phase)
                {
                    upload.PhaseStartedAt = DateTime.UtcNow;
                }
                upload.CurrentPhase = phase;
            }
            if (rowsProcessed.HasValue) upload.RowsProcessed = rowsProcessed;
            if (totalRows.HasValue) upload.TotalRows = totalRows;
            if (message != null) upload.StatusMessage = message;

            await _context.SaveChangesAsync(cancellationToken);
        }
    }

    /// <inheritdoc/>
    public async Task<List<Upload>> GetByUserAsync(
        string username,
        int skip = 0,
        int take = 50,
        CancellationToken cancellationToken = default)
    {
        return await _context.Uploads
            .Where(u => u.UploadedBy == username)
            .OrderByDescending(u => u.UploadedAt)
            .Skip(skip)
            .Take(take)
            .ToListAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<List<Upload>> GetAllAsync(
        int skip = 0,
        int take = 50,
        string? status = null,
        CancellationToken cancellationToken = default)
    {
        var query = _context.Uploads.AsQueryable();

        if (!string.IsNullOrEmpty(status))
        {
            query = query.Where(u => u.Status == status);
        }

        return await query
            .OrderByDescending(u => u.UploadedAt)
            .Skip(skip)
            .Take(take)
            .ToListAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<int> GetCountAsync(
        string? status = null,
        string? username = null,
        CancellationToken cancellationToken = default)
    {
        var query = _context.Uploads.AsQueryable();

        if (!string.IsNullOrEmpty(status))
        {
            query = query.Where(u => u.Status == status);
        }

        if (!string.IsNullOrEmpty(username))
        {
            query = query.Where(u => u.UploadedBy == username);
        }

        return await query.CountAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<List<Upload>> GetQueuedUploadsAsync(CancellationToken cancellationToken = default)
    {
        return await _context.Uploads
            .Where(u => u.Status == "Queued")
            .OrderBy(u => u.UploadedAt)
            .ToListAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<bool> DeleteAsync(Guid uploadId, CancellationToken cancellationToken = default)
    {
        var upload = await _context.Uploads.FindAsync(new object[] { uploadId }, cancellationToken);
        if (upload == null) return false;

        _context.Uploads.Remove(upload);
        await _context.SaveChangesAsync(cancellationToken);
        return true;
    }

    /// <inheritdoc/>
    public async Task<int> DeleteOldUploadsAsync(DateTime cutoffDate, CancellationToken cancellationToken = default)
    {
        // Only delete records that are in a terminal state and older than the cutoff
        var terminalStatuses = new[] { "Completed", "Failed", "Cancelled" };

        var uploadsToDelete = await _context.Uploads
            .Where(u => terminalStatuses.Contains(u.Status) && u.CompletedAt < cutoffDate)
            .ToListAsync(cancellationToken);

        if (uploadsToDelete.Count == 0)
        {
            return 0;
        }

        _context.Uploads.RemoveRange(uploadsToDelete);
        await _context.SaveChangesAsync(cancellationToken);
        return uploadsToDelete.Count;
    }

    /// <inheritdoc/>
    public async Task AddImportStatisticsAsync(
        Guid uploadId,
        IEnumerable<ImportStatistic> statistics,
        CancellationToken cancellationToken = default)
    {
        foreach (var stat in statistics)
        {
            stat.UploadId = uploadId;
            _context.ImportStatistics.Add(stat);
        }

        await _context.SaveChangesAsync(cancellationToken);
    }
}
