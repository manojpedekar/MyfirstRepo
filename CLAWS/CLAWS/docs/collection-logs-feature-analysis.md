# Collection Logs Feature Analysis

## Architecture Summary

### End-to-End Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                 DATA FLOW                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  UI Layer (Upload Details Page)                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  "Collection Logs" Button (per-inventory)                                 │   │
│  │  "All Logs" Button (under Actions panel)                                  │   │
│  │              │                                                            │   │
│  └──────────────┼────────────────────────────────────────────────────────────┘   │
│                 │                                                                │
│                 ▼                                                                │
│  API Layer (StatusController / New CollectionLogsController)                     │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  1. Receive request with UploadId + optional InventoryId                  │   │
│  │  2. Get Upload record → Check MergeStatus                                 │   │
│  │  3. Determine schema: fssimport OR fsapp                                  │   │
│  │  4. Build query with InventoryID filter                                   │   │
│  │  5. Execute with pagination, filtering, ordering                          │   │
│  │  6. Return CollectionLogViewModel                                         │   │
│  └──────────────┼────────────────────────────────────────────────────────────┘   │
│                 │                                                                │
│                 ▼                                                                │
│  Database Layer                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                                                                           │   │
│  │  ┌─────────────────────────┐     ┌─────────────────────────┐             │   │
│  │  │   MergeStatus !=        │     │   MergeStatus ==        │             │   │
│  │  │   "Merged"              │     │   "Merged"              │             │   │
│  │  │         │               │     │         │               │             │   │
│  │  │         ▼               │     │         ▼               │             │   │
│  │  │  [fssimport].[EventLog] │     │  [fsapp].[EventLog]     │             │   │
│  │  │  (Staging schema)       │     │  (Production schema)    │             │   │
│  │  └─────────────────────────┘     └─────────────────────────┘             │   │
│  │                                                                           │   │
│  │  Key Columns: InventoryID, Timestamp, Severity, Source, Message, Path    │   │
│  │                                                                           │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Database Analysis

### 1.1 EventLog Table Structure

Both `[fssimport].[EventLog]` and `[fsapp].[EventLog]` share the same schema:

| Column | Type | Description | Filterable |
|--------|------|-------------|------------|
| `EventID` | INT | Unique event identifier (IDENTITY in fsapp, plain INT in fssimport) | Primary Key |
| `InventoryID` | UNIQUEIDENTIFIER | **KEY FILTER** - Links to collection/inventory | Yes - Required |
| `Timestamp` | datetimeoffset(3) | When the event occurred | Yes - Range filter |
| `Severity` | VARCHAR(20) | Log level: ERROR, WARNING, INFO, SUCCESS | Yes - Dropdown |
| `Source` | NVARCHAR(100) | Component that generated the log | Yes |
| `Message` | NVARCHAR(MAX) | Log message content | Yes - Search |
| `Path` | NVARCHAR(4000) | File/folder path related to event | Yes - Search |
| `ErrorCode` | INT | Windows error code (if applicable) | Yes |
| `ThreadID` | INT | Thread that generated the event | No |
| `AdditionalData` | NVARCHAR(MAX) | JSON-formatted additional context | No |

**Source**: `database/MSSQL/002_create_tables.sql:501-519` and `database/MSSQL/006_create_import_staging_tables.sql:294-311`

### 1.2 Existing Indexes on EventLog

From `database/MSSQL/003_create_indexes.sql`:
- `IX_EventLog_InventoryID` - Critical for per-inventory filtering
- `IX_EventLog_Severity` - For severity filtering
- `IX_EventLog_Timestamp` - For time-range queries
- `IX_EventLog_Source` - For source filtering

**Performance Note**: These indexes exist only on `[fsapp].[EventLog]`. The `[fssimport]` schema has minimal indexing for fast bulk import. Consider adding temporary indexes during validation/review workflows.

### 1.3 Key Correlation Columns

