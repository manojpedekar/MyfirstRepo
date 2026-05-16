# SQLite Integrity Check Optimization

## Issue Summary

The SQLite integrity check during file upload is taking an excessive amount of time for large databases. A 1.7GB compressed ZIP file containing a ~16GB SQLite database has been observed running the integrity check for over 20 minutes without completing.

**Observed Logs:**
```
2025-12-24 11:35:21.287 [INF] Starting import job for upload "5b3d9ae2-1651-4ced-8175-6c371ec32e92"
2025-12-24 11:35:21.326 [INF] Running SQLite integrity check on T:\ImportData\Extraction\5b3d9ae2-1651-4ced-8175-6c371ec32e92\DSKCFILE1PD_AD.db
```

## Root Cause Analysis

The current implementation in `DatabaseValidator.cs:70` uses:

```csharp
command.CommandText = "PRAGMA integrity_check";
```

### What `PRAGMA integrity_check` Does

SQLite's `integrity_check` is the most thorough validation option but also the slowest:

1. **Full Database Scan**: Reads every single page in the database file
2. **B-Tree Validation**: Verifies all B-tree data structures are well-formed
3. **Index Verification**: Ensures all indexes contain the correct entries matching their tables
4. **Row Data Validation**: Checks all row payloads and cross-references
5. **Foreign Key Checks**: Validates referential integrity constraints

For a 16GB database with SQLite's default 4KB page size, this means:
- ~4 million pages to read and verify
- I/O bound operation limited by disk speed
- Network storage (if T: is a network drive) will be significantly slower

### Current Code Location

**File:** `NTFSPermsUploader.Core/Validation/DatabaseValidator.cs`

```csharp
public async Task<ValidationResult> RunIntegrityCheckAsync(
    string sqlitePath,
    CancellationToken cancellationToken = default)
{
    // ...
    command.CommandText = "PRAGMA integrity_check";
    var result = await command.ExecuteScalarAsync(cancellationToken);
    // ...
}
```

**Called from:** `NTFSPermsUploader.Jobs/ImportJob.cs:100`

```csharp
var integrityResult = await _dbValidator.RunIntegrityCheckAsync(sqlitePath, cancellationToken);
```

---

## Recommendations

### Option 1: Use `PRAGMA quick_check` (Recommended - Low Risk)

**Estimated Improvement:** 30-50% faster

Replace `integrity_check` with `quick_check`:

```csharp
command.CommandText = "PRAGMA quick_check";
```

**Differences:**
| Check | integrity_check | quick_check |
|-------|----------------|-------------|
| B-tree structure | Yes | Yes |
| Row data | Yes | Yes |
| Index validity | Yes | **No** |
| Cross-table references | Yes | **No** |

**Risk Assessment:** Low. The database was just created by CollectNTFSPerms and extracted from a ZIP file. Index corruption without data corruption is extremely rare and would typically only occur with hardware failures mid-write.

---

### Option 2: Make Integrity Check Configurable (Recommended)

Add configuration to control integrity check behavior:

```json
{
  "Import": {
    "IntegrityCheckMode": "Quick",
    "IntegrityCheckTimeoutMinutes": 30,
    "IntegrityCheckMaxFileSizeGB": 10
  }
}
```

**Modes:**
- `Full`: Use `PRAGMA integrity_check` (current behavior)
- `Quick`: Use `PRAGMA quick_check` (faster, recommended default)
- `None`: Skip integrity check entirely
- `Auto`: Use `quick_check` for files over threshold, `integrity_check` for smaller files

**Configuration Schema Update for `AppSettings.cs`:**

```csharp
public class ImportSettings
{
    // ... existing properties ...

    /// <summary>
    /// SQLite integrity check mode: Full, Quick, None, or Auto.
    /// </summary>
    public IntegrityCheckMode IntegrityCheckMode { get; set; } = IntegrityCheckMode.Quick;

    /// <summary>
    /// Timeout in minutes for integrity check operations.
    /// </summary>
    public int IntegrityCheckTimeoutMinutes { get; set; } = 30;

    /// <summary>
    /// File size threshold in GB for Auto mode to switch from Full to Quick.
    /// </summary>
    public double IntegrityCheckAutoThresholdGB { get; set; } = 5.0;
}

public enum IntegrityCheckMode
{
    Full,
    Quick,
    None,
    Auto
}
```

---

### Option 3: Add Timeout with Fallback

Implement a timeout mechanism that falls back to accepting the file:

