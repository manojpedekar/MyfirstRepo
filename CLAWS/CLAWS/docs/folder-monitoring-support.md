# Folder Monitoring Support for File Uploads

## Overview

This document analyzes the requirements and proposes solutions for supporting folder-based file uploads via SMB share or local folder monitoring. This would allow users to drop ZIP files directly into a monitored folder instead of using the web UI or REST API.

## Use Case

Users need to upload large ZIP files containing SQLite databases. Currently:
- **Web UI**: Requires browser session, subject to session timeouts for large files
- **REST API**: Requires API key management, programmatic integration

**Proposed addition**: A monitored folder (e.g., SMB share) where users can:
1. Copy/move a ZIP file to the folder
2. The system automatically detects and processes the file
3. Results are logged and optionally sent via notification

## Key Challenges

### 1. File Completion Detection
When a large file is copied over SMB, it takes time to transfer. The system must wait until the file is completely written before processing.

**Indicators a file is still being written:**
- File handle is open by another process
- File size is changing
- Last write time is recent

### 2. User Identification
SMB uploads have no inherent user context like web requests do. Options:
- Use file owner from NTFS security descriptor
- Require files in user-named subfolders (`/SMB/jsmith/file.zip`)
- Use a metadata file alongside the ZIP (`file.zip.meta`)
- Default to "FolderMonitor" or similar generic user

### 3. Error Handling
Unlike web uploads, there's no immediate response channel:
- Move failed files to an "Errors" subfolder
- Create `.error` files with failure details
- Optional: Email notification, SignalR broadcast, or webhook

### 4. Duplicate Prevention
Prevent reprocessing the same file:
- Track processed files by name+size+date
- Rename/move files after processing begins
- Use a database table to track processed files

---

## Proposed Solutions

### Option A: Scheduled Polling with Hangfire (Recommended)

**Description**: A recurring Hangfire job polls the folder at regular intervals, checks for new ZIP files, and queues them for import.

**Pros:**
- Consistent with existing job patterns (CleanupJob, DiskMonitorJob)
- Simple to implement and debug
- Works reliably with SMB/network shares
- No issues with FileSystemWatcher limitations on network paths
- Easy to configure polling interval

**Cons:**
- Not real-time (latency depends on poll interval)
- Slightly less efficient (periodic checks even when no files)

**Implementation Outline:**

```csharp
public interface IFolderMonitorJob
{
    [JobDisplayName("Monitor: Upload Folder")]
    Task ScanForUploadsAsync(CancellationToken cancellationToken);
}

public class FolderMonitorJob : IFolderMonitorJob
{
    public async Task ScanForUploadsAsync(CancellationToken cancellationToken)
    {
        var watchPath = _settings.WatchFolderPath;
        if (string.IsNullOrEmpty(watchPath) || !Directory.Exists(watchPath))
            return;

        foreach (var file in Directory.GetFiles(watchPath, "*.zip"))
        {
            if (await IsFileCompleteAsync(file))
            {
                await ProcessDroppedFileAsync(file, cancellationToken);
            }
        }
    }

    private async Task<bool> IsFileCompleteAsync(string filePath)
    {
        var fileInfo = new FileInfo(filePath);

        // Check 1: File hasn't been modified in X seconds
        if (DateTime.UtcNow - fileInfo.LastWriteTimeUtc < TimeSpan.FromSeconds(30))
            return false;

        // Check 2: Try to open file exclusively
        try
        {
            using var stream = File.Open(filePath, FileMode.Open,
                FileAccess.Read, FileShare.None);
            return true;
        }
        catch (IOException)
        {
            return false; // File still in use
        }
    }
}
```

**Configuration:**

```json
{
  "AppSettings": {
    "FolderMonitor": {
      "Enabled": true,
      "WatchPath": "T:\\ImportShare\\Incoming",
      "ProcessedPath": "T:\\ImportShare\\Processing",
      "ErrorPath": "T:\\ImportShare\\Errors",
      "PollIntervalSeconds": 60,
      "FileStabilitySeconds": 30,
      "DefaultUserName": "FolderMonitor"
    }
  }
}
```

