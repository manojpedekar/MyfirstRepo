# MFT Test Script Performance Analysis

**Script:** `mft_test.py`
**Analysis Date:** 2026-01-31
**Current Performance:** ~875-1,000 records/sec → **Optimized** (see below)
**Target Volume:** 2,049,007 MFT records
**Current Scan Time:** ~35-40 minutes → **Projected: 6-8 minutes**

---

## Optimization Status

**All Priority 1-6 optimizations have been implemented.** The code has been updated with the following changes:

| Optimization | Status | Implementation |
|-------------|--------|----------------|
| Early size filtering | ✅ Applied | Directory flag checked first via `record.header.Flags & 0x02`, size check before name resolution |
| Lazy path resolution | ✅ Applied | `--no-paths` flag / `resolve_paths=False` parameter skips `full_path()` calls |
| Simplify FILE_NAME selection | ✅ Applied | Takes `fn_attrs[-1]` (last attribute) instead of iterating all |
| Replace hasattr() | ✅ Applied | All hot-path `hasattr()` calls replaced with `try/except` |
| Optional timestamps | ✅ Applied | `--no-timestamps` flag / `include_timestamps=False` parameter |
| Cache psutil.Process | ✅ Applied | `_PROCESS` cached at module level |

### New CLI Flags

```bash
python mft_test.py --no-paths       # Skip full path resolution (faster)
python mft_test.py --no-timestamps  # Skip timestamp extraction (faster)
python mft_test.py --no-paths --no-timestamps  # Maximum speed mode
```

---

## ⚠️ Performance Investigation Update (2026-01-31)

**See: [MFT_PERFORMANCE_INVESTIGATION.md](MFT_PERFORMANCE_INVESTIGATION.md)**

Testing revealed that the optimizations above provide only **~6% improvement** (872 → 922 records/sec), not the projected 4-6x speedup. Profiling identified the actual bottleneck:

| Component | Time Share | Description |
|-----------|-----------|-------------|
| `record.attributes` parsing | **87%** | dissect.ntfs parses ALL attributes on first access |
| Python-level code | 13% | What our optimizations targeted |

**Key finding:** The dissect.ntfs library design parses all attributes for a record when any attribute is accessed. Our optimizations targeted 13% of processing time while 87% is library overhead.

**Actual performance:**
- Current: ~870-920 records/sec
- Scan time for 2M records: ~39 minutes
- Theoretical maximum (header only): 6,461 records/sec

To achieve 4,000+ records/sec would require raw MFT binary parsing, bypassing the library's attribute parser.

---

## Salt Execution Module Compatibility

This analysis includes compatibility notes for implementing these optimizations in a custom Salt execution module. Each recommendation is marked with:

- **SALT: YES** — Fully compatible with Salt execution modules
- **SALT: PARTIAL** — Compatible with caveats or additional considerations
- **SALT: NO** — Not viable for Salt execution modules

### Salt Environment Constraints

Salt execution modules operate under specific constraints:

1. **Python Runtime:** Salt minions use CPython (typically 3.8+). Alternative runtimes like PyPy are not available.
2. **Dependencies:** External packages must be installed on each minion. Prefer stdlib or packages already in Salt's dependency tree.
3. **Single-threaded Model:** Salt execution modules run synchronously. Multiprocessing is possible but adds complexity.
4. **Serialization:** Return values must be JSON-serializable for transport back to the master.
5. **Timeouts:** Long-running operations may hit Salt's timeout limits (default 300 seconds).
6. **Code Distribution:** Modules sync to minions as `.py` files. Compiled extensions (Cython) require separate deployment.

---

## Executive Summary

The script successfully parses the MFT using `dissect.ntfs` but operates at approximately 1/10th to 1/15th of the theoretical maximum speed. The primary bottlenecks are:

1. Expensive `full_path()` resolution for every matching file
2. Iterating all FILE_NAME attributes to find the longest name
3. Excessive `hasattr()` checks in the hot loop
4. Extracting timestamps for all matching files regardless of need

