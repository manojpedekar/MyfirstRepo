# API Changes for ADInventory Support

## Overview

This document outlines the API changes required to support ADInventory database uploads in the NTFSPermsUploader.

**Key Finding**: The current API design allows for **backward compatible** changes. Existing clients will continue to work without modification.

---

## Current API Endpoints

### REST API (`/api/v1/`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/health` | Health check (no auth) |
| `GET` | `/api/v1/health/ready` | Readiness check (no auth) |
| `POST` | `/api/v1/upload` | Upload a ZIP file |
| `GET` | `/api/v1/upload/{uploadId}/status` | Get upload status |
| `GET` | `/api/v1/upload/{uploadId}/logs` | Get upload logs |
| `DELETE` | `/api/v1/upload/{uploadId}` | Cancel/delete upload |
| `GET` | `/api/v1/uploads` | List uploads (paginated) |

### Web UI Endpoints

| Controller | Purpose |
|------------|---------|
| `UploadController` | Web form uploads |
| `StatusController` | View upload status, validate, merge |
| `AdminController` | Administration functions |

---

## Breaking Changes

**None.** All changes are additive.

The upload type detection occurs **after** the file is uploaded and extracted, so existing clients don't need to specify the type upfront. The system auto-detects based on database schema.

---

## Required Response Model Changes

### 1. `UploadResponseData`

**File**: `NTFSPermsUploader.Core/Models/ApiResponse.cs`

```csharp
public class UploadResponseData
{
    [JsonPropertyName("uploadId")]
    public Guid UploadId { get; set; }

    [JsonPropertyName("status")]
    public string Status { get; set; } = string.Empty;

    [JsonPropertyName("message")]
    public string? Message { get; set; }

    [JsonPropertyName("queuePosition")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? QueuePosition { get; set; }

    // NEW FIELD
    /// <summary>
    /// Type of database detected (NTFSPermissions, ADInventory).
    /// </summary>
    [JsonPropertyName("uploadType")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? UploadType { get; set; }
}
```

### 2. `UploadStatusData`

**File**: `NTFSPermsUploader.Core/Models/ApiResponse.cs`

```csharp
public class UploadStatusData
{
    // ... existing fields ...

    // NEW FIELD
    /// <summary>
    /// Type of upload (NTFSPermissions, ADInventory).
    /// </summary>
    [JsonPropertyName("uploadType")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? UploadType { get; set; }
}
```

---

## API Response Changes

### `POST /api/v1/upload`

**Current Response:**
```json
{
  "success": true,
  "data": {
    "uploadId": "5b3d9ae2-1651-4ced-8175-6c371ec32e92",
    "status": "Queued",
    "message": "File validated successfully. Import queued.",
    "queuePosition": 1
  },
  "timestamp": "2024-12-24T16:35:21Z"
}
```

**New Response:**
```json
{
  "success": true,
  "data": {
    "uploadId": "5b3d9ae2-1651-4ced-8175-6c371ec32e92",
    "status": "Queued",
    "message": "File validated successfully. Import queued.",
    "queuePosition": 1,
    "uploadType": "ADInventory"
  },
  "timestamp": "2024-12-24T16:35:21Z"
}
```

### `GET /api/v1/upload/{id}/status`

**Current Response:**
```json
{
  "success": true,
  "data": {
    "uploadId": "5b3d9ae2-1651-4ced-8175-6c371ec32e92",
    "originalFilename": "ADInventory_20241224.zip",
    "fileSizeBytes": 1809984277,
    "status": "Importing",
    "statusMessage": "Importing AD Objects...",
    "currentPhase": "AD_Object",
    "importProgress": 45,
    "uploadedAt": "2024-12-24T16:34:30Z",
    "uploadedBy": "DOMAIN\\user"
  },
  "timestamp": "2024-12-24T16:45:21Z"
}
```

**New Response:**
```json
{
  "success": true,
  "data": {
    "uploadId": "5b3d9ae2-1651-4ced-8175-6c371ec32e92",
    "originalFilename": "ADInventory_20241224.zip",
    "fileSizeBytes": 1809984277,
    "status": "Importing",
    "statusMessage": "Importing AD Objects...",
    "currentPhase": "AD_Object",
    "importProgress": 45,
    "uploadedAt": "2024-12-24T16:34:30Z",
    "uploadedBy": "DOMAIN\\user",
    "uploadType": "ADInventory"
  },
  "timestamp": "2024-12-24T16:45:21Z"
}
```

### `GET /api/v1/uploads`

Each item in the `items` array will include the new `uploadType` field.

---

## Database Schema Change

### Uploads Table

**File**: New migration or manual script

