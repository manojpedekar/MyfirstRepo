# Performance regression investigation

Use when `manifest.collection.scenario_hint = performance`, or the operator
reports "the box is slow", "high CPU", "memory pressure", "disk is hot".

## Orientation

0. `manifest.collection.problem_description.text` -- if present, the
   operator wrote this themselves to describe what they are investigating.
   It overrides any inference you would make from the data alone.
1. `summary/perf_summary.json` -- min, avg, max, and p95 for CPU, memory,
   disk, network, and TCP counters over the 60-second sample window
   (`manifest.time_window.perf_from_utc` to `perf_to_utc`).
2. `summary/processes.json` -- four top-N lists:
   `top_by_cpu_seconds`, `top_by_workingset_mb`, `top_by_handles`,
   `top_by_threads`. Total process count alongside each.
3. `summary/storage.json` -- volumes, page files, physical disks.

If `summary/perf_summary.json` is missing, the Performance collector was
skipped or failed -- check `manifest.collection_errors` for
`Get-DiagPerformance` entries. Without it, this prompt is largely guesswork.

## Patterns to look for

### CPU saturation

- `perf_summary.json` -> `\Processor(_Total)\% Processor Time` p95 above 80.
- `processes.json` -> `top_by_cpu_seconds`: which process is dominating?
  Cross-reference `command_line` and `parent_pid` for context.
- `\System\Processor Queue Length` sustained above the host's logical
  processor count is real contention, not just busy.
- `\System\Context Switches/sec` very high with no obvious dominant
  process suggests excessive thread thrash; check `top_by_threads`.

### Memory pressure

- `perf_summary.json` -> `\Memory\Available MBytes` min near zero.
- `\Memory\Pages/sec` avg above ~1000 indicates active paging.
- `processes.json` -> `top_by_workingset_mb` -- one outlier or many?
- `storage.json` -> `page_files` -> `peak_usage_mb` close to
  `allocated_mb` is full pagefile.

### Disk slowness

- `perf_summary.json` -> `\PhysicalDisk(_Total)\Avg. Disk sec/Read` or
  `/Write` p95 above 0.020 (20 ms) is slow. Above 0.050 is bad.
- `\PhysicalDisk(_Total)\% Disk Time` sustained above 80 with non-trivial
  `Disk Reads/sec` or `Disk Writes/sec` is queueing.
- `storage.json` -> `physical_disks` for `media_type` (HDD vs SSD) and
  `bus_type` -- expectations differ.

### Network pressure

- `perf_summary.json` -> `\Network Interface(*)\Bytes Total/sec` and
  `\Network Interface(*)\Output Queue Length`.
- `\TCPv4\Segments Retransmitted/sec` rising without bandwidth saturation
  is a connectivity quality signal.

### Handle or thread leak

- `processes.json` -> `top_by_handles` or `top_by_threads` with values
  out of proportion to peers (10x+) -- usually a leak. Use the process's
  `command_line` and `start_time` to triage age.

## Drill-down hops

1. `raw/perf/snapshot.blg` via `Import-Counter` for the full 60-second
   sample, not just the aggregates. Useful when the p95 is high but the
   max is misleading.
2. `raw/eventlogs/System.evtx` for disk subsystem errors (EventID 51, 153)
   or memory pressure (EventID 2004 from `Resource-Exhaustion-Detector`).
3. `raw/eventlogs/Application.evtx` for application crashes that line up
   with the high-CPU process from `top_by_cpu_seconds`.
