#!/usr/bin/env python3
"""
MFT Parsing Feasibility Test
Tests dissect.ntfs performance for potential Salt execution module use.

Requirements:
    pip install dissect.ntfs

Usage (run as Administrator):
    python mft_test.py
    python mft_test.py --drive D --min-size 100
    python mft_test.py --output results.json
    python mft_test.py --no-paths --no-timestamps   # Fastest mode
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime

try:
    from dissect.ntfs import NTFS
    from dissect.ntfs.exceptions import Error as NTFSError
except ImportError:
    print("ERROR: dissect.ntfs not installed")
    print("Run: pip install dissect.ntfs")
    sys.exit(1)

try:
    import psutil
    HAS_PSUTIL = True
    # Cache the Process object to avoid creating new one each call
    _PROCESS = psutil.Process()
except ImportError:
    HAS_PSUTIL = False
    _PROCESS = None


def get_memory_mb():
    """Get current process memory usage in MB."""
    if _PROCESS:
        return _PROCESS.memory_info().rss / (1024 * 1024)
    return 0


def format_size(size_bytes):
    """Convert bytes to human-readable format."""
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size_bytes < 1024:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024
    return f"{size_bytes:.1f} PB"


def scan_mft(drive, min_size_bytes, progress_interval=100000,
              resolve_paths=True, include_timestamps=True):
    """
    Scan MFT and return file information.

    Args:
        drive: Drive letter (e.g., 'C')
        min_size_bytes: Minimum file size to include
        progress_interval: Print progress every N records
        resolve_paths: If True, resolve full paths (slower). If False, return filenames only.
        include_timestamps: If True, include mtime/atime. If False, skip for speed.

    Returns:
        dict with scan results and statistics
    """
    volume_path = f"\\\\.\\{drive}:"
    
    print(f"Opening volume: {volume_path}")
    print(f"Minimum file size: {format_size(min_size_bytes)}")
    print("-" * 60)
    
    start_time = time.time()
    start_memory = get_memory_mb()
    
    files = []
    stats = {
        "total_records": 0,
        "file_records": 0,
        "dir_records": 0,
        "files_matching_size": 0,
        "errors": 0,
        "total_size_bytes": 0,
    }
    
    try:
        with open(volume_path, "rb") as fh:
            fs = NTFS(fh)
            
            # Print volume info if available
            try:
                if hasattr(fs, 'volume_name') and fs.volume_name:
                    print(f"Volume name: {fs.volume_name}")
                if hasattr(fs, 'serial') and fs.serial:
                    print(f"Serial: {fs.serial:X}")
            except Exception:
                print("(Volume metadata not available)")
            print("-" * 60)
            print("Scanning MFT records...")
            
            for record in fs.mft.segments():
                stats["total_records"] += 1

                # Progress indicator
                if stats["total_records"] % progress_interval == 0:
                    elapsed = time.time() - start_time
                    rate = stats["total_records"] / elapsed
                    mem = get_memory_mb()
                    print(f"  Processed {stats['total_records']:,} records "
                          f"({rate:,.0f}/sec, {mem:.0f} MB RAM, "
                          f"{stats['files_matching_size']:,} files matched)")

                try:
                    # Skip if no valid record
                    if record is None:
                        continue

                    # OPTIMIZATION 1: Check directory flag FIRST (fast header access)
                    # Skip directories immediately - they don't have DATA attributes
                    # Note: Flags is capital F in dissect.ntfs
                    try:
                        is_dir = bool(record.header.Flags & 0x02)
                    except Exception:
                        continue

                    if is_dir:
                        stats["dir_records"] += 1
                        continue

                    stats["file_records"] += 1

                    # OPTIMIZATION 2: Early size filtering for files only
                    # Get DATA attribute size (only for files, not directories)
                    size = 0
                    try:
                        data_attr = next(iter(record.attributes.DATA), None)
                        if data_attr and data_attr.header:
                            size = data_attr.header.size or 0
                    except Exception:
                        pass

                    if size < min_size_bytes:
                        continue

                    # OPTIMIZATION 3: Simplify FILE_NAME selection
                    # Take the last FILE_NAME attribute (typically Win32 namespace)
                    # instead of iterating all to find longest
                    full_path = None
                    file_name = None

                    try:
                        fn_attrs = list(record.attributes.FILE_NAME)
                        if fn_attrs:
                            # Last attribute is typically the Win32 long name
                            best_fn = fn_attrs[-1]
                            file_name = best_fn.file_name

                            # OPTIMIZATION 4: Lazy path resolution
                            # Only resolve full path if requested
                            if resolve_paths:
                                try:
                                    full_path = best_fn.full_path()
                                except Exception:
                                    pass
                    except Exception:
                        pass

                    if not full_path and not file_name:
                        continue

                    display_path = full_path or file_name

                    stats["files_matching_size"] += 1
                    stats["total_size_bytes"] += size

                    # OPTIMIZATION 5: Optional timestamp extraction
                    mtime = None
                    atime = None
                    if include_timestamps:
                        try:
                            si = next(iter(record.attributes.STANDARD_INFORMATION), None)
                            if si:
                                mtime = getattr(si, 'mtime', None)
                                atime = getattr(si, 'atime', None)
                        except Exception:
                            pass

                    file_info = {
                        "path": display_path,
                        "size": size,
                        "size_human": format_size(size),
                    }
                    if include_timestamps:
                        file_info["modified"] = mtime.isoformat() if mtime else None
                        file_info["accessed"] = atime.isoformat() if atime else None

                    files.append(file_info)

                except NTFSError:
                    stats["errors"] += 1
                except Exception:
                    stats["errors"] += 1
                    
    except PermissionError:
        print("\nERROR: Access denied. Run as Administrator.")
        sys.exit(1)
    except FileNotFoundError:
        print(f"\nERROR: Volume {volume_path} not found.")
        sys.exit(1)
    
    elapsed = time.time() - start_time
    end_memory = get_memory_mb()
    
    stats["elapsed_seconds"] = round(elapsed, 2)
    stats["records_per_second"] = round(stats["total_records"] / elapsed, 0)
    stats["memory_start_mb"] = round(start_memory, 1)
    stats["memory_end_mb"] = round(end_memory, 1)
    stats["memory_used_mb"] = round(end_memory - start_memory, 1)
    
    return {
        "drive": drive,
        "scan_time": datetime.now().isoformat(),
        "stats": stats,
        "files": files,
    }


def print_summary(results):
    """Print scan summary to console."""
    stats = results["stats"]
    
    print("\n" + "=" * 60)
    print("SCAN COMPLETE")
    print("=" * 60)
    print(f"Drive:                  {results['drive']}:")
    print(f"Total MFT records:      {stats['total_records']:,}")
    print(f"  - Directories:        {stats['dir_records']:,}")
    print(f"  - Files:              {stats['file_records']:,}")
    print(f"  - Errors/skipped:     {stats['errors']:,}")
    print(f"Files matching filter:  {stats['files_matching_size']:,}")
    print(f"Total size (matched):   {format_size(stats['total_size_bytes'])}")
    print("-" * 60)
    print(f"Elapsed time:           {stats['elapsed_seconds']:.1f} seconds")
    print(f"Processing rate:        {stats['records_per_second']:,.0f} records/sec")
    if HAS_PSUTIL:
        print(f"Memory used:            {stats['memory_used_mb']:.0f} MB")
    else:
        print("Memory used:            (install psutil for memory tracking)")
    print("=" * 60)
    
    # Show top 10 largest files
    if results["files"]:
        print("\nTop 10 largest files:")
        print("-" * 60)
        sorted_files = sorted(results["files"], key=lambda x: x["size"], reverse=True)
        for i, f in enumerate(sorted_files[:10], 1):
            print(f"  {i:2}. {f['size_human']:>10}  {f['path']}")


def main():
    parser = argparse.ArgumentParser(
        description="Test MFT parsing performance with dissect.ntfs"
    )
    parser.add_argument(
        "--drive", "-d",
        default="C",
        help="Drive letter to scan (default: C)"
    )
    parser.add_argument(
        "--min-size", "-m",
        type=int,
        default=1,
        help="Minimum file size in MB (default: 1)"
    )
    parser.add_argument(
        "--output", "-o",
        help="Output JSON file (optional)"
    )
    parser.add_argument(
        "--files-only",
        action="store_true",
        help="Output only the files array (smaller JSON)"
    )
    parser.add_argument(
        "--no-paths",
        action="store_true",
        help="Skip full path resolution (faster, returns filenames only)"
    )
    parser.add_argument(
        "--no-timestamps",
        action="store_true",
        help="Skip timestamp extraction (faster)"
    )

    args = parser.parse_args()
    
    # Check for admin
    if os.name == "nt":
        try:
            import ctypes
            if not ctypes.windll.shell32.IsUserAnAdmin():
                print("WARNING: Not running as Administrator. This will likely fail.")
                print("Right-click and 'Run as administrator'")
                print()
        except Exception:
            pass
    
    min_size_bytes = args.min_size * 1024 * 1024
    
    print("=" * 60)
    print("MFT PARSING FEASIBILITY TEST")
    print("=" * 60)
    if not HAS_PSUTIL:
        print("TIP: pip install psutil for memory tracking")
    print()
    
    results = scan_mft(
        args.drive,
        min_size_bytes,
        resolve_paths=not args.no_paths,
        include_timestamps=not args.no_timestamps
    )
    print_summary(results)
    
    if args.output:
        output_data = results["files"] if args.files_only else results
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(output_data, f, indent=2, default=str)
        print(f"\nResults written to: {args.output}")
        print(f"File size: {format_size(os.path.getsize(args.output))}")


if __name__ == "__main__":
    main()