| Purpose | Table | Key Columns |
|---------|-------|-------------|
| Upload → Inventories | `app.ImportStatistics` | `UploadId`, `InventoryId` |
| Inventory → Logs | `fssimport.EventLog` or `fsapp.EventLog` | `InventoryID` |
| Merge Status | `app.Uploads` | `MergeStatus` |

**Critical Relationship**:
```sql
-- Get InventoryIDs for an Upload
SELECT DISTINCT InventoryId
FROM app.ImportStatistics
WHERE UploadId = @UploadId;

-- Get logs for specific Inventory
SELECT * FROM [schema].EventLog
WHERE InventoryID = @InventoryId
ORDER BY Timestamp;
```

---

## 2. Merge Status Detection

### 2.1 Where Merge State is Determined

**File**: `src/NTFSPermsUploader.Data/Entities/Upload.cs:134-148`

```csharp
/// <summary>
/// Merge status: NotMerged, Merged, PartiallyMerged, Failed.
/// </summary>
[MaxLength(20)]
public string MergeStatus { get; set; } = "NotMerged";
```

**Valid MergeStatus Values**:
| Status | Description | Log Source |
|--------|-------------|------------|
| `"NotMerged"` | Data only in staging schema | `fssimport.EventLog` |
| `"InProgress"` | Migration currently running | `fssimport.EventLog` |
| `"Merged"` | All data migrated to production | `fsapp.EventLog` |
| `"PartiallyMerged"` | Some inventories migrated, some failed | **Mixed** - see below |
| `"Failed"` | Migration failed | `fssimport.EventLog` |

### 2.2 Schema Selection Logic

**Recommendation for API/Service Layer**:

```csharp
public async Task<string> GetEventLogSchemaAsync(Guid uploadId, Guid inventoryId)
{
    var upload = await _uploadRepository.GetByIdAsync(uploadId);

    if (upload.MergeStatus == "Merged")
    {
        // All data in fsapp - use production schema
        return "fsapp";
    }
    else if (upload.MergeStatus == "PartiallyMerged")
    {
        // Need to check if THIS specific inventory was merged
        // Check if data exists in fsapp.CollectionInfo for this InventoryID
        var existsInFsapp = await CheckInventoryInSchema("fsapp", inventoryId);
        return existsInFsapp ? "fsapp" : "fssimport";
    }
    else
    {
        // NotMerged, InProgress, or Failed - use staging schema
        return "fssimport";
    }
}
```

### 2.3 Migration Procedure Reference

**File**: `database/MSSQL/StoredProcedures/008_usp_MigrateCollection.sql`

The `usp_MigrateCollection` procedure:
1. Copies EventLog from `[fssimport].[EventLog]` to `[fsapp].[EventLog]` (lines 418-445)
2. Offsets EventIDs to avoid conflicts with migration log entries
3. Deletes from fssimport after successful migration (if CleanupImport=1)
4. Updates Upload.MergeStatus via the calling code in `MigrationService.cs`

---

## 3. Frontend Analysis

### 3.1 Upload Details Page Structure

**File**: `src/NTFSPermsUploader.Web/Views/Status/Details.cshtml`

**Current Layout**:
```
┌─────────────────────────────────────────────────────────────────┐
│  Upload Details (h1)                                            │
├───────────────────────────────────────┬─────────────────────────┤
│  col-md-8                             │  col-md-4               │
│  ┌─────────────────────────────────┐  │  ┌───────────────────┐  │
│  │ Card: Upload Info               │  │  │ Card: Actions     │  │
│  │ - Upload ID                     │  │  │ - Cancel          │  │
│  │ - Filename, Size                │  │  │ - Validate/Merge  │  │
│  │ - Import Status                 │  │  │ - Delete          │  │
│  │ - Progress (if processing)      │  │  │ - Back to List    │  │
│  │ - Timestamps                    │  │  │                   │  │
│  └─────────────────────────────────┘  │  │ ← ADD: All Logs   │  │
│                                       │  │        button here │  │
│  ┌─────────────────────────────────┐  │  └───────────────────┘  │
│  │ Card: Inventories (table)       │  │                         │
│  │ Computer | Path | Collected | # │  │                         │
│  │ ← ADD: Logs button per row      │  │                         │
│  └─────────────────────────────────┘  │                         │
│                                       │                         │
│  ┌─────────────────────────────────┐  │                         │
│  │ Card: Validation & Merge Status │  │                         │
│  └─────────────────────────────────┘  │                         │
└───────────────────────────────────────┴─────────────────────────┘
```

