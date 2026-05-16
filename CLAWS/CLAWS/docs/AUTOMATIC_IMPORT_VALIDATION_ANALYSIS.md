# Automatic Import Validation & Merge Feature Analysis

## Executive Summary

This document provides a comprehensive architectural analysis for adding automatic validation and merge functionality to the NTFS Permissions Uploader. The feature will allow uploads to be automatically validated and optionally merged after initial processing completes, removing the need for manual intervention under controlled conditions.

---

## Table of Contents

1. [Current Architecture Overview](#1-current-architecture-overview)
2. [Upload Processing Flow Analysis](#2-upload-processing-flow-analysis)
3. [Frontend Analysis](#3-frontend-analysis)
4. [Backend Analysis](#4-backend-analysis)
5. [Database Analysis](#5-database-analysis)
6. [State & Error Handling Analysis](#6-state--error-handling-analysis)
7. [Implementation Plan](#7-implementation-plan)
8. [Open Questions & Risks](#8-open-questions--risks)
9. [Optional Enhancements](#9-optional-enhancements)

---

## 1. Current Architecture Overview

### Project Structure

```
NTFSPermsUploader/
├── src/
│   ├── NTFSPermsUploader.Web/          # Web layer
│   │   ├── Controllers/                 # MVC Controllers
│   │   ├── Views/Admin/Configuration.cshtml  # Configuration UI
│   │   ├── Services/                    # Business services
│   │   │   ├── MigrationService.cs      # Validation & merge logic
│   │   │   └── UploadService.cs         # Upload management
│   │   └── Models/ViewModels.cs         # View models
│   │
│   ├── NTFSPermsUploader.Core/          # Core business logic
│   │   ├── Configuration/AppSettings.cs # Application settings
│   │   ├── Validation/                  # Validation components
│   │   │   ├── ZipValidator.cs          # ZIP structure validation
│   │   │   └── DatabaseValidator.cs     # SQLite schema validation
│   │   └── Import/SqliteImporter.cs     # Data import logic
│   │
│   ├── NTFSPermsUploader.Data/          # Data access layer
│   │   ├── Entities/
│   │   │   ├── Configuration.cs         # Configuration entity
│   │   │   └── Upload.cs                # Upload entity
│   │   └── Repositories/                # Repository interfaces
│   │
│   └── NTFSPermsUploader.Jobs/          # Background jobs (Hangfire)
│       ├── UploadProcessingJob.cs       # Main processing job
│       └── ImportJob.cs                 # Import orchestration
└── sql/                                 # Database scripts
```

### Technology Stack

| Component | Technology |
|-----------|------------|
| Web Framework | ASP.NET Core 8.0 MVC |
| Background Jobs | Hangfire |
| Database | SQL Server |
| Frontend | Bootstrap 5, Vanilla JavaScript |
| Realtime Updates | Polling (SignalR-ready) |

---

## 2. Upload Processing Flow Analysis

### Current End-to-End Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                            CURRENT UPLOAD PROCESSING FLOW                            │
└─────────────────────────────────────────────────────────────────────────────────────┘

  ┌─────────────┐     ┌─────────────┐     ┌─────────────────────────────────────────┐
  │   Upload    │     │    Save     │     │         UploadProcessingJob             │
  │  Controller │ ──► │  ZIP File   │ ──► │  (Hangfire Background Job)              │
  │             │     │  + Record   │     │                                         │
  └─────────────┘     └─────────────┘     │  1. ZIP Validation (ZipValidator)       │
                                          │     - Is valid ZIP?                     │
                                          │     - Contains single SQLite DB?        │
                                          │     - Not a zip bomb?                   │
                                          │                                         │
                                          │  2. Database Validation (DatabaseValidator)│
                                          │     - Schema matches expected?          │
                                          │     - Version requirements met?         │
                                          │                                         │
                                          │  3. Import (SqliteImporter)             │
                                          │     - Extract to fssimport schema       │
                                          │     - Track progress                    │
                                          │     - Status: "Completed"               │
                                          └───────────────────────────────────────────┘
                                                              │
                                                              ▼
                        ┌────────────────────────────────────────────────────────────┐
                        │                    MANUAL USER ACTION                       │
                        │              (Status/Details.cshtml buttons)                │
                        │                                                            │
                        │   ┌──────────────────┐    ┌──────────────────┐             │
                        │   │  "Validate" Btn  │    │    "Merge" Btn   │             │
                        │   │                  │    │                  │             │
                        │   │  Calls:          │    │  Calls:          │             │
                        │   │  MigrationService│    │  MigrationService│             │
                        │   │  .ValidateAsync()│    │  .MigrateAsync() │             │
                        │   └────────┬─────────┘    └────────┬─────────┘             │
                        │            │                       │                        │
                        │            ▼                       ▼                        │
                        │   ┌──────────────────────────────────────────────┐         │
                        │   │       dbo.usp_ValidateImportData             │         │
                        │   │       dbo.usp_MigrateCollection              │         │
                        │   └──────────────────────────────────────────────┘         │
                        └────────────────────────────────────────────────────────────┘
                                                              │
                                                              ▼
                                               ┌──────────────────────────┐
                                               │  Data in fsapp schema    │
                                               │  (Production tables)     │
                                               └──────────────────────────┘
```

### Key Processing States (UploadStatus enum)

| Status | Description |
|--------|-------------|
| `Pending` | Queued, waiting for processing |
| `Processing` | ZIP validation in progress |
| `Validating` | Database schema validation |
| `Importing` | Data being imported to fssimport |
| `Completed` | Import finished, awaiting manual validation/merge |
| `Failed` | Processing failed |
| `Cancelled` | User cancelled |

### Validation & Merge States (Upload entity)

| Field | Values | Description |
|-------|--------|-------------|
| `ValidationStatus` | `NotValidated`, `InProgress`, `Passed`, `Failed` | Data validation state |
| `MergeStatus` | `NotMerged`, `InProgress`, `Merged`, `PartiallyMerged`, `Failed` | Merge to fsapp state |

---

## 3. Frontend Analysis

### Current Configuration UI

**File:** `src/NTFSPermsUploader.Web/Views/Admin/Configuration.cshtml`

The configuration page uses a card-based layout with collapsible sections. Relevant existing sections:

```
┌─────────────────────────────────────────┐
│  SQL Server Configuration               │  ← Database settings
├─────────────────────────────────────────┤
│  Database Performance                   │  ← Timeouts, batch sizes
├─────────────────────────────────────────┤
│  Upload Limits                          │  ← File size limits
├─────────────────────────────────────────┤
│  Import Settings                        │  ← TransactionMode, DuplicateHandling
├─────────────────────────────────────────┤
│  >>> NEW: Automatic Import Options <<<  │  ← TO BE ADDED
├─────────────────────────────────────────┤
│  Cleanup Settings                       │  ← Retention policies
├─────────────────────────────────────────┤
│  Version Requirements                   │  ← Min exe/db versions
└─────────────────────────────────────────┘
```

### Existing Import Settings ViewModel

**File:** `src/NTFSPermsUploader.Web/Models/ViewModels.cs:390-401`

```csharp
public class ImportSettingsConfigViewModel
{
    public string TransactionMode { get; set; } = "PerTable";
    public string DuplicateHandling { get; set; } = "Reject";
    // NEW FIELDS NEEDED:
    // public bool EnableAutomaticValidation { get; set; }
    // public bool EnableAutomaticMerge { get; set; }
}
```

### Proposed UI Changes

#### New Controls in Import Settings Section

```
┌─────────────────────────────────────────────────────────────────────────┐
│  IMPORT SETTINGS                                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Transaction Mode:  [PerTable ▼]                                       │
│  Duplicate Handling: [Reject ▼]                                        │
│                                                                         │
│  ─────────────── Automatic Processing ───────────────                  │
│                                                                         │
│  ☐ Enable Automatic Validation                                         │
│      Automatically validate imported data after upload processing      │
│      completes successfully.                                           │
│                                                                         │
│  ☐ Enable Automatic Merge                                              │
│      ⚠️ Warning: Enabling this will automatically migrate validated    │
│      data to production tables without manual review.                  │
│                                                                         │
│      Requires: Automatic Validation must be enabled                    │
│      Behavior: Merge only proceeds if validation passes                │
│                                                                         │
│  [Save Import Settings]                                                 │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### UX Safeguards Required

1. **Dependency Enforcement:**
   - When "Enable Automatic Merge" is checked, automatically check "Enable Automatic Validation"
   - When "Enable Automatic Validation" is unchecked, automatically uncheck "Enable Automatic Merge"
   - Disable the merge checkbox when validation is unchecked

2. **Warning Modal for Automatic Merge:**
   - Display a confirmation dialog when enabling automatic merge
   - Explain the implications: data will flow directly to production tables
   - Require explicit acknowledgment

3. **Visual Indicators:**
   - Show warning icon/styling when automatic merge is enabled
   - Display current setting status prominently in Status pages

---

## 4. Backend Analysis

### Current Validation & Merge Entry Points

**StatusController** (`src/NTFSPermsUploader.Web/Controllers/StatusController.cs`)

| Action | Line | Description |
|--------|------|-------------|
| `Validate(id)` | 147-188 | Manual validation trigger |
| `Merge(id)` | 190-231 | Manual merge trigger |
| `ValidateAndMerge(id)` | 233-274 | Combined validation + merge |

All actions call `IMigrationService` methods.

### MigrationService Methods

**File:** `src/NTFSPermsUploader.Web/Services/MigrationService.cs`

| Method | Description |
|--------|-------------|
| `ValidateAsync(uploadId)` | Calls `dbo.usp_ValidateImportData` for each inventory |
| `MigrateAsync(uploadId)` | Calls `dbo.usp_MigrateCollection` for each inventory |
| `ValidateAndMigrateAsync(uploadId)` | Runs validation, then merge if validation passes |

### Key Integration Point: UploadProcessingJob

**File:** `src/NTFSPermsUploader.Jobs/UploadProcessingJob.cs`

```csharp
public async Task ExecuteAsync(Guid uploadId, CancellationToken cancellationToken)
{
    // 1. Safety validation (ZIP, schema)
    // 2. Import to fssimport
    // 3. Update status to "Completed"

    // >>> PROPOSED INJECTION POINT <<<
    // 4. If AutoValidation enabled: Call ValidateAsync()
    // 5. If AutoMerge enabled AND validation passed: Call MigrateAsync()
}
```

### Proposed Backend Changes

#### 1. Add Settings to AppSettings

**File:** `src/NTFSPermsUploader.Core/Configuration/AppSettings.cs`

```csharp
public class ImportSettings
{
    public string TransactionMode { get; set; } = "PerTable";
    public string DuplicateHandling { get; set; } = "Reject";

    // NEW:
    public bool EnableAutomaticValidation { get; set; } = false;
    public bool EnableAutomaticMerge { get; set; } = false;
}
```

#### 2. Modify UploadProcessingJob

```csharp
// After successful import (status = Completed):
if (_importSettings.EnableAutomaticValidation)
{
    _logger.LogInformation("Auto-validation enabled, validating upload {UploadId}", uploadId);
    var validationResult = await _migrationService.ValidateAsync(uploadId, cancellationToken);

    if (_importSettings.EnableAutomaticMerge && validationResult.Success)
    {
        _logger.LogInformation("Auto-merge enabled, merging upload {UploadId}", uploadId);
        await _migrationService.MigrateAsync(uploadId, cancellationToken);
    }
    else if (_importSettings.EnableAutomaticMerge && !validationResult.Success)
    {
        _logger.LogWarning("Auto-merge skipped: validation failed for {UploadId}", uploadId);
        // Status already set to ValidationFailed by ValidateAsync
    }
}
```

#### 3. Configuration Repository Extensions

Add methods to read/write the new settings:
- `GetAutomaticValidationEnabledAsync()`
- `GetAutomaticMergeEnabledAsync()`
- `SetAutomaticValidationEnabledAsync(bool)`
- `SetAutomaticMergeEnabledAsync(bool)`

### Idempotency Considerations

| Scenario | Behavior |
|----------|----------|
| Re-running validation | Safe - stored proc is idempotent |
| Re-running merge | Safe - stored proc checks if already migrated (returns code 2) |
| Job retry after crash | Safe - states track progress, validation/merge won't duplicate |

---

## 5. Database Analysis

### Current Configuration Storage

**Table:** `app.Configuration`

**Entity:** `src/NTFSPermsUploader.Data/Entities/Configuration.cs`

```csharp
public class ConfigurationEntry
{
    public int Id { get; set; }
    public string Key { get; set; }   // e.g., "Import:TransactionMode"
    public string Value { get; set; } // e.g., "PerTable"
    public string? Description { get; set; }
    public DateTime ModifiedAt { get; set; }
    public string? ModifiedBy { get; set; }
}
```

### Proposed Schema Changes

**No schema changes required.** The existing `app.Configuration` table supports key-value storage.

New configuration keys to add:

| Key | Default Value | Description |
|-----|---------------|-------------|
| `Import:EnableAutomaticValidation` | `false` | Enable auto-validation |
| `Import:EnableAutomaticMerge` | `false` | Enable auto-merge |

### Configuration Key Naming Convention

Existing keys follow the pattern: `{Category}:{SettingName}`

Examples:
- `Import:TransactionMode`
- `Import:DuplicateHandling`
- `Cleanup:AutoPruneCompleted`
- `Performance:CommandTimeoutMinutes`

---

## 6. State & Error Handling Analysis

### Current Error Handling Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         ERROR HANDLING FLOW                              │
└──────────────────────────────────────────────────────────────────────────┘

  PROCESSING PHASE              ERROR RESPONSE
  ─────────────────             ─────────────────────────────────────
  ZIP Validation Failure   →    Upload.Status = "Failed"
                                Upload.StatusMessage = error details
                                File moved to /errors folder

  Schema Validation Fail   →    Upload.Status = "Failed"
                                Upload.StatusMessage = schema error

  Import Failure           →    Upload.Status = "Failed"
                                Partial data may exist in fssimport

  Manual Validation Fail   →    Upload.ValidationStatus = "Failed"
                                Upload.ValidationMessage = error count
                                Upload remains in "Completed" status

  Manual Merge Failure     →    Upload.MergeStatus = "Failed"
                                Upload.MergeMessage = error details
                                Upload remains in "Completed" status
```

### Proposed Error Handling for Automatic Processing

#### Automatic Validation Failure

```
IF automatic validation fails:
  - Upload.ValidationStatus = "Failed"
  - Upload.ValidationMessage = "Automatic validation found X error(s)"
  - Upload.Status remains "Completed"
  - Automatic merge does NOT proceed (enforced by code logic)
  - Log entry created: Category="Validation", Severity="WARNING"
  - User notification: Status page shows validation failure
```

#### Automatic Merge Failure

```
IF automatic merge fails (after successful validation):
  - Upload.MergeStatus = "Failed" or "PartiallyMerged"
  - Upload.MergeMessage = error details
  - Log entry created: Category="Import", Severity="ERROR"
  - Data may be partially in fsapp (PartiallyMerged case)
  - Manual intervention required to resolve
```

### Retry Considerations

| Phase | Retryable? | Strategy |
|-------|------------|----------|
| Automatic Validation | Yes | User can click "Validate" button manually |
| Automatic Merge | Yes | User can click "Merge" button manually |
| Job Failure | Yes | Hangfire automatic retry (configured) |

### Status Visibility

Users will see automatic processing status through:

1. **Status Index Page** - Shows ValidationStatus and MergeStatus columns
2. **Status Details Page** - Shows detailed status cards with messages
3. **Admin Logs Page** - Full audit trail of automatic processing
4. **Upload notifications** - If enabled, email/webhook on completion

---

## 7. Implementation Plan

### Phase 1: Database & Configuration Layer

| Step | Description | Files |
|------|-------------|-------|
| 1.1 | Add config keys to seed data | `sql/seed-configuration.sql` |
| 1.2 | Add properties to ImportSettings | `AppSettings.cs` |
| 1.3 | Add repository methods | `IConfigurationRepository.cs`, `ConfigurationRepository.cs` |
| 1.4 | Update startup configuration binding | `Program.cs` |

### Phase 2: UI Layer

| Step | Description | Files |
|------|-------------|-------|
| 2.1 | Add ViewModel properties | `ViewModels.cs` |
| 2.2 | Add UI controls to Configuration page | `Configuration.cshtml` |
| 2.3 | Add JavaScript for dependency enforcement | `Configuration.cshtml` (inline) |
| 2.4 | Add warning modal for merge enablement | `Configuration.cshtml` |
| 2.5 | Update AdminController save logic | `AdminController.cs` |

### Phase 3: Backend Processing Logic

| Step | Description | Files |
|------|-------------|-------|
| 3.1 | Inject settings into UploadProcessingJob | `UploadProcessingJob.cs` |
| 3.2 | Add automatic validation call after import | `UploadProcessingJob.cs` |
| 3.3 | Add automatic merge call after validation | `UploadProcessingJob.cs` |
| 3.4 | Add structured logging for auto-processing | `UploadProcessingJob.cs` |
| 3.5 | Unit tests for new logic | `Tests/` |

### Phase 4: Testing & Documentation

| Step | Description |
|------|-------------|
| 4.1 | Integration tests: auto-validation only |
| 4.2 | Integration tests: auto-validation + auto-merge |
| 4.3 | Integration tests: validation failure blocks merge |
| 4.4 | Update user documentation |
| 4.5 | Update admin guide |

### Dependency Graph

```
Phase 1 (Database) ──┬──► Phase 2 (UI)
                     │
                     └──► Phase 3 (Backend) ──► Phase 4 (Testing)
```

---

## 8. Open Questions & Risks

### Open Questions

| # | Question | Recommendation |
|---|----------|----------------|
| Q1 | Should automatic processing be logged to a separate audit table? | No - use existing logging infrastructure with Category="AutoProcess" |
| Q2 | Should we add email notifications for auto-validation/merge failures? | Optional - Phase 2 enhancement if notification system exists |
| Q3 | Should there be a delay between validation and merge? | No - immediate processing. Delay is a future enhancement. |
| Q4 | Should automatic merge be admin-only configurable? | Yes - already protected by admin role on Configuration page |

### Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Auto-merge pushes bad data to production | **HIGH** | Validation MUST pass first; merge stored proc has additional checks |
| Long-running auto-processing blocks job queue | MEDIUM | Use same timeout settings as manual processing; Hangfire handles queuing |
| User confusion about automatic vs manual states | MEDIUM | Clear status indicators; distinct logging messages |
| Settings changed mid-processing | LOW | Settings read at job start; changes apply to next upload |
| Database connection timeout during auto-processing | MEDIUM | Existing retry logic in MigrationService handles this |

### Safety Constraints (Non-Negotiable)

1. ❌ Automatic merge CANNOT be enabled without automatic validation
2. ❌ Merge CANNOT proceed if validation fails
3. ❌ Existing safety validations (ZIP, schema) CANNOT be bypassed
4. ❌ Auto-processing CANNOT run until initial processing completes successfully

---

## 9. Optional Enhancements

### Enhancement 1: Per-Upload Override (OPTIONAL)

Allow users to specify auto-processing behavior per upload, overriding global settings.

**UI Change:**
```
Upload Page:
  ☐ Override default auto-processing
    ○ Validate Only
    ○ Validate & Merge
    ○ Manual (no auto-processing)
```

**Database Change:**
```sql
ALTER TABLE app.Uploads ADD
    AutoProcessingOverride NVARCHAR(20) NULL;
    -- Values: NULL (use global), 'ValidateOnly', 'ValidateAndMerge', 'Manual'
```

**Complexity:** Medium
**Recommendation:** Defer to Phase 2

---

### Enhancement 2: Delayed Merge Scheduling (OPTIONAL)

Allow automatic merge to be delayed by a configurable time window, enabling review before merge.

**UI Change:**
```
Configuration Page:
  Auto-Merge Delay: [0] hours
    (0 = immediate, 1-72 = delay before merge)
```

**Backend Change:**
- Schedule merge as separate Hangfire job with delay
- Add `ScheduledMergeAt` column to Uploads table

**Complexity:** Medium-High
**Recommendation:** Defer to Phase 2

---

### Enhancement 3: Environment-Specific Defaults (OPTIONAL)

Different default settings for dev/staging/production environments.

**Implementation:**
- Use `appsettings.{Environment}.json` for defaults
- Database settings override file-based defaults

**Complexity:** Low
**Recommendation:** Consider for Phase 1 if environments differ significantly

---

### Enhancement 4: Webhook/Notification on Auto-Process Completion (OPTIONAL)

Send notifications when automatic processing completes or fails.

**Implementation:**
- Add webhook URL configuration setting
- Add notification service
- Call notification after auto-processing completes

**Complexity:** Medium
**Recommendation:** Defer to Phase 2

---

## Appendix A: Key File References

| File | Purpose |
|------|---------|
| `src/NTFSPermsUploader.Web/Views/Admin/Configuration.cshtml` | Configuration UI |
| `src/NTFSPermsUploader.Web/Controllers/AdminController.cs` | Configuration save logic |
| `src/NTFSPermsUploader.Web/Models/ViewModels.cs` | View models including ImportSettingsConfigViewModel |
| `src/NTFSPermsUploader.Core/Configuration/AppSettings.cs` | Application settings classes |
| `src/NTFSPermsUploader.Data/Entities/Configuration.cs` | Configuration entity |
| `src/NTFSPermsUploader.Data/Repositories/IConfigurationRepository.cs` | Configuration repository interface |
| `src/NTFSPermsUploader.Jobs/UploadProcessingJob.cs` | Main processing job |
| `src/NTFSPermsUploader.Web/Services/MigrationService.cs` | Validation & merge logic |
| `src/NTFSPermsUploader.Web/Controllers/StatusController.cs` | Manual validation/merge endpoints |

---

## Appendix B: Current Configuration Keys

Reference of existing configuration key patterns:

```
Import:TransactionMode = "PerTable"
Import:DuplicateHandling = "Reject"
Cleanup:AutoPruneCompleted = "true"
Cleanup:CompletedRetentionDays = "7"
Cleanup:ErrorRetentionDays = "0"
Cleanup:ExtractionRetentionDays = "7"
Performance:CommandTimeoutMinutes = "30"
Performance:ConnectionTimeoutSeconds = "30"
Performance:ImportBatchSize = "10000"
Performance:MaxConcurrentExtractions = "2"
DiskSpace:WarningThresholdPercent = "20"
DiskSpace:CriticalThresholdPercent = "10"
```

---

*Document Version: 1.0*
*Analysis Date: 2025-12-28*
*Author: Claude (Automated Analysis)*
