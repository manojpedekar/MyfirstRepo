# Troubleshooting Upload Failures

Solutions for problems when uploading collections to the web application.

## Pre-Upload Failures

### "Invalid file type"

**Cause:** File doesn't have .zip extension.

**Solution:** Ensure you're uploading a .zip file created by the collector.

### "File too large"

**Cause:** File exceeds the upload size limit (default: 3 GB).

**Solutions:**

1. **Reduce collection scope**
   ```powershell
   # Limit depth
   Invoke-NTFSPermissionCollection -Path "D:\Shares" -MaxDepth 5 -OutputPath "C:\Output"

   # Exclude large folders
   Invoke-NTFSPermissionCollection -Path "D:\Shares" `
       -ExcludeFolders @("archive", "backup") -OutputPath "C:\Output"
   ```

2. **Split into multiple collections**
   ```powershell
   Invoke-NTFSPermissionCollection -Path "D:\Shares\Finance" -OutputPath "C:\Output"
   Invoke-NTFSPermissionCollection -Path "D:\Shares\HR" -OutputPath "C:\Output"
   ```

3. **Contact admin** to increase limits if needed

### "Access denied" on upload page

**Cause:** You don't have upload permissions.

**Solutions:**

1. Verify you're logged in
2. Confirm you're in an upload-authorized group
3. Contact your administrator

## Upload Progress Failures

### Upload stalls or times out

**Causes:**
- Network connectivity issues
- Server timeout
- Browser issues

**Solutions:**

1. **Check network**
   ```powershell
   Test-NetConnection -ComputerName "ntfspermsuploader.company.com" -Port 443
   ```

2. **Use API upload for large files**
   ```powershell
   Invoke-RestMethod -Uri $url -Method Post -TimeoutSec 3600 ...
   ```

3. **Try a different browser**

### "Connection reset"

**Cause:** Network interruption during upload.

**Solutions:**

1. Use wired network instead of Wi-Fi
2. Upload during off-peak hours
3. Try from a different location

## Validation Failures

### "ZIP validation failed"

**Cause:** ZIP file is corrupt or invalid.

**Solutions:**

1. **Test ZIP integrity**
   ```powershell
   # Using .NET
   try {
       $zip = [System.IO.Compression.ZipFile]::OpenRead("C:\Output\file.zip")
       $zip.Dispose()
       Write-Host "ZIP is valid"
   } catch {
       Write-Error "ZIP is corrupt"
   }
   ```

2. **Re-run the collection** to create a new file

3. **Check disk health** on the collection server

### "Database validation failed"

**Cause:** SQLite database inside ZIP is corrupt.

**Solutions:**

1. **Re-run the collection**
2. **Check collection log** for errors during collection
3. **Verify collector version** is current

### "Unsupported schema version"

**Cause:** Collector version doesn't match what server expects.

**Solution:**
1. Download latest collector from the web application
2. Re-run collection with new version
3. Upload the new file

## Import Failures

### "Import failed: duplicate key"

**Cause:** Data already exists from a previous upload.

**Solution:** This is usually handled automatically. If it persists:
1. Contact administrator
2. Previous collection may need to be deleted first

### "Import failed: foreign key constraint"

**Cause:** Data integrity issue in the collection.

**Solutions:**

1. **Re-run collection** to ensure data consistency
2. **Check collection log** for errors
3. **Report to support** with the error details

### "Import timeout"

**Cause:** Very large collection or server under load.

**Solutions:**

1. **Wait and retry** - server may be busy
2. **Split collection** into smaller files
3. **Contact admin** - timeout may need adjustment

## Migration Failures

### "Migration failed"

**Cause:** Error moving data from staging to production.

**Solutions:**

1. **Check status page** for detailed error
2. **Contact administrator** - may be a server-side issue
3. **Retry** - temporary database issues may resolve

## API Upload Errors

### "Unauthorized" (401)

**Cause:** Invalid or missing API key.

**Solutions:**

```powershell
# Verify API key is correct
$headers = @{ "X-API-Key" = $apiKey }

# Check key isn't expired (in web app: Account > API Keys)
```

### "Request too large" (413)

**Cause:** File exceeds server limit.

**Solution:** See "File too large" above.

### "Rate limited" (429)

**Cause:** Too many requests.

**Solution:** Wait a few minutes and retry.

## Checking Upload Status

### Via Web Interface

1. Go to **Upload Status** page
2. Find your upload by filename or date
3. Click to see detailed status and logs

### Via API

```powershell
$status = Invoke-RestMethod -Uri "$baseUrl/uploads/$uploadId/status" `
    -Headers @{ "X-API-Key" = $apiKey }

Write-Host "Status: $($status.data.status)"
Write-Host "Error: $($status.data.errorMessage)"
```

## When to Contact Support

Contact support if:

- Error message is unclear
- Issue persists after troubleshooting
- Server-side error is indicated
- You need limit increases

**Include:**
- Error message (exact text)
- Upload ID if available
- Collection filename
- Steps you've already tried

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