---

### Option B: FileSystemWatcher with Delayed Processing

**Description**: Use .NET's `FileSystemWatcher` to detect new files immediately, then delay processing until the file is stable.

**Pros:**
- Near real-time detection
- Event-driven (no polling overhead)

**Cons:**
- FileSystemWatcher has known issues:
  - Doesn't work reliably on network shares/SMB
  - Can miss events under high load
  - Buffer overflow can cause missed notifications
- Requires a hosted service running continuously
- More complex error recovery

**Implementation Outline:**

```csharp
public class FolderWatcherService : BackgroundService
{
    private FileSystemWatcher? _watcher;
    private readonly ConcurrentDictionary<string, DateTime> _pendingFiles = new();

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _watcher = new FileSystemWatcher(_settings.WatchPath, "*.zip")
        {
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite,
            EnableRaisingEvents = true
        };

        _watcher.Created += OnFileCreated;
        _watcher.Changed += OnFileChanged;

        // Process pending files periodically
        while (!stoppingToken.IsCancellationRequested)
        {
            await ProcessStableFilesAsync(stoppingToken);
            await Task.Delay(5000, stoppingToken);
        }
    }

    private void OnFileCreated(object sender, FileSystemEventArgs e)
    {
        _pendingFiles[e.FullPath] = DateTime.UtcNow;
    }

    private async Task ProcessStableFilesAsync(CancellationToken ct)
    {
        var stableTime = DateTime.UtcNow.AddSeconds(-30);
        var stableFiles = _pendingFiles
            .Where(kvp => kvp.Value < stableTime)
            .Select(kvp => kvp.Key)
            .ToList();

        foreach (var file in stableFiles)
        {
            if (_pendingFiles.TryRemove(file, out _))
            {
                await ProcessDroppedFileAsync(file, ct);
            }
        }
    }
}
```

---

### Option C: Hybrid Approach (Recommended for SMB)

**Description**: Use FileSystemWatcher for local folders with Hangfire polling as fallback/primary for network shares.

**Implementation:**
- Detect if path is local or network (UNC path)
- Use appropriate strategy based on path type
- Hangfire job acts as a "safety net" to catch any missed files

---

## Recommended Architecture

### File Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│  SMB Share: \\server\NTFSUploads                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  /Incoming/          User drops files here                         │
│     ├── collection1.zip                                             │
│     └── collection2.zip                                             │
│                                                                     │
│  /Processing/        Files being processed (prevents re-pickup)     │
│     └── {guid}_collection1.zip                                      │
│                                                                     │
│  /Completed/         Successfully imported files                    │
│     └── 2024-01-15_collection1.zip                                  │
│                                                                     │
│  /Errors/            Failed files with error details                │
│     ├── collection2.zip                                             │
│     └── collection2.zip.error   (error details)                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Processing Flow

```
1. FolderMonitorJob runs on schedule (every 60 seconds)
         │
         ▼
2. Scan /Incoming for *.zip files
         │
         ▼
3. For each file, check if stable:
   - LastWriteTime > 30 seconds ago
   - Can open file exclusively
         │
         ▼
4. If stable, move to /Processing/{guid}_{filename}
         │
         ▼
5. Create Upload record in database
   - Status: "ReceivedFromFolder"
   - UploadedBy: File owner or default
         │
         ▼
6. Call ProcessStreamedUploadAsync()
   (reuses existing validation/import logic)
         │
         ├─── Success ───▶ Move to /Completed
         │                  Delete from /Processing
         │
         └─── Failure ───▶ Move to /Errors
                           Create .error file with details
```

---

## Database Changes

### New Configuration Fields

Add to `StorageSettings` or create new `FolderMonitorSettings`:

