# MFT Performance Investigation Report

**Date:** 2026-01-31
**System:** Laptop with NVMe SSD
**Issue:** Actual performance (~870 records/sec) significantly below projected (4,000-6,000 records/sec)

---

## Executive Summary

The performance gap between projected and actual results is due to an incorrect assumption in the original analysis. **The bottleneck is not in Python-level code optimizations but in the dissect.ntfs library's attribute parsing design.**

| Metric | Projected | Actual | Gap |
|--------|-----------|--------|-----|
| Processing rate | 4,000-6,000/sec | 872/sec | **85% slower** |
| Scan time (2M records) | 6-8 minutes | 39 minutes | **5x longer** |

---

## Root Cause Analysis

### Profiling Results

Two profiling runs were conducted on 50,000 MFT records:

#### Test 1: Minimal Access (header flags only)
```
Processing rate: 6,461 records/sec ✓
Time: 7.7 seconds
```

#### Test 2: Full Attribute Access (DATA, FILE_NAME, timestamps)
```
Processing rate: 464 records/sec ✗
Time: 107.7 seconds (14x slower)
```

### The Actual Bottleneck

**Time breakdown from profiling (107.7 seconds total):**

| Component | Time (sec) | % of Total | Description |
|-----------|-----------|------------|-------------|
| `record.attributes` | 93.9 | **87%** | Lazy property that parses ALL attributes |
| C-struct parsing | 72.3 | 67% | `dissect.cstruct` structure parsing |
| Attribute init | 48.3 | 45% | `ntfs/attr.py` attribute object creation |
| Header parsing | 43.2 | 40% | `_ATTRIBUTE_RECORD_HEADER._read` |
| FILE_NAME parsing | 18.1 | 17% | `_FILE_NAME._read` for all FILE_NAME attrs |
| Disk I/O | 3.3 | 3% | Actual disk reads |

*Note: Times overlap as they're cumulative (child functions included in parent)*

### Key Finding

**The dissect.ntfs library parses ALL attributes whenever `record.attributes` is accessed, even if you only need one attribute (like DATA size).**

```python
# This innocent-looking code:
data_attr = next(iter(record.attributes.DATA), None)

# Actually triggers:
# 1. Parse ALL attributes for the record (not just DATA)
# 2. Create Attribute objects for each (~5-10 per record)
# 3. Parse C-structures for each attribute header
# 4. Parse attribute-specific data (FILE_NAME, etc.)
```

This is a library design choice - `record.attributes` is a `@cached_property` that parses everything on first access.

---

## Why Original Optimizations Didn't Help

The original analysis targeted Python-level inefficiencies:

| Optimization | Expected Impact | Actual Impact | Why |
|-------------|-----------------|---------------|-----|
| Early size filtering | 20-40% | **<5%** | Still must access `record.attributes` to get DATA size |
| Lazy path resolution | 10-20% | **<2%** | `full_path()` only 7.9s of 107s total |
| Simplify FILE_NAME | 10-15% | **<1%** | FILE_NAME already parsed when attributes accessed |
| Replace hasattr() | 5-10% | **<1%** | Negligible vs 93s attribute parsing |
| Optional timestamps | 3-5% | **<1%** | STANDARD_INFORMATION already parsed |

**The optimizations targeted ~50% of a 10% slice, not the 90% bottleneck.**

---

## Recommendations

### Option 1: Raw MFT Parsing (High Impact, High Effort)

Bypass dissect.ntfs attribute parsing and read MFT records directly:

```python
# MFT record structure (simplified)
# Offset 0x00: Signature "FILE"
# Offset 0x14: First attribute offset
# Offset 0x16: Flags (in_use, directory)
#
# Attribute header:
# Offset 0x00: Type (0x30=FILE_NAME, 0x80=DATA)
# Offset 0x04: Length
# Offset 0x10: Resident flag
# For resident DATA: Offset 0x10 has size
# For non-resident DATA: Offset 0x28/0x30 has real_size

def get_file_size_fast(record_bytes):
    """Extract DATA attribute size without full parsing."""
    # Parse just enough to find DATA attribute and its size
    # Skip full dissect.ntfs attribute parsing
    pass
```

