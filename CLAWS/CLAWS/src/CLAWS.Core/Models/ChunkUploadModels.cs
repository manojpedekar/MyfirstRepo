using System.Text.Json.Serialization;

namespace CLAWS.Core.Models;

/// <summary>
/// Request to initialize a chunked upload session.
/// </summary>
public class InitChunkedRequest
{
    /// <summary>
    /// Original file name.
    /// </summary>
    public string FileName { get; set; } = string.Empty;

    /// <summary>
    /// Total file size in bytes.
    /// </summary>
    public long FileSize { get; set; }

    /// <summary>
    /// Total number of chunks.
    /// </summary>
    public int TotalChunks { get; set; }

    /// <summary>
    /// Size of each chunk in bytes.
    /// </summary>
    public int ChunkSize { get; set; }

    /// <summary>
    /// Optional SHA256 hash of the complete file for verification.
    /// </summary>
    public string? ContentHash { get; set; }

    /// <summary>
    /// Optional auto-processing override (ValidateOnly, ValidateAndMerge, Manual).
    /// </summary>
    public string? AutoProcessingOverride { get; set; }
}

/// <summary>
/// Result of initializing a chunked upload session.
/// </summary>
public class InitChunkedResult
{
    public bool Success { get; set; }
    public Guid? UploadId { get; set; }
    public DateTime? ExpiresAt { get; set; }
    public string? ErrorCode { get; set; }
    public string? ErrorMessage { get; set; }

    public static InitChunkedResult Succeed(Guid uploadId, DateTime expiresAt) => new()
    {
        Success = true,
        UploadId = uploadId,
        ExpiresAt = expiresAt
    };

    public static InitChunkedResult Fail(string errorCode, string errorMessage) => new()
    {
        Success = false,
        ErrorCode = errorCode,
        ErrorMessage = errorMessage
    };
}

/// <summary>
/// Result of uploading a single chunk.
/// </summary>
public class UploadChunkResult
{
    public bool Success { get; set; }
    public Guid? UploadId { get; set; }
    public int ChunkIndex { get; set; }
    public long BytesReceived { get; set; }
    public int ChunksReceived { get; set; }
    public int TotalChunks { get; set; }
    public double PercentComplete { get; set; }
    public string? ErrorCode { get; set; }
    public string? ErrorMessage { get; set; }

    public static UploadChunkResult Succeed(Guid uploadId, int chunkIndex, long bytesReceived, int chunksReceived, int totalChunks) => new()
    {
        Success = true,
        UploadId = uploadId,
        ChunkIndex = chunkIndex,
        BytesReceived = bytesReceived,
        ChunksReceived = chunksReceived,
        TotalChunks = totalChunks,
        PercentComplete = totalChunks > 0 ? Math.Round(chunksReceived * 100.0 / totalChunks, 1) : 0
    };

    public static UploadChunkResult Fail(string errorCode, string errorMessage) => new()
    {
        Success = false,
        ErrorCode = errorCode,
        ErrorMessage = errorMessage
    };
}

/// <summary>
/// Result of getting chunk upload status (for resume support).
/// </summary>
public class ChunkStatusResult
{
    public bool Success { get; set; }
    public Guid? UploadId { get; set; }
    public string? FileName { get; set; }
    public long FileSize { get; set; }
    public int TotalChunks { get; set; }
    public List<int> ReceivedChunks { get; set; } = new();
    public List<int> MissingChunks { get; set; } = new();
    public double PercentComplete { get; set; }
    public DateTime? CreatedAt { get; set; }
    public DateTime? ExpiresAt { get; set; }
    public bool CanResume { get; set; }
    public string? ErrorCode { get; set; }
    public string? ErrorMessage { get; set; }

    public static ChunkStatusResult Fail(string errorCode, string errorMessage) => new()
    {
        Success = false,
        ErrorCode = errorCode,
        ErrorMessage = errorMessage
    };
}

/// <summary>
/// Request to finalize a chunked upload.
/// </summary>
public class FinalizeChunkedRequest
{
    /// <summary>
    /// Upload session ID.
    /// </summary>
    public Guid UploadId { get; set; }

    /// <summary>
    /// Whether to verify SHA256 hash after assembly.
    /// </summary>
    public bool VerifyHash { get; set; }
}

/// <summary>
/// Result of finalizing a chunked upload.
/// </summary>
public class FinalizeChunkedResult
{
    public bool Success { get; set; }
    public Guid? UploadId { get; set; }
    public long AssembledSize { get; set; }
    public int? QueuePosition { get; set; }
    public string? Message { get; set; }
    public string? ErrorCode { get; set; }
    public string? ErrorMessage { get; set; }
    public List<int>? MissingChunks { get; set; }

