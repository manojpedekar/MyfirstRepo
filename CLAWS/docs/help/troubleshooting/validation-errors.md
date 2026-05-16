# Troubleshooting Validation Errors

Solutions for data validation errors during upload processing.

## Understanding Validation

When you upload a collection, the system validates:

1. **ZIP integrity** - File is a valid ZIP archive
2. **Database integrity** - SQLite database passes integrity check
3. **Schema validation** - Database has expected tables/columns
4. **Data validation** - Data meets format requirements
5. **Reference validation** - Foreign key relationships are valid

## ZIP Validation Errors

### "Invalid ZIP file"

The uploaded file is not a valid ZIP archive.

**Causes:**
- File was corrupted during transfer
- Wrong file uploaded
- Incomplete collection

**Solutions:**
1. Verify file opens in Windows Explorer
2. Re-download and re-upload
3. Re-run the collection

### "ZIP bomb detected"

The file has an unusually high compression ratio.

**Cause:** Collection output has unusual compression characteristics.

**Solution:** Contact support - this may be a false positive.

### "Path traversal detected"

ZIP contains entries with suspicious paths (e.g., `../`).

**Cause:** ZIP file may be compromised.

**Solution:** Re-run collection with official collector.

## Database Validation Errors

### "Database integrity check failed"

SQLite database is corrupt.

**Causes:**
- Disk error during collection
- File corrupted during transfer
- Interrupted collection

**Solutions:**

1. **Verify file integrity locally:**
   ```powershell
   Expand-Archive "C:\Output\file.zip" -DestinationPath "C:\Temp"
   sqlite3 "C:\Temp\NTFSPerms.db" "PRAGMA integrity_check"
   ```

2. **Re-run collection**
3. **Check disk health** on collection server

### "Missing required table"

Database doesn't have expected tables.

**Causes:**
- Wrong collector version
- Incomplete collection
- Wrong file uploaded

**Solutions:**
1. Verify you're using the latest collector
2. Re-run collection
3. Ensure you uploaded the correct file

### "Schema version mismatch"

Database schema doesn't match what server expects.

**Solution:**
1. Download latest collector
2. Re-run collection
3. Upload new file

## Data Validation Errors

### "Invalid SID format"

SID data doesn't match expected format.

**Cause:** Unusual or corrupt SID data in source.

**Solution:**
1. Check collection log for SID-related errors
2. Report specific SIDs to support

### "Invalid path format"

File paths contain invalid characters.

**Cause:** Source file system has unusual characters.

**Solution:**
1. Note the specific paths from error
2. May need to exclude those paths from collection

### "Date/time out of range"

Timestamp values are outside valid range.

**Cause:** Source has files with corrupt timestamps.

**Solution:**
1. Note specific folders/files
2. May need to exclude from collection

## Reference Validation Errors

### "Orphaned ACL entries"

ACL entries reference folders that don't exist.

**Cause:** Collection timing issue or interrupted collection.

**Solution:**
1. Re-run collection
2. If issue persists, contact support

### "Missing SID references"

ACE entries reference SIDs not in SID table.

**Cause:** Incomplete SID collection.

**Solution:**
1. Re-run collection
2. Report to support if consistent

## Reading Validation Details

### In Web Interface

1. Go to **Upload Status**
2. Click on the failed upload
3. Select **Logs** tab
4. Look for "Validation" entries

### Common Log Patterns

```
[VALIDATION] ZIP integrity check: PASSED
[VALIDATION] Database integrity check: PASSED
[VALIDATION] Schema version: 1.8.0
[VALIDATION] Table count validation: PASSED
[ERROR] Data validation failed: Invalid SID format in row 12456
```

## Partial Validation Failures

Sometimes validation passes with warnings. Data is still imported but:

- Some rows may be skipped
- Warnings are logged for review
- Data quality may be affected

## Preventing Validation Errors

| Practice | Benefit |
|----------|---------|
| Use latest collector | Ensures schema compatibility |
| Run on stable storage | Prevents corruption |
| Review collection logs | Catch issues before upload |
| Upload promptly | Reduces file handling |

## Reporting Validation Issues

If validation fails and troubleshooting doesn't help:

1. **Gather information:**
   - Exact error message
   - Upload ID
   - Collection log file
   - Collector version

2. **Contact support:**
   - GlobalWindowsServers@sscinc.com
   - Include all gathered information

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
