using Microsoft.Data.SqlClient;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Core.Models;
using Semver;

namespace CLAWS.Core.Validation;

/// <summary>
/// Validates SQLite databases for imports.
/// </summary>
public interface IDatabaseValidator
{
    /// <summary>
    /// Validates a SQLite database structure and versions (legacy - assumes NTFSPermissions).
    /// </summary>
    /// <param name="sqlitePath">Path to the SQLite database file.</param>
    /// <param name="requiredDbVersion">Minimum required DB schema version.</param>
    /// <param name="requiredAppVersion">Minimum required application version.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Validation result with version and collection information.</returns>
    Task<DatabaseValidationResult> ValidateAsync(
        string sqlitePath,
        string requiredDbVersion,
        string requiredAppVersion,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Validates a SQLite database structure and versions for a specific upload type.
    /// </summary>
    /// <param name="sqlitePath">Path to the SQLite database file.</param>
    /// <param name="uploadType">Type of database to validate.</param>
    /// <param name="requiredDbVersion">Minimum required DB schema version.</param>
    /// <param name="requiredAppVersion">Minimum required application version (not used for ADInventory).</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Validation result with version and collection information.</returns>
    Task<DatabaseValidationResult> ValidateAsync(
        string sqlitePath,
        UploadType uploadType,
        string requiredDbVersion,
        string? requiredAppVersion,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Runs SQLite integrity check.
    /// </summary>
    /// <param name="sqlitePath">Path to the SQLite database file.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Validation result.</returns>
    Task<ValidationResult> RunIntegrityCheckAsync(
        string sqlitePath,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Checks if any InventoryIDs from the SQLite database already exist in SQL Server (legacy - assumes NTFSPermissions).
    /// </summary>
    /// <param name="sqlitePath">Path to the SQLite database file.</param>
    /// <param name="sqlServerConnectionString">SQL Server connection string.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Result indicating if duplicates were found.</returns>
    Task<DuplicateCheckResult> CheckForDuplicateInventoriesAsync(
        string sqlitePath,
        string sqlServerConnectionString,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Checks if any InventoryIDs from the SQLite database already exist in SQL Server for a specific upload type.
    /// </summary>
    /// <param name="sqlitePath">Path to the SQLite database file.</param>
    /// <param name="sqlServerConnectionString">SQL Server connection string.</param>
    /// <param name="uploadType">Type of database being checked.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Result indicating if duplicates were found.</returns>
    Task<DuplicateCheckResult> CheckForDuplicateInventoriesAsync(
        string sqlitePath,
        string sqlServerConnectionString,
        UploadType uploadType,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Implementation of SQLite database validation.
/// </summary>
public class DatabaseValidator : IDatabaseValidator
{
    private readonly ILogger<DatabaseValidator> _logger;
    private readonly AppSettings _appSettings;

    public DatabaseValidator(ILogger<DatabaseValidator> logger, Microsoft.Extensions.Options.IOptions<AppSettings> appSettings)
    {
        _logger = logger;
        _appSettings = appSettings.Value;
    }

    /// <inheritdoc/>
    public async Task<ValidationResult> RunIntegrityCheckAsync(
        string sqlitePath,
        CancellationToken cancellationToken = default)
    {
        var mode = _appSettings.Import.IntegrityCheckMode;
        var thresholdMB = _appSettings.Import.AutoIntegrityCheckThresholdMB;

        // Handle 'None' mode - skip integrity check entirely
        if (mode == IntegrityCheckMode.None)
        {
            _logger.LogInformation("Skipping SQLite integrity check (mode=None) for {Path}", sqlitePath);
            return ValidationResult.Success();
        }

        // Handle 'Auto' mode - determine based on file size
        if (mode == IntegrityCheckMode.Auto)
        {
            var fileInfo = new System.IO.FileInfo(sqlitePath);
            var fileSizeMB = fileInfo.Length / (1024.0 * 1024.0);

            if (fileSizeMB > thresholdMB)
            {
                mode = IntegrityCheckMode.Quick;
                _logger.LogInformation("Using quick_check for {Path} (file size {Size:F1} MB > threshold {Threshold} MB)",
                    sqlitePath, fileSizeMB, thresholdMB);
            }
            else
            {
                mode = IntegrityCheckMode.Full;
                _logger.LogInformation("Using integrity_check for {Path} (file size {Size:F1} MB <= threshold {Threshold} MB)",
                    sqlitePath, fileSizeMB, thresholdMB);
            }
        }

        var pragmaCommand = mode == IntegrityCheckMode.Quick ? "PRAGMA quick_check" : "PRAGMA integrity_check";
        _logger.LogInformation("Running SQLite {Mode} on {Path}", pragmaCommand, sqlitePath);

        try
        {
            var connectionString = new SqliteConnectionStringBuilder
            {
                DataSource = sqlitePath,
                Mode = SqliteOpenMode.ReadOnly
            }.ConnectionString;

            await using var connection = new SqliteConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = connection.CreateCommand();
            command.CommandText = pragmaCommand;

            var result = await command.ExecuteScalarAsync(cancellationToken);
            var resultStr = result?.ToString() ?? "unknown";

            if (resultStr.Equals("ok", StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogInformation("SQLite {Mode} passed", pragmaCommand);
                return ValidationResult.Success();
            }

            _logger.LogWarning("SQLite {Mode} failed: {Result}", pragmaCommand, resultStr);
            return ValidationResult.Failure(
                "SQLITE_CORRUPT",
                $"SQLite database failed {pragmaCommand}: {resultStr}");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error running {Mode} on {Path}", pragmaCommand, sqlitePath);
            return ValidationResult.Failure(
                "SQLITE_ERROR",
                $"Error checking database integrity: {ex.Message}");
        }
    }

    /// <inheritdoc/>
    public Task<DatabaseValidationResult> ValidateAsync(
        string sqlitePath,
        string requiredDbVersion,
        string requiredAppVersion,
        CancellationToken cancellationToken = default)
    {
        // Legacy method - assumes NTFSPermissions
        return ValidateAsync(sqlitePath, UploadType.NTFSPermissions, requiredDbVersion, requiredAppVersion, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<DatabaseValidationResult> ValidateAsync(
        string sqlitePath,
        UploadType uploadType,
        string requiredDbVersion,
        string? requiredAppVersion,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("Validating SQLite database {Path} for type {Type}", sqlitePath, uploadType);

        try
        {
            var connectionString = new SqliteConnectionStringBuilder
            {
                DataSource = sqlitePath,
                Mode = SqliteOpenMode.ReadOnly
            }.ConnectionString;

            await using var connection = new SqliteConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            // Type-specific validation
            return uploadType switch
            {
                UploadType.NTFSPermissions => await ValidateNtfsPermissionsAsync(connection, requiredDbVersion, requiredAppVersion, cancellationToken),
                UploadType.ADInventory => await ValidateAdInventoryAsync(connection, requiredDbVersion, cancellationToken),
                _ => new DatabaseValidationResult
                {
                    IsValid = false,
                    ErrorCode = "UNKNOWN_TYPE",
                    ErrorMessage = $"Unknown upload type: {uploadType}"
                }
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error validating SQLite database: {Path}", sqlitePath);
            return new DatabaseValidationResult
            {
                IsValid = false,
                ErrorCode = "VALIDATION_ERROR",
                ErrorMessage = $"Error validating database: {ex.Message}"
            };
        }
    }

    private async Task<DatabaseValidationResult> ValidateNtfsPermissionsAsync(
        SqliteConnection connection,
        string requiredDbVersion,
        string? requiredAppVersion,
        CancellationToken cancellationToken)
    {
        // Check for required tables
        var hasVersionTable = await TableExistsAsync(connection, "app__Version", cancellationToken);
        if (!hasVersionTable)
        {
            return new DatabaseValidationResult
            {
                IsValid = false,
                ErrorCode = "MISSING_VERSION_TABLE",
                ErrorMessage = "Required table app__Version not found. This may not be a valid CollectNTFSPerms database."
            };
        }

        var hasCollectionInfo = await TableExistsAsync(connection, "app__CollectionInfo", cancellationToken);
        if (!hasCollectionInfo)
        {
            return new DatabaseValidationResult
            {
                IsValid = false,
                ErrorCode = "MISSING_COLLECTION_INFO",
                ErrorMessage = "Required table app__CollectionInfo not found or is empty."
            };
        }

        // Get DB version
        var dbVersion = await GetNtfsDbVersionAsync(connection, cancellationToken);
        if (string.IsNullOrEmpty(dbVersion))
        {
            return new DatabaseValidationResult
            {
                IsValid = false,
                ErrorCode = "MISSING_DB_VERSION",
                ErrorMessage = "Database version not found in app__Version table."
            };
        }

        _logger.LogInformation("SQLite DB version: {Version}", dbVersion);

        // Validate DB version
        if (!string.IsNullOrEmpty(requiredDbVersion))
        {
            if (!CompareVersions(dbVersion, requiredDbVersion, out var dbVersionValid) || !dbVersionValid)
            {
                return new DatabaseValidationResult
                {
                    IsValid = false,
                    ErrorCode = "DB_VERSION_TOO_LOW",
                    ErrorMessage = $"Database schema version {dbVersion} does not meet minimum required version {requiredDbVersion}.",
                    DbVersion = dbVersion,
                    RequiredDbVersion = requiredDbVersion
                };
            }
        }

        // Get collection info
        var collections = await GetNtfsCollectionsAsync(connection, cancellationToken);
        if (collections.Count == 0)
        {
            return new DatabaseValidationResult
            {
                IsValid = false,
                ErrorCode = "NO_COLLECTIONS",
                ErrorMessage = "No collections found in app__CollectionInfo table."
            };
        }

        _logger.LogInformation("Found {Count} collections in database", collections.Count);

        // Validate application versions
        var versionErrors = new List<CollectionVersionError>();
        if (!string.IsNullOrEmpty(requiredAppVersion))
        {
            foreach (var collection in collections)
            {
                if (!CompareVersions(collection.ApplicationVersion, requiredAppVersion, out var isValid) || !isValid)
                {
                    versionErrors.Add(new CollectionVersionError
                    {
                        InventoryId = collection.InventoryId,
                        FoundVersion = collection.ApplicationVersion,
                        RequiredVersion = requiredAppVersion
                    });
                }
            }

            if (versionErrors.Count > 0)
            {
                var firstError = versionErrors.First();
                return new DatabaseValidationResult
                {
                    IsValid = false,
                    ErrorCode = "APP_VERSION_TOO_LOW",
                    ErrorMessage = $"Collection {firstError.InventoryId} was created with application version {firstError.FoundVersion}, which does not meet minimum required version {firstError.RequiredVersion}.",
                    DbVersion = dbVersion,
                    RequiredDbVersion = requiredDbVersion,
                    Collections = collections,
                    VersionErrors = versionErrors
                };
            }
        }

        _logger.LogInformation("SQLite database validation successful");

        return new DatabaseValidationResult
        {
            IsValid = true,
            DbVersion = dbVersion,
            RequiredDbVersion = requiredDbVersion,
            Collections = collections
        };
    }

    private async Task<DatabaseValidationResult> ValidateAdInventoryAsync(
        SqliteConnection connection,
        string requiredDbVersion,
        CancellationToken cancellationToken)
    {
        // Check for required tables
        var hasSchemaVersion = await TableExistsAsync(connection, "Schema_Version", cancellationToken);
        if (!hasSchemaVersion)
        {
            return new DatabaseValidationResult
            {
                IsValid = false,
                ErrorCode = "MISSING_VERSION_TABLE",
                ErrorMessage = "Required table Schema_Version not found. This may not be a valid ADInventory database."
            };
        }

        var hasCollectionInfo = await TableExistsAsync(connection, "AD_CollectionInfo", cancellationToken);
        if (!hasCollectionInfo)
        {
            return new DatabaseValidationResult
            {
                IsValid = false,
                ErrorCode = "MISSING_COLLECTION_INFO",
                ErrorMessage = "Required table AD_CollectionInfo not found."
            };
        }

        // Get DB version from Schema_Version
        var dbVersion = await GetAdInventoryVersionAsync(connection, cancellationToken);
        if (string.IsNullOrEmpty(dbVersion))
        {
            return new DatabaseValidationResult
            {
                IsValid = false,
                ErrorCode = "MISSING_DB_VERSION",
                ErrorMessage = "Database version not found in Schema_Version table."
            };
        }

        _logger.LogInformation("ADInventory DB version: {Version}", dbVersion);

        // Validate DB version
        if (!string.IsNullOrEmpty(requiredDbVersion))
        {
            if (!CompareVersions(dbVersion, requiredDbVersion, out var dbVersionValid) || !dbVersionValid)
            {
                return new DatabaseValidationResult
                {
                    IsValid = false,
                    ErrorCode = "DB_VERSION_TOO_LOW",
                    ErrorMessage = $"Database schema version {dbVersion} does not meet minimum required version {requiredDbVersion}.",
                    DbVersion = dbVersion,
                    RequiredDbVersion = requiredDbVersion
                };
            }
        }

        // Get collection info from AD_CollectionInfo
        var collections = await GetAdInventoryCollectionsAsync(connection, cancellationToken);
        if (collections.Count == 0)
        {
            return new DatabaseValidationResult
            {
                IsValid = false,
                ErrorCode = "NO_COLLECTIONS",
                ErrorMessage = "No collections found in AD_CollectionInfo table."
            };
        }

        _logger.LogInformation("Found {Count} AD collections (domains) in database", collections.Count);

        // ADInventory doesn't have per-collection application versions
        // Just validate the schema version was met

        return new DatabaseValidationResult
        {
            IsValid = true,
            DbVersion = dbVersion,
            RequiredDbVersion = requiredDbVersion,
            Collections = collections
        };
    }

    private static async Task<bool> TableExistsAsync(
        SqliteConnection connection,
        string tableName,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=@name";
        command.Parameters.AddWithValue("@name", tableName);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return Convert.ToInt32(result) > 0;
    }

    private static async Task<string?> GetNtfsDbVersionAsync(
        SqliteConnection connection,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT PropertyValue FROM app__Version WHERE PropertyName = 'DBVersion'";
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result?.ToString();
    }

    private static async Task<string?> GetAdInventoryVersionAsync(
        SqliteConnection connection,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT Version FROM Schema_Version ORDER BY AppliedDate DESC LIMIT 1";
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result?.ToString();
    }

    private static async Task<List<CollectionInfo>> GetNtfsCollectionsAsync(
        SqliteConnection connection,
        CancellationToken cancellationToken)
    {
        var collections = new List<CollectionInfo>();

        await using var command = connection.CreateCommand();
        command.CommandText = @"
            SELECT InventoryID, ApplicationVersion, ComputerName, CollectionDateTime
            FROM app__CollectionInfo";

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            collections.Add(new CollectionInfo
            {
                InventoryId = Guid.Parse(reader.GetString(0)),
                ApplicationVersion = reader.GetString(1),
                ComputerName = reader.IsDBNull(2) ? null : reader.GetString(2),
                CollectionDate = reader.IsDBNull(3) ? null : DateTime.Parse(reader.GetString(3))
            });
        }

        return collections;
    }

    private static async Task<List<CollectionInfo>> GetAdInventoryCollectionsAsync(
        SqliteConnection connection,
        CancellationToken cancellationToken)
    {
        var collections = new List<CollectionInfo>();

        await using var command = connection.CreateCommand();
        // AD_CollectionInfo uses InventoryID, DomainName, and CollectionDateTime
        command.CommandText = @"
            SELECT InventoryID, DomainName, CollectionDateTime
            FROM AD_CollectionInfo";

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            collections.Add(new CollectionInfo
            {
                // InventoryID in ADInventory is stored as text (GUID string)
                InventoryId = Guid.Parse(reader.GetString(0)),
                // Use DomainName as the "ComputerName" equivalent for display
                ComputerName = reader.IsDBNull(1) ? null : reader.GetString(1),
                // ADInventory stores datetime as ISO 8601 string
                CollectionDate = reader.IsDBNull(2) ? null : DateTime.Parse(reader.GetString(2)),
                // ADInventory doesn't have per-collection app version
                ApplicationVersion = "N/A"
            });
        }

        return collections;
    }

    private static bool CompareVersions(string found, string required, out bool isValid)
    {
        isValid = false;

        try
        {
            // Try to parse as semantic versions
            if (SemVersion.TryParse(found, SemVersionStyles.Any, out var foundVersion) &&
                SemVersion.TryParse(required, SemVersionStyles.Any, out var requiredVersion))
            {
                isValid = foundVersion.CompareSortOrderTo(requiredVersion) >= 0;
                return true;
            }

            // Fall back to simple version comparison
            if (Version.TryParse(found, out var foundVer) &&
                Version.TryParse(required, out var requiredVer))
            {
                isValid = foundVer >= requiredVer;
                return true;
            }

            return false;
        }
        catch
        {
            return false;
        }
    }

    /// <inheritdoc/>
    public Task<DuplicateCheckResult> CheckForDuplicateInventoriesAsync(
        string sqlitePath,
        string sqlServerConnectionString,
        CancellationToken cancellationToken = default)
    {
        // Legacy method - assumes NTFSPermissions
        return CheckForDuplicateInventoriesAsync(sqlitePath, sqlServerConnectionString, UploadType.NTFSPermissions, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<DuplicateCheckResult> CheckForDuplicateInventoriesAsync(
        string sqlitePath,
        string sqlServerConnectionString,
        UploadType uploadType,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("Checking for duplicate InventoryIDs in {Path} for type {Type}", sqlitePath, uploadType);

        try
        {
            // Get InventoryIDs from SQLite
            var sqliteConnectionString = new SqliteConnectionStringBuilder
            {
                DataSource = sqlitePath,
                Mode = SqliteOpenMode.ReadOnly
            }.ConnectionString;

            var inventoryIds = new List<(Guid Id, string? Name)>();

            await using (var sqliteConn = new SqliteConnection(sqliteConnectionString))
            {
                await sqliteConn.OpenAsync(cancellationToken);

                await using var cmd = sqliteConn.CreateCommand();

                // Type-specific query
                if (uploadType == UploadType.ADInventory)
                {
                    cmd.CommandText = "SELECT InventoryID, DomainName FROM AD_CollectionInfo";
                }
                else
                {
                    cmd.CommandText = "SELECT InventoryID, ComputerName FROM app__CollectionInfo";
                }

                await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    var id = Guid.Parse(reader.GetString(0));
                    var name = reader.IsDBNull(1) ? null : reader.GetString(1);
                    inventoryIds.Add((id, name));
                }
            }

            if (inventoryIds.Count == 0)
            {
                _logger.LogWarning("No InventoryIDs found in SQLite database");
                return DuplicateCheckResult.Success();
            }

            _logger.LogInformation("Found {Count} InventoryID(s) to check for duplicates", inventoryIds.Count);

            // Get schema names based on upload type
            var stagingSchema = uploadType.GetStagingSchema();
            var productionSchema = uploadType.GetProductionSchema();
            var nameColumn = uploadType == UploadType.ADInventory ? "DomainName" : "ComputerName";

            // Check SQL Server for duplicates
            var duplicates = new List<DuplicateInventoryInfo>();

            await using var sqlConn = new SqlConnection(sqlServerConnectionString);
            await sqlConn.OpenAsync(cancellationToken);

            foreach (var (inventoryId, name) in inventoryIds)
            {
                // Check production schema (already merged)
                await using (var checkCmd = sqlConn.CreateCommand())
                {
                    checkCmd.CommandText = $@"
                        SELECT TOP 1 {nameColumn}, CollectionDateTime
                        FROM [{productionSchema}].CollectionInfo
                        WHERE InventoryID = @InventoryId";
                    checkCmd.Parameters.AddWithValue("@InventoryId", inventoryId);

                    try
                    {
                        await using var reader = await checkCmd.ExecuteReaderAsync(cancellationToken);
                        if (await reader.ReadAsync(cancellationToken))
                        {
                            DateTime? existingDate = null;
                            if (!reader.IsDBNull(1))
                            {
                                var value = reader.GetValue(1);
                                existingDate = value switch
                                {
                                    DateTimeOffset dto => dto.DateTime,
                                    DateTime dt => dt,
                                    _ => null
                                };
                            }

                            duplicates.Add(new DuplicateInventoryInfo
                            {
                                InventoryId = inventoryId,
                                ComputerName = reader.IsDBNull(0) ? name : reader.GetString(0),
                                Location = DuplicateLocation.Production,
                                ExistingImportDate = existingDate
                            });

                            _logger.LogWarning(
                                "Duplicate InventoryID {InventoryId} found in {Schema}.CollectionInfo (production)",
                                inventoryId, productionSchema);

                            continue; // Already found in production, skip staging check
                        }
                    }
                    catch (SqlException ex) when (ex.Message.Contains("Invalid object name"))
                    {
                        // Production schema doesn't exist yet - skip and check staging
                        _logger.LogDebug("Production schema {Schema} doesn't exist yet", productionSchema);
                    }
                }

                // Check staging schema (imported but not merged)
                await using (var checkCmd = sqlConn.CreateCommand())
                {
                    checkCmd.CommandText = $@"
                        SELECT TOP 1 {nameColumn}, CollectionDateTime
                        FROM [{stagingSchema}].CollectionInfo
                        WHERE InventoryID = @InventoryId";
                    checkCmd.Parameters.AddWithValue("@InventoryId", inventoryId);

                    try
                    {
                        await using var reader = await checkCmd.ExecuteReaderAsync(cancellationToken);
                        if (await reader.ReadAsync(cancellationToken))
                        {
                            DateTime? existingDate = null;
                            if (!reader.IsDBNull(1))
                            {
                                var value = reader.GetValue(1);
                                existingDate = value switch
                                {
                                    DateTimeOffset dto => dto.DateTime,
                                    DateTime dt => dt,
                                    _ => null
                                };
                            }

                            duplicates.Add(new DuplicateInventoryInfo
                            {
                                InventoryId = inventoryId,
                                ComputerName = reader.IsDBNull(0) ? name : reader.GetString(0),
                                Location = DuplicateLocation.Staging,
                                ExistingImportDate = existingDate
                            });

                            _logger.LogWarning(
                                "Duplicate InventoryID {InventoryId} found in {Schema}.CollectionInfo (staging)",
                                inventoryId, stagingSchema);
                        }
                    }
                    catch (SqlException ex) when (ex.Message.Contains("Invalid object name"))
                    {
                        // Staging schema doesn't exist yet - no duplicates in staging
                        _logger.LogDebug("Staging schema {Schema} doesn't exist yet", stagingSchema);
                    }
                }
            }

            if (duplicates.Count > 0)
            {
                _logger.LogWarning(
                    "Found {Count} duplicate InventoryID(s): {Ids}",
                    duplicates.Count,
                    string.Join(", ", duplicates.Select(d => d.InventoryId)));

                return DuplicateCheckResult.DuplicatesFound(duplicates);
            }

            _logger.LogInformation("No duplicate InventoryIDs found");
            return DuplicateCheckResult.Success();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking for duplicate InventoryIDs");
            return new DuplicateCheckResult
            {
                IsValid = false,
                ErrorCode = "DUPLICATE_CHECK_ERROR",
                ErrorMessage = $"Error checking for duplicate inventories: {ex.Message}"
            };
        }
    }
}