### 3.2 Inventory Table Location (lines 158-197)

The inventories table currently renders with columns: Computer, Scan Path, Collected, Records.

**Recommended Addition**:
```html
<!-- Add new column header -->
<th class="text-center" style="width: 100px;">Logs</th>

<!-- Add button in each row -->
<td class="text-center">
    <button type="button" class="btn btn-sm btn-outline-secondary"
            onclick="showCollectionLogs('@inv.InventoryId')"
            title="View collection logs for this inventory">
        <i class="bi bi-journal-text"></i>
    </button>
</td>
```

### 3.3 Actions Panel Location (lines 241-353)

The Actions card is in `col-md-4`. The "All Logs" button should be added after the existing action buttons but before the "Back to My Uploads" link.

**Recommended Position** (after line 348):
```html
<button type="button" class="btn btn-outline-info w-100 mb-2"
        onclick="showAllCollectionLogs('@Model.UploadId')">
    <i class="bi bi-journal-text"></i> View All Collection Logs
</button>
```

### 3.4 UI Pattern Recommendation: Modal Approach

**Rationale**:
- Consistent with web app patterns (no page navigation)
- Allows viewing logs without losing context
- Bootstrap 5 modals are already available in the layout
- Can implement pagination and filtering within the modal

**Alternative Considered**: Dedicated page
- Pros: More screen real estate, browser back button works
- Cons: Context loss, more navigation complexity
- **Recommendation**: Use modal for initial implementation, can add dedicated page later if needed

**Modal Structure**:
```html
<!-- Collection Logs Modal -->
<div class="modal fade modal-xl" id="collectionLogsModal" tabindex="-1">
    <div class="modal-dialog modal-dialog-scrollable">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title">
                    <i class="bi bi-journal-text"></i> Collection Logs
                </h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
                <!-- Filters -->
                <div class="row mb-3">
                    <div class="col-md-3">
                        <select class="form-select form-select-sm" id="severityFilter">
                            <option value="">All Severities</option>
                            <option value="ERROR">Error</option>
                            <option value="WARNING">Warning</option>
                            <option value="INFO">Info</option>
                        </select>
                    </div>
                    <div class="col-md-4">
                        <input type="text" class="form-control form-control-sm"
                               id="messageSearch" placeholder="Search messages...">
                    </div>
                </div>

                <!-- Logs Table -->
                <div id="logsTableContainer">
                    <!-- Loaded via AJAX -->
                </div>

                <!-- Pagination -->
                <nav id="logsPagination"></nav>
            </div>
        </div>
    </div>
</div>
```

---

## 4. Backend Analysis

### 4.1 Existing Related Controllers/Services

| Component | File | Purpose |
|-----------|------|---------|
| `StatusController` | `Controllers/StatusController.cs` | Upload details, validation, merge actions |
| `MigrationService` | `Services/MigrationService.cs` | `GetInventoryInfoAsync()`, merge operations |
| `IUploadRepository` | `Repositories/IUploadRepository.cs` | Upload CRUD operations |

### 4.2 Required New Endpoints

**Option A: Extend StatusController**
```csharp
// GET: /Status/{uploadId}/logs
// GET: /Status/{uploadId}/logs/{inventoryId}
```

**Option B: New CollectionLogsController** (Recommended)
```csharp
// GET: /CollectionLogs/{uploadId}              - All logs for upload
// GET: /CollectionLogs/{uploadId}/{inventoryId} - Logs for specific inventory
// Both return JSON for AJAX consumption
```

