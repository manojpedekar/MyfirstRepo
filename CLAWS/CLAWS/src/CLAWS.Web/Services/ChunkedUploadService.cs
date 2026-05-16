using System.Collections.Concurrent;
using System.Text.Json;
using CLAWS.Core.Configuration;
using CLAWS.Core.Models;
using CLAWS.Core.Services;

namespace CLAWS.Web.Services;

/// <summary>
/// Service for handling chunked file uploads.
/// Allows large files to be uploaded in smaller chunks, bypassing IIS size limits.
/// </summary>
public class ChunkedUploadService : IChunkedUploadService
{
    private readonly ILogger<ChunkedUploadService> _logger;
    private readonly IUploadService _uploadService;
    private readonly IDiskSpaceService _diskSpaceService;
    private readonly AppSettings _appSettings;
    private readonly StorageSettings _storageSettings;

    // Per-session locks to prevent race conditions when updating metadata with concurrent chunk uploads
    private static readonly ConcurrentDictionary<Guid, SemaphoreSlim> _sessionLocks = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public ChunkedUploadService(
        ILogger<ChunkedUploadService> logger,
        IUploadService uploadService,
        IDiskSpaceService diskSpaceService,
        AppSettings appSettings)
    {
        _logger = logger;
        _uploadService = uploadService;
        _diskSpaceService = diskSpaceService;
        _appSettings = appSettings;
        _storageSettings = appSettings.Storage;
    }

    private string GetChunkDirectory(Guid uploadId) =>
        Path.Combine(_storageSettings.GetUploadPath(), "chunks", uploadId.ToString());

    private string GetMetadataPath(Guid uploadId) =>
        Path.Combine(GetChunkDirectory(uploadId), "metadata.json");

    private string GetChunkPath(Guid uploadId, int chunkIndex) =>
        Path.Combine(GetChunkDirectory(uploadId), $"chunk_{chunkIndex:D5}");

    /// <summary>
    /// Gets or creates a lock for the specified upload session.
    /// This prevents race conditions when multiple chunks are uploaded concurrently.
    /// </summary>
    private static SemaphoreSlim GetSessionLock(Guid uploadId) =>
        _sessionLocks.GetOrAdd(uploadId, _ => new SemaphoreSlim(1, 1));

    /// <summary>
    /// Removes and disposes the lock for a completed/cancelled session.
    /// </summary>
    private static void ReleaseSessionLock(Guid uploadId)
    {
        if (_sessionLocks.TryRemove(uploadId, out var semaphore))
        {
            semaphore.Dispose();
        }
    }