With the optimizations outlined below, performance could potentially improve to **5,000-10,000+ records/sec**.

---

## Current Architecture

```
for each MFT segment:
    ├── Check if record is None
    ├── Check if record is in use (hasattr + property access)
    ├── Determine file vs directory (multiple hasattr checks)
    ├── Get file size from DATA attribute
    ├── [If size >= threshold]
    │   ├── Iterate ALL FILE_NAME attributes to find longest
    │   ├── Call full_path() to resolve complete path  ← EXPENSIVE
    │   ├── Get STANDARD_INFORMATION for timestamps
    │   └── Create dict and append to results list
    └── Update statistics
```

---

## Identified Bottlenecks

### 1. `full_path()` Resolution (Lines 179-183) — **HIGH IMPACT**

**Problem:** The `full_path()` method traverses parent directory references up to the root, requiring multiple MFT lookups per file.

**Evidence:** This method is called for every file matching the size filter. For 357 files >100MB, this adds significant overhead, but the real cost is that the library may be doing work even for the call setup.

**Current Code:**
```python
if hasattr(best_fn, 'full_path') and callable(best_fn.full_path):
    try:
        full_path = best_fn.full_path()
    except Exception:
        full_path = None
```

**Estimated Impact:** 10-30% of total processing time for matching files.

---

### 2. FILE_NAME Attribute Iteration (Lines 171-175) — **MEDIUM-HIGH IMPACT**

**Problem:** Iterates through ALL FILE_NAME attributes for every file record to find the longest name (Win32 vs DOS 8.3).

**Current Code:**
```python
for fn_attr in record.attributes.FILE_NAME:
    name = getattr(fn_attr, 'file_name', '') or ''
    if len(name) > best_len:
        best_len = len(name)
        best_fn = fn_attr
```

**Analysis:**
- Most files have 2 FILE_NAME attributes (Win32 + DOS 8.3 short name)
- This loop runs 1,637,463 times (once per file record)
- Each iteration: attribute access + getattr + string length check

**Estimated Impact:** 15-25% of total processing time.

---

### 3. Excessive `hasattr()` Calls — **MEDIUM IMPACT**

**Problem:** `hasattr()` internally uses `getattr()` wrapped in try/except, making it slower than direct attribute access.

**Locations:**
- Line 118: `hasattr(record, 'in_use')`
- Line 127: `hasattr(record, 'is_file')`
- Line 129: `hasattr(record, 'is_dir')`
- Line 131: `hasattr(record, 'is_directory')`
- Line 179: `hasattr(best_fn, 'full_path') and callable(best_fn.full_path)`

**Analysis:** Called 5+ times per record × 2M records = 10M+ hasattr calls.

**Estimated Impact:** 5-10% of total processing time.

---

### 4. Timestamp Extraction (Lines 198-204) — **LOW-MEDIUM IMPACT**

**Problem:** Extracts mtime/atime for every matching file, even when timestamps aren't needed for the use case.

**Current Code:**
```python
si = next(iter(record.attributes.STANDARD_INFORMATION), None)
if si:
    mtime = getattr(si, 'mtime', None)
    atime = getattr(si, 'atime', None)
```

**Estimated Impact:** 3-5% for matching files.

---

### 5. Progress Reporting Overhead (Lines 103-109) — **LOW IMPACT**

**Problem:** Creates a new `psutil.Process()` object every 100,000 records.

**Current Code:**
```python
def get_memory_mb():
    if HAS_PSUTIL:
        return psutil.Process().memory_info().rss / (1024 * 1024)
```

**Estimated Impact:** <1% (only called 20 times for 2M records).

---

### 6. Dictionary Creation Per File (Lines 206-212) — **LOW IMPACT**

**Problem:** Creates a new dictionary for each matching file with string formatting.