### 4.3 Proposed Service Interface

**File**: `Services/ICollectionLogService.cs`

```csharp
public interface ICollectionLogService
{
    /// <summary>
    /// Gets paginated collection logs for an upload (all inventories).
    /// </summary>
    Task<PagedResult<CollectionLogEntry>> GetLogsForUploadAsync(
        Guid uploadId,
        CollectionLogFilter filter,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets paginated collection logs for a specific inventory.
    /// </summary>
    Task<PagedResult<CollectionLogEntry>> GetLogsForInventoryAsync(
        Guid uploadId,
        Guid inventoryId,
        CollectionLogFilter filter,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default);
}

public class CollectionLogFilter
{
    public string? Severity { get; set; }         // ERROR, WARNING, INFO, etc.
    public string? MessageSearch { get; set; }     // Free text search
    public string? Source { get; set; }            // Filter by source
    public DateTime? FromDate { get; set; }        // Time range start
    public DateTime? ToDate { get; set; }          // Time range end
    public string SortBy { get; set; } = "Timestamp";
    public bool Descending { get; set; } = true;
}

public class CollectionLogEntry
{
    public int EventId { get; set; }
    public Guid InventoryId { get; set; }
    public DateTimeOffset Timestamp { get; set; }
    public string Severity { get; set; }
    public string Source { get; set; }
    public string Message { get; set; }
    public string? Path { get; set; }
    public int? ErrorCode { get; set; }
}
```

### 4.4 Schema Selection Implementation

```csharp
public class CollectionLogService : ICollectionLogService
{
    private async Task<string> DetermineSchemaAsync(
        Guid uploadId,
        Guid? inventoryId,
        CancellationToken cancellationToken)
    {
        var upload = await _uploadRepository.GetByIdAsync(uploadId, cancellationToken);
        if (upload == null)
            throw new NotFoundException($"Upload {uploadId} not found");

        // Simple case: Not merged or failed
        if (upload.MergeStatus != "Merged" && upload.MergeStatus != "PartiallyMerged")
            return "fssimport";

        // Simple case: Fully merged
        if (upload.MergeStatus == "Merged")
            return "fsapp";

        // Complex case: Partially merged - need to check specific inventory
        if (inventoryId.HasValue && upload.MergeStatus == "PartiallyMerged")
        {
            // Check if this specific inventory exists in fsapp
            var existsInFsapp = await CheckInventoryExistsInSchemaAsync(
                "fsapp", inventoryId.Value, cancellationToken);
            return existsInFsapp ? "fsapp" : "fssimport";
        }

        // Default to fssimport for safety
        return "fssimport";
    }
}
```

---

## 5. Authorization and Access Control

### 5.1 Current Authorization Pattern

From `StatusController.cs:74-79`:
```csharp
// Check if user owns this upload or is admin
var userName = User.Identity?.Name ?? "Unknown";
if (upload.UploadedBy != userName && !User.IsInRole(_appSettings.Authorization.AdminGroup ?? ""))
{
    return Forbid();
}
```

### 5.2 Recommendation for Collection Logs

Apply the same authorization pattern:
1. User can view logs for their own uploads
2. Admin group members can view all logs
3. Return 403 Forbidden if unauthorized

---

## 6. Performance Considerations

### 6.1 Expected Log Volumes

Based on CollectNTFSPerms behavior:
- **Small scan** (few thousand folders): 10-100 log entries
- **Medium scan** (100K folders): 100-1,000 log entries
- **Large scan** (1M+ folders): 1,000-10,000+ log entries
- **Most entries**: Access denied errors, timing information, skipped items

### 6.2 Safeguards Against Loading Excessive Data

1. **Mandatory Pagination**: Never return unbounded results
   - Default page size: 50
   - Maximum page size: 200
   - Return total count for pagination UI