    /// <inheritdoc/>
    public async Task<InitChunkedResult> InitializeAsync(
        InitChunkedRequest request,
        string userName,
        string? sourceIp,
        CancellationToken cancellationToken)
    {
        // Validate chunked uploads are enabled
        if (!_appSettings.ChunkedUpload.Enabled)
        {
            return InitChunkedResult.Fail("CHUNKED_DISABLED", "Chunked uploads are not enabled.");
        }

        // Validate request
        if (string.IsNullOrEmpty(request.FileName))
            return InitChunkedResult.Fail("INVALID_FILENAME", "File name is required.");

        if (request.FileSize <= 0)
            return InitChunkedResult.Fail("INVALID_SIZE", "File size must be positive.");

        if (request.TotalChunks <= 0)
            return InitChunkedResult.Fail("INVALID_CHUNKS", "Total chunks must be positive.");

        if (request.ChunkSize <= 0)
            return InitChunkedResult.Fail("INVALID_CHUNK_SIZE", "Chunk size must be positive.");

        // Check file extension
        var extension = Path.GetExtension(request.FileName).ToLowerInvariant();
        if (extension != ".zip")
            return InitChunkedResult.Fail("INVALID_FILE_TYPE", "Only ZIP files are accepted.");

        // Check concurrent session limits
        var userSessions = await GetActiveSessionCountForUserAsync(userName, cancellationToken);
        if (userSessions >= _appSettings.ChunkedUpload.MaxConcurrentUploadsPerUser)
        {
            return InitChunkedResult.Fail("TOO_MANY_USER_SESSIONS",
                $"Maximum concurrent uploads per user ({_appSettings.ChunkedUpload.MaxConcurrentUploadsPerUser}) exceeded. " +
                "Please complete or cancel existing uploads first.");
        }

        var globalSessions = await GetActiveSessionCountAsync(cancellationToken);
        if (globalSessions >= _appSettings.ChunkedUpload.MaxConcurrentUploadsGlobal)
        {
            return InitChunkedResult.Fail("TOO_MANY_GLOBAL_SESSIONS",
                $"Maximum concurrent system-wide uploads ({_appSettings.ChunkedUpload.MaxConcurrentUploadsGlobal}) exceeded. " +
                "Please try again later.");
        }

        // Check disk space (need space for chunks + assembled file)
        var requiredSpace = request.FileSize * 2 + _appSettings.UploadLimits.MinFreeDiskSpaceBytes;
        if (!_diskSpaceService.HasSufficientSpace(_storageSettings.ImportBasePath, requiredSpace))
        {
            var freeSpace = _diskSpaceService.GetFreeSpace(_storageSettings.ImportBasePath);
            return InitChunkedResult.Fail("INSUFFICIENT_DISK_SPACE",
                $"Not enough disk space. Required: {requiredSpace / (1024 * 1024 * 1024.0):F1} GB, " +
                $"Available: {freeSpace / (1024 * 1024 * 1024.0):F1} GB");
        }

        // Create session
        var uploadId = Guid.NewGuid();
        var chunkDir = GetChunkDirectory(uploadId);
        Directory.CreateDirectory(chunkDir);

        var session = new ChunkUploadSession
        {
            UploadId = uploadId,
            FileName = request.FileName,
            FileSize = request.FileSize,
            TotalChunks = request.TotalChunks,
            ChunkSize = request.ChunkSize,
            ContentHash = request.ContentHash,
            AutoProcessingOverride = request.AutoProcessingOverride,
            CreatedAt = DateTime.UtcNow,
            ExpiresAt = DateTime.UtcNow.AddHours(_appSettings.ChunkedUpload.SessionExpirationHours),
            LastActivityAt = DateTime.UtcNow,
            UploadedBy = userName,
            SourceIp = sourceIp
        };

        await SaveSessionAsync(session, cancellationToken);

        _logger.LogInformation(
            "Initialized chunked upload: UploadId={UploadId}, FileName={FileName}, " +
            "FileSize={FileSize} ({FileSizeMB:F1} MB), TotalChunks={TotalChunks}, User={User}",
            uploadId, request.FileName, request.FileSize,
            request.FileSize / (1024.0 * 1024.0), request.TotalChunks, userName);

        return InitChunkedResult.Succeed(uploadId, session.ExpiresAt);
    }

    /// <inheritdoc/>
    public async Task<UploadChunkResult> ReceiveChunkAsync(
        Guid uploadId,
        int chunkIndex,
        Stream chunkData,
        CancellationToken cancellationToken)
    {
        // First, validate session exists and is valid (quick check outside the lock)
        var sessionCheck = await LoadSessionAsync(uploadId, cancellationToken);
        if (sessionCheck == null)
            return UploadChunkResult.Fail("SESSION_NOT_FOUND", "Upload session not found or expired.");

        if (sessionCheck.IsExpired)
        {
            CleanupSession(uploadId);
            ReleaseSessionLock(uploadId);
            return UploadChunkResult.Fail("SESSION_EXPIRED", "Upload session has expired. Please start a new upload.");
        }

        if (chunkIndex < 0 || chunkIndex >= sessionCheck.TotalChunks)
            return UploadChunkResult.Fail("INVALID_CHUNK_INDEX",
                $"Chunk index {chunkIndex} is out of range (0-{sessionCheck.TotalChunks - 1}).");

        // Save chunk to disk (this can happen concurrently since each chunk has its own file)
        var chunkPath = GetChunkPath(uploadId, chunkIndex);
        long bytesReceived;

        try
        {
            await using (var fileStream = new FileStream(
                chunkPath,
                FileMode.Create,
                FileAccess.Write,
                FileShare.None,
                81920,
                FileOptions.Asynchronous))
            {
                await chunkData.CopyToAsync(fileStream, cancellationToken);
                bytesReceived = fileStream.Length;
            }
        }
        catch (IOException ex)
        {
            _logger.LogError(ex, "Failed to write chunk {ChunkIndex} for upload {UploadId}", chunkIndex, uploadId);
            return UploadChunkResult.Fail("CHUNK_WRITE_FAILED", "Failed to save chunk to disk.");
        }

        // Update session metadata under lock to prevent race conditions with concurrent chunk uploads
        var sessionLock = GetSessionLock(uploadId);
        int receivedCount;
        int totalChunks;
        double percentComplete;

        await sessionLock.WaitAsync(cancellationToken);
        try
        {
            // Re-load session inside the lock to get the current state
            var session = await LoadSessionAsync(uploadId, cancellationToken);
            if (session == null)
            {
                // Session was deleted while we were waiting
                return UploadChunkResult.Fail("SESSION_NOT_FOUND", "Upload session not found or expired.");
            }

            // Add chunk index if not already present (handles retries)
            if (!session.ReceivedChunks.Contains(chunkIndex))
            {
                session.ReceivedChunks.Add(chunkIndex);
            }
            session.LastActivityAt = DateTime.UtcNow;
            await SaveSessionAsync(session, cancellationToken);

            receivedCount = session.ReceivedChunks.Count;
            totalChunks = session.TotalChunks;
            percentComplete = session.PercentComplete;
        }
        finally
        {
            sessionLock.Release();
        }

        if (_appSettings.Logging.EnableUploadDiagnostics)
        {
            _logger.LogInformation(
                "[UPLOAD-DIAG] Chunk received: UploadId={UploadId}, ChunkIndex={ChunkIndex}/{TotalChunks}, " +
                "BytesReceived={Bytes}, Progress={Percent:F1}%",
                uploadId, chunkIndex + 1, totalChunks, bytesReceived, percentComplete);
        }

        return UploadChunkResult.Succeed(
            uploadId,
            chunkIndex,
            bytesReceived,
            receivedCount,
            totalChunks);
    }