```python
files.append({
    "path": display_path,
    "size": size,
    "size_human": format_size(size),
    "modified": mtime.isoformat() if mtime else None,
    "accessed": atime.isoformat() if atime else None,
})
```

**Estimated Impact:** Negligible for current file counts (<1000 files).

---

## Optimization Recommendations

### Priority 1: Early Size Filtering (Restructure Loop Order)

**SALT: YES** — Pure Python logic change, fully compatible.

**Current order:** Check file type → Get size → Filter → Get name
**Optimal order:** Get size → Filter → Check file type → Get name

**Rationale:** Size check via `DATA.header.size` is fast. By checking size FIRST, we can skip all subsequent work for small files (99%+ of records).

**Expected Improvement:** 20-40% faster

**Salt Implementation Notes:**
- No special considerations. This is a straightforward loop restructure.
- Works identically in Salt execution module context.

---

### Priority 2: Lazy Path Resolution

**SALT: YES** — Pure Python logic change, fully compatible.

**Approach:** Don't call `full_path()` during the scan. Store the FILE_NAME attribute reference and resolve paths only during output.

**Alternative:** Add `paths=False` parameter that outputs only filenames, not full paths.

**Expected Improvement:** 10-20% faster for scans with many matching files

**Salt Implementation Notes:**
- Expose as a function parameter: `def mft_large_files(drive='C', min_size_mb=100, resolve_paths=True)`
- When `resolve_paths=False`, return filenames only — faster for simple size audits.
- Full paths are often needed for Salt file operations, so default to `True`.

---

### Priority 3: Simplify FILE_NAME Selection

**SALT: YES** — Pure Python logic change, fully compatible.

**Approach:** Instead of iterating all FILE_NAME attributes:
- Take the LAST FILE_NAME attribute (typically Win32 namespace)
- Or take the first one with length > 12 (not DOS 8.3)

```python
# Simplified: take last FILE_NAME attribute
fn_attrs = list(record.attributes.FILE_NAME)
if fn_attrs:
    best_fn = fn_attrs[-1]  # Last is usually Win32
```

**Expected Improvement:** 10-15% faster

**Salt Implementation Notes:**
- No special considerations. This optimization reduces CPU cycles per record.
- May occasionally return DOS 8.3 name if Win32 name is missing (rare edge case).

---

### Priority 4: Replace hasattr() with Direct Access

**SALT: YES** — Pure Python logic change, fully compatible.

**Approach:** Use try/except or getattr with defaults instead of hasattr checks.

```python
# Instead of:
if hasattr(record, 'is_file'):
    is_file = record.is_file()

# Use:
try:
    is_file = record.is_file()
except AttributeError:
    is_file = False
```

**Expected Improvement:** 5-10% faster

**Salt Implementation Notes:**
- Standard Python optimization pattern.
- Improves performance in Salt's CPython environment.

---

### Priority 5: Optional Timestamp Extraction

**SALT: YES** — Pure Python logic change, fully compatible.

**Approach:** Add `timestamps=False` parameter to skip STANDARD_INFORMATION extraction.

**Expected Improvement:** 3-5% faster when disabled

**Salt Implementation Notes:**
- Expose as function parameter: `def mft_large_files(..., include_timestamps=False)`
- Timestamps are useful for age-based queries; make it optional.
- Reduces return payload size when disabled.

---

### Priority 6: Cache psutil.Process Object

**SALT: PARTIAL** — Compatible, but psutil may not be available on all minions.

```python
# At module level or in scan_mft:
_process = psutil.Process() if HAS_PSUTIL else None

def get_memory_mb():
    if _process:
        return _process.memory_info().rss / (1024 * 1024)
    return 0
```

**Expected Improvement:** <1% (minimal, but good practice)

**Salt Implementation Notes:**
- `psutil` is not a Salt dependency and may not be installed on minions.
- For a Salt module, consider removing memory tracking entirely, or use it only for debugging.
- Alternative: Use `resource` module on Linux (stdlib), but not available on Windows.
- Recommendation: Skip memory tracking in production Salt module.

