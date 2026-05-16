# General triage

Use when `manifest.collection.scenario_hint = general`, or the operator
reports a vague problem and is not sure where to look.

## Orientation pass

Read these in order, looking for anything obviously wrong:

0. `manifest.collection.problem_description.text` -- if present, the
   operator wrote this themselves to describe what they are investigating.
   It overrides any inference you would make from the data alone. Absent
   = unattended (Salt / SSM / scheduled) collection; proceed with caution
   about assumed intent.
1. `summary/inventory.json` -- is this the host you think it is? OS
   caption, uptime, last boot, domain, role.
2. `manifest.collection_errors[]` -- non-info entries are the collector's
   own complaints. Many warnings can mean a degraded host or a
   non-standard environment.
3. `summary/events_summary.json` -- per-channel `error_count` and
   `warning_count` totals. A channel suddenly hot is a tell.
4. `summary/services.json` -> `stopped_auto_count` and
   `stopped_auto_names` -- services configured to start automatically
   that are not running.
5. `summary/storage.json` -> `volumes` -- any `free_pct` under 10?
6. `summary/patching.json` -> `pending_reboot` -- any flag set?
7. `summary/ad_context.json` -- if domain-joined, check `w32tm_status`
   and (DC only) `dcdiag_summary` for a quick "is the directory healthy"
   read.
8. `summary/boot_timeline.json` -> `anomalies[]` -- pre-classified boot
   anomalies (`incomplete_boot`, `missing_shutdown_event`, `abnormal_gap`).
   On a healthy box this is empty in one read; on a box that recently did
   not come back from a reboot it is the headline.
9. `summary/crashes_wer.json` -> `kernel_dumps.interpretation` -- one-line
   answer to "would a future bugcheck even produce a dump on this host?"
   `dumps_disabled = true` is a quiet but high-impact finding.

## Pivot rules

- Hot Application channel + a slow box -> use `prompts/performance_regression.md`.
- Hot WindowsUpdateClient or Servicing channel -> use `prompts/post_patch.md`.
- Recent unexpected reboot (`boot_markers` shows a 6008) and you do not
  yet know why -> drill into `raw/eventlogs/System.evtx` around the 6008
  timestamp; check `summary/crashes_wer.json` for cabs near that time.
- Disk free under 10 percent -> identify the largest consumer, but the
  bundle does not include filesystem walks; flag for follow-up.
- Heavy `collection_errors` with `severity = error` -> the host may be in
  a degraded state that broke the collector itself; mention this to the
  operator before attempting a deeper read.
- Non-empty `summary/baseline_diff.json` with `services.removed` or
  `scheduled_tasks.added` -> something was reconfigured since the last
  baseline; cross-check with `summary/patching.json` to see whether a
  patch caused it.

## When in doubt

Read `manifest.collection_errors` fully. Many "soft" findings are recorded
there and nowhere else (skipped collectors, missing channels, locked
files, registry keys absent, role collectors that did not run). It is the
second most important file after `manifest.json`.

If the elevation field shows `User`, expect partial data and reach for
re-collection under Administrator or SYSTEM rather than guessing.