    /// <inheritdoc/>
    public async Task<ChunkStatusResult> GetStatusAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var session = await LoadSessionAsync(uploadId, cancellationToken);
        if (session == null)
            return ChunkStatusResult.Fail("SESSION_NOT_FOUND", "Upload session not found.");

        return new ChunkStatusResult
        {
            Success = true,
            UploadId = session.UploadId,
            FileName = session.FileName,
            FileSize = session.FileSize,
            TotalChunks = session.TotalChunks,
            ReceivedChunks = session.ReceivedChunks.OrderBy(c => c).ToList(),
            MissingChunks = session.MissingChunks.ToList(),
            PercentComplete = session.PercentComplete,
            CreatedAt = session.CreatedAt,
            ExpiresAt = session.ExpiresAt,
            CanResume = !session.IsExpired
        };
    }

    /// <inheritdoc/>
    public async Task<FinalizeChunkedResult> FinalizeAsync(
        Guid uploadId,
        bool verifyHash,
        CancellationToken cancellationToken)
    {
        var session = await LoadSessionAsync(uploadId, cancellationToken);
        if (session == null)
            return FinalizeChunkedResult.Fail("SESSION_NOT_FOUND", "Upload session not found.");

        if (session.IsExpired)
        {
            CleanupSession(uploadId);
            return FinalizeChunkedResult.Fail("SESSION_EXPIRED", "Upload session has expired.");
        }

        // Verify all chunks received
        if (!session.IsComplete)
        {
            var missing = session.MissingChunks.ToList();
            return FinalizeChunkedResult.Fail(
                "INCOMPLETE_UPLOAD",
                $"Upload is incomplete. Missing {missing.Count} chunks.",
                missing);
        }

        var chunkDir = GetChunkDirectory(uploadId);
        var finalPath = Path.Combine(_storageSettings.GetUploadPath(), $"{uploadId}.zip");

        _logger.LogInformation(
            "Assembling chunked upload: UploadId={UploadId}, TotalChunks={TotalChunks}, FileName={FileName}",
            uploadId, session.TotalChunks, session.FileName);

        // Assemble chunks into final file
        long assembledSize = 0;
        try
        {
            await using (var finalStream = new FileStream(
                finalPath,
                FileMode.Create,
                FileAccess.Write,
                FileShare.None,
                81920,
                FileOptions.Asynchronous))
            {
                for (int i = 0; i < session.TotalChunks; i++)
                {
                    cancellationToken.ThrowIfCancellationRequested();

                    var chunkPath = GetChunkPath(uploadId, i);
                    if (!File.Exists(chunkPath))
                    {
                        _logger.LogError("Chunk file missing during assembly: {ChunkPath}", chunkPath);
                        return FinalizeChunkedResult.Fail("CHUNK_MISSING", $"Chunk {i} file is missing.", new List<int> { i });
                    }

                    await using var chunkStream = new FileStream(
                        chunkPath,
                        FileMode.Open,
                        FileAccess.Read,
                        FileShare.Read,
                        81920,
                        FileOptions.Asynchronous | FileOptions.SequentialScan);
                    await chunkStream.CopyToAsync(finalStream, cancellationToken);
                    assembledSize += chunkStream.Length;

                    if (_appSettings.Logging.EnableUploadDiagnostics && (i + 1) % 50 == 0)
                    {
                        _logger.LogInformation(
                            "[UPLOAD-DIAG] Assembly progress: UploadId={UploadId}, Chunks={Current}/{Total}, " +
                            "Assembled={AssembledMB:F1} MB",
                            uploadId, i + 1, session.TotalChunks, assembledSize / (1024.0 * 1024.0));
                    }
                }
            }

            _logger.LogInformation(
                "Chunked upload assembled: UploadId={UploadId}, AssembledSize={Size} ({SizeMB:F1} MB)",
                uploadId, assembledSize, assembledSize / (1024.0 * 1024.0));
        }
        catch (IOException ex)
        {
            _logger.LogError(ex, "Failed to assemble chunks for upload {UploadId}", uploadId);

            // Clean up partial assembly
            if (File.Exists(finalPath))
            {
                try { File.Delete(finalPath); }
                catch { /* Best effort */ }
            }

            return FinalizeChunkedResult.Fail("ASSEMBLY_FAILED", "Failed to assemble file from chunks.");
        }

        // Optional hash verification
        if (verifyHash && !string.IsNullOrEmpty(session.ContentHash))
        {
            try
            {
                using var sha256 = System.Security.Cryptography.SHA256.Create();
                await using var fileStream = File.OpenRead(finalPath);
                var hashBytes = await sha256.ComputeHashAsync(fileStream, cancellationToken);
                var computedHash = "sha256:" + Convert.ToHexString(hashBytes).ToLowerInvariant();

                if (!string.Equals(computedHash, session.ContentHash, StringComparison.OrdinalIgnoreCase))
                {
                    _logger.LogWarning(
                        "Hash mismatch for upload {UploadId}: Expected={Expected}, Computed={Computed}",
                        uploadId, session.ContentHash, computedHash);

                    // Clean up
                    File.Delete(finalPath);
                    return FinalizeChunkedResult.Fail("HASH_MISMATCH",
                        "File integrity check failed. The uploaded file may be corrupted.");
                }

                _logger.LogInformation("Hash verification passed for upload {UploadId}", uploadId);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during hash verification for upload {UploadId}", uploadId);
                // Continue without verification on error
            }
        }

        // Clean up chunk directory and release session lock
        try
        {
            Directory.Delete(chunkDir, recursive: true);
            _logger.LogDebug("Cleaned up chunk directory: {ChunkDir}", chunkDir);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to clean up chunk directory: {Path}", chunkDir);
        }
        ReleaseSessionLock(uploadId);

        // Continue with normal upload processing
        var result = await _uploadService.ProcessStreamedUploadAsync(
            uploadId,
            finalPath,
            session.FileName,
            assembledSize,
            session.UploadedBy,
            session.SourceIp,
            session.AutoProcessingOverride,
            cancellationToken);

        if (!result.Success)
        {
            return FinalizeChunkedResult.Fail(
                result.ErrorCode ?? "PROCESSING_ERROR",
                result.ErrorMessage ?? "Failed to process upload.");
        }

        return FinalizeChunkedResult.Succeed(uploadId, assembledSize, result.QueuePosition);
    }

    /// <inheritdoc/>
    public async Task<(bool Success, long BytesFreed)> CancelAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var session = await LoadSessionAsync(uploadId, cancellationToken);
        if (session == null)
            return (false, 0);

        var chunkDir = GetChunkDirectory(uploadId);
        long bytesFreed = 0;

        if (Directory.Exists(chunkDir))
        {
            bytesFreed = GetDirectorySize(chunkDir);
            try
            {
                Directory.Delete(chunkDir, recursive: true);
                ReleaseSessionLock(uploadId);
                _logger.LogInformation(
                    "Cancelled chunked upload: UploadId={UploadId}, User={User}, BytesFreed={Bytes}",
                    uploadId, session.UploadedBy, bytesFreed);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to clean up cancelled upload: {UploadId}", uploadId);
                return (false, 0);
            }
        }

        return (true, bytesFreed);
    }

    /// <inheritdoc/>
    public async Task<List<ActiveChunkedUpload>> GetActiveUploadsAsync(CancellationToken cancellationToken)
    {
        var uploads = new List<ActiveChunkedUpload>();
        var chunksBasePath = Path.Combine(_storageSettings.GetUploadPath(), "chunks");

        if (!Directory.Exists(chunksBasePath))
            return uploads;

        foreach (var sessionDir in Directory.GetDirectories(chunksBasePath))
        {
            cancellationToken.ThrowIfCancellationRequested();

            var metadataPath = Path.Combine(sessionDir, "metadata.json");
            if (!File.Exists(metadataPath))
                continue;

            try
            {
                var json = await File.ReadAllTextAsync(metadataPath, cancellationToken);
                var session = JsonSerializer.Deserialize<ChunkUploadSession>(json, JsonOptions);
                if (session != null && !session.IsExpired)
                {
                    uploads.Add(ActiveChunkedUpload.FromSession(session));
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error reading session metadata: {Path}", metadataPath);
            }
        }

        return uploads.OrderByDescending(u => u.CreatedAt).ToList();
    }

    /// <inheritdoc/>
    public async Task<int> GetActiveSessionCountForUserAsync(string userName, CancellationToken cancellationToken)
    {
        var uploads = await GetActiveUploadsAsync(cancellationToken);
        return uploads.Count(u => string.Equals(u.UploadedBy, userName, StringComparison.OrdinalIgnoreCase));
    }

    /// <inheritdoc/>
    public async Task<int> GetActiveSessionCountAsync(CancellationToken cancellationToken)
    {
        var uploads = await GetActiveUploadsAsync(cancellationToken);
        return uploads.Count;
    }

    /// <inheritdoc/>
    public async Task<(int SessionsCleaned, long BytesFreed)> CleanupExpiredSessionsAsync(CancellationToken cancellationToken)
    {
        var chunksBasePath = Path.Combine(_storageSettings.GetUploadPath(), "chunks");
        if (!Directory.Exists(chunksBasePath))
            return (0, 0);

        var expiredCount = 0;
        long freedBytes = 0;

        foreach (var sessionDir in Directory.GetDirectories(chunksBasePath))
        {
            cancellationToken.ThrowIfCancellationRequested();

            var metadataPath = Path.Combine(sessionDir, "metadata.json");
            Guid? uploadId = null;

            // Parse directory name as GUID for logging
            var dirName = Path.GetFileName(sessionDir);
            if (Guid.TryParse(dirName, out var parsedId))
                uploadId = parsedId;

            if (!File.Exists(metadataPath))
            {
                // No metadata, check directory age
                var dirInfo = new DirectoryInfo(sessionDir);
                if (dirInfo.CreationTimeUtc < DateTime.UtcNow.AddHours(-24))
                {
                    var size = GetDirectorySize(sessionDir);
                    try
                    {
                        Directory.Delete(sessionDir, recursive: true);
                        freedBytes += size;
                        expiredCount++;
                        _logger.LogInformation(
                            "Cleaned up orphaned chunk directory: {Path}, Age={Age}",
                            sessionDir, DateTime.UtcNow - dirInfo.CreationTimeUtc);
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
                    ReleaseSessionLock(session.UploadId);
                    freedBytes += size;
                    expiredCount++;

                    _logger.LogInformation(
                        "Cleaned up expired chunked upload: UploadId={UploadId}, User={User}, " +
                        "ExpiredAt={ExpiredAt}, BytesFreed={Bytes}",
                        session.UploadId, session.UploadedBy, session.ExpiresAt, size);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error checking chunked upload session: {Path}", sessionDir);
            }
        }

        if (expiredCount > 0)
        {
            _logger.LogInformation(
                "Chunked upload cleanup complete: Sessions={Count}, BytesFreed={Bytes} ({BytesMB:F1} MB)",
                expiredCount, freedBytes, freedBytes / (1024.0 * 1024.0));
        }

        return (expiredCount, freedBytes);
    }

    private async Task SaveSessionAsync(ChunkUploadSession session, CancellationToken cancellationToken)
    {
        var metadataPath = GetMetadataPath(session.UploadId);
        var json = JsonSerializer.Serialize(session, JsonOptions);
        await File.WriteAllTextAsync(metadataPath, json, cancellationToken);
    }

    private async Task<ChunkUploadSession?> LoadSessionAsync(Guid uploadId, CancellationToken cancellationToken)
    {
        var metadataPath = GetMetadataPath(uploadId);
        if (!File.Exists(metadataPath))
            return null;

        try
        {
            var json = await File.ReadAllTextAsync(metadataPath, cancellationToken);
            return JsonSerializer.Deserialize<ChunkUploadSession>(json, JsonOptions);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to load session metadata: {Path}", metadataPath);
            return null;
        }
    }

    private void CleanupSession(Guid uploadId)
    {
        var chunkDir = GetChunkDirectory(uploadId);
        if (Directory.Exists(chunkDir))
        {
            try
            {
                Directory.Delete(chunkDir, recursive: true);
                ReleaseSessionLock(uploadId);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to cleanup expired session: {UploadId}", uploadId);
            }
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
}
