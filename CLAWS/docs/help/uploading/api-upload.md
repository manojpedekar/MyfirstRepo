# API Upload

Upload collections programmatically using the REST API.

## Overview

The API upload enables:
- Automated uploads from scripts
- Integration with CI/CD pipelines
- Scheduled upload tasks
- Remote upload from collection servers

## Prerequisites

- Valid API key (obtain from Account > API Keys)
- Network access to the web application
- .zip file from collector

## API Endpoint

```
POST /api/v1/uploads
```

## Authentication

Include your API key in the request header:

```
X-API-Key: your-api-key-here
```

## Request Format

Send the file as multipart/form-data:

| Field | Type | Description |
|-------|------|-------------|
| file | File | The .zip file to upload |

## PowerShell Examples

### Basic Upload

```powershell
$apiKey = "your-api-key-here"
$uploadUrl = "https://ntfspermsuploader.company.com/api/v1/uploads"
$filePath = "C:\Output\SERVER_20260112_143022.zip"

$response = Invoke-RestMethod -Uri $uploadUrl -Method Post `
    -Headers @{ "X-API-Key" = $apiKey } `
    -Form @{ file = Get-Item $filePath }

Write-Host "Upload ID: $($response.data.uploadId)"
Write-Host "Status: $($response.data.status)"
```

### Check Upload Status

```powershell
$uploadId = "12345678-1234-1234-1234-123456789abc"
$statusUrl = "https://ntfspermsuploader.company.com/api/v1/uploads/$uploadId/status"

$status = Invoke-RestMethod -Uri $statusUrl -Method Get `
    -Headers @{ "X-API-Key" = $apiKey }

Write-Host "Status: $($status.data.status)"
Write-Host "Progress: $($status.data.progressPercent)%"
```

### Upload and Wait for Completion

```powershell
$apiKey = "your-api-key-here"
$baseUrl = "https://ntfspermsuploader.company.com/api/v1"
$filePath = "C:\Output\SERVER_20260112_143022.zip"

# Upload
$upload = Invoke-RestMethod -Uri "$baseUrl/uploads" -Method Post `
    -Headers @{ "X-API-Key" = $apiKey } `
    -Form @{ file = Get-Item $filePath }

$uploadId = $upload.data.uploadId
Write-Host "Uploaded. ID: $uploadId"

# Wait for completion
do {
    Start-Sleep -Seconds 10
    $status = Invoke-RestMethod -Uri "$baseUrl/uploads/$uploadId/status" `
        -Headers @{ "X-API-Key" = $apiKey }

    Write-Host "Status: $($status.data.status) - $($status.data.progressPercent)%"
} while ($status.data.status -notin @("Completed", "Failed", "Cancelled"))

if ($status.data.status -eq "Completed") {
    Write-Host "Upload completed successfully!"
} else {
    Write-Error "Upload failed: $($status.data.errorMessage)"
}
```

## cURL Examples

### Upload File

```bash
curl -X POST \
  -H "X-API-Key: your-api-key-here" \
  -F "file=@/path/to/collection.zip" \
  https://ntfspermsuploader.company.com/api/v1/uploads
```

### Check Status

```bash
curl -H "X-API-Key: your-api-key-here" \
  https://ntfspermsuploader.company.com/api/v1/uploads/{uploadId}/status
```

## Response Format

### Successful Upload

```json
{
  "success": true,
  "data": {
    "uploadId": "12345678-1234-1234-1234-123456789abc",
    "status": "Queued",
    "fileName": "SERVER_20260112_143022.zip",
    "fileSize": 156789012,
    "uploadedAt": "2026-01-12T14:30:22Z"
  }
}
```

### Status Response

```json
{
  "success": true,
  "data": {
    "uploadId": "12345678-1234-1234-1234-123456789abc",
    "status": "Importing",
    "progressPercent": 45,
    "currentOperation": "Importing SIDs table",
    "recordsProcessed": 12456,
    "startedAt": "2026-01-12T14:30:25Z"
  }
}
```

### Error Response

```json
{
  "success": false,
  "error": {
    "code": "INVALID_FILE_TYPE",
    "message": "Only .zip files are accepted"
  }
}
```

## Error Codes

| Code | Description |
|------|-------------|
| UNAUTHORIZED | Invalid or missing API key |
| INVALID_FILE_TYPE | File is not a .zip |
| FILE_TOO_LARGE | Exceeds size limit |
| VALIDATION_FAILED | File failed validation |
| QUOTA_EXCEEDED | Upload quota reached |

## API Key Management

### Get an API Key

1. Log in to the web application
2. Go to **Account** > **API Keys**
3. Click **Create New Key**
4. Copy the key (shown only once)

### Key Security

- Store keys securely (not in scripts)
- Use environment variables or secret management
- Rotate keys periodically
- Delete unused keys

```powershell
# Use environment variable
$apiKey = $env:NTFS_UPLOAD_API_KEY
```

## Rate Limits

| Limit | Value |
|-------|-------|
| Concurrent uploads | 3 per API key |
| Requests per minute | 60 |

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
