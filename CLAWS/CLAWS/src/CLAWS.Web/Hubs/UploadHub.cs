using Microsoft.AspNetCore.SignalR;
using CLAWS.Jobs;

namespace CLAWS.Web.Hubs;

/// <summary>
/// SignalR hub for real-time upload progress updates.
/// </summary>
public class UploadHub : Hub
{
    private readonly ILogger<UploadHub> _logger;

    public UploadHub(ILogger<UploadHub> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Subscribe to updates for a specific upload.
    /// </summary>
    public async Task SubscribeToUpload(string uploadId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"upload-{uploadId}");
        _logger.LogDebug("Client {ConnectionId} subscribed to upload {UploadId}",
            Context.ConnectionId, uploadId);
    }

    /// <summary>
    /// Unsubscribe from updates for a specific upload.
    /// </summary>
    public async Task UnsubscribeFromUpload(string uploadId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"upload-{uploadId}");
        _logger.LogDebug("Client {ConnectionId} unsubscribed from upload {UploadId}",
            Context.ConnectionId, uploadId);
    }

    public override async Task OnConnectedAsync()
    {
        _logger.LogDebug("Client connected: {ConnectionId}", Context.ConnectionId);
        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        _logger.LogDebug("Client disconnected: {ConnectionId}", Context.ConnectionId);
        await base.OnDisconnectedAsync(exception);
    }
}

/// <summary>
/// Service for sending notifications via SignalR.
/// </summary>
public class SignalRHubNotifier : IHubNotifier
{
    private readonly IHubContext<UploadHub> _hubContext;
    private readonly ILogger<SignalRHubNotifier> _logger;

    public SignalRHubNotifier(IHubContext<UploadHub> hubContext, ILogger<SignalRHubNotifier> logger)
    {
        _hubContext = hubContext;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task SendProgressAsync(Guid uploadId, string phase, string currentTable, int percent, string message)
    {
        var groupName = $"upload-{uploadId}";

        try
        {
            await _hubContext.Clients.Group(groupName).SendAsync("ProgressUpdate", new
            {
                uploadId = uploadId.ToString(),
                phase,
                currentTable,
                percent,
                message,
                timestamp = DateTime.UtcNow
            });

            _logger.LogDebug("SignalR progress sent to group {Group}: {Phase} {Percent}% - {Message}",
                groupName, phase, percent, message);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to send SignalR progress update to group {Group}", groupName);
        }
    }
}
