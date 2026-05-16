using CLAWS.Data.Entities;

namespace CLAWS.Data.Repositories;

/// <summary>
/// Repository for configuration operations.
/// </summary>
public interface IConfigurationRepository
{
    /// <summary>
    /// Gets a configuration value by key.
    /// </summary>
    Task<string?> GetValueAsync(string key, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a configuration entry by key.
    /// </summary>
    Task<ConfigurationEntry?> GetAsync(string key, CancellationToken cancellationToken = default);

    /// <summary>
    /// Sets a configuration value.
    /// </summary>
    Task SetAsync(string key, string? value, string modifiedBy, bool isEncrypted = false, string? description = null, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all configuration entries.
    /// </summary>
    Task<List<ConfigurationEntry>> GetAllAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes a configuration entry.
    /// </summary>
    Task<bool> DeleteAsync(string key, CancellationToken cancellationToken = default);
}

/// <summary>
/// Implementation of configuration repository.
/// </summary>
public class ConfigurationRepository : IConfigurationRepository
{
    private readonly Context.ApplicationDbContext _context;

    public ConfigurationRepository(Context.ApplicationDbContext context)
    {
        _context = context;
    }

    /// <inheritdoc/>
    public async Task<string?> GetValueAsync(string key, CancellationToken cancellationToken = default)
    {
        var entry = await _context.Configuration.FindAsync(new object[] { key }, cancellationToken);
        return entry?.ConfigValue;
    }

    /// <inheritdoc/>
    public async Task<ConfigurationEntry?> GetAsync(string key, CancellationToken cancellationToken = default)
    {
        return await _context.Configuration.FindAsync(new object[] { key }, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task SetAsync(
        string key,
        string? value,
        string modifiedBy,
        bool isEncrypted = false,
        string? description = null,
        CancellationToken cancellationToken = default)
    {
        var entry = await _context.Configuration.FindAsync(new object[] { key }, cancellationToken);

        if (entry == null)
        {
            entry = new ConfigurationEntry
            {
                ConfigKey = key,
                ConfigValue = value,
                IsEncrypted = isEncrypted,
                LastModifiedBy = modifiedBy,
                LastModifiedAt = DateTime.UtcNow,
                Description = description
            };
            _context.Configuration.Add(entry);
        }
        else
        {
            entry.ConfigValue = value;
            entry.IsEncrypted = isEncrypted;
            entry.LastModifiedBy = modifiedBy;
            entry.LastModifiedAt = DateTime.UtcNow;
            if (description != null) entry.Description = description;
        }

        await _context.SaveChangesAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<List<ConfigurationEntry>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        return await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions
            .ToListAsync(_context.Configuration, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<bool> DeleteAsync(string key, CancellationToken cancellationToken = default)
    {
        var entry = await _context.Configuration.FindAsync(new object[] { key }, cancellationToken);
        if (entry == null) return false;

        _context.Configuration.Remove(entry);
        await _context.SaveChangesAsync(cancellationToken);
        return true;
    }
}
