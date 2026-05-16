using Microsoft.EntityFrameworkCore;
using CLAWS.Data.Entities;

namespace CLAWS.Data.Repositories;

/// <summary>
/// Repository for banner message operations.
/// </summary>
public interface IBannerMessageRepository
{
    /// <summary>
    /// Gets all banner messages.
    /// </summary>
    Task<List<BannerMessage>> GetAllAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all active banner messages (enabled and within date range).
    /// </summary>
    Task<List<BannerMessage>> GetActiveAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a banner message by ID.
    /// </summary>
    Task<BannerMessage?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>
    /// Creates a new banner message.
    /// </summary>
    Task<BannerMessage> CreateAsync(BannerMessage bannerMessage, CancellationToken cancellationToken = default);

    /// <summary>
    /// Updates an existing banner message.
    /// </summary>
    Task<BannerMessage> UpdateAsync(BannerMessage bannerMessage, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes a banner message.
    /// </summary>
    Task<bool> DeleteAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>
    /// Sets the enabled status of a banner message.
    /// </summary>
    Task<bool> SetEnabledAsync(Guid id, bool enabled, string modifiedBy, CancellationToken cancellationToken = default);
}

/// <summary>
/// Implementation of banner message repository.
/// </summary>
public class BannerMessageRepository : IBannerMessageRepository
{
    private readonly Context.ApplicationDbContext _context;

    public BannerMessageRepository(Context.ApplicationDbContext context)
    {
        _context = context;
    }

    /// <inheritdoc/>
    public async Task<List<BannerMessage>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        return await _context.BannerMessages
            .OrderBy(b => b.DisplayOrder)
            .ThenByDescending(b => b.CreatedAt)
            .ToListAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<List<BannerMessage>> GetActiveAsync(CancellationToken cancellationToken = default)
    {
        var now = DateTime.UtcNow;

        return await _context.BannerMessages
            .Where(b => b.IsEnabled)
            .Where(b => !b.StartDate.HasValue || b.StartDate <= now)
            .Where(b => !b.EndDate.HasValue || b.EndDate >= now)
            .OrderBy(b => b.DisplayOrder)
            .ThenByDescending(b => b.CreatedAt)
            .ToListAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<BannerMessage?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
    {
        return await _context.BannerMessages.FindAsync(new object[] { id }, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<BannerMessage> CreateAsync(BannerMessage bannerMessage, CancellationToken cancellationToken = default)
    {
        bannerMessage.BannerMessageId = Guid.NewGuid();
        bannerMessage.CreatedAt = DateTime.UtcNow;
        bannerMessage.LastModifiedAt = DateTime.UtcNow;

        _context.BannerMessages.Add(bannerMessage);
        await _context.SaveChangesAsync(cancellationToken);

        return bannerMessage;
    }

    /// <inheritdoc/>
    public async Task<BannerMessage> UpdateAsync(BannerMessage bannerMessage, CancellationToken cancellationToken = default)
    {
        var existing = await _context.BannerMessages.FindAsync(new object[] { bannerMessage.BannerMessageId }, cancellationToken);
        if (existing == null)
        {
            throw new InvalidOperationException($"Banner message with ID {bannerMessage.BannerMessageId} not found.");
        }

        existing.Title = bannerMessage.Title;
        existing.Message = bannerMessage.Message;
        existing.MessageType = bannerMessage.MessageType;
        existing.IsEnabled = bannerMessage.IsEnabled;
        existing.DisplayOrder = bannerMessage.DisplayOrder;
        existing.StartDate = bannerMessage.StartDate;
        existing.EndDate = bannerMessage.EndDate;
        existing.LastModifiedBy = bannerMessage.LastModifiedBy;
        existing.LastModifiedAt = DateTime.UtcNow;

        await _context.SaveChangesAsync(cancellationToken);

        return existing;
    }

    /// <inheritdoc/>
    public async Task<bool> DeleteAsync(Guid id, CancellationToken cancellationToken = default)
    {
        var bannerMessage = await _context.BannerMessages.FindAsync(new object[] { id }, cancellationToken);
        if (bannerMessage == null)
        {
            return false;
        }

        _context.BannerMessages.Remove(bannerMessage);
        await _context.SaveChangesAsync(cancellationToken);

        return true;
    }

    /// <inheritdoc/>
    public async Task<bool> SetEnabledAsync(Guid id, bool enabled, string modifiedBy, CancellationToken cancellationToken = default)
    {
        var bannerMessage = await _context.BannerMessages.FindAsync(new object[] { id }, cancellationToken);
        if (bannerMessage == null)
        {
            return false;
        }

        bannerMessage.IsEnabled = enabled;
        bannerMessage.LastModifiedBy = modifiedBy;
        bannerMessage.LastModifiedAt = DateTime.UtcNow;

        await _context.SaveChangesAsync(cancellationToken);

        return true;
    }
}
