#!/usr/bin/env python3
"""
Filesystem Enumeration using Windows NtQueryDirectoryFile API

Uses low-level Windows NT API for directory enumeration to compare
performance against MFT parsing approach.

Requirements:
    - Windows OS
    - No admin rights required (unlike MFT parsing)

Usage:
    python ntquery_test.py
    python ntquery_test.py --drive D --min-size 100
    python ntquery_test.py --output results.json
"""

import argparse
import ctypes
import ctypes.wintypes as wintypes
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    import psutil
    HAS_PSUTIL = True
    _PROCESS = psutil.Process()
except ImportError:
    HAS_PSUTIL = False
    _PROCESS = None

# ============================================================================
# Windows NT API Definitions
# ============================================================================

ntdll = ctypes.WinDLL('ntdll')
kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)

# NT Status codes
STATUS_SUCCESS = 0
STATUS_NO_MORE_FILES = 0x80000006
STATUS_BUFFER_OVERFLOW = 0x80000005

# File information classes
FileDirectoryInformation = 1
FileBothDirectoryInformation = 3
FileIdBothDirectoryInformation = 37

# File attributes
FILE_ATTRIBUTE_DIRECTORY = 0x10
FILE_ATTRIBUTE_REPARSE_POINT = 0x400

# Access and share modes
FILE_LIST_DIRECTORY = 0x0001
FILE_TRAVERSE = 0x0020
SYNCHRONIZE = 0x00100000
FILE_SHARE_READ = 0x00000001
FILE_SHARE_WRITE = 0x00000002
FILE_SHARE_DELETE = 0x00000004

# Creation disposition
FILE_OPEN = 1

# Create options
FILE_DIRECTORY_FILE = 0x00000001
FILE_SYNCHRONOUS_IO_NONALERT = 0x00000020
FILE_OPEN_FOR_BACKUP_INTENT = 0x00004000

# Object attributes
OBJ_CASE_INSENSITIVE = 0x00000040

NTSTATUS = ctypes.c_long
HANDLE = wintypes.HANDLE
PVOID = ctypes.c_void_p
ULONG = wintypes.ULONG
USHORT = wintypes.USHORT
WCHAR = wintypes.WCHAR
BOOLEAN = ctypes.c_ubyte
LARGE_INTEGER = ctypes.c_longlong


class UNICODE_STRING(ctypes.Structure):
    _fields_ = [
        ('Length', USHORT),
        ('MaximumLength', USHORT),
        ('Buffer', ctypes.POINTER(WCHAR)),
    ]


class OBJECT_ATTRIBUTES(ctypes.Structure):
    _fields_ = [
        ('Length', ULONG),
        ('RootDirectory', HANDLE),
        ('ObjectName', ctypes.POINTER(UNICODE_STRING)),
        ('Attributes', ULONG),
        ('SecurityDescriptor', PVOID),
        ('SecurityQualityOfService', PVOID),
    ]


class IO_STATUS_BLOCK(ctypes.Structure):
    _fields_ = [
        ('Status', NTSTATUS),
        ('Information', PVOID),
    ]


class FILE_DIRECTORY_INFORMATION(ctypes.Structure):
    _fields_ = [
        ('NextEntryOffset', ULONG),
        ('FileIndex', ULONG),
        ('CreationTime', LARGE_INTEGER),
        ('LastAccessTime', LARGE_INTEGER),
        ('LastWriteTime', LARGE_INTEGER),
        ('ChangeTime', LARGE_INTEGER),
        ('EndOfFile', LARGE_INTEGER),
        ('AllocationSize', LARGE_INTEGER),
        ('FileAttributes', ULONG),
        ('FileNameLength', ULONG),
        ('FileName', WCHAR * 1),  # Variable length
    ]


# Function prototypes
ntdll.NtOpenFile.argtypes = [
    ctypes.POINTER(HANDLE),
    ULONG,
    ctypes.POINTER(OBJECT_ATTRIBUTES),
    ctypes.POINTER(IO_STATUS_BLOCK),
    ULONG,
    ULONG,
]
ntdll.NtOpenFile.restype = NTSTATUS

