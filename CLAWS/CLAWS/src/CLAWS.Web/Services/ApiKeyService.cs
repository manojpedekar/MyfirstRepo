using System.Security.Cryptography;
using System.Text;
using CLAWS.Data.Entities;
using CLAWS.Data.Repositories;

namespace CLAWS.Web.Services;

/// <summary>
/// Service for managing API keys.
/// </summary>
public interface IApiKeyService
{
    /// <summary>
    /// Generates a new API key.
    /// </summary>
    Task<(ApiKey ApiKey, string PlainTextKey)> GenerateKeyAsync(
        string description,
        string createdBy,
        DateTime? expiresAt = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Validates an API key.
    /// </summary>
    Task<ApiKey?> ValidateKeyAsync(string apiKey, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all API keys.
    /// </summary>
    Task<List<ApiKey>> GetAllKeysAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Revokes an API key.
    /// </summary>
    Task<bool> RevokeKeyAsync(Guid apiKeyId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes an API key.
    /// </summary>
    Task<bool> DeleteKeyAsync(Guid apiKeyId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all API keys created by a specific user.
    /// </summary>
    Task<List<ApiKey>> GetKeysByUserAsync(string username, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets an API key by ID.
    /// </summary>
    Task<ApiKey?> GetKeyByIdAsync(Guid apiKeyId, CancellationToken cancellationToken = default);
}

/// <summary>
/// Implementation of API key service.
/// </summary>
public class ApiKeyService : IApiKeyService
{
    private readonly IApiKeyRepository _repository;
    private readonly ILogger<ApiKeyService> _logger;

    public ApiKeyService(IApiKeyRepository repository, ILogger<ApiKeyService> logger)
    {
        _repository = repository;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task<(ApiKey ApiKey, string PlainTextKey)> GenerateKeyAsync(
        string description,
        string createdBy,
        DateTime? expiresAt = null,
        CancellationToken cancellationToken = default)
    {
        // Generate a secure random key
        var keyBytes = new byte[32];
        using (var rng = RandomNumberGenerator.Create())
        {
            rng.GetBytes(keyBytes);
        }

        var plainTextKey = Convert.ToBase64String(keyBytes)
            .Replace("+", "-")
            .Replace("/", "_")
            .TrimEnd('=');

        // Generate salt
        var salt = new byte[32];
        using (var rng = RandomNumberGenerator.Create())
        {
            rng.GetBytes(salt);
        }

        // Hash the key
        var hash = HashKey(plainTextKey, salt);

        var apiKey = new ApiKey
        {
            ApiKeyId = Guid.NewGuid(),
            KeyHash = hash,
            KeySalt = salt,
            KeyPrefix = plainTextKey[..8],
            Description = description,
            CreatedBy = createdBy,
            ExpiresAt = expiresAt,
            IsEnabled = true
        };

        await _repository.CreateAsync(apiKey, cancellationToken);

        _logger.LogInformation("API key generated: {Prefix}... by {CreatedBy}", apiKey.KeyPrefix, createdBy);

        return (apiKey, plainTextKey);
    }

    /// <inheritdoc/>
    public async Task<ApiKey?> ValidateKeyAsync(string apiKey, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrEmpty(apiKey) || apiKey.Length < 8)
            return null;

        var prefix = apiKey[..8];
        var candidates = await _repository.GetByPrefixAsync(prefix, cancellationToken);

        foreach (var candidate in candidates)
        {
            // Check expiration
            if (candidate.ExpiresAt.HasValue && candidate.ExpiresAt.Value < DateTime.UtcNow)
                continue;

            // Verify hash
            var hash = HashKey(apiKey, candidate.KeySalt);
            if (hash.SequenceEqual(candidate.KeyHash))
            {
                // Update last used
                await _repository.UpdateLastUsedAsync(candidate.ApiKeyId, cancellationToken);
                return candidate;
            }
        }

        return null;
    }

    /// <inheritdoc/>
    public async Task<List<ApiKey>> GetAllKeysAsync(CancellationToken cancellationToken = default)
    {
        return await _repository.GetAllAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<bool> RevokeKeyAsync(Guid apiKeyId, CancellationToken cancellationToken = default)
    {
        var result = await _repository.DisableAsync(apiKeyId, cancellationToken);
        if (result)
        {
            _logger.LogInformation("API key revoked: {ApiKeyId}", apiKeyId);
        }
        return result;
    }

    /// <inheritdoc/>
    public async Task<bool> DeleteKeyAsync(Guid apiKeyId, CancellationToken cancellationToken = default)
    {
        var result = await _repository.DeleteAsync(apiKeyId, cancellationToken);
        if (result)
        {
            _logger.LogInformation("API key deleted: {ApiKeyId}", apiKeyId);
        }
        return result;
    }

    /// <inheritdoc/>
    public async Task<List<ApiKey>> GetKeysByUserAsync(string username, CancellationToken cancellationToken = default)
    {
        return await _repository.GetByCreatedByAsync(username, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<ApiKey?> GetKeyByIdAsync(Guid apiKeyId, CancellationToken cancellationToken = default)
    {
        return await _repository.GetByIdAsync(apiKeyId, cancellationToken);
    }

    private static byte[] HashKey(string key, byte[] salt)
    {
        using var hmac = new HMACSHA256(salt);
        return hmac.ComputeHash(Encoding.UTF8.GetBytes(key));
    }
}
