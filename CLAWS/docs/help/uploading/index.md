# Uploading Data

This section explains how to upload your NTFS permissions or AD Inventory collections to the web application.

## Upload Methods

| Method | Best For |
|--------|----------|
| [Web Interface](web-upload.md) | Interactive uploads, manual verification |
| [API Upload](api-upload.md) | Automation, scheduled tasks, scripted uploads |

## Before You Upload

### Verify Your Collection

Ensure your collection completed successfully:

1. Check the collection log for errors
2. Verify the .zip file was created
3. Confirm the file size is reasonable

### File Requirements

| Requirement | Value |
|-------------|-------|
| Format | .zip only |
| Maximum size | 3 GB (configurable) |
| Maximum extracted size | 50 GB (configurable) |
| Contents | Must contain valid SQLite database |

## Upload Process Overview

```
1. Select file → 2. Upload → 3. Validation → 4. Import → 5. Migration → 6. Complete
```

### Stages Explained

| Stage | Description |
|-------|-------------|
| **Upload** | File transferred to server |
| **Validation** | ZIP integrity, database verification |
| **Import** | Data loaded into staging tables |
| **Migration** | Data moved to production tables |
| **Complete** | Data available for querying |

## Upload Status

After uploading, you can track progress:

| Status | Meaning |
|--------|---------|
| Queued | Waiting to be processed |
| Validating | Checking file integrity |
| Importing | Loading data |
| Migrating | Moving to production |
| Completed | Successfully finished |
| Failed | Error occurred (check logs) |

## In This Section

| Article | Description |
|---------|-------------|
| [Web Interface](web-upload.md) | Upload via browser |
| [API Upload](api-upload.md) | Upload via REST API |
| [Large Files](large-files.md) | Tips for large collections |

## Quick Start

### Web Upload (Simplest)

1. Log in to the web application
2. Click **Upload** in the navigation
3. Select your .zip file
4. Click **Upload**
5. Wait for processing to complete

### API Upload (Automated)

```powershell
$apiKey = "your-api-key"
$file = "C:\Output\SERVER_20260112.zip"

Invoke-RestMethod -Uri "https://server/api/v1/uploads" `
    -Method Post `
    -Headers @{ "X-API-Key" = $apiKey } `
    -Form @{ file = Get-Item $file }
```

## Troubleshooting Uploads

Common issues and solutions:

| Issue | Solution |
|-------|----------|
| "File too large" | Check size limits, contact admin |
| "Invalid file type" | Ensure file has .zip extension |
| "Validation failed" | Check collection completed properly |
| "Import failed" | Review error details in status page |

See [Troubleshooting Upload Failures](../troubleshooting/upload-failures.md) for detailed help.

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