ntdll.NtQueryDirectoryFile.argtypes = [
    HANDLE,
    HANDLE,
    PVOID,
    PVOID,
    ctypes.POINTER(IO_STATUS_BLOCK),
    PVOID,
    ULONG,
    ctypes.c_int,
    BOOLEAN,
    ctypes.POINTER(UNICODE_STRING),
    BOOLEAN,
]
ntdll.NtQueryDirectoryFile.restype = NTSTATUS

ntdll.NtClose.argtypes = [HANDLE]
ntdll.NtClose.restype = NTSTATUS

ntdll.RtlInitUnicodeString.argtypes = [
    ctypes.POINTER(UNICODE_STRING),
    ctypes.c_wchar_p,
]
ntdll.RtlInitUnicodeString.restype = None


# ============================================================================
# Helper Functions
# ============================================================================

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


def filetime_to_datetime(filetime):
    """Convert Windows FILETIME (100ns since 1601) to datetime."""
    if filetime <= 0:
        return None
    try:
        # FILETIME is 100-nanosecond intervals since January 1, 1601
        EPOCH_DIFF = 116444736000000000  # Difference between 1601 and 1970 in 100ns
        timestamp = (filetime - EPOCH_DIFF) / 10000000
        if timestamp < 0:
            return None
        return datetime.fromtimestamp(timestamp)
    except (OSError, OverflowError, ValueError):
        return None


def open_directory_nt(path):
    """Open a directory using NtOpenFile."""
    # Convert path to NT path format
    if path.startswith('\\\\?\\'):
        nt_path = path.replace('\\\\?\\', '\\??\\')
    elif path.startswith('\\??\\'):
        nt_path = path
    elif len(path) >= 2 and path[1] == ':':
        nt_path = f'\\??\\{path}'
    else:
        nt_path = path

    # Initialize UNICODE_STRING
    us = UNICODE_STRING()
    ntdll.RtlInitUnicodeString(ctypes.byref(us), nt_path)

    # Initialize OBJECT_ATTRIBUTES
    oa = OBJECT_ATTRIBUTES()
    oa.Length = ctypes.sizeof(OBJECT_ATTRIBUTES)
    oa.RootDirectory = None
    oa.ObjectName = ctypes.pointer(us)
    oa.Attributes = OBJ_CASE_INSENSITIVE
    oa.SecurityDescriptor = None
    oa.SecurityQualityOfService = None

    # Open directory
    handle = HANDLE()
    io_status = IO_STATUS_BLOCK()

    status = ntdll.NtOpenFile(
        ctypes.byref(handle),
        FILE_LIST_DIRECTORY | SYNCHRONIZE,
        ctypes.byref(oa),
        ctypes.byref(io_status),
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        FILE_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT | FILE_OPEN_FOR_BACKUP_INTENT,
    )

    if status != STATUS_SUCCESS:
        return None

    return handle


def query_directory(handle, buffer_size=65536):
    """Query directory contents using NtQueryDirectoryFile."""
    buffer = ctypes.create_string_buffer(buffer_size)
    io_status = IO_STATUS_BLOCK()
    restart = True

    while True:
        status = ntdll.NtQueryDirectoryFile(
            handle,
            None,  # Event
            None,  # ApcRoutine
            None,  # ApcContext
            ctypes.byref(io_status),
            buffer,
            buffer_size,
            FileDirectoryInformation,
            False,  # ReturnSingleEntry
            None,   # FileName filter
            restart,
        )

        restart = False

        if status == STATUS_NO_MORE_FILES:
            break
        elif status != STATUS_SUCCESS:
            break

        # Parse buffer entries
        offset = 0
        while True:
            entry = ctypes.cast(
                ctypes.byref(buffer, offset),
                ctypes.POINTER(FILE_DIRECTORY_INFORMATION)
            ).contents

            # Extract filename
            name_len = entry.FileNameLength // 2  # Length is in bytes, we need chars
            name_ptr = ctypes.cast(
                ctypes.byref(buffer, offset + FILE_DIRECTORY_INFORMATION.FileName.offset),
                ctypes.POINTER(WCHAR * name_len)
            )
            filename = ''.join(name_ptr.contents[:name_len])

            yield {
                'name': filename,
                'size': entry.EndOfFile,
                'attributes': entry.FileAttributes,
                'mtime': entry.LastWriteTime,
                'atime': entry.LastAccessTime,
            }

            if entry.NextEntryOffset == 0:
                break
            offset += entry.NextEntryOffset


