using CLAWS.Core.Models;

namespace CLAWS.Web.Services;

/// <summary>
/// Service for handling chunked file uploads.
/// Allows large files to be uploaded in smaller chunks, bypassing IIS size limits.
/// </summary>
public interface IChunkedUploadService
{
    /// <summary>
    /// Initializes a new chunked upload session.
    /// </summary>
    /// <param name="request">The initialization request with file metadata.</param>
    /// <param name="userName">User initiating the upload.</param>
    /// <param name="sourceIp">Source IP address.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Result containing upload ID and session info.</returns>
    Task<InitChunkedResult> InitializeAsync(
        InitChunkedRequest request,
        string userName,
        string? sourceIp,
        CancellationToken cancellationToken);

    /// <summary>
    /// Receives and stores a single chunk.
    /// </summary>
    /// <param name="uploadId">The upload session ID.</param>
    /// <param name="chunkIndex">Zero-based chunk index.</param>
    /// <param name="chunkData">Stream containing chunk data.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Result indicating success and progress.</returns>
    Task<UploadChunkResult> ReceiveChunkAsync(
        Guid uploadId,
        int chunkIndex,
        Stream chunkData,
        CancellationToken cancellationToken);

    /// <summary>
    /// Gets the status of a chunked upload session (for resume support).
    /// </summary>
    /// <param name="uploadId">The upload session ID.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Status including received/missing chunks.</returns>
    Task<ChunkStatusResult> GetStatusAsync(Guid uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Finalizes the chunked upload by assembling chunks and queuing for processing.
    /// </summary>
    /// <param name="uploadId">The upload session ID.</param>
    /// <param name="verifyHash">Whether to verify SHA256 hash after assembly.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Result indicating success or failure.</returns>
    Task<FinalizeChunkedResult> FinalizeAsync(
        Guid uploadId,
        bool verifyHash,
        CancellationToken cancellationToken);

    /// <summary>
    /// Cancels a chunked upload and cleans up temporary files.
    /// </summary>
    /// <param name="uploadId">The upload session ID.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Number of bytes freed.</returns>
    Task<(bool Success, long BytesFreed)> CancelAsync(Guid uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets all active chunked upload sessions (for admin view).
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>List of active uploads.</returns>
    Task<List<ActiveChunkedUpload>> GetActiveUploadsAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Gets count of active sessions for a specific user.
    /// </summary>
    /// <param name="userName">Username to check.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Number of active sessions.</returns>
    Task<int> GetActiveSessionCountForUserAsync(string userName, CancellationToken cancellationToken);

    /// <summary>
    /// Gets total count of active sessions globally.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Number of active sessions.</returns>
    Task<int> GetActiveSessionCountAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Cleans up expired chunked upload sessions.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Number of sessions cleaned up and bytes freed.</returns>
    Task<(int SessionsCleaned, long BytesFreed)> CleanupExpiredSessionsAsync(CancellationToken cancellationToken);
}
