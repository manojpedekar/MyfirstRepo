using Microsoft.Extensions.Caching.Memory;
using CLAWS.Data.Entities;
using CLAWS.Data.Repositories;

namespace CLAWS.Web.Services;

/// <summary>
/// Service for managing banner messages.
/// </summary>
public interface IBannerMessageService
{
    /// <summary>
    /// Gets all banner messages.
    /// </summary>
    Task<List<BannerMessage>> GetAllAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all active banner messages (enabled and within date range).
    /// Uses caching for performance.
    /// </summary>
    Task<List<BannerMessage>> GetActiveAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a banner message by ID.
    /// </summary>
    Task<BannerMessage?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>
    /// Creates a new banner message.
    /// </summary>
    Task<BannerMessage> CreateAsync(
        string title,
        string message,
        string messageType,
        bool isEnabled,
        int displayOrder,
        DateTime? startDate,
        DateTime? endDate,
        string createdBy,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Updates an existing banner message.
    /// </summary>
    Task<BannerMessage> UpdateAsync(
        Guid id,
        string title,
        string message,
        string messageType,
        bool isEnabled,
        int displayOrder,
        DateTime? startDate,
        DateTime? endDate,
        string modifiedBy,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes a banner message.
    /// </summary>
    Task<bool> DeleteAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>
    /// Sets the enabled status of a banner message.
    /// </summary>
    Task<bool> SetEnabledAsync(Guid id, bool enabled, string modifiedBy, CancellationToken cancellationToken = default);

    /// <summary>
    /// Invalidates the active messages cache.
    /// </summary>
    void InvalidateCache();
}

/// <summary>
/// Implementation of banner message service with caching.
/// </summary>
public class BannerMessageService : IBannerMessageService
{
    private const string ActiveMessagesCacheKey = "BannerMessages_Active";
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(5);

    private readonly IBannerMessageRepository _repository;
    private readonly IMemoryCache _cache;
    private readonly ILogger<BannerMessageService> _logger;

    public BannerMessageService(
        IBannerMessageRepository repository,
        IMemoryCache cache,
        ILogger<BannerMessageService> logger)
    {
        _repository = repository;
        _cache = cache;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task<List<BannerMessage>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        return await _repository.GetAllAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<List<BannerMessage>> GetActiveAsync(CancellationToken cancellationToken = default)
    {
        if (_cache.TryGetValue(ActiveMessagesCacheKey, out List<BannerMessage>? cached) && cached != null)
        {
            return cached;
        }

        var messages = await _repository.GetActiveAsync(cancellationToken);

        var cacheOptions = new MemoryCacheEntryOptions()
            .SetAbsoluteExpiration(CacheDuration);

        _cache.Set(ActiveMessagesCacheKey, messages, cacheOptions);

        return messages;
    }

    /// <inheritdoc/>
    public async Task<BannerMessage?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
    {
        return await _repository.GetByIdAsync(id, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<BannerMessage> CreateAsync(
        string title,
        string message,
        string messageType,
        bool isEnabled,
        int displayOrder,
        DateTime? startDate,
        DateTime? endDate,
        string createdBy,
        CancellationToken cancellationToken = default)
    {
        if (!BannerMessageTypes.IsValid(messageType))
        {
            throw new ArgumentException($"Invalid message type: {messageType}. Valid types are: {string.Join(", ", BannerMessageTypes.All)}", nameof(messageType));
        }

        var bannerMessage = new BannerMessage
        {
            Title = title,
            Message = message,
            MessageType = messageType,
            IsEnabled = isEnabled,
            DisplayOrder = displayOrder,
            StartDate = startDate,
            EndDate = endDate,
            CreatedBy = createdBy,
            LastModifiedBy = createdBy
        };

        var created = await _repository.CreateAsync(bannerMessage, cancellationToken);

        _logger.LogInformation("Banner message created: {BannerMessageId} - {Title} by {CreatedBy}",
            created.BannerMessageId, title, createdBy);

        InvalidateCache();

        return created;
    }

    /// <inheritdoc/>
    public async Task<BannerMessage> UpdateAsync(
        Guid id,
        string title,
        string message,
        string messageType,
        bool isEnabled,
        int displayOrder,
        DateTime? startDate,
        DateTime? endDate,
        string modifiedBy,
        CancellationToken cancellationToken = default)
    {
        if (!BannerMessageTypes.IsValid(messageType))
        {
            throw new ArgumentException($"Invalid message type: {messageType}. Valid types are: {string.Join(", ", BannerMessageTypes.All)}", nameof(messageType));
        }

        var existing = await _repository.GetByIdAsync(id, cancellationToken)
            ?? throw new InvalidOperationException($"Banner message with ID {id} not found.");

        existing.Title = title;
        existing.Message = message;
        existing.MessageType = messageType;
        existing.IsEnabled = isEnabled;
        existing.DisplayOrder = displayOrder;
        existing.StartDate = startDate;
        existing.EndDate = endDate;
        existing.LastModifiedBy = modifiedBy;

        var updated = await _repository.UpdateAsync(existing, cancellationToken);

        _logger.LogInformation("Banner message updated: {BannerMessageId} - {Title} by {ModifiedBy}",
            id, title, modifiedBy);

        InvalidateCache();

        return updated;
    }

    /// <inheritdoc/>
    public async Task<bool> DeleteAsync(Guid id, CancellationToken cancellationToken = default)
    {
        var result = await _repository.DeleteAsync(id, cancellationToken);

        if (result)
        {
            _logger.LogInformation("Banner message deleted: {BannerMessageId}", id);
            InvalidateCache();
        }

        return result;
    }

    /// <inheritdoc/>
    public async Task<bool> SetEnabledAsync(Guid id, bool enabled, string modifiedBy, CancellationToken cancellationToken = default)
    {
        var result = await _repository.SetEnabledAsync(id, enabled, modifiedBy, cancellationToken);

        if (result)
        {
            _logger.LogInformation("Banner message {BannerMessageId} {Action} by {ModifiedBy}",
                id, enabled ? "enabled" : "disabled", modifiedBy);
            InvalidateCache();
        }

        return result;
    }

    /// <inheritdoc/>
    public void InvalidateCache()
    {
        _cache.Remove(ActiveMessagesCacheKey);
    }
}