```csharp
public async Task<ValidationResult> RunIntegrityCheckAsync(
    string sqlitePath,
    TimeSpan timeout,
    CancellationToken cancellationToken = default)
{
    using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
    cts.CancelAfter(timeout);

    try
    {
        // Run integrity check...
    }
    catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
    {
        _logger.LogWarning("Integrity check timed out after {Timeout}, proceeding with import", timeout);
        return ValidationResult.Success(); // Or a warning result
    }
}
```

---

### Option 4: Skip Integrity Check Entirely (High Risk Reduction)

**Estimated Improvement:** 100% (eliminates the delay)

For files from trusted sources (authenticated API uploads from known clients), the integrity check may be unnecessary:

1. **ZIP Extraction Already Validates**: The ZIP extraction process would fail if the archive were corrupt
2. **SQLite Opens Successfully**: If the database opens and passes schema validation, basic structural integrity is confirmed
3. **Client-Side Validation**: CollectNTFSPerms already creates a valid database

**Implementation:**

```csharp
public async Task ExecuteAsync(Guid uploadId, string sqlitePath, CancellationToken cancellationToken)
{
    // ... existing code ...

    // Skip integrity check for trusted sources or large files
    if (_importSettings.IntegrityCheckMode == IntegrityCheckMode.None)
    {
        _logger.LogInformation("Skipping integrity check (disabled by configuration)");
    }
    else
    {
        var integrityResult = await _dbValidator.RunIntegrityCheckAsync(sqlitePath, cancellationToken);
        if (!integrityResult.IsValid)
        {
            // ... handle failure ...
        }
    }

    // ... rest of import ...
}
```

---

### Option 5: Parallel Processing with Checksum Validation

Instead of full integrity checks, use checksums:

1. **Client-Side**: CollectNTFSPerms calculates MD5/SHA256 of the database before zipping
2. **Server-Side**: Verify checksum after extraction, skip full integrity check

This approach:
- Detects corruption during transfer/extraction
- Much faster than full database scan
- Requires client-side changes

---

## Implementation Priority

| Priority | Option | Effort | Risk | Impact |
|----------|--------|--------|------|--------|
| 1 | Quick Check | Low | Low | Medium (30-50% faster) |
| 2 | Configurable Mode | Medium | Low | High (user control) |
| 3 | Timeout Fallback | Medium | Low | Medium (prevents hangs) |
| 4 | Skip for Large Files | Low | Medium | High (eliminates delay) |
| 5 | Checksum Validation | High | Low | High (requires client changes) |

---

## Performance Estimates

Based on typical disk I/O performance:

| Database Size | integrity_check | quick_check | Skip |
|--------------|-----------------|-------------|------|
| 1 GB | ~2 min | ~1 min | 0 sec |
| 5 GB | ~10 min | ~5 min | 0 sec |
| 16 GB | ~30+ min | ~15 min | 0 sec |
| 50 GB | ~2+ hours | ~1 hour | 0 sec |

*Estimates assume local SSD storage. Network storage will be significantly slower.*

---

## Additional Considerations

### Indexes Will Not Help

Adding indexes to SQLite tables will **not** improve integrity check performance. The integrity check must read all data regardless of indexes. In fact, indexes add more B-tree structures that must be validated.

### Network vs Local Storage

If `T:\ImportData` is network storage:
- Consider extracting to local SSD first
- Network latency multiplies with millions of page reads
- Local extraction + network copy may be faster

### Progress Reporting

Consider adding progress reporting for long-running operations:

```csharp
// SQLite doesn't natively support progress callbacks for PRAGMA commands
// Alternative: Estimate based on file size and report progress by time
var fileSize = new FileInfo(sqlitePath).Length;
var estimatedSeconds = fileSize / (100 * 1024 * 1024); // ~100MB/sec estimate
```

---

## Recommended Immediate Action

1. **Short Term**: Change `PRAGMA integrity_check` to `PRAGMA quick_check` in `DatabaseValidator.cs`
2. **Medium Term**: Add configuration option for integrity check mode
3. **Long Term**: Implement checksum-based validation with client-side support

---

## References

- [SQLite PRAGMA documentation](https://www.sqlite.org/pragma.html#pragma_integrity_check)
- [SQLite File Format](https://www.sqlite.org/fileformat.html)
- Current implementation: `NTFSPermsUploader.Core/Validation/DatabaseValidator.cs:52-93`
