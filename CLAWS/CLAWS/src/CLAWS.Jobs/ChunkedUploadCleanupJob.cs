using System.Text.Json;
using Hangfire;
using Microsoft.Extensions.Logging;
using CLAWS.Core.Configuration;
using CLAWS.Core.Models;

namespace CLAWS.Jobs;

/// <summary>
/// Hangfire job for cleaning up expired chunked upload sessions.
/// </summary>
public interface IChunkedUploadCleanupJob
{
    /// <summary>
    /// Cleans up expired chunked upload sessions and orphaned directories.
    /// </summary>
    [JobDisplayName("Cleanup: Expired Chunked Uploads")]
    Task ExecuteAsync(CancellationToken cancellationToken);
}

/// <summary>
/// Implementation of the chunked upload cleanup job.
/// </summary>
public class ChunkedUploadCleanupJob : IChunkedUploadCleanupJob
{
    private readonly ILogger<ChunkedUploadCleanupJob> _logger;
    private readonly StorageSettings _storageSettings;
    private readonly ChunkedUploadSettings _chunkedUploadSettings;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public ChunkedUploadCleanupJob(
        ILogger<ChunkedUploadCleanupJob> logger,
        StorageSettings storageSettings,
        ChunkedUploadSettings chunkedUploadSettings)
    {
        _logger = logger;
        _storageSettings = storageSettings;
        _chunkedUploadSettings = chunkedUploadSettings;
    }

    /// <inheritdoc/>
    public async Task ExecuteAsync(CancellationToken cancellationToken)
    {
        if (!_chunkedUploadSettings.Enabled)
        {
            _logger.LogDebug("Chunked uploads are disabled, skipping cleanup");
            return;
        }

        var chunksBasePath = Path.Combine(_storageSettings.GetUploadPath(), "chunks");
        if (!Directory.Exists(chunksBasePath))
        {
            _logger.LogDebug("Chunks directory does not exist: {Path}", chunksBasePath);
            return;
        }

        _logger.LogInformation("Starting chunked upload cleanup scan in: {Path}", chunksBasePath);

        var expiredCount = 0;
        long freedBytes = 0;
        var orphanedCount = 0;

        foreach (var sessionDir in Directory.GetDirectories(chunksBasePath))
        {
            cancellationToken.ThrowIfCancellationRequested();

            var metadataPath = Path.Combine(sessionDir, "metadata.json");
            var dirName = Path.GetFileName(sessionDir);

            // Try to parse directory name as GUID for logging
            Guid.TryParse(dirName, out var uploadId);

            if (!File.Exists(metadataPath))
            {
                // No metadata file - check if directory is old enough to delete
                var dirInfo = new DirectoryInfo(sessionDir);
                if (dirInfo.CreationTimeUtc < DateTime.UtcNow.AddHours(-24))
                {
                    var size = GetDirectorySize(sessionDir);
                    try
                    {
                        Directory.Delete(sessionDir, recursive: true);
                        freedBytes += size;
                        orphanedCount++;
                        _logger.LogInformation(
                            "Cleaned up orphaned chunk directory: {Path}, Age={Age:g}, Size={Size}",
                            sessionDir, DateTime.UtcNow - dirInfo.CreationTimeUtc, FormatBytes(size));
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, "Failed to delete orphaned directory: {Path}", sessionDir);
                    }
                }
                continue;
            }

            try
            {
                var json = await File.ReadAllTextAsync(metadataPath, cancellationToken);
                var session = JsonSerializer.Deserialize<ChunkUploadSession>(json, JsonOptions);

                if (session?.IsExpired == true)
                {
                    var size = GetDirectorySize(sessionDir);
                    Directory.Delete(sessionDir, recursive: true);
                    freedBytes += size;
                    expiredCount++;

                    _logger.LogInformation(
                        "Cleaned up expired chunked upload: UploadId={UploadId}, User={User}, " +
                        "FileName={FileName}, ExpiredAt={ExpiredAt}, Size={Size}",
                        session.UploadId, session.UploadedBy, session.FileName,
                        session.ExpiresAt, FormatBytes(size));
                }
            }
            catch (JsonException ex)
            {
                _logger.LogWarning(ex, "Invalid metadata JSON in: {Path}", metadataPath);

                // Delete directories with invalid metadata if they're old
                var dirInfo = new DirectoryInfo(sessionDir);
                if (dirInfo.CreationTimeUtc < DateTime.UtcNow.AddHours(-24))
                {
                    var size = GetDirectorySize(sessionDir);
                    try
                    {
                        Directory.Delete(sessionDir, recursive: true);
                        freedBytes += size;
                        orphanedCount++;
                    }
                    catch { /* Best effort */ }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error checking chunked upload session: {Path}", sessionDir);
            }
        }

        if (expiredCount > 0 || orphanedCount > 0)
        {
            _logger.LogInformation(
                "Chunked upload cleanup complete: ExpiredSessions={Expired}, OrphanedDirs={Orphaned}, " +
                "TotalFreed={Bytes} ({BytesMB:F1} MB)",
                expiredCount, orphanedCount, freedBytes, freedBytes / (1024.0 * 1024.0));
        }
        else
        {
            _logger.LogDebug("Chunked upload cleanup: No expired sessions found");
        }
    }

    private static long GetDirectorySize(string path)
    {
        try
        {
            return new DirectoryInfo(path)
                .EnumerateFiles("*", SearchOption.AllDirectories)
                .Sum(f => f.Length);
        }
        catch
        {
            return 0;
        }
    }

    private static string FormatBytes(long bytes)
    {
        string[] suffixes = { "B", "KB", "MB", "GB" };
        int i = 0;
        double size = bytes;
        while (size >= 1024 && i < suffixes.Length - 1)
        {
            size /= 1024;
            i++;
        }
        return $"{size:F1} {suffixes[i]}";
    }
}