def scan_directory_recursive(path, min_size_bytes, stats, progress_callback=None):
    """Recursively scan directory using NtQueryDirectoryFile."""
    files = []
    dirs_to_process = [path]

    while dirs_to_process:
        current_dir = dirs_to_process.pop()

        handle = open_directory_nt(current_dir)
        if handle is None:
            stats['errors'] += 1
            continue

        try:
            for entry in query_directory(handle):
                name = entry['name']

                # Skip . and ..
                if name in ('.', '..'):
                    continue

                stats['total_entries'] += 1

                full_path = os.path.join(current_dir, name)
                is_dir = bool(entry['attributes'] & FILE_ATTRIBUTE_DIRECTORY)
                is_reparse = bool(entry['attributes'] & FILE_ATTRIBUTE_REPARSE_POINT)

                if is_dir:
                    stats['dir_count'] += 1
                    # Don't follow reparse points (symlinks, junctions)
                    if not is_reparse:
                        dirs_to_process.append(full_path)
                else:
                    stats['file_count'] += 1
                    size = entry['size']

                    if size >= min_size_bytes:
                        stats['files_matching_size'] += 1
                        stats['total_size_bytes'] += size

                        mtime = filetime_to_datetime(entry['mtime'])
                        atime = filetime_to_datetime(entry['atime'])

                        files.append({
                            'path': full_path,
                            'size': size,
                            'size_human': format_size(size),
                            'modified': mtime.isoformat() if mtime else None,
                            'accessed': atime.isoformat() if atime else None,
                        })

                if progress_callback:
                    progress_callback(stats)

        except Exception as e:
            stats['errors'] += 1
        finally:
            ntdll.NtClose(handle)

    return files


# ============================================================================
# Alternative: os.scandir approach (for comparison)
# ============================================================================

def scan_directory_scandir(path, min_size_bytes, stats, progress_callback=None):
    """Scan using os.scandir (Python's optimized approach)."""
    files = []
    dirs_to_process = [path]

    while dirs_to_process:
        current_dir = dirs_to_process.pop()

        try:
            with os.scandir(current_dir) as entries:
                for entry in entries:
                    stats['total_entries'] += 1

                    try:
                        is_dir = entry.is_dir(follow_symlinks=False)
                        is_symlink = entry.is_symlink()

                        if is_dir:
                            stats['dir_count'] += 1
                            if not is_symlink:
                                dirs_to_process.append(entry.path)
                        else:
                            stats['file_count'] += 1

                            # Get file stats
                            try:
                                st = entry.stat(follow_symlinks=False)
                                size = st.st_size
                            except OSError:
                                continue

                            if size >= min_size_bytes:
                                stats['files_matching_size'] += 1
                                stats['total_size_bytes'] += size

                                try:
                                    mtime = datetime.fromtimestamp(st.st_mtime)
                                    atime = datetime.fromtimestamp(st.st_atime)
                                except (OSError, OverflowError, ValueError):
                                    mtime = atime = None

                                files.append({
                                    'path': entry.path,
                                    'size': size,
                                    'size_human': format_size(size),
                                    'modified': mtime.isoformat() if mtime else None,
                                    'accessed': atime.isoformat() if atime else None,
                                })

                        if progress_callback:
                            progress_callback(stats)

                    except OSError:
                        stats['errors'] += 1

        except PermissionError:
            stats['errors'] += 1
        except OSError:
            stats['errors'] += 1

    return files


# ============================================================================
# Main Scan Function
# ============================================================================

