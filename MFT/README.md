# MFT

Tooling for collecting, storing, and visualizing NTFS volume contents on Windows servers for space-utilization reporting. The C++ scanners enumerate file/directory metadata, the PowerShell importers load the CSV output into SQL Server, and the Grafana dashboards visualize it.

Two scanning approaches exist for the same job:

- **Direct MFT parsing** -- reads the `$MFT` file directly. Faster, but requires administrator privileges. The canonical implementation lives at `CLAWS/DirectMFTParsing/`. A historical snapshot is preserved here under `DirectMFTParsing/` -- see that folder's README.
- **Filesystem enumeration** -- uses Win32 `FindFirstFile`-style APIs. Slower, no admin needed. Implemented here as `mftscan`.

## Layout

| Folder | Contents |
|---|---|
| `DirectMFTParsing/` | **Historical snapshot only.** Older 2026-02-11 variant of the direct-MFT-parsing C++ project. The canonical version is `CLAWS/DirectMFTParsing/`. See `DirectMFTParsing/README.md`. |
| `mftscan/` | Multi-threaded NTFS volume scanner using filesystem enumeration. Outputs CSV of file/directory metadata. Standalone C++ project. |
| `mfttest/` | Producer-consumer test harness for high-performance directory scanning. Companion project used during perf tuning. |
| `database/` | SQL Server schema, stored procedures, indexes, backfill scripts, and `Import-MftScan*.ps1` importers that load scan-output CSVs into the DB. |
| `database/FileSizes/` | Self-contained sub-database for the FileSizes feature -- tables, views, stored procs, and the `grafana-ro` read-only login. |
| `Grafana/` | Dashboard JSON exports (`dashboard_enhanced_v2.json` is current; `demoboard.json` and `dashboard_enhanced.json` are earlier iterations) plus `panel_descriptions.md` and `dashboard_analysis.md`. |
| `docs/` | Analysis and performance investigation notes from the design phase. `data_structure_optimization.md`, `MFT_PERFORMANCE_INVESTIGATION.md`, `MFT_PERFORMANCE_ANALYSIS.md`, `MFT_DATA_EXTRACTION_ANALYSIS.md`, `PERFORMANCE_COMPARISON.md`. |
| `perf-tests/` | Python methodology scripts referenced by the docs. `mft_test.py` (dissect.ntfs MFT-parsing prototype), `ntquery_test.py` (filesystem-enumeration prototype), `profile_mft.py` / `profile_mft_full.py` (cProfile harnesses). |

## Build

Each C++ project has its own `.vcxproj` (and `mfttest/` ships a `.sln`). Open in Visual Studio 2022 or later. Build outputs are gitignored via the repo-root `.gitignore`.

The project files were copied verbatim from the original development tree. Include paths or output paths may reference the old layout (`cpp/mftscan/...`) and may need updating after the relocation.

## Database setup

`database/FileSizes/FileSizes.Database.sql` is the top-level database script. The other `.sql` files create tables, views, stored procedures, and the `grafana-ro` user. `database/Import-MftScanV2.ps1` is the current importer; `Import-MftScanBatch.ps1` predates it.

## Relationship to CLAWS

`DirectMFTParsing/` here and `CLAWS/DirectMFTParsing/` at the repo root are two snapshots of the same tool. Edit the CLAWS copy. The one under this directory is read-only history.