```sql
-- Add UploadType column to track what type of database was uploaded
ALTER TABLE [dbo].[Uploads]
ADD [UploadType] NVARCHAR(50) NULL;

-- Optional: Add index for filtering
CREATE INDEX IX_Uploads_UploadType ON [dbo].[Uploads] ([UploadType]);

-- Backfill existing records as NTFSPermissions (the original type)
UPDATE [dbo].[Uploads]
SET [UploadType] = 'NTFSPermissions'
WHERE [UploadType] IS NULL;
```

### Upload Entity

**File**: `NTFSPermsUploader.Data/Entities/Upload.cs`

```csharp
public class Upload
{
    // ... existing properties ...

    /// <summary>
    /// Type of upload (NTFSPermissions, ADInventory).
    /// </summary>
    public string? UploadType { get; set; }
}
```

---

## Optional API Enhancements

### 1. Filter Uploads by Type

**Endpoint**: `GET /api/v1/uploads?uploadType=ADInventory`

**Implementation** in `ApiController.cs`:
```csharp
[HttpGet("uploads")]
public async Task<IActionResult> ListUploads(
    [FromQuery] int page = 1,
    [FromQuery] int pageSize = 20,
    [FromQuery] string? status = null,
    [FromQuery] string? uploadType = null,  // NEW PARAMETER
    CancellationToken cancellationToken = default)
{
    // Pass uploadType to repository
}
```

### 2. Get Supported Upload Types

**Endpoint**: `GET /api/v1/upload-types`

**Response**:
```json
{
  "success": true,
  "data": {
    "types": [
      {
        "id": "NTFSPermissions",
        "name": "NTFS Permissions",
        "description": "File system permissions from CollectNTFSPerms",
        "filePattern": "*_AD.zip"
      },
      {
        "id": "ADInventory",
        "name": "AD Inventory",
        "description": "Active Directory inventory from ADInventory module",
        "filePattern": "ADInventory_*.zip"
      }
    ]
  }
}
```

### 3. Type-Specific Statistics

**Endpoint**: `GET /api/v1/upload/{id}/statistics`

**Response for NTFSPermissions**:
```json
{
  "success": true,
  "data": {
    "uploadType": "NTFSPermissions",
    "statistics": {
      "folders": 125000,
      "acls": 125000,
      "aces": 450000,
      "sids": 5000,
      "shares": 150
    }
  }
}
```

**Response for ADInventory**:
```json
{
  "success": true,
  "data": {
    "uploadType": "ADInventory",
    "statistics": {
      "users": 15000,
      "groups": 3500,
      "computers": 8000,
      "contacts": 500,
      "directMemberships": 45000,
      "flattenedMemberships": 250000,
      "trusts": 12,
      "domains": 5,
      "foreignSecurityPrincipals": 150
    }
  }
}
```

---

## Implementation Checklist

### Required Changes

- [ ] Add `UploadType` property to `Upload` entity
- [ ] Add database migration for `UploadType` column
- [ ] Add `UploadType` to `UploadResponseData` model
- [ ] Add `UploadType` to `UploadStatusData` model
- [ ] Update `UploadService` to set `UploadType` after detection
- [ ] Update `UploadRepository` to persist `UploadType`

### Optional Enhancements

- [ ] Add `uploadType` query parameter to `GET /api/v1/uploads`
- [ ] Add `GET /api/v1/upload-types` endpoint
- [ ] Add `GET /api/v1/upload/{id}/statistics` endpoint
- [ ] Update API documentation (Swagger/OpenAPI)

---

## Client Compatibility

| Client Type | Impact | Action Required |
|-------------|--------|-----------------|
| Existing NTFS collectors | None | No changes needed |
| New ADInventory collectors | None | Same upload endpoint works |
| Monitoring/automation scripts | None | New field is additive |
| Custom integrations | Optional | Can use new `uploadType` field for routing |

---

## Error Handling

### New Error Codes

| Code | Description |
|------|-------------|
| `UNKNOWN_UPLOAD_TYPE` | Database schema not recognized |
| `UNSUPPORTED_VERSION` | Database version too old for this upload type |

### Example Error Response

```json
{
  "success": false,
  "error": {
    "code": "UNKNOWN_UPLOAD_TYPE",
    "message": "Unable to determine database type. The database does not contain expected schema tables.",
    "details": {
      "checkedTables": ["app__Version", "Schema_Version"],
      "foundTables": ["some_other_table"]
    }
  },
  "timestamp": "2024-12-24T16:35:21Z"
}
```

---

## Summary

| Category | Impact |
|----------|--------|
| **Breaking Changes** | None |
| **New Response Fields** | `uploadType` (additive) |
| **New Query Parameters** | `uploadType` filter (optional) |
| **New Endpoints** | Optional enhancements |
| **Database Changes** | Add `UploadType` column |
| **Client Updates** | Not required |
