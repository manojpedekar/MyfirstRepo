#!/usr/bin/env python3
"""Profile MFT parsing with full attribute access to identify bottlenecks."""

import cProfile
import pstats
import io
import time

from dissect.ntfs import NTFS

def main():
    volume_path = r"\\.\C:"
    count = 0
    files_found = 0
    max_records = 50000
    min_size_bytes = 1 * 1024 * 1024  # 1 MB

    print(f"Profiling first {max_records:,} MFT records with FULL attribute access...")
    print(f"Volume: {volume_path}")
    print("-" * 60)

    with open(volume_path, "rb") as fh:
        fs = NTFS(fh)

        profiler = cProfile.Profile()
        start = time.time()
        profiler.enable()

        for record in fs.mft.segments():
            count += 1
            if record is None:
                continue

            # Check directory flag (fast)
            try:
                is_dir = bool(record.header.Flags & 0x02)
            except:
                continue

            if is_dir:
                continue

            # Get DATA attribute size - THIS IS LIKELY SLOW
            size = 0
            try:
                data_attr = next(iter(record.attributes.DATA), None)
                if data_attr and data_attr.header:
                    size = data_attr.header.size or 0
            except:
                pass

            if size < min_size_bytes:
                continue

            # Get FILE_NAME - THIS IS LIKELY SLOW
            try:
                fn_attrs = list(record.attributes.FILE_NAME)
                if fn_attrs:
                    best_fn = fn_attrs[-1]
                    file_name = best_fn.file_name
                    # Get full path - THIS IS DEFINITELY SLOW
                    try:
                        full_path = best_fn.full_path()
                    except:
                        full_path = file_name
            except:
                continue

            # Get timestamps
            try:
                si = next(iter(record.attributes.STANDARD_INFORMATION), None)
                if si:
                    mtime = getattr(si, 'mtime', None)
                    atime = getattr(si, 'atime', None)
            except:
                pass

            files_found += 1

            if count >= max_records:
                break

        profiler.disable()
        elapsed = time.time() - start

    print(f"Processed {count:,} records in {elapsed:.1f}s ({count/elapsed:,.0f}/sec)")
    print(f"Files matching filter: {files_found:,}")
    print()
    print("Top 40 functions by cumulative time:")
    print("=" * 80)

    s = io.StringIO()
    ps = pstats.Stats(profiler, stream=s).sort_stats('cumulative')
    ps.print_stats(40)
    print(s.getvalue())

if __name__ == "__main__":
    main()