---

## Advanced Optimizations

### Use Generator Instead of List for Results

**SALT: PARTIAL** — Generators work, but Salt serializes the final result anyway.

For very large result sets, yield results instead of accumulating in a list:

```python
def scan_mft_iter(drive, min_size_bytes):
    for record in fs.mft.segments():
        # ... processing ...
        yield file_info  # Instead of files.append(file_info)
```

**Benefit:** Lower memory usage, faster time-to-first-result.

**Salt Implementation Notes:**
- Salt execution module return values are serialized to JSON/msgpack for transport to the master.
- A generator must be converted to a list before returning: `return list(scan_mft_iter(...))`
- However, using a generator internally still helps:
  - Allows early termination with `--limit` parameter
  - Reduces peak memory if processing in chunks
- For streaming results to master, consider Salt's `runner` or `reactor` patterns instead.

---

### Multiprocessing with Producer-Consumer Pattern

**SALT: PARTIAL** — Possible but adds significant complexity.

```
Producer Thread:     Read MFT segments into queue
Consumer Thread(s):  Process segments, extract attributes
Main Thread:         Aggregate results
```

**Caveat:** MFT reading is I/O bound; parallelism helps more with CPU-bound attribute extraction.

**Expected Improvement:** 2-4x on multi-core systems

**Salt Implementation Notes:**
- Salt minions are single-process by default. Spawning subprocesses works but adds complexity.
- `multiprocessing` module works on Windows but requires `if __name__ == '__main__'` guards.
- Process spawning overhead may negate benefits for short scans.
- Risk: Child processes may not clean up properly if Salt kills the parent.
- Recommendation: Only implement if single-threaded performance is insufficient after other optimizations.
- Alternative: Use `concurrent.futures.ThreadPoolExecutor` for lighter-weight parallelism (GIL limits benefit for CPU-bound work, but helps with I/O).

---

### Use PyPy Instead of CPython

**SALT: NO** — Salt minions run CPython; PyPy is not supported.

The tight loop with many attribute accesses benefits significantly from JIT compilation.

**Expected Improvement:** 2-5x faster with PyPy

**Why Not Compatible:**
- Salt is designed for and tested with CPython only.
- Salt minions install via system packages (apt, yum, etc.) which bundle CPython.
- PyPy would require a completely separate Salt installation and is not officially supported.
- Some Salt modules and dependencies may not be PyPy-compatible.

---

### Cython Compilation

**SALT: NO** — Requires compiled binaries, breaks Salt's module sync mechanism.

Compile the hot loop with Cython for near-C performance.

**Expected Improvement:** 3-10x faster for CPU-bound portions

