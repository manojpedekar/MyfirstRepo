# NTFSPermsUploader API Documentation

## Base URL

```
https://your-server/api/v1/
```

## Authentication

All API endpoints except `/health` require authentication via API key.

Include the API key in the `X-API-Key` header:

```bash
curl -H "X-API-Key: your-api-key" https://server/api/v1/uploads
```

### Generating API Keys

1. Log in to the web UI
2. Navigate to Admin > API Keys
3. Click "Generate New Key"
4. Copy the key immediately (it's only shown once)

## Response Format

All responses use a consistent JSON structure:

### Success Response

```json
{
  "success": true,
  "data": { ... },
  "timestamp": "2025-01-15T10:30:00Z"
}
```

### Error Response

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message",
    "details": { ... }
  },
  "timestamp": "2025-01-15T10:30:00Z"
}
```

## HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 201 | Created (successful upload) |
| 400 | Bad request (validation failed) |
| 401 | Unauthorized (missing/invalid API key) |
| 404 | Not found |
| 413 | Payload too large |
| 429 | Rate limit exceeded |
| 500 | Server error |
| 503 | Service unavailable (disk full, DB down) |

## Endpoints

### Health Check

Check if the service is running.

```
GET /api/v1/health
```

**Authentication**: Not required

**Response**:
```json
{
  "success": true,
  "data": {
    "status": "healthy",
    "version": "1.0.0"
  }
}
```

### Readiness Check

Check if the service is ready to accept uploads.

```
GET /api/v1/health/ready
```

**Authentication**: Not required

**Response**:
```json
{
  "success": true,
  "data": {
    "status": "healthy",
    "version": "1.0.0",
    "checks": {
      "database": { "status": "healthy" },
      "diskSpace": { "status": "healthy" }
    }
  }
}
```

### Upload File

Upload a ZIP file for import.

```
POST /api/v1/upload
Content-Type: multipart/form-data
```

**Parameters**:
| Name | Type | Description |
|------|------|-------------|
| file | file | ZIP file containing SQLite database |

**Example**:
```bash
curl -X POST \
  -H "X-API-Key: your-api-key" \
  -F "file=@database.zip" \
  https://server/api/v1/upload
```

**Success Response** (201):
```json
{
  "success": true,
  "data": {
    "uploadId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "status": "Queued",
    "message": "File validated successfully. Import queued.",
    "queuePosition": 1
  }
}
```

**Error Response** (400):
```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Database schema version 1.4.0 does not meet minimum required version 1.6.0.",
    "details": {
      "foundVersion": "1.4.0",
      "requiredVersion": "1.6.0"
    }
  }
}
```

### Get Upload Status

Get the current status of an upload.

```
GET /api/v1/upload/{uploadId}/status
```

**Response**:
```json
{
  "success": true,
  "data": {
    "uploadId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "originalFilename": "database.zip",
    "fileSizeBytes": 1234567890,
    "status": "Importing",
    "statusMessage": "Importing Folders: 500,000 / 1,000,000 rows",
    "currentPhase": "Folders",
    "importProgress": 50,
    "uploadedAt": "2025-01-15T10:00:00Z",
    "startedAt": "2025-01-15T10:01:00Z",
    "completedAt": null,
    "uploadedBy": "API:MyScript"
  }
}
```

### Get Upload Logs

Get detailed logs for an upload.

```
GET /api/v1/upload/{uploadId}/logs
```

**Response**:
```json
{
  "success": true,
  "data": {
    "uploadId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "logs": [
      {
        "timestamp": "2025-01-15T10:00:00Z",
        "level": "INFO",
        "message": "Upload started"
      },
      ...
    ]
  }
}
```

### Cancel/Delete Upload

Cancel a pending upload or delete a completed upload record.

```
DELETE /api/v1/upload/{uploadId}
```

**Response** (200):
```json
{
  "success": true
}
```

**Error Response** (400):
```json
{
  "success": false,
  "error": {
    "code": "CANNOT_CANCEL",
    "message": "Cannot cancel this upload. It may already be completed or in progress."
  }
}
```

### List Uploads

Get a paginated list of uploads.

```
GET /api/v1/uploads?page=1&pageSize=20&status=Completed
```

**Query Parameters**:
| Name | Type | Default | Description |
|------|------|---------|-------------|
| page | int | 1 | Page number |
| pageSize | int | 20 | Items per page (max 100) |
| status | string | - | Filter by status |

**Response**:
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "uploadId": "...",
        "originalFilename": "database.zip",
        "fileSizeBytes": 1234567890,
        "status": "Completed",
        "uploadedAt": "2025-01-15T10:00:00Z",
        "uploadedBy": "DOMAIN\\user"
      }
    ],
    "page": 1,
    "pageSize": 20,
    "totalPages": 5,
    "totalItems": 100
  }
}
```

## Error Codes

| Code | Description |
|------|-------------|
| NO_FILE | No file was provided |
| INVALID_FILE_TYPE | File is not a ZIP |
| FILE_TOO_LARGE | File exceeds maximum size |
| INSUFFICIENT_DISK_SPACE | Not enough disk space |
| DB_NOT_CONFIGURED | Database connection not configured |
| ZIP_EMPTY | ZIP file is empty |
| ZIP_MULTIPLE_FILES | ZIP contains more than one file |
| ZIP_CONTAINS_FOLDER | ZIP contains directories |
| ZIP_PATH_TRAVERSAL | ZIP entry has invalid path |
| ZIP_SIZE_EXCEEDED | Extracted size exceeds limit |
| ZIP_BOMB_SUSPECTED | Compression ratio too high |
| ZIP_CORRUPT | ZIP file is corrupt |
| NOT_SQLITE | File is not a SQLite database |
| SQLITE_CORRUPT | SQLite integrity check failed |
| MISSING_VERSION_TABLE | app__Version table not found |
| MISSING_COLLECTION_INFO | app__CollectionInfo not found |
| DB_VERSION_TOO_LOW | Database schema version too low |
| APP_VERSION_TOO_LOW | Application version too low |
| NOT_FOUND | Resource not found |
| UNAUTHORIZED | Authentication required |
| CANNOT_CANCEL | Upload cannot be cancelled |

## Rate Limiting

API requests are rate limited (configurable):
- Default: 10 requests/minute, 100 requests/hour

When rate limited, you'll receive a 429 response:
```json
{
  "success": false,
  "error": {
    "code": "RATE_LIMITED",
    "message": "Too many requests. Please try again later."
  }
}
```

## WebSocket (SignalR)

For real-time progress updates, connect to the SignalR hub:

```javascript
const connection = new signalR.HubConnectionBuilder()
    .withUrl("/hubs/upload")
    .build();

connection.on("ProgressUpdate", (data) => {
    console.log(data.uploadId, data.phase, data.percent, data.message);
});

await connection.start();
await connection.invoke("SubscribeToUpload", uploadId);
```
