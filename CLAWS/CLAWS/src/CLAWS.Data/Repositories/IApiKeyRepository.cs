using Microsoft.EntityFrameworkCore;
using CLAWS.Data.Context;
using CLAWS.Data.Entities;

namespace CLAWS.Data.Repositories;

/// <summary>
/// Repository for API key operations.
/// </summary>
public interface IApiKeyRepository
{
    /// <summary>
    /// Creates a new API key.
    /// </summary>
    Task<ApiKey> CreateAsync(ApiKey apiKey, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets an API key by ID.
    /// </summary>
    Task<ApiKey?> GetByIdAsync(Guid apiKeyId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets API keys by prefix (for key lookup).
    /// </summary>
    Task<List<ApiKey>> GetByPrefixAsync(string prefix, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all API keys.
    /// </summary>
    Task<List<ApiKey>> GetAllAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Updates an API key.
    /// </summary>
    Task<ApiKey> UpdateAsync(ApiKey apiKey, CancellationToken cancellationToken = default);

    /// <summary>
    /// Updates the last used timestamp.
    /// </summary>
    Task UpdateLastUsedAsync(Guid apiKeyId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes an API key.
    /// </summary>
    Task<bool> DeleteAsync(Guid apiKeyId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Disables an API key.
    /// </summary>
    Task<bool> DisableAsync(Guid apiKeyId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets an API key by description.
    /// </summary>
    Task<ApiKey?> GetByDescriptionAsync(string description, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all API keys created by a specific user.
    /// </summary>
    Task<List<ApiKey>> GetByCreatedByAsync(string createdBy, CancellationToken cancellationToken = default);
}

/// <summary>
/// Implementation of API key repository.
/// </summary>
public class ApiKeyRepository : IApiKeyRepository
{
    private readonly ApplicationDbContext _context;

    public ApiKeyRepository(ApplicationDbContext context)
    {
        _context = context;
    }

    /// <inheritdoc/>
    public async Task<ApiKey> CreateAsync(ApiKey apiKey, CancellationToken cancellationToken = default)
    {
        _context.ApiKeys.Add(apiKey);
        await _context.SaveChangesAsync(cancellationToken);
        return apiKey;
    }

    /// <inheritdoc/>
    public async Task<ApiKey?> GetByIdAsync(Guid apiKeyId, CancellationToken cancellationToken = default)
    {
        return await _context.ApiKeys.FindAsync(new object[] { apiKeyId }, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<List<ApiKey>> GetByPrefixAsync(string prefix, CancellationToken cancellationToken = default)
    {
        return await _context.ApiKeys
            .Where(k => k.KeyPrefix == prefix && k.IsEnabled)
            .ToListAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<List<ApiKey>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        return await _context.ApiKeys
            .OrderByDescending(k => k.CreatedAt)
            .ToListAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<ApiKey> UpdateAsync(ApiKey apiKey, CancellationToken cancellationToken = default)
    {
        _context.ApiKeys.Update(apiKey);
        await _context.SaveChangesAsync(cancellationToken);
        return apiKey;
    }

    /// <inheritdoc/>
    public async Task UpdateLastUsedAsync(Guid apiKeyId, CancellationToken cancellationToken = default)
    {
        var apiKey = await _context.ApiKeys.FindAsync(new object[] { apiKeyId }, cancellationToken);
        if (apiKey != null)
        {
            apiKey.LastUsedAt = DateTime.UtcNow;
            await _context.SaveChangesAsync(cancellationToken);
        }
    }

    /// <inheritdoc/>
    public async Task<bool> DeleteAsync(Guid apiKeyId, CancellationToken cancellationToken = default)
    {
        var apiKey = await _context.ApiKeys.FindAsync(new object[] { apiKeyId }, cancellationToken);
        if (apiKey == null) return false;

        _context.ApiKeys.Remove(apiKey);
        await _context.SaveChangesAsync(cancellationToken);
        return true;
    }

    /// <inheritdoc/>
    public async Task<bool> DisableAsync(Guid apiKeyId, CancellationToken cancellationToken = default)
    {
        var apiKey = await _context.ApiKeys.FindAsync(new object[] { apiKeyId }, cancellationToken);
        if (apiKey == null) return false;

        apiKey.IsEnabled = false;
        await _context.SaveChangesAsync(cancellationToken);
        return true;
    }

    /// <inheritdoc/>
    public async Task<ApiKey?> GetByDescriptionAsync(string description, CancellationToken cancellationToken = default)
    {
        return await _context.ApiKeys
            .FirstOrDefaultAsync(k => k.Description == description, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<List<ApiKey>> GetByCreatedByAsync(string createdBy, CancellationToken cancellationToken = default)
    {
        return await _context.ApiKeys
            .Where(k => k.CreatedBy == createdBy)
            .OrderByDescending(k => k.CreatedAt)
            .ToListAsync(cancellationToken);
    }
}