| Field | Type | Description |
|-------|------|-------------|
| `FolderMonitorEnabled` | bool | Enable/disable folder monitoring |
| `WatchPath` | string | Path to monitor for incoming files |
| `ProcessingPath` | string | Temp location during processing |
| `FileStabilitySeconds` | int | Seconds to wait after last write |
| `PollIntervalSeconds` | int | How often to scan (for scheduled approach) |
| `DefaultUserName` | string | Username for files without owner info |
| `MoveToCompleted` | bool | Whether to move processed files |
| `MoveToErrors` | bool | Whether to move failed files |

### Tracking Table (Optional)

To prevent reprocessing and provide audit trail:

```sql
CREATE TABLE app.FolderMonitorHistory (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    FileName NVARCHAR(500) NOT NULL,
    FilePath NVARCHAR(1000) NOT NULL,
    FileSizeBytes BIGINT NOT NULL,
    FileModifiedUtc DATETIME2 NOT NULL,
    DetectedAtUtc DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    ProcessedAtUtc DATETIME2 NULL,
    UploadId UNIQUEIDENTIFIER NULL,
    Status NVARCHAR(50) NOT NULL, -- Detected, Processing, Completed, Failed, Skipped
    ErrorMessage NVARCHAR(MAX) NULL,

    INDEX IX_FolderMonitorHistory_Status (Status),
    INDEX IX_FolderMonitorHistory_FileName (FileName)
);
```

---

## Implementation Checklist

### Phase 1: Core Infrastructure
- [ ] Create `FolderMonitorSettings` configuration class
- [ ] Add settings to `appsettings.json` schema
- [ ] Create `IFolderMonitorJob` interface
- [ ] Implement `FolderMonitorJob` with file stability detection
- [ ] Register job in `Program.cs`
- [ ] Add recurring job schedule

### Phase 2: File Processing
- [ ] Implement file move to Processing folder
- [ ] Extract file owner from NTFS security descriptor (optional)
- [ ] Integrate with `ProcessStreamedUploadAsync()`
- [ ] Implement post-processing file moves (Completed/Errors)
- [ ] Create `.error` files with failure details

### Phase 3: UI & Monitoring
- [ ] Add folder monitor status to admin dashboard
- [ ] Show recent folder uploads in status page
- [ ] Add Hangfire dashboard job visibility
- [ ] Implement email/webhook notifications (optional)

### Phase 4: Testing & Documentation
- [ ] Unit tests for file stability detection
- [ ] Integration tests with mock file system
- [ ] Test with actual SMB share
- [ ] Performance testing with large files
- [ ] Update user documentation

---

## Security Considerations

1. **Path Validation**: Ensure watch path doesn't allow directory traversal
2. **File Type Validation**: Only process `.zip` files, validate ZIP structure
3. **Permissions**: Service account needs read/write/delete on watch folders
4. **Audit Trail**: Log all file operations for compliance
5. **Quota/Rate Limiting**: Consider limits on files per hour to prevent abuse

---

## Estimated Effort

| Phase | Effort |
|-------|--------|
| Phase 1: Core Infrastructure | 4-6 hours |
| Phase 2: File Processing | 4-6 hours |
| Phase 3: UI & Monitoring | 2-4 hours |
| Phase 4: Testing & Documentation | 4-6 hours |
| **Total** | **14-22 hours** |

---

## Recommendation

**Use Option A (Scheduled Polling with Hangfire)** for the following reasons:

1. **Reliability**: Works consistently with both local and network paths
2. **Simplicity**: Follows existing patterns in the codebase
3. **Debuggability**: Easy to troubleshoot via Hangfire dashboard
4. **Resilience**: Job retries handle transient failures
5. **No additional dependencies**: Uses existing Hangfire infrastructure

The 60-second polling interval is acceptable for most use cases. For more time-sensitive requirements, reduce to 30 seconds or implement the hybrid approach with FileSystemWatcher for local paths.
