# Forensic preservation review

Use when `manifest.collection.scenario_hint = forensic`, or the bundle was
captured to preserve state before logs roll over.

## Goals

- Verify that the collection captured what the responder needed.
- Identify gaps that may need a follow-up bundle or a different tool.
- Confirm bundle integrity.

## Verify completeness

0. `manifest.collection.problem_description.text` -- if present, the
   operator's own narrative about what they were preserving. Treat it as
   the authoritative statement of intent (especially for forensic captures
   where ambiguity about scope is expensive).
1. `manifest.collection.elevation` -- if `User`, several collectors
   degraded. GPO output is silently absent, dcdiag was skipped, some
   service state was unreadable, certain registry exports failed.
   Re-collect under `SYSTEM` or `Administrator` if any of these matter.
2. `manifest.collection_errors[]` -- every `severity = error` entry is a
   category that produced no output. Every `severity = warning` is reduced
   output; inspect what did come back.
3. `manifest.size_budget.truncations[]` -- any artifacts trimmed for the
   raw budget cap (default 2GB). When non-empty, the listed files were
   dropped from the bundle entirely.
4. `summary/crashes_wer.json` -- `cabs_skipped_budget` and
   `dumps_skipped_budget` indicate WER artifacts left out due to the
   50MB cap. The indexes
   (`raw/wer/ReportArchive_index.csv`, `raw/dumps/minidump_index.csv`)
   list every file that existed even when the content was excluded.

## Confirm integrity

1. `checksums.txt` covers every file except itself. Re-hash any file the
   consumer extracts and compare.
2. `manifest.artifacts[].sha256` should match what is recomputed from
   disk, with one expected divergence: files modified by
   `Invoke-DiagRedaction` carry the post-redaction hash.
3. `manifest.collection.collector_version` pins the module version that
   produced this bundle. Reproducibility hinges on it.

## Common gaps to flag

- No `raw/eventlogs/Security.evtx` -- Security channel may have been
  empty in the window, or `wevtutil` failed to read it (typically a
  permissions signal). Check `collection_errors` for the channel name.
- No `raw/perf/snapshot.blg` -- Performance collector skipped or failed.
  Check `collection_errors` for `Get-DiagPerformance` entries.
- No `summary/baseline_diff.json` -- no baseline exists on this host.
  Means the diff signal was unavailable, not that nothing changed.
- `raw/windowsupdate/*.etl` present but no readable text -- ETL needs
  `Get-WindowsUpdateLog` conversion. The bundle does not pre-convert.
- No `raw/role_specific/...` content for a role you expected -- check
  `summary/roles_apps.json` -> `detected` to see whether the role
  collector ran. Detection uses feature/service presence; a custom or
  non-standard install may not register.

## Next steps

If the bundle is incomplete for the question being asked, the right move
is usually a fresh bundle with the right elevation and scenario hint,
not extracting more from this one. Note the bundle_id of the original
when filing the follow-up so the two collections can be correlated.
