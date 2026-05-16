# Uploading Large Files

Tips and best practices for uploading large collection files.

## Size Limits

| Limit | Default | Description |
|-------|---------|-------------|
| Maximum upload size | 10 GB | Compressed .zip file |
| Maximum extracted size | 100 GB | Uncompressed contents |

> **Note:** These limits are configurable by administrators.

## Strategies for Large Collections

### 1. Reduce Collection Scope

Collect less data to reduce file size:

```powershell
# NTFS: Limit depth
Invoke-NTFSPermissionCollection -Path "D:\Shares" -MaxDepth 5 -OutputPath "C:\Output"

# NTFS: Exclude large folders
Invoke-NTFSPermissionCollection -Path "D:\Shares" `
    -ExcludeFolders @("archive", "backup", "temp") `
    -OutputPath "C:\Output"

# NTFS: Exclude inherited permissions
Invoke-NTFSPermissionCollection -Path "D:\Shares" `
    -IncludeInherited:$false `
    -OutputPath "C:\Output"
```

### 2. Split Collections

Collect different paths separately:

```powershell
# Instead of one large collection
Invoke-NTFSPermissionCollection -Path "D:\Shares" -OutputPath "C:\Output"

# Split into multiple smaller collections
Invoke-NTFSPermissionCollection -Path "D:\Shares\Finance" -OutputPath "C:\Output"
Invoke-NTFSPermissionCollection -Path "D:\Shares\HR" -OutputPath "C:\Output"
Invoke-NTFSPermissionCollection -Path "D:\Shares\IT" -OutputPath "C:\Output"
```

### 3. Use API Upload

The API upload is more reliable for large files than web upload:

```powershell
# API upload with longer timeout
$response = Invoke-RestMethod -Uri $uploadUrl -Method Post `
    -Headers @{ "X-API-Key" = $apiKey } `
    -Form @{ file = Get-Item $filePath } `
    -TimeoutSec 3600
```

## Optimizing Upload Performance

### Network Considerations

| Factor | Recommendation |
|--------|----------------|
| Connection | Use wired network, not Wi-Fi |
| Bandwidth | Upload during off-peak hours |
| Latency | Upload from server closest to app |
| Stability | Ensure stable connection |

### Upload from Collection Server

If possible, upload directly from the collection server:

```powershell
# On the collection server
$apiKey = $env:UPLOAD_API_KEY
$latestFile = Get-ChildItem "C:\Output\*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

Invoke-RestMethod -Uri "https://ntfspermsuploader.company.com/api/v1/uploads" `
    -Method Post `
    -Headers @{ "X-API-Key" = $apiKey } `
    -Form @{ file = Get-Item $latestFile.FullName }
```

### Pre-Upload Validation

Validate files before uploading:

```powershell
# Check file integrity
$zipFile = "C:\Output\SERVER_20260112.zip"

# Verify ZIP
try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipFile)
    $zip.Dispose()
    Write-Host "ZIP file is valid"
} catch {
    Write-Error "ZIP file is corrupt: $_"
}

# Check file size
$fileSize = (Get-Item $zipFile).Length
$maxSize = 3GB
if ($fileSize -gt $maxSize) {
    Write-Warning "File exceeds upload limit ($($fileSize / 1GB) GB > 3 GB)"
}
```

## Troubleshooting Large Uploads

### Upload Timeout

**Symptom:** Upload fails after running for a long time.

**Solutions:**
- Use API upload with extended timeout
- Upload from a location with better network connectivity
- Contact admin to increase server timeout settings

### Out of Disk Space

**Symptom:** Upload fails during extraction/processing.

**Solutions:**
- Ensure server has sufficient disk space
- Contact admin to clear space or expand storage

### Connection Reset

**Symptom:** Upload fails with "connection reset" error.

**Solutions:**
- Check for network issues or firewalls
- Retry the upload
- Split into smaller collections

## When to Contact Support

Contact support if:

- Your file exceeds size limits and cannot be reduced
- Uploads consistently fail despite troubleshooting
- You need increased limits for your use case

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