**Expected improvement:** 5-10x faster (approaching 6,000+ records/sec)
**Effort:** High - requires understanding MFT binary format
**Risk:** Medium - must handle edge cases (sparse, compressed, multiple DATA streams)

### Option 2: Use dissect.ntfs MFT Iterator Differently (Medium Impact, Low Effort)

Check if dissect.ntfs provides a lower-level API:

```python
# Instead of:
for record in fs.mft.segments():
    data = record.attributes.DATA  # Parses all attributes

# Check if library supports:
for record in fs.mft.segments():
    # Access raw record data before full parsing
    raw = record._buf  # May exist
    # Or use record.header only (already fast at 6,461/sec)
```

**Expected improvement:** Unknown - depends on library internals
**Effort:** Low - just API exploration
**Risk:** Low

### Option 3: Pre-filter by Record Header (Low Impact, Low Effort)

Skip attribute parsing for directories entirely:

```python
for record in fs.mft.segments():
    # This is already fast (6,461/sec)
    if record.header.Flags & 0x02:  # Directory
        continue

    # Only parse attributes for files
    # Still slow but skips 20% of records (411k directories)
```

**Current implementation already does this.** The ~20% reduction in attribute parsing is reflected in results.

**Expected improvement:** Already applied
**Effort:** None
**Risk:** None

### Option 4: Alternative Library or Tool (Variable Impact)

Consider alternatives to dissect.ntfs:

1. **python-ntfs** - Another Python NTFS library, may have different performance
2. **Raw $MFT file parsing** - Copy $MFT file, parse offline
3. **Windows API** - Use `NtQueryDirectoryFile` or similar (different approach entirely)
4. **External tool** - Call optimized C/C++ tool, parse output

**Expected improvement:** Variable
**Effort:** High - requires evaluation and potential rewrite
**Risk:** Variable

### Option 5: Accept Current Performance (No Impact, No Effort)

For 2M records at 872/sec:
- Scan time: ~39 minutes
- Still faster than filesystem enumeration via OS APIs
- Acceptable for scheduled/batch operations

**Mitigations:**
- Run during off-hours
- Increase Salt timeout to 3000+ seconds
- Use `--no-paths --no-timestamps` for marginal improvement

---

## Recommended Path Forward

### Short Term (Immediate)

1. **Accept current performance** for initial deployment
2. Document 30-40 minute scan time as expected
3. Configure Salt timeout appropriately (3000+ seconds)

### Medium Term (If Performance Critical)

1. **Investigate raw MFT parsing** - Read MFT record bytes directly, parse only:
   - Record header (for in_use, directory flags)
   - DATA attribute header (for size)
   - FILE_NAME attribute (for name)

2. **Prototype minimal parser:**
   ```python
   def parse_mft_record_minimal(record_bytes):
       """Parse only what we need, skip full dissect parsing."""
       # ~100 lines of binary parsing code
       # Should achieve 5,000+ records/sec
   ```

### Long Term

1. **Contribute to dissect.ntfs** - Add selective attribute parsing API
2. **Consider Rust/C extension** - For maximum performance
3. **Evaluate if MFT scanning is the right approach** vs. other enumeration methods

---

## Benchmark Data

### Full Scan Results (2,049,007 records)

```
Drive:                  C:
Total MFT records:      2,049,007
  - Directories:        411,543 (20%)
  - Files:              1,637,464 (80%)
Files matching 1MB+:    33,959
Elapsed time:           2350.3 seconds (39.2 minutes)
Processing rate:        872 records/sec
Memory used:            154 MB
```

### With --no-paths --no-timestamps

```
Processing rate:        922 records/sec (+6%)
Elapsed time:           2223.2 seconds (37.1 minutes)
```

### Theoretical Maximum (header only)

```
Processing rate:        6,461 records/sec
Projected time:         5.3 minutes
```

---

## Conclusion

The original performance analysis identified real inefficiencies but missed that **87% of processing time is spent in library-level attribute parsing**, not in the Python code we optimized.

To achieve the projected 4,000-6,000 records/sec, we would need to either:
1. Implement custom raw MFT parsing (bypassing dissect.ntfs for attribute extraction)
2. Find/create a more efficient NTFS library
3. Use a compiled language for the hot path

For now, the ~870 records/sec performance is acceptable for batch operations, and the implemented optimizations provide marginal improvements and cleaner code architecture.
