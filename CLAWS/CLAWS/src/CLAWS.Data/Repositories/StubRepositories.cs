using CLAWS.Data.Entities;

namespace CLAWS.Data.Repositories;

/// <summary>
/// Stub upload repository that returns empty data when database is not configured.
/// </summary>
public class StubUploadRepository : IUploadRepository
{
    public Task<Upload> CreateAsync(Upload upload, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database is not configured. Please configure SQL Server connection.");

    public Task<Upload?> GetByIdAsync(Guid uploadId, CancellationToken cancellationToken = default)
        => Task.FromResult<Upload?>(null);

    public Task<Upload> UpdateAsync(Upload upload, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database is not configured. Please configure SQL Server connection.");

    public Task UpdateStatusAsync(Guid uploadId, string status, string? message = null, int? progress = null, string? phase = null, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database is not configured. Please configure SQL Server connection.");

    public Task UpdateProgressAsync(Guid uploadId, int progress, string? phase = null, long? rowsProcessed = null, long? totalRows = null, string? message = null, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database is not configured. Please configure SQL Server connection.");

    public Task<List<Upload>> GetByUserAsync(string username, int skip = 0, int take = 50, CancellationToken cancellationToken = default)
        => Task.FromResult(new List<Upload>());

    public Task<List<Upload>> GetAllAsync(int skip = 0, int take = 50, string? status = null, CancellationToken cancellationToken = default)
        => Task.FromResult(new List<Upload>());

    public Task<int> GetCountAsync(string? status = null, string? username = null, CancellationToken cancellationToken = default)
        => Task.FromResult(0);

    public Task<List<Upload>> GetQueuedUploadsAsync(CancellationToken cancellationToken = default)
        => Task.FromResult(new List<Upload>());

    public Task<bool> DeleteAsync(Guid uploadId, CancellationToken cancellationToken = default)
        => Task.FromResult(false);

    public Task<int> DeleteOldUploadsAsync(DateTime cutoffDate, CancellationToken cancellationToken = default)
        => Task.FromResult(0);

    public Task AddImportStatisticsAsync(Guid uploadId, IEnumerable<ImportStatistic> statistics, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database is not configured. Please configure SQL Server connection.");
}

/// <summary>
/// Stub configuration repository that returns empty data when database is not configured.
/// </summary>
public class StubConfigurationRepository : IConfigurationRepository
{
    public Task<string?> GetValueAsync(string key, CancellationToken cancellationToken = default)
        => Task.FromResult<string?>(null);

    public Task<ConfigurationEntry?> GetAsync(string key, CancellationToken cancellationToken = default)
        => Task.FromResult<ConfigurationEntry?>(null);

    public Task SetAsync(string key, string? value, string modifiedBy, bool isEncrypted = false, string? description = null, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database is not configured. Please configure SQL Server connection.");

    public Task<List<ConfigurationEntry>> GetAllAsync(CancellationToken cancellationToken = default)
        => Task.FromResult(new List<ConfigurationEntry>());

    public Task<bool> DeleteAsync(string key, CancellationToken cancellationToken = default)
        => Task.FromResult(false);
}

/// <summary>
/// Stub API key repository that returns empty data when database is not configured.
/// </summary>
public class StubApiKeyRepository : IApiKeyRepository
{
    public Task<ApiKey> CreateAsync(ApiKey apiKey, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database is not configured. Please configure SQL Server connection.");

    public Task<ApiKey?> GetByIdAsync(Guid apiKeyId, CancellationToken cancellationToken = default)
        => Task.FromResult<ApiKey?>(null);

    public Task<List<ApiKey>> GetByPrefixAsync(string prefix, CancellationToken cancellationToken = default)
        => Task.FromResult(new List<ApiKey>());

    public Task<List<ApiKey>> GetAllAsync(CancellationToken cancellationToken = default)
        => Task.FromResult(new List<ApiKey>());

    public Task<ApiKey> UpdateAsync(ApiKey apiKey, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database is not configured. Please configure SQL Server connection.");

    public Task UpdateLastUsedAsync(Guid apiKeyId, CancellationToken cancellationToken = default)
        => Task.CompletedTask;

    public Task<bool> DeleteAsync(Guid apiKeyId, CancellationToken cancellationToken = default)
        => Task.FromResult(false);

    public Task<bool> DisableAsync(Guid apiKeyId, CancellationToken cancellationToken = default)
        => Task.FromResult(false);

    public Task<ApiKey?> GetByDescriptionAsync(string description, CancellationToken cancellationToken = default)
        => Task.FromResult<ApiKey?>(null);

    public Task<List<ApiKey>> GetByCreatedByAsync(string createdBy, CancellationToken cancellationToken = default)
        => Task.FromResult(new List<ApiKey>());
}

/// <summary>
/// Stub banner message repository that returns empty data when database is not configured.
/// </summary>
public class StubBannerMessageRepository : IBannerMessageRepository
{
    public Task<List<BannerMessage>> GetAllAsync(CancellationToken cancellationToken = default)
        => Task.FromResult(new List<BannerMessage>());

    public Task<List<BannerMessage>> GetActiveAsync(CancellationToken cancellationToken = default)
        => Task.FromResult(new List<BannerMessage>());

    public Task<BannerMessage?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
        => Task.FromResult<BannerMessage?>(null);

    public Task<BannerMessage> CreateAsync(BannerMessage bannerMessage, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database is not configured. Please configure SQL Server connection.");

    public Task<BannerMessage> UpdateAsync(BannerMessage bannerMessage, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database is not configured. Please configure SQL Server connection.");

    public Task<bool> DeleteAsync(Guid id, CancellationToken cancellationToken = default)
        => Task.FromResult(false);

    public Task<bool> SetEnabledAsync(Guid id, bool enabled, string modifiedBy, CancellationToken cancellationToken = default)
        => Task.FromResult(false);
}