**Why Not Compatible:**
- Salt syncs execution modules as `.py` files to minions via `saltutil.sync_modules`.
- Cython produces `.pyd` (Windows) or `.so` (Linux) files that are platform-specific.
- Would require:
  - Pre-compiling for every target platform/architecture
  - Separate deployment mechanism (not Salt's module sync)
  - Managing binary compatibility across OS versions
- Maintenance burden is high for marginal benefit.
- Recommendation: If Cython-level performance is needed, consider a standalone compiled tool invoked via `cmd.run` instead.

---

## Benchmarking Recommendations

To validate optimizations, add benchmarking instrumentation:

```python
import cProfile
import pstats

profiler = cProfile.Profile()
profiler.enable()
# ... scan code ...
profiler.disable()
stats = pstats.Stats(profiler).sort_stats('cumulative')
stats.print_stats(20)
```

Key metrics to track:
- `record.attributes.FILE_NAME` iteration time
- `full_path()` call time
- Total time in `hasattr()` calls

---

## Summary Table

| Optimization | Difficulty | Expected Speedup | Risk | Salt Compatible | Status |
|-------------|-----------|------------------|------|-----------------|--------|
| Early size filtering | Low | 20-40% | Low | **YES** | ✅ Applied |
| Lazy path resolution | Medium | 10-20% | Low | **YES** | ✅ Applied |
| Simplify FILE_NAME selection | Low | 10-15% | Low | **YES** | ✅ Applied |
| Replace hasattr() | Low | 5-10% | Low | **YES** | ✅ Applied |
| Optional timestamps | Low | 3-5% | None | **YES** | ✅ Applied |
| Cache psutil.Process | Low | <1% | None | PARTIAL (dependency) | ✅ Applied |
| Generator pattern | Low | Memory savings | None | PARTIAL (serialization) | Not implemented |
| Multiprocessing | High | 100-300% | Medium | PARTIAL (complexity) | Not implemented |
| PyPy runtime | Low | 100-400% | Low | **NO** | N/A |
| Cython compilation | High | 200-900% | Medium | **NO** | N/A |

---

## Salt Execution Module Recommendations

For a production Salt execution module, implement these optimizations in order:

### Recommended (High Value, Low Risk)
1. **Early size filtering** — Restructure loop to check size first
2. **Simplify FILE_NAME selection** — Take last attribute instead of iterating
3. **Replace hasattr()** — Use try/except for faster attribute access
4. **Optional timestamps** — Add `include_timestamps` parameter
5. **Lazy path resolution** — Add `resolve_paths` parameter

### Optional (Situational)
6. **Generator pattern** — Use internally for memory efficiency with large result sets
7. **Skip psutil** — Remove memory tracking or make it debug-only

### Not Recommended for Salt
8. **Multiprocessing** — Only if single-threaded is insufficient; adds significant complexity
9. **PyPy** — Not compatible with Salt's CPython requirement
10. **Cython** — Breaks Salt's module sync mechanism

### Expected Salt Module Performance

With optimizations 1-5 implemented:
- **Projected speed:** 4,000-6,000 records/sec
- **Scan time for 2M records:** 6-8 minutes
- **Compatible with Salt's 300-second default timeout:** Yes (with margin)

For volumes with >3M MFT records, consider increasing Salt's timeout:
```yaml
# In minion config or pillar
timeout: 600
```

---

## Conclusion

~~The current implementation prioritizes correctness and readability over performance. For a feasibility test, this is appropriate. For production use at scale, implementing Priority 1-5 optimizations could improve performance from ~900 records/sec to **4,000-6,000 records/sec**, reducing scan time from ~38 minutes to ~6-8 minutes.~~

~~**Update (2026-01-31):** All Priority 1-6 optimizations have been implemented...~~

**Final Update (2026-01-31):** Performance testing and profiling revealed that the original analysis **incorrectly identified the bottleneck**. See [MFT_PERFORMANCE_INVESTIGATION.md](MFT_PERFORMANCE_INVESTIGATION.md) for full details.

### Actual Results

| Metric | Original Projection | Actual Result |
|--------|---------------------|---------------|
| Processing rate | 4,000-6,000/sec | **872/sec** |
| Scan time (2M records) | 6-8 minutes | **39 minutes** |
| Optimization impact | 4-6x faster | **6% faster** |

### Root Cause

The bottleneck is **dissect.ntfs library attribute parsing** (87% of time), not Python-level inefficiencies (13%). The library parses ALL attributes when `record.attributes` is accessed, even if only one attribute is needed.

### Recommendations

1. **Short term:** Accept ~870 records/sec performance; configure Salt timeout to 3000+ seconds
2. **Medium term:** Implement raw MFT binary parsing to bypass library overhead (could achieve 5,000+ records/sec)
3. **Long term:** Consider compiled language or alternative library for hot path

**For Salt execution modules:** Current performance is acceptable for scheduled batch operations. The optimizations implemented improve code quality and provide marginal speed gains. For production deployments with >2M MFT records, plan for 30-40 minute scan times.
