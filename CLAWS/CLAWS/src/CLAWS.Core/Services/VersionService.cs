using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Models;

namespace CLAWS.Core.Services;

/// <summary>
/// Represents a schema version entry with metadata.
/// </summary>
public class SchemaVersionEntry
{
    public string SchemaName { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public DateTime? AppliedDate { get; set; }
    public string? Description { get; set; }
}

/// <summary>
/// Provides version requirement information from SQL Server.
/// </summary>
public interface IVersionService
{
    /// <summary>
    /// Gets the minimum required database schema version from SQL Server (legacy - for NTFSPermissions).
    /// </summary>
    /// <param name="connectionString">SQL Server connection string.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Minimum DB version or null if not configured.</returns>
    Task<string?> GetRequiredDbVersionAsync(string connectionString, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the minimum required database schema version from SQL Server for a specific upload type.
    /// </summary>
    /// <param name="connectionString">SQL Server connection string.</param>
    /// <param name="uploadType">The type of upload to get requirements for.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Minimum DB version or null if not configured.</returns>
    Task<string?> GetRequiredDbVersionAsync(string connectionString, UploadType uploadType, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the minimum required application version from SQL Server (legacy - for NTFSPermissions).
    /// </summary>
    /// <param name="connectionString">SQL Server connection string.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Minimum app version or null if not configured.</returns>
    Task<string?> GetRequiredAppVersionAsync(string connectionString, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the minimum required application version from SQL Server for a specific upload type.
    /// </summary>
    /// <param name="connectionString">SQL Server connection string.</param>
    /// <param name="uploadType">The type of upload to get requirements for.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Minimum app version or null if not configured (may return null for types that don't track app version).</returns>
    Task<string?> GetRequiredAppVersionAsync(string connectionString, UploadType uploadType, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all version requirements from SQL Server.
    /// </summary>
    /// <param name="connectionString">SQL Server connection string.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Dictionary of schema names to versions.</returns>
    Task<Dictionary<string, string>> GetAllVersionRequirementsAsync(string connectionString, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all version requirements with full metadata from SQL Server.
    /// </summary>
    /// <param name="connectionString">SQL Server connection string.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>List of schema version entries with metadata.</returns>
    Task<List<SchemaVersionEntry>> GetAllVersionEntriesAsync(string connectionString, CancellationToken cancellationToken = default);

    /// <summary>
    /// Updates a version requirement in SQL Server.
    /// </summary>
    /// <param name="connectionString">SQL Server connection string.</param>
    /// <param name="schemaName">Schema name (e.g., "CollectNTFSPerm" or "DBVersion").</param>
    /// <param name="version">New version value.</param>
    /// <param name="description">Optional description.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>True if successful.</returns>
    Task<bool> UpdateVersionRequirementAsync(string connectionString, string schemaName, string version, string? description = null, CancellationToken cancellationToken = default);
}

/// <summary>
/// Implementation of version service.
/// </summary>
public class VersionService : IVersionService
{
    private readonly ILogger<VersionService> _logger;

    public VersionService(ILogger<VersionService> logger)
    {
        _logger = logger;
    }

    /// <inheritdoc/>
    public Task<string?> GetRequiredDbVersionAsync(string connectionString, CancellationToken cancellationToken = default)
    {
        // Legacy method - assumes NTFSPermissions
        return GetRequiredDbVersionAsync(connectionString, UploadType.NTFSPermissions, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<string?> GetRequiredDbVersionAsync(string connectionString, UploadType uploadType, CancellationToken cancellationToken = default)
    {
        var versions = await GetAllVersionRequirementsAsync(connectionString, cancellationToken);

        // Get the schema name for this upload type
        var schemaName = uploadType switch
        {
            UploadType.NTFSPermissions => "DBVersion",
            UploadType.ADInventory => "ADInventory",
            _ => "DBVersion"
        };

        return versions.TryGetValue(schemaName, out var version) ? version : null;
    }

    /// <inheritdoc/>
    public Task<string?> GetRequiredAppVersionAsync(string connectionString, CancellationToken cancellationToken = default)
    {
        // Legacy method - assumes NTFSPermissions
        return GetRequiredAppVersionAsync(connectionString, UploadType.NTFSPermissions, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<string?> GetRequiredAppVersionAsync(string connectionString, UploadType uploadType, CancellationToken cancellationToken = default)
    {
        var versions = await GetAllVersionRequirementsAsync(connectionString, cancellationToken);

        // Get the application version schema name for this upload type
        var schemaName = uploadType switch
        {
            UploadType.NTFSPermissions => "CollectNTFSPerm",
            UploadType.ADInventory => null, // ADInventory doesn't track app version
            _ => "CollectNTFSPerm"
        };

        if (schemaName == null)
            return null;

        return versions.TryGetValue(schemaName, out var version) ? version : null;
    }

    /// <inheritdoc/>
    public async Task<Dictionary<string, string>> GetAllVersionRequirementsAsync(string connectionString, CancellationToken cancellationToken = default)
    {
        var versions = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = connection.CreateCommand();
            command.CommandText = "SELECT SchemaName, Version FROM [fsapp].[SchemaVersion]";

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var schemaName = reader.GetString(0);
                var version = reader.GetString(1);
                versions[schemaName] = version;
            }

            _logger.LogInformation("Retrieved {Count} version requirements from SQL Server", versions.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving version requirements from SQL Server");
        }

        return versions;
    }

    /// <inheritdoc/>
    public async Task<List<SchemaVersionEntry>> GetAllVersionEntriesAsync(string connectionString, CancellationToken cancellationToken = default)
    {
        var entries = new List<SchemaVersionEntry>();

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = connection.CreateCommand();
            command.CommandText = "SELECT SchemaName, Version, AppliedDate, Description FROM [fsapp].[SchemaVersion]";

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                entries.Add(new SchemaVersionEntry
                {
                    SchemaName = reader.GetString(0),
                    Version = reader.GetString(1),
                    AppliedDate = reader.IsDBNull(2) ? null : reader.GetDateTime(2),
                    Description = reader.IsDBNull(3) ? null : reader.GetString(3)
                });
            }

            _logger.LogInformation("Retrieved {Count} version entries from SQL Server", entries.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving version entries from SQL Server");
        }

        return entries;
    }

    /// <inheritdoc/>
    public async Task<bool> UpdateVersionRequirementAsync(string connectionString, string schemaName, string version, string? description = null, CancellationToken cancellationToken = default)
    {
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = connection.CreateCommand();
            command.CommandText = @"
                UPDATE [fsapp].[SchemaVersion]
                SET Version = @Version,
                    AppliedDate = GETDATE(),
                    Description = COALESCE(@Description, Description)
                WHERE SchemaName = @SchemaName;

                IF @@ROWCOUNT = 0
                BEGIN
                    INSERT INTO [fsapp].[SchemaVersion] (SchemaName, Version, AppliedDate, Description)
                    VALUES (@SchemaName, @Version, GETDATE(), @Description);
                END";

            command.Parameters.AddWithValue("@SchemaName", schemaName);
            command.Parameters.AddWithValue("@Version", version);
            command.Parameters.AddWithValue("@Description", (object?)description ?? DBNull.Value);

            await command.ExecuteNonQueryAsync(cancellationToken);

            _logger.LogInformation("Updated version requirement {SchemaName} to {Version}", schemaName, version);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating version requirement {SchemaName}", schemaName);
            return false;
        }
    }
}
