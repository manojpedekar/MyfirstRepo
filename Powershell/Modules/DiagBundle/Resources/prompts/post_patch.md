# Post-patch investigation

Use when `manifest.collection.scenario_hint = post_patch`, or when the
operator says "after patching" / "since the last reboot".

## Orientation

0. `manifest.collection.problem_description.text` -- if present, the
   operator wrote this themselves to describe what they are investigating.
   It overrides any inference you would make from the data alone.
1. `raw/salt/patching_automation/patching.log` (and rotated
   `patching.log.YYYY-MM-DD` siblings) -- the **operator-decisions layer**
   from the org's Salt patch orchestration. Read this BEFORE forming a
   hypothesis from WUA / Setup.evtx data alone. It tells you which window
   the host SHOULD have patched in, which GUIDs Salt actually attempted,
   Salt's per-patch [OK]/[FAIL] outcomes, schedule-registration errors,
   and whether a post-window retry was correctly suppressed. See README
   "Salt patching automation logs" for the highest-leverage greps. Absent
   on hosts that do not run the org's Salt patching automation.
2. `summary/patching.json` -- what was offered, installed, or failed in the
   last 24 hours (or the `WindowHours` value in `manifest.time_window`).
3. `summary/inventory.json` -> `last_boot_utc` -- did the box reboot? When?
4. `summary/boot_timeline.json` -> `anomalies[]` first, then `boots[]` --
   pre-classified per-boot records with `boot_type` (clean/dirty),
   `shutdown_initiator` (e.g. `salt_orchestrator`, `windows_update`,
   `interactive_admin_console`), and gap detection. The `incomplete_boot`
   anomaly fires when a boot was inferred from a 6008 prior-shutdown
   timestamp but the kernel never reached EventLog start -- exactly the
   "patched, rebooted, did not come back" case.
5. `summary/events_summary.json` -> System channel -> `boot_markers` --
   the raw flat list (6005, 6006, 6008, 1074) is still here for cross-checks.
6. `summary/salt.json` -- if Salt is the patch orchestrator, this confirms
   it is installed and active and shows recent jobs in window. The
   `data.patching_logs` block confirms whether the orchestration logs
   were collected.

## Patterns to look for

### A patch failed

- `patching.json` -> `update_history` -> entries with `operation = Install`
  and `result_code != 2` (2 = Succeeded). `hresult` is the Windows error
  code in hex.
- `raw/eventlogs/Setup.evtx` -- correlated install or rollback events
  around the failed update's `date_utc`.
- `raw/cbs/CBS.log` -- search for the package name. CBS errors include
  `STATUS_CANNOT_DELETE`, `ERROR_SXS_ASSEMBLY_MISSING`,
  `CBS_E_INVALID_PACKAGE`.
- `raw/cbs/CbsPersist_*.log` -- prior session logs. The 50MB tail is
  applied; older detail may be off the front of the file.

### A patch installed but the box is now misbehaving

- `summary/baseline_diff.json` (if present) -- services, scheduled tasks,
  or autoruns that changed since the last baseline.
- `summary/services.json` -> `stopped_auto_names` -- services configured
  Auto-start that are not running.
- `summary/events_summary.json` -> Application and System channels -> top
  events. New errors appearing only since the latest `boot_markers` entry
  are highly suspicious.
- `summary/ad_context.json` -> `w32tm_status` -- patches occasionally
  break time sync; verify the host still has a synced peer.

### The post-patch reboot did not return cleanly

- `summary/boot_timeline.json` -> `anomalies[]` -- look for `incomplete_boot`
  (boot inferred from 6008 never reached EventLog start) and `abnormal_gap`
  (>4h warning, >12h critical between clean shutdown and next boot).
- `summary/boot_timeline.json` -> `boots[]` -- the first boot after the
  failed-boot window typically has `boot_type = dirty`,
  `operator_console_interaction = true` (F8 / boot menu), and a clean
  follow-up reboot a few minutes later as the operator clears broken
  service state.
- `summary/crashes_wer.json` -> `kernel_dumps` -- if `policy.crash_dump_enabled = 0`
  the host will never produce a kernel dump on bugcheck; that is itself the
  reason there is no in-guest evidence of the hang. If
  `policy.crash_dump_enabled` is non-zero but `minidump_dir.file_count = 0`
  and `memory_dmp.in_collection_window = false`, the boot probably hung
  before reaching the dump-write phase -- look outside the guest (vCenter
  task log, OOB power log).

