#!/usr/bin/env python3
"""Profile MFT parsing to identify bottlenecks."""

import cProfile
import pstats
import io
import time
import sys

from dissect.ntfs import NTFS

def main():
    volume_path = r"\\.\C:"
    count = 0
    max_records = 50000

    print(f"Profiling first {max_records:,} MFT records...")
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
            # Minimal work - just access header flags
            try:
                _ = record.header.Flags
            except:
                pass
            if count >= max_records:
                break

        profiler.disable()
        elapsed = time.time() - start

    print(f"Processed {count:,} records in {elapsed:.1f}s ({count/elapsed:,.0f}/sec)")
    print()
    print("Top 30 functions by cumulative time:")
    print("=" * 80)

    s = io.StringIO()
    ps = pstats.Stats(profiler, stream=s).sort_stats('cumulative')
    ps.print_stats(30)
    print(s.getvalue())

if __name__ == "__main__":
    main()
