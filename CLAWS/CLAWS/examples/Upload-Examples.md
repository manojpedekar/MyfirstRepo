# NTFSPermsUploader API Upload Examples

## Quick Reference

### Minimal PowerShell Upload (One-liner)

```powershell
# Simple upload using Invoke-RestMethod
Invoke-RestMethod -Uri "https://server/api/v1/upload" `
    -Method Post `
    -Headers @{"X-API-Key" = "your-api-key"} `
    -Form @{file = Get-Item "C:\path\to\file.zip"}
```

> **Note:** The `-Form` parameter requires PowerShell 6.0+. For PowerShell 5.1, use the full script below.

### PowerShell 5.1 Compatible Upload

```powershell
# For PowerShell 5.1 (Windows PowerShell)
$apiKey = "your-api-key"
$serverUrl = "https://server"
$zipPath = "C:\path\to\file.zip"

# Read file and create multipart body
$fileBytes = [IO.File]::ReadAllBytes($zipPath)
$fileName = [IO.Path]::GetFileName($zipPath)
$boundary = [Guid]::NewGuid().ToString()

$body = (
    "--$boundary`r`n" +
    "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"`r`n" +
    "Content-Type: application/zip`r`n`r`n"
)
$bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
$footerBytes = [Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n")

$requestBody = New-Object byte[] ($bodyBytes.Length + $fileBytes.Length + $footerBytes.Length)
[Buffer]::BlockCopy($bodyBytes, 0, $requestBody, 0, $bodyBytes.Length)
[Buffer]::BlockCopy($fileBytes, 0, $requestBody, $bodyBytes.Length, $fileBytes.Length)
[Buffer]::BlockCopy($footerBytes, 0, $requestBody, $bodyBytes.Length + $fileBytes.Length, $footerBytes.Length)

$response = Invoke-RestMethod -Uri "$serverUrl/api/v1/upload" `
    -Method Post `
    -Headers @{"X-API-Key" = $apiKey} `
    -ContentType "multipart/form-data; boundary=$boundary" `
    -Body $requestBody

$response.data  # Returns uploadId, status, message, queuePosition
```

### Check Upload Status

```powershell
$uploadId = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
$status = Invoke-RestMethod -Uri "$serverUrl/api/v1/upload/$uploadId/status" `
    -Headers @{"X-API-Key" = $apiKey}

$status.data | Format-List
```

### Poll Until Complete

```powershell
$uploadId = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
$terminalStates = @("Completed", "Failed", "Cancelled")

do {
    $status = Invoke-RestMethod -Uri "$serverUrl/api/v1/upload/$uploadId/status" `
        -Headers @{"X-API-Key" = $apiKey}

    Write-Host "$($status.data.status): $($status.data.statusMessage)"

    if ($status.data.status -notin $terminalStates) {
        Start-Sleep -Seconds 5
    }
} while ($status.data.status -notin $terminalStates)

Write-Host "Final status: $($status.data.status)"
```

### List All Uploads

```powershell
$uploads = Invoke-RestMethod -Uri "$serverUrl/api/v1/uploads?page=1&pageSize=10" `
    -Headers @{"X-API-Key" = $apiKey}

$uploads.data.items | Format-Table uploadId, originalFilename, status, uploadedAt
```

## cURL Examples

### Upload a File

```bash
curl -X POST \
  -H "X-API-Key: your-api-key" \
  -F "file=@/path/to/database.zip" \
  https://server/api/v1/upload
```

### Check Health (No Auth Required)

```bash
curl https://server/api/v1/health
```

### Check Readiness (No Auth Required)

```bash
curl https://server/api/v1/health/ready
```

### Get Upload Status

```bash
curl -H "X-API-Key: your-api-key" \
  https://server/api/v1/upload/a1b2c3d4-e5f6-7890-abcd-ef1234567890/status
```

## Error Handling

Common error codes and their meanings:

| Error Code | Meaning | Solution |
|------------|---------|----------|
| `UNAUTHORIZED` | Invalid or missing API key | Check your X-API-Key header |
| `INVALID_FILE_TYPE` | Not a ZIP file | Ensure file has .zip extension |
| `FILE_TOO_LARGE` | Exceeds 3 GB limit | Split or compress further |
| `INSUFFICIENT_DISK_SPACE` | Server disk full | Contact administrator |
| `VALIDATION_FAILED` | Database validation failed | Check database schema version |
| `DB_VERSION_TOO_LOW` | Schema version too old | Update CollectNTFSPerms tool |

## Response Examples

### Successful Upload (201)

```json
{
  "success": true,
  "data": {
    "uploadId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "status": "Queued",
    "message": "File validated successfully. Import queued.",
    "queuePosition": 1
  },
  "timestamp": "2025-01-15T10:30:00Z"
}
```

### Validation Error (400)

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
  },
  "timestamp": "2025-01-15T10:30:00Z"
}
```

### Status Response

```json
{
  "success": true,
  "data": {
    "uploadId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "originalFilename": "permissions.zip",
    "fileSizeBytes": 1234567890,
    "status": "Importing",
    "statusMessage": "Importing Folders: 500,000 / 1,000,000 rows",
    "currentPhase": "Folders",
    "importProgress": 50,
    "uploadedAt": "2025-01-15T10:00:00Z",
    "startedAt": "2025-01-15T10:01:00Z"
  }
}
```