def scan_filesystem(drive, min_size_bytes, progress_interval=100000, method='ntquery'):
    """
    Scan filesystem and return file information.

    Args:
        drive: Drive letter (e.g., 'C')
        min_size_bytes: Minimum file size to include
        progress_interval: Print progress every N entries
        method: 'ntquery' for NtQueryDirectoryFile, 'scandir' for os.scandir

    Returns:
        dict with scan results and statistics
    """
    root_path = f"{drive}:\\"

    print(f"Scanning: {root_path}")
    print(f"Method: {method}")
    print(f"Minimum file size: {format_size(min_size_bytes)}")
    print("-" * 60)

    start_time = time.time()
    start_memory = get_memory_mb()
    last_progress = [0]  # Use list to allow modification in nested function

    stats = {
        'total_entries': 0,
        'file_count': 0,
        'dir_count': 0,
        'files_matching_size': 0,
        'errors': 0,
        'total_size_bytes': 0,
    }

    def progress_callback(s):
        if s['total_entries'] - last_progress[0] >= progress_interval:
            last_progress[0] = s['total_entries']
            elapsed = time.time() - start_time
            rate = s['total_entries'] / elapsed if elapsed > 0 else 0
            mem = get_memory_mb()
            print(f"  Processed {s['total_entries']:,} entries "
                  f"({rate:,.0f}/sec, {mem:.0f} MB RAM, "
                  f"{s['files_matching_size']:,} files matched)")

    if method == 'ntquery':
        files = scan_directory_recursive(root_path, min_size_bytes, stats, progress_callback)
    else:
        files = scan_directory_scandir(root_path, min_size_bytes, stats, progress_callback)

    elapsed = time.time() - start_time
    end_memory = get_memory_mb()

    stats['elapsed_seconds'] = round(elapsed, 2)
    stats['entries_per_second'] = round(stats['total_entries'] / elapsed, 0) if elapsed > 0 else 0
    stats['memory_start_mb'] = round(start_memory, 1)
    stats['memory_end_mb'] = round(end_memory, 1)
    stats['memory_used_mb'] = round(end_memory - start_memory, 1)

    return {
        'drive': drive,
        'method': method,
        'scan_time': datetime.now().isoformat(),
        'stats': stats,
        'files': files,
    }


def print_summary(results):
    """Print scan summary to console."""
    stats = results['stats']

    print("\n" + "=" * 60)
    print("SCAN COMPLETE")
    print("=" * 60)
    print(f"Drive:                  {results['drive']}:")
    print(f"Method:                 {results['method']}")
    print(f"Total entries scanned:  {stats['total_entries']:,}")
    print(f"  - Directories:        {stats['dir_count']:,}")
    print(f"  - Files:              {stats['file_count']:,}")
    print(f"  - Errors/skipped:     {stats['errors']:,}")
    print(f"Files matching filter:  {stats['files_matching_size']:,}")
    print(f"Total size (matched):   {format_size(stats['total_size_bytes'])}")
    print("-" * 60)
    print(f"Elapsed time:           {stats['elapsed_seconds']:.1f} seconds")
    print(f"Processing rate:        {stats['entries_per_second']:,.0f} entries/sec")
    if HAS_PSUTIL:
        print(f"Memory used:            {stats['memory_used_mb']:.0f} MB")
    else:
        print("Memory used:            (install psutil for memory tracking)")
    print("=" * 60)

    # Show top 10 largest files
    if results['files']:
        print("\nTop 10 largest files:")
        print("-" * 60)
        sorted_files = sorted(results['files'], key=lambda x: x['size'], reverse=True)
        for i, f in enumerate(sorted_files[:10], 1):
            # Truncate path for display
            path = f['path']
            if len(path) > 60:
                path = '...' + path[-57:]
            print(f"  {i:2}. {f['size_human']:>10}  {path}")


def main():
    parser = argparse.ArgumentParser(
        description="Test filesystem enumeration performance using Windows NT API"
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
        "--method",
        choices=['ntquery', 'scandir'],
        default='ntquery',
        help="Enumeration method: ntquery (NtQueryDirectoryFile) or scandir (os.scandir)"
    )
    parser.add_argument(
        "--progress", "-p",
        type=int,
        default=100000,
        help="Progress interval (default: 100000)"
    )

    args = parser.parse_args()

    if sys.platform != 'win32':
        print("ERROR: This script requires Windows.")
        sys.exit(1)

    min_size_bytes = args.min_size * 1024 * 1024

    print("=" * 60)
    print("FILESYSTEM ENUMERATION TEST")
    print(f"Method: {args.method.upper()}")
    print("=" * 60)
    if not HAS_PSUTIL:
        print("TIP: pip install psutil for memory tracking")
    print()

    results = scan_filesystem(
        args.drive,
        min_size_bytes,
        progress_interval=args.progress,
        method=args.method,
    )
    print_summary(results)

    if args.output:
        output_data = results['files'] if args.files_only else results
        with open(args.output, 'w', encoding='utf-8') as f:
            json.dump(output_data, f, indent=2, default=str)
        print(f"\nResults written to: {args.output}")
        print(f"File size: {format_size(os.path.getsize(args.output))}")


if __name__ == "__main__":
    main()