2. **Query Optimization**:
   ```sql
   -- Use indexed columns in WHERE clause
   WHERE InventoryID = @InventoryId
     AND (@Severity IS NULL OR Severity = @Severity)
   ORDER BY Timestamp DESC
   OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY
   ```

3. **Client-Side Limits**:
   - Limit message display length in UI (truncate with "show more")
   - Lazy-load additional context (AdditionalData column)

4. **Response Size Control**:
   - Don't include AdditionalData in initial response
   - Fetch on demand when user expands a row

### 6.3 Index Recommendations for fssimport

For large datasets, consider adding temporary indexes during review:

```sql
-- Only if needed for specific upload review
CREATE INDEX IX_import_EventLog_InventoryID
ON [fssimport].[EventLog] (InventoryID)
INCLUDE (Timestamp, Severity, Source, Message);
```

---

## 7. Implementation Plan

### Phase 1: Backend Foundation

| Step | Task | Files to Create/Modify |
|------|------|----------------------|
| 1.1 | Create `CollectionLogEntry` model | `Models/CollectionLogModels.cs` |
| 1.2 | Create `ICollectionLogService` interface | `Services/ICollectionLogService.cs` |
| 1.3 | Implement `CollectionLogService` | `Services/CollectionLogService.cs` |
| 1.4 | Register service in DI | `Program.cs` |
| 1.5 | Create API controller | `Controllers/CollectionLogsController.cs` |
| 1.6 | Add authorization middleware | `Controllers/CollectionLogsController.cs` |

### Phase 2: Frontend Implementation

| Step | Task | Files to Modify |
|------|------|-----------------|
| 2.1 | Add modal HTML to Details page | `Views/Status/Details.cshtml` |
| 2.2 | Add "Logs" column to inventory table | `Views/Status/Details.cshtml` |
| 2.3 | Add "All Logs" button to Actions | `Views/Status/Details.cshtml` |
| 2.4 | Implement JavaScript for modal | `Views/Status/Details.cshtml` (Scripts section) |
| 2.5 | Add log table styling | `Views/Status/Details.cshtml` (Styles section) |

### Phase 3: Testing & Polish

| Step | Task |
|------|------|
| 3.1 | Test with small upload (< 100 logs) |
| 3.2 | Test with medium upload (1000+ logs) |
| 3.3 | Test merged vs non-merged scenarios |
| 3.4 | Test partial merge scenario |
| 3.5 | Test authorization (owner vs non-owner vs admin) |
| 3.6 | Performance testing with pagination |

---

## 8. Open Questions / Risks

### 8.1 Partial Merge Ambiguity

**Question**: How should we handle logs for a "PartiallyMerged" upload?

**Scenarios**:
1. User clicks "All Logs" - Which schema to query?
2. Some inventories in fsapp, some in fssimport

**Proposed Solution**:
- For "All Logs": Query both schemas and merge results
- For per-inventory: Check which schema contains that inventory
- Show indicator in UI: "Logs from staging" vs "Logs from production"

### 8.2 Migration-Added Events

**Question**: The migration procedure adds its own events to fsapp.EventLog. Should these be shown?

**Analysis**: `usp_MigrateCollection` logs SUCCESS, INFO, WARNING, ERROR events with source "usp_MigrateCollection" or "usp_LogMigrationEvent".

**Proposed Solution**:
- Show by default but allow filtering by Source
- Could add UI toggle: "Include migration events"

### 8.3 EventLog Cleanup Timing

**Question**: When is fssimport.EventLog data deleted?

**Answer**: During `usp_MigrateCollection` when `@CleanupImport = 1` (default). Data is deleted from fssimport after successful copy to fsapp.

**Risk**: If merge fails partway through, some EventLog data may be in both schemas.

**Mitigation**: Schema selection logic handles this by checking actual data presence.

### 8.4 Large Log Volume Edge Case

**Question**: What if a collection has 100,000+ log entries?

**Risk**: Query performance, UI responsiveness

**Mitigations**:
1. Always paginate (50 entries default)
2. Show total count in UI
3. Consider adding date range filter with reasonable defaults
4. Add loading indicator for slow queries