    public static FinalizeChunkedResult Succeed(Guid uploadId, long assembledSize, int? queuePosition) => new()
    {
        Success = true,
        UploadId = uploadId,
        AssembledSize = assembledSize,
        QueuePosition = queuePosition,
        Message = "File assembled successfully. Import queued."
    };

    public static FinalizeChunkedResult Fail(string errorCode, string errorMessage, List<int>? missingChunks = null) => new()
    {
        Success = false,
        ErrorCode = errorCode,
        ErrorMessage = errorMessage,
        MissingChunks = missingChunks
    };
}

/// <summary>
/// Chunked upload session state (persisted to metadata.json).
/// </summary>
public class ChunkUploadSession
{
    [JsonPropertyName("uploadId")]
    public Guid UploadId { get; set; }

    [JsonPropertyName("fileName")]
    public string FileName { get; set; } = string.Empty;

    [JsonPropertyName("fileSize")]
    public long FileSize { get; set; }

    [JsonPropertyName("totalChunks")]
    public int TotalChunks { get; set; }

    [JsonPropertyName("chunkSize")]
    public int ChunkSize { get; set; }

    [JsonPropertyName("contentHash")]
    public string? ContentHash { get; set; }

    [JsonPropertyName("autoProcessingOverride")]
    public string? AutoProcessingOverride { get; set; }

    [JsonPropertyName("receivedChunks")]
    public HashSet<int> ReceivedChunks { get; set; } = new();

    [JsonPropertyName("createdAt")]
    public DateTime CreatedAt { get; set; }

    [JsonPropertyName("expiresAt")]
    public DateTime ExpiresAt { get; set; }

    [JsonPropertyName("lastActivityAt")]
    public DateTime LastActivityAt { get; set; }

    [JsonPropertyName("uploadedBy")]
    public string UploadedBy { get; set; } = string.Empty;

    [JsonPropertyName("sourceIp")]
    public string? SourceIp { get; set; }

    /// <summary>
    /// Whether all chunks have been received.
    /// </summary>
    [JsonIgnore]
    public bool IsComplete => ReceivedChunks.Count == TotalChunks;

    /// <summary>
    /// Percentage of chunks received.
    /// </summary>
    [JsonIgnore]
    public double PercentComplete => TotalChunks > 0
        ? Math.Round(ReceivedChunks.Count * 100.0 / TotalChunks, 1)
        : 0;

    /// <summary>
    /// Chunk indices that haven't been received yet.
    /// </summary>
    [JsonIgnore]
    public IEnumerable<int> MissingChunks =>
        Enumerable.Range(0, TotalChunks).Except(ReceivedChunks);

    /// <summary>
    /// Time remaining until session expires.
    /// </summary>
    [JsonIgnore]
    public TimeSpan TimeUntilExpiration => ExpiresAt - DateTime.UtcNow;

    /// <summary>
    /// Whether the session is expired.
    /// </summary>
    [JsonIgnore]
    public bool IsExpired => DateTime.UtcNow >= ExpiresAt;
}

/// <summary>
/// Active chunked upload for admin display.
/// </summary>
public class ActiveChunkedUpload
{
    public Guid UploadId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public long FileSize { get; set; }
    public string UploadedBy { get; set; } = string.Empty;
    public string? SourceIp { get; set; }
    public int TotalChunks { get; set; }
    public int ReceivedChunks { get; set; }
    public double PercentComplete { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime LastActivityAt { get; set; }

    public TimeSpan TimeUntilExpiration => ExpiresAt - DateTime.UtcNow;
    public bool IsExpiringSoon => TimeUntilExpiration.TotalMinutes < 30;
    public bool IsStalled => (DateTime.UtcNow - LastActivityAt).TotalMinutes > 10;

    public static ActiveChunkedUpload FromSession(ChunkUploadSession session) => new()
    {
        UploadId = session.UploadId,
        FileName = session.FileName,
        FileSize = session.FileSize,
        UploadedBy = session.UploadedBy,
        SourceIp = session.SourceIp,
        TotalChunks = session.TotalChunks,
        ReceivedChunks = session.ReceivedChunks.Count,
        PercentComplete = session.PercentComplete,
        CreatedAt = session.CreatedAt,
        ExpiresAt = session.ExpiresAt,
        LastActivityAt = session.LastActivityAt
    };
}
