using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Models;

namespace CLAWS.Core.Validation;

/// <summary>
/// Detects the type of uploaded SQLite database.
/// </summary>
public interface IUploadTypeDetector
{
    /// <summary>
    /// Detects the upload type based on database schema.
    /// </summary>
    /// <param name="sqlitePath">Path to the SQLite database file.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The detected upload type.</returns>
    Task<UploadType> DetectTypeAsync(string sqlitePath, CancellationToken cancellationToken = default);

    /// <summary>
    /// Detects the upload type and returns detailed detection result.
    /// </summary>
    /// <param name="sqlitePath">Path to the SQLite database file.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Detection result with type and metadata.</returns>
    Task<UploadTypeDetectionResult> DetectTypeWithDetailsAsync(string sqlitePath, CancellationToken cancellationToken = default);
}

/// <summary>
/// Result of upload type detection.
/// </summary>
public class UploadTypeDetectionResult
{
    /// <summary>
    /// Detected upload type.
    /// </summary>
    public UploadType UploadType { get; set; }

    /// <summary>
    /// Whether detection was successful.
    /// </summary>
    public bool Success { get; set; }

    /// <summary>
    /// Error message if detection failed.
    /// </summary>
    public string? ErrorMessage { get; set; }

    /// <summary>
    /// Database version found in the database.
    /// </summary>
    public string? DbVersion { get; set; }

    /// <summary>
    /// Tables found during detection.
    /// </summary>
    public List<string> DetectedTables { get; set; } = new();
}

/// <summary>
/// Implementation of upload type detection.
/// </summary>
public class UploadTypeDetector : IUploadTypeDetector
{
    private readonly ILogger<UploadTypeDetector> _logger;

    // Tables that indicate NTFSPermissions database
    private static readonly string[] NtfsIndicatorTables = new[]
    {
        "app__Version",
        "app__CollectionInfo",
        "app__Folders"
    };

    // Tables that indicate ADInventory database
    private static readonly string[] AdInventoryIndicatorTables = new[]
    {
        "Schema_Version",
        "AD_CollectionInfo",
        "AD_Object"
    };

    public UploadTypeDetector(ILogger<UploadTypeDetector> logger)
    {
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task<UploadType> DetectTypeAsync(string sqlitePath, CancellationToken cancellationToken = default)
    {
        var result = await DetectTypeWithDetailsAsync(sqlitePath, cancellationToken);
        return result.UploadType;
    }

    /// <inheritdoc/>
    public async Task<UploadTypeDetectionResult> DetectTypeWithDetailsAsync(string sqlitePath, CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("Detecting upload type for {Path}", sqlitePath);

        var result = new UploadTypeDetectionResult();

        try
        {
            var connectionString = new SqliteConnectionStringBuilder
            {
                DataSource = sqlitePath,
                Mode = SqliteOpenMode.ReadOnly
            }.ConnectionString;

            await using var connection = new SqliteConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Get all tables in the database
            var tables = await GetAllTablesAsync(connection, cancellationToken);
            result.DetectedTables = tables;

            _logger.LogDebug("Found {Count} tables in database: {Tables}",
                tables.Count, string.Join(", ", tables.Take(10)));

            // Check for NTFSPermissions indicators
            var hasNtfsVersion = tables.Contains("app__Version", StringComparer.OrdinalIgnoreCase);
            var hasNtfsCollectionInfo = tables.Contains("app__CollectionInfo", StringComparer.OrdinalIgnoreCase);

            // Check for ADInventory indicators
            var hasAdSchemaVersion = tables.Contains("Schema_Version", StringComparer.OrdinalIgnoreCase);
            var hasAdCollectionInfo = tables.Contains("AD_CollectionInfo", StringComparer.OrdinalIgnoreCase);

            if (hasNtfsVersion && hasNtfsCollectionInfo)
            {
                result.UploadType = UploadType.NTFSPermissions;
                result.Success = true;
                result.DbVersion = await GetNtfsVersionAsync(connection, cancellationToken);
                _logger.LogInformation("Detected upload type: NTFSPermissions (version: {Version})", result.DbVersion);
            }
            else if (hasAdSchemaVersion && hasAdCollectionInfo)
            {
                result.UploadType = UploadType.ADInventory;
                result.Success = true;
                result.DbVersion = await GetAdInventoryVersionAsync(connection, cancellationToken);
                _logger.LogInformation("Detected upload type: ADInventory (version: {Version})", result.DbVersion);
            }
            else
            {
                result.UploadType = UploadType.Unknown;
                result.Success = false;
                result.ErrorMessage = "Unable to determine database type. " +
                    $"Expected tables not found. Found: {string.Join(", ", tables.Take(5))}...";
                _logger.LogWarning("Unknown database type. Tables: {Tables}", string.Join(", ", tables));
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error detecting upload type for {Path}", sqlitePath);
            result.UploadType = UploadType.Unknown;
            result.Success = false;
            result.ErrorMessage = $"Error reading database: {ex.Message}";
        }

        return result;
    }

    private static async Task<List<string>> GetAllTablesAsync(SqliteConnection connection, CancellationToken cancellationToken)
    {
        var tables = new List<string>();

        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name";

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            tables.Add(reader.GetString(0));
        }

        return tables;
    }

    private static async Task<string?> GetNtfsVersionAsync(SqliteConnection connection, CancellationToken cancellationToken)
    {
        try
        {
            await using var command = connection.CreateCommand();
            command.CommandText = "SELECT PropertyValue FROM app__Version WHERE PropertyName = 'DBVersion'";
            var result = await command.ExecuteScalarAsync(cancellationToken);
            return result?.ToString();
        }
        catch
        {
            return null;
        }
    }

    private static async Task<string?> GetAdInventoryVersionAsync(SqliteConnection connection, CancellationToken cancellationToken)
    {
        try
        {
            await using var command = connection.CreateCommand();
            command.CommandText = "SELECT Version FROM Schema_Version ORDER BY AppliedDate DESC LIMIT 1";
            var result = await command.ExecuteScalarAsync(cancellationToken);
            return result?.ToString();
        }
        catch
        {
            return null;
        }
    }
}