### A reboot is still pending

- `summary/patching.json` -> `pending_reboot` block. Each flag has a
  distinct cause:
  - `cbs_reboot_pending` -- Windows component servicing finished a stage
    that requires a reboot.
  - `wu_reboot_required` -- Windows Update Auto Update has staged a
    reboot.
  - `pending_file_rename` -- file replacements queued at next boot via
    Session Manager. Drill into `pending_file_rename_list[]` to see which
    files are queued (`source`, `destination`, `operation` of `rename` or
    `delete`); third-party agents (Cohesity, Cortex XDR, EDR products)
    frequently queue file replacements and the queued path tells you which
    subsystem is mid-update. List capped at 200 entries; check
    `pending_file_rename_truncated` and consult
    `raw/registry/session_manager_pending_renames.reg` for the full source.
  - `sccm_pending_reboot` -- the SCCM client says reboot pending. Trusts
    `root\ccm\ClientSDK CCM_ClientUtilities.DetermineIfRebootPending`
    when available; falls back to a registry breadcrumb that can give a
    false positive on some boxes (this collector prefers the WMI path).

Name the flag(s) when reporting to the operator.

### Hypervisor / guest-agent activity raced the patch reboot

This pattern recurs on every hypervisor: a guest agent or paravirt driver
upgrade fires off automatically and overlaps with the OS reboot window.
Symptoms include long boot times, post-reboot service failures, or
network/storage stalls in the first minutes after the box returns.

- `summary/hypervisor.json` -> `data.detected_platform` -- which platform
  is in scope.
- `summary/hypervisor.json` -> `data.guest_agent_version` -- if this
  recently changed (compare the `installer_log_count` and look at
  `raw/role_specific/hypervisor/<platform>/installer_logs/` for in-window
  installs), the agent upgraded right around the patch window.
- `raw/role_specific/hypervisor/<platform>/tools_logs/` (VMware) or
  `agent_logs/` (KVM) -- guest-agent operational logs around the reboot
  point. Look for heartbeat-related lines and time-sync activity.
- `summary/events_summary.json` -> `interesting_providers[]` -- this
  flat index always contains hypervisor-relevant events (VMware:
  `VMUpgradeHelper`, `vmci`, `vmxnet3`; Hyper-V: `vmbus`, `netvsc`,
  `storvsc`; KVM: `viostor`, `netkvm`, `qemu-ga`) regardless of whether
  they fell below the per-channel top-50 truncation. Each entry has
  `source` = `top_events` (was already in the per-channel top) or
  `rescan` (caught by the targeted re-scan).
- `summary/hypervisor.json` -> `data.paravirt_drivers[]` -- driver
  versions and dates. A driver date inside the patch window means the
  paravirt driver upgraded then; cross-reference with the platform's
  `Microsoft-Windows-Hyper-V-*` or `VMware*` channels for the install/
  load timeline.

### A LiveKernelReport was emitted (recoverable kernel hang)

When the kernel detects a recoverable hang or stall (KernelStackOverflow,
USERMODE_HEALTH_MONITOR, etc.) it writes a `.dmp` to
`C:\Windows\LiveKernelReports\` containing the call stack of the hung
component. These are smaller than full kernel dumps but identify which
component the kernel suspected.

- `summary/crashes_wer.json` -> `kernel_dumps.live_kernel_reports.files[]`
  -- one entry per file; `in_window` and `copied` flags decide whether the
  file was brought into the bundle. `skip_reason` distinguishes "out of
  window", "over per-file cap" (operator pulls manually), or
  "crash_artifacts_disabled".
- `raw/dumps/livekernelreports/<name>` -- the actual `.dmp`. Open in
  WinDbg with `!analyze -v`; symbols from the public Microsoft store.
- If the only in-window LKR has `skip_reason = over_per_file_cap`, the
  file is too large to ship in the bundle but still on the host at the
  recorded path. Pull it manually with `Copy-Item` and analyze offline.

## Drill-down hops

1. From a suspicious EventID in `events_summary.json` -> `wevtutil qe` on
   the raw EVTX (see README.md "Drill-down recipes").
2. From a CBS reference -> grep `raw/cbs/CBS.log` for the package or
   session GUID.
3. From a Windows Update entry -> `Get-WindowsUpdateLog` on
   `raw/windowsupdate/*.etl`.
4. From a service that stopped auto-starting -> `services.json` row for
   `path_name` and `start_name`; cross-check `events_summary.json`
   Application channel for crash signatures of the binary.