---

## 9. Optional Enhancements

### 9.1 Severity Filtering (Phase 1)

Already planned in base implementation:
- Dropdown filter: All / Error / Warning / Info / Success

### 9.2 Message/Path Search (Phase 1)

Already planned:
- Free text search box
- Search in Message and Path columns

### 9.3 Time Range Filtering (Phase 2)

Add date/time pickers:
- From/To date inputs
- Pre-sets: "Last hour", "Last 24h", "All"

### 9.4 Export to CSV (Phase 2)

Add export button:
- Export current filter results
- Include all columns
- Apply row limit (e.g., max 10,000 rows)

### 9.5 Correlation with Inventory Metadata (Phase 3)

Show context alongside logs:
- Inventory info: Computer, ScanPath, CollectionDateTime
- Collection statistics: FoldersProcessed, FoldersWithErrors
- Link: Jump to specific folder path in permission viewer (future)

### 9.6 Real-time Logs for In-Progress Imports (Phase 3)

For imports in progress:
- Show live log updates
- Use SignalR (already configured in app)
- Auto-refresh or streaming

---

## 10. ViewModels Reference

### 10.1 Existing Models (for reference)

**File**: `Models/ViewModels.cs:463-515`

```csharp
public class LogsViewModel          // app.Logs (application logs)
{
    public List<LogItem> Logs { get; set; }
    public int Page { get; set; }
    public int PageSize { get; set; }
    public int TotalItems { get; set; }
    public string? SeverityFilter { get; set; }
    public Guid? UploadIdFilter { get; set; }
}

public class LogItem                // app.Logs entry
{
    public long LogId { get; set; }
    public DateTime Timestamp { get; set; }
    public string SeverityName { get; set; }
    public string Hostname { get; set; }
    public string? MessageId { get; set; }
    public Guid? UploadId { get; set; }
    public string? Category { get; set; }
    public string Message { get; set; }
    public string? Exception { get; set; }
}
```

### 10.2 New Models Required

```csharp
public class CollectionLogsViewModel
{
    public Guid UploadId { get; set; }
    public Guid? InventoryId { get; set; }      // null = all inventories
    public string? InventoryLabel { get; set; } // "SERVER01 - C:\Data" or "All Inventories"
    public string DataSource { get; set; }      // "fssimport" or "fsapp"
    public bool IsMerged { get; set; }

    public List<CollectionLogItem> Logs { get; set; } = new();

    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 50;
    public int TotalItems { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalItems / (double)PageSize);

    // Filters
    public string? SeverityFilter { get; set; }
    public string? SourceFilter { get; set; }
    public string? SearchText { get; set; }
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
}

public class CollectionLogItem
{
    public int EventId { get; set; }
    public Guid InventoryId { get; set; }
    public DateTimeOffset Timestamp { get; set; }
    public string Severity { get; set; } = string.Empty;
    public string Source { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public string? Path { get; set; }
    public int? ErrorCode { get; set; }

    // UI helpers
    public string SeverityBadgeClass => Severity switch
    {
        "ERROR" => "bg-danger",
        "WARNING" => "bg-warning text-dark",
        "INFO" => "bg-info",
        "SUCCESS" => "bg-success",
        _ => "bg-secondary"
    };
}
```

---

## 11. Summary

This analysis provides a complete blueprint for implementing Collection Logs viewing functionality on the Upload Details page. The key design decisions are:

1. **Schema Selection**: Dynamically choose between `fssimport` and `fsapp` based on `Upload.MergeStatus`
2. **UI Pattern**: Modal-based viewing with pagination and filtering
3. **Performance**: Mandatory pagination with safeguards for large datasets
4. **Authorization**: Consistent with existing upload ownership checks

The implementation should be straightforward given the existing architecture and patterns in the codebase.

---

*Document created: 2025-12-27*
*Based on analysis of NTFSPermsUploader codebase*
