# DiagBundle

This ZIP is a one-shot Windows Server diagnostic bundle produced by the
DiagBundle PowerShell module. It captures a snapshot of one host at one point
in time, intended for AI-assisted analysis or human triage.

Schema version: see `manifest.json` -> `schema_version`. Treat the manifest
shape as a stability commitment; major changes bump the version. The current
schema version is **1.3** (1.2 -> 1.3: new optional `manifest.timings` block
recording per-step wall-clock durations for every timed call in the bundle,
sorted slowest-first; the same data is also in `transcript/collector.log`
as line-delimited JSON entries with `message="timing"`. 1.1 -> 1.2: optional
`manifest.collection.problem_description` block added for operator-supplied
narrative. 1.0 -> 1.1: `summary/inventory.json` -> `data.time_zone` changed
from a string to an object; new artifacts `summary/boot_timeline.json` and
`summary/salt.json` were added; `summary/crashes_wer.json` gained a
`kernel_dumps` block).

Per-summary schema bumps independent of the manifest version:
- `summary/crashes_wer.json` schema 1.3 (1.2 -> 1.3 added per-file
  LiveKernelReports inventory, in-window copy under `LkrCopyCapBytes`, and
  the new `raw/dumps/livekernelreports/` raw artifact directory).
- `summary/events_summary.json` schema 1.1 (1.0 -> 1.1 added
  `detected_platform` and the `interesting_providers` index for hypervisor-
  specific events that fall below per-channel top-50 truncation).
- `summary/hypervisor.json` schema 1.0 (new derived summary; see Bundle
  layout and "What hypervisor is this guest on" below).
- `summary/inventory.json` schema 1.1 (1.0 -> 1.1 added the optional
  `data.cloud` block populated from Salt grains: image, platform,
  account, project, subproject, datacenter, instance_id, environment).
  Absent when Salt is not installed or grains.item failed.
- `summary/salt.json` schema 1.2 (1.1 -> 1.2 added tolerant YAML parsing
  for `master:` scalar/inline-list/block-list forms, default-path log
  capture, cached `minion_id` file, static grains file capture, PKI
  inventory with `master_sign.pub` presence check, TCP probes to master
  ports 4505/4506, and live `salt-call --local` probes including
  test.ping, grains.items, saltutil.is_running, and state.show_top for
  the active saltenv plus base).
- `summary/salt_grains.json` schema 1.0 (new derived summary; full
  `salt-call --local grains.items` output as JSON).
- `summary/cloudbase_init.json` schema 1.0 (new derived summary; parsed
  last-run state including version, plugin sequence, LocalScripts exit
  codes, metadata service, instance_id, and reboots initiated).
- `summary/scheduled_tasks.json` schema 1.0 (new derived summary; per-name
  presence check against `Resources/expected_tasks.json`. Initial seed
  list contains `SaltHighState` only).

## Read in this order

0. **manifest.collection.problem_description.text** -- if present, this is
   the operator's own description of what they are investigating. Read it
   before forming a hypothesis from data alone. The field is absent when
   the bundle was collected unattended (Salt / SSM / scheduled).
1. **manifest.json** -- root inventory. Lists every artifact with path,
   category, type (`derived` or `raw`), schema_version, sha256, size, and a
   one-line description. Also carries `collection_errors[]` -- the second
   most important field after `artifacts[]`.
2. **summary/*.json** -- pre-aggregated, AI-friendly views per category.
   Read all of these next. Small, structured, opinionated.
3. **raw/** -- forensic artifacts referenced by summaries. Open only when a
   summary points at something worth investigating deeper.
4. **prompts/** -- short investigation scaffolds aligned to the four
   `Scenario` values. Use the one that matches `manifest.collection.scenario_hint`,
   or pick by symptom.

## Bundle layout

```
manifest.json           # entry point
summary/                # AI-friendly aggregated JSON
  inventory.json
  drivers.json
  patching.json
  events_summary.json   # adds detected_platform + interesting_providers index (schema 1.1)
  boot_timeline.json    # per-boot records, gaps, anomalies (incomplete_boot, missing_shutdown_event, abnormal_gap)
  processes.json
  services.json
  perf_summary.json     # absent if the Performance collector was skipped
  storage.json
  network.json
  ad_context.json
  crashes_wer.json      # WER + minidump inventory; kernel_dumps section (CrashControl policy + dump dirs + page-file adequacy + LiveKernelReports per-file inventory) (schema 1.3)
  roles_apps.json
  hypervisor.json       # detected hypervisor + guest agent + paravirt drivers + time-sync state; stub on physical/unknown
  salt.json             # Salt minion install state, masters, log path, PKI inventory, master TCP probes, live salt-call probes (schema 1.2)
  salt_grains.json      # Full grains.items output as JSON (absent if salt-call probes failed)
  cloudbase_init.json   # Cloudbase-Init last-run summary: version, plugins, LocalScripts exit codes, reboots (only if cloudbase-init is installed)
  scheduled_tasks.json  # Expected-task absence check (driven by Resources/expected_tasks.json; SaltHighState seed)
  baseline_diff.json    # only if a baseline existed
raw/                    # forensic preservation, untransformed
  eventlogs/*.evtx
  cbs/CBS.log + CbsPersist_*.log
  windowsupdate/*.etl
  drivers/pnputil_enum_drivers.txt
  perf/snapshot.blg
  wer/, netsh/, gpo/, tasks/, role_specific/
  dumps/                # minidumps + livekernelreports/ (in-window LKR files under LkrCopyCapBytes)
  registry/             # exports incl. session_manager_pending_renames.reg (PendingFileRenameOperations source)
  role_specific/hypervisor/<platform>/  # vmware/, hyperv/, kvm/ -- agent logs, registry, installer logs
  salt/                 # minion config, minion_id cache, minion.d/, grains, log tail, jobs cache, probes/, pki_inventory (PKI private key never read)
  cloudbase_init/       # log/, conf/, LocalScripts/ contents + sha256, userdata if present (only if Cloudbase-Init is installed)
transcript/
  collector.log         # per-event JSON lines from the collector
  transcript.txt        # PowerShell Start-Transcript output
prompts/                # investigation scaffolds
  post_patch.md
  performance_regression.md
  general_triage.md
  forensic_preservation.md
README.md               # this file
checksums.txt           # SHA256 of every other file
```

## Where to start by question

- "What changed recently?" -> `summary/patching.json` and `summary/baseline_diff.json`.
- "Why is the box slow?" -> `summary/perf_summary.json` and `summary/processes.json`.
- "What broke last patch cycle?" -> `summary/patching.json`, `raw/cbs/CBS.log`, `raw/eventlogs/Setup.evtx`.
- "Is this thing rebooting?" -> `summary/boot_timeline.json` first (per-boot records + classified anomalies). The flat `summary/events_summary.json` -> System channel -> `boot_markers` is also present and never truncated.
- "Did the previous boot hang or get stuck?" -> `summary/boot_timeline.json` -> `anomalies[]` (look for `incomplete_boot` and `abnormal_gap`); cross-reference with `summary/crashes_wer.json` -> `kernel_dumps` (would a bugcheck even produce a dump on this host?).
- "Are kernel dumps actually being captured?" -> `summary/crashes_wer.json` -> `kernel_dumps`. `policy.crash_dump_enabled` (0=disabled, 1=complete, 2=kernel, 3=small/minidump, 7=automatic), `minidump_dir.file_count` and `in_window_count`, `memory_dmp.exists` + `in_collection_window`, `page_file.verdict` (whether the page file is large enough for the configured dump type). The `interpretation` field one-lines the answer.
- "Is this host's local time UTC-? right now?" -> `summary/inventory.json` -> `time_zone` (object with `id`, `current_utc_offset_minutes`, `currently_in_daylight_time`, `dst_transition_in_window`). Use this to interpret any local-time string (EVTX 6008 message text, CBS.log timestamps).
- "Did Salt run a patch job recently?" -> `summary/salt.json` -> `data.recent_jobs_count` and `raw/salt/jobs_recent.csv`; cross-reference `raw/windowsupdate/ReportingEvents.log` for the WUA-side install attempts.
- "Why didn't highstate run on this freshly built VM?" -> Read in this order: (1) `summary/scheduled_tasks.json` -- is `SaltHighState` present? Cloudbase-Init's `02-highstate.ps1` calls `Start-ScheduledTask -TaskName SaltHighState`; if the task is missing, highstate never fires. (2) `summary/cloudbase_init.json` -> `local_scripts[]` -- look for `exit_code == 0` AND `stderr_had_content == true`; that is the silent-failure pattern. (3) `summary/salt.json` -> `data.probes.show_top_active_env_assignment_count` -- if 0, the minion's configured `saltenv` has no state assignments for this host (top.sls targeting mismatch). (4) `summary/salt.json` -> `data.org_grains.ssnc_server_role` -- empty value means the grain that gates targeting was never populated. (5) `summary/salt.json` -> `data.master_connectivity[]` and `data.probes.test_ping_ok` -- confirms basic master reachability.
- "Did Cloudbase-Init succeed on first boot?" -> `summary/cloudbase_init.json` -> `last_run_outcome` (`succeeded` iff log ends with 'Plugins execution done'). `plugins[]` lists each plugin invocation with start time. `local_scripts[]` lists each LocalScript with exit code and stderr_bytes -- a script with exit_code=0 and stderr_had_content=true is suspicious (cloudbase-init swallows the error). `reboots_initiated[]` lists every "Rebooting" line in the log.
- "What cloud image was this VM built from?" -> `summary/inventory.json` -> `data.cloud.image` (and platform/account/project/subproject/datacenter/instance_id/environment). Populated from Salt grains; absent if Salt is not installed or grains.item failed.
- "Did the salt minion authenticate to the master?" -> `summary/salt.json` -> `data.master_connectivity[]` for TCP 4505/4506 reachability + `data.probes.test_ping_ok` for end-to-end auth. If `verify_master_pubkey_sign_required = true` and `verify_master_pubkey_sign_satisfiable = false`, the master will accept the auth but every published job is silently rejected (missing `master_sign.pub`).
- "Is an expected scheduled task missing from this host?" -> `summary/scheduled_tasks.json` -> `data.expected_tasks_missing` count, then the array entries with `present: false`. Initial list is just `SaltHighState`; extensible via `Resources/expected_tasks.json` shipped with the module.
- "What did the operator say was wrong?" -> `manifest.collection.problem_description.text`. `source` tells you whether they typed at the console (`prompt`), passed a string parameter (`parameter`), pointed at a file (`file`), or were prompted but cancelled (`prompt_cancelled`). Field is absent for unattended collections.
- "What was slow this run?" -> `manifest.timings.steps[]` is sorted by `duration_ms` descending, so the head of the list is the slowest operation. `manifest.timings.by_collector_seconds` aggregates the same data per collector (also slowest first). The full per-step log is in `transcript/collector.log` as line-delimited JSON with `message="timing"`. Trustworthy for post-mortem because it captures the actual run, not a rerun against warm caches.
- "Is anything pending a reboot?" -> `summary/patching.json` -> `pending_reboot` block. Includes `pending_file_rename_list[]` -- one entry per `PendingFileRenameOperations` pair, with `source`, `destination`, and `operation` (`rename` or `delete`). Capped at 200 entries; check `pending_file_rename_truncated`. The full source registry is at `raw/registry/session_manager_pending_renames.reg`.
- "What hypervisor is this guest on, and is the guest agent healthy?" -> `summary/hypervisor.json` -> `data`. Fields: `detected_platform` (`vmware` | `hyperv` | `kvm` | `unknown` | `physical`), `is_virtualized`, `guest_agent_name`, `guest_agent_version`, `guest_agent_install_path`, `guest_agent_log_count` and `_total_bytes` (logs copied), `paravirt_drivers[]` (with `version`, `date`, `provider`, `signer` per driver), `paravirt_nic_advanced[]` (NIC RSS/LRO/offload knobs), `time_sync_provider_text` (raw `w32tm /query /providers` and `/query /status` output). Platform-specific raw artifacts under `raw/role_specific/hypervisor/<platform>/`. On physical or unknown hypervisor the file is a stub with the right `detected_platform` and empty arrays.
- "Did a kernel hang produce a LiveKernelReport?" -> `summary/crashes_wer.json` -> `kernel_dumps.live_kernel_reports`. `files[]` is the per-file inventory (every file under `C:\Windows\LiveKernelReports\` with `name`, `size_bytes`, `modified_utc`, `in_window`, `copied`, `skip_reason`). Copied files land at `raw/dumps/livekernelreports/<name>`. Skip reasons: `out_of_window`, `over_per_file_cap` (file is bigger than `copy_cap_per_file_bytes`; pull manually from the host using the recorded path), `crash_artifacts_disabled`, `copy_failed`.
- "What roles or apps are installed?" -> `summary/roles_apps.json`.
- "What does the host think its time is?" -> `summary/ad_context.json` -> `w32tm_status`.
- "Are any drivers stale or third-party?" -> `summary/drivers.json` -> `pnputil_drivers` (DriverStore packages with provider/class/date), `signed_drivers` (currently bound drivers), and `kernel_drivers` (all kernel-mode + FS drivers with state). Filter `pnputil_drivers` by `driver_date` for staleness, by `signer` for unsigned/third-party, by `class_guid` for boot-critical classes (Firmware `f2e7dd72-...`, Storage controllers `4d36e97b-...`, Network adapters `4d36e972-...`). Filter `kernel_drivers` by `driver_type='File System'` AND `state='Running'` for loaded filter drivers (AV/EDR/backup minifilters). Cross-reference with `raw/drivers/fltmc_filters.txt` for altitude (AV/EDR usually 300000-330000, backup 180000-190000).
- "Is the system drive too full to install patches?" -> `summary/storage.json` -> `update_readiness` (`system_free_gb`, `wu_threshold_gb`, `wu_blocked_by_free_space`, `low_space_volumes`).
- "How does this volume actually live on disk?" -> `summary/storage.json` -> `disks[*].partitions[*]` (disk -> partition -> volume traversal, including dynamic disks and storage spaces in `virtual_disks` / `storage_pools`).
- "Why is this box not getting patches from WSUS?" -> `summary/patching.json` -> `wu_client_state` (`flags.scan_stale`, `flags.install_stale`, `flags.download_stuck_likely`, `flags.wsus_reporting_stale`, plus per-field ages and `install_path` of `wua_direct` / `wsus_or_sccm` / `unknown`) and `wsus_check.verdict` (`wsus_responding`, `tcp_blocked`, `http_ok_but_not_wsus`, `http_error`, `no_wsus_configured`, `skipped_by_parameter`). The probe hits the WUA-canonical client endpoint `ClientWebService/Client.asmx?WSDL` plus `SelfUpdate/wuident.cab`.
- "Is Secure Boot on, and is this UEFI or BIOS?" -> `summary/inventory.json` -> `firmware_type` (`UEFI`, `BIOS`, or `unknown`) and `secure_boot` (`enabled`, `disabled`, `not_applicable`, `requires_elevation`, `unknown`). On UEFI without elevation the collector falls back to reading `HKLM:\System\CurrentControlSet\Control\SecureBoot\State\UEFISecureBootEnabled`.

## Severity vocabulary (`manifest.collection_errors[].severity`)

- `info` -- not applicable on this host (channel absent, role absent, key
  absent, collector skipped). Not a failure; just context.
- `warning` -- collector produced reduced output. Inspect what it did
  return.
- `error` -- collector produced no output for its category. Treat the
  category as missing.

## Drill-down recipes

Some artifacts are binary or otherwise opaque. The summary will point at
them; here is how to read them.

### EVTX (`raw/eventlogs/*.evtx`)

```
# Full text of every record matching an EventID
wevtutil qe raw\eventlogs\System.evtx /lf:true /q:"*[System[EventID=7031]]" /f:text

# Same in PowerShell
Get-WinEvent -Path raw\eventlogs\System.evtx -FilterXPath "*[System[EventID=7031]]" |
    Select-Object TimeCreated, Id, ProviderName, Message
```

### Performance counters (`raw/perf/snapshot.blg`)

```
Import-Counter -Path raw\perf\snapshot.blg |
    Select-Object -ExpandProperty CounterSamples |
    Where-Object Path -like '*Processor*' |
    Format-Table Timestamp, Path, CookedValue
```

### Windows Update ETL (`raw/windowsupdate/*.etl`)

```
Get-WindowsUpdateLog -ETLPath raw\windowsupdate -LogPath WindowsUpdate.log
# then read WindowsUpdate.log as plain text
```

### WUA reporting events (`raw/windowsupdate/ReportingEvents.log`)

Plain text. Each line is one event WUA tried to send to WSUS. Recent
"AU successfully reported event" lines mean the box is checking in;
"AU failed to report" means it is not. The artifact is the last 1MB
when the source file is oversize.

### WER reports (`raw/wer/reports/<report_dirname>/`)

Each report directory holds the per-crash artifacts WER produced. The text
manifest is `Report.wer` -- plain text, open with any editor; key fields:

```
EventName=AppHang | AppCrash | Critical
AppName=...
AppVersion=...
ModuleName=...
```

If a `.cab` is present, expand it for the embedded minidump and additional
metadata:

```
expand.exe -F:* raw\wer\reports\<dirname>\Report.cab .\extracted\
```

Hosts that have WER consent locked down (`DontShowUI` /
`DontSendAdditionalData`) typically produce only the `Report.wer` manifest --
no cab. The manifest alone is still enough to identify which faulting module
crashed and when.

### Boot timeline (`summary/boot_timeline.json`)

Pre-computed at collection time from System EVTX. Read `anomalies[]` first --
each entry has a `severity` (`warning` or `critical`) and a `type`
(`incomplete_boot`, `missing_shutdown_event`, `abnormal_gap`). Then walk
`boots[]` for per-boot detail (`boot_type` is `clean` or `dirty`,
`shutdown_initiator` taxonomy includes `interactive_admin_console`,
`cloudbase_init`, `salt_orchestrator`, `windows_update`,
`kernel_initiated`, `bugcheck`, etc.). The `cloudbase_init` label is
matched on a full-path `\Cloudbase Solutions\Cloudbase-Init\` substring
OR a `*\cloudbase-init` shutdown user, and is checked BEFORE the
generic `python.exe -> salt_orchestrator` rule (Cloudbase-Init runs as
python.exe so the leaf check alone would mis-attribute).
Built-in Administrator detection respects RID 500, so renamed accounts
(e.g. `_lslocal`) are still classified as admin-console actions.

Local-time conversion (e.g. EventLog 6008 message text contains a local
timestamp) is done using `summary/inventory.json` -> `time_zone` -- the
`current_utc_offset_minutes` is the offset at collection time. If
`dst_transition_in_window = true`, double-check times that fall on the DST
boundary.

### Salt minion (`raw/salt/`, `summary/salt.json`)

`summary/salt.json -> data.installed = false` is the no-Salt case. When
installed:

- `version` and `minion_id` come from `salt-call --version` and the parsed
  `conf/minion`.
- `recent_jobs_count` is jobs in window from `var/cache/salt/minion/proc/`;
  the full per-JID inventory is in `raw/salt/jobs_recent.csv` (filename +
  size + mtime, payload not included).
- `raw/salt/minion_log_tail.log` is the last 5MB of the active minion log;
  use `Select-String 'ERROR|WARNING|state.apply|win_wua'` for the highlights.
- `data.other_orchestrators_detected` is best-effort PDQ Deploy / PDQ
  Inventory service detection. Bolt and Ansible run agentlessly against
  Windows targets and are not detected by design.

The PKI directory (`conf/pki/`) is NEVER collected. Pillar data is NEVER
read. Salt config files are passed through the standard
password/secret/token redaction pass; treat anything in `raw/salt/conf/`
as scrubbed.

### Salt patching automation logs (`raw/salt/patching_automation/`)

The org's custom Salt patch orchestration writes its own log file separate
from the salt-minion log. Source path on the host is
`C:\salt_custom_logs\patching_automation\` (always collected when present,
independent of Salt install detection). Active `patching.log` plus up to
three rotated `patching.log.YYYY-MM-DD` files; ~1MB total in practice.

These logs are the **operator-decisions layer above Microsoft's mechanics**.
WUA / Setup.evtx tell you what packages installed or failed at the OS
level. The Salt patching log tells you which window the host SHOULD have
patched in, which GUIDs Salt actually attempted, what Salt's wrapper
around `win_wua` decided, and how many post-patch reboots have already
happened in the current window. Always read these BEFORE forming a
hypothesis from WUA / Setup.evtx data alone; Salt may have made a
correct decision that looks like a Microsoft-side failure (or vice versa).

Highest-leverage greps:

```
Select-String -Path raw\salt\patching_automation\*.log -Pattern '----> (Starting|Resuming|Patch installation)'
Select-String -Path raw\salt\patching_automation\*.log -Pattern 'Patching (start|end|group):'
Select-String -Path raw\salt\patching_automation\*.log -Pattern 'Found \d+ update.*for installation'
Select-String -Path raw\salt\patching_automation\*.log -Pattern 'Failed to download'
Select-String -Path raw\salt\patching_automation\*.log -Pattern '\[FAIL\]|\[OK-WITH-ERRORS\]'
Select-String -Path raw\salt\patching_automation\*.log -Pattern '\[patch-error\]'
Select-String -Path raw\salt\patching_automation\*.log -Pattern 'outside its scheduled maintenance window'
Select-String -Path raw\salt\patching_automation\*.log -Pattern 'restart.*time.*maintenance window'
Select-String -Path raw\salt\patching_automation\*.log -Pattern 'Failed to add job|Successfully created/updated patching schedule'
```

`summary/salt.json -> data.patching_logs` carries per-file metadata
(active log size + mtime, rotated file inventory, total bytes) for an
at-a-glance "did we capture them" check.

### Salt live probes (`raw/salt/probes/`, `summary/salt.json -> data.probes`)

Live `salt-call --local` (and master-touching) probes are recorded as
both raw JSON output under `raw/salt/probes/` and pre-parsed summary
fields under `summary/salt.json -> data.probes`.

- `test_ping.json` -- `salt-call --local test.ping`. `data.probes.test_ping_ok` is
  the boolean answer.
- `grains_items.json` -- full grains output. Also written separately as
  `summary/salt_grains.json` for direct consumption. The most common
  trap on this fleet is an empty `ssnc_server_role` grain -- it gates
  the master's top.sls targeting; an empty value generally means
  highstate will apply zero states.
- `is_running.json` -- `saltutil.is_running` (currently executing JIDs).
- `state_show_top_<env>.json` -- `state.show_top` for the active saltenv
  and `base`. `data.probes.show_top_active_env_assignment_count = 0` is
  the canonical "no states match this host in the active environment"
  signal, flagged as a `warning` in `collection_errors`. Cross-reference
  against `data.org_grains.ssnc_server_role`: an empty role grain is
  the most common cause of zero assignments.

### Salt PKI inventory (`summary/salt.json -> data.pki_files`)

Per-file `{ name, size_bytes, mtime_utc, sha256 }` for `minion.pub`,
`minion_master.pub`, `master_sign.pub` (public keys hashed for forensic
identity) and `minion.pem` (length only, never hashed -- defense in
depth against future "we always hash" refactors). The private key file
contents are NEVER read or copied.

When `data.verify_master_pubkey_sign_required = true` (the minion conf
sets `verify_master_pubkey_sign: True`) and `master_sign.pub` is
absent, the collector raises severity `error`:
`verify_master_pubkey_sign is True but master_sign.pub is missing ...
Every published job will be silently rejected.` Treat as a hard
blocker, not a warning.

### Cloudbase-Init (`raw/cloudbase_init/`, `summary/cloudbase_init.json`)

Cloudbase-Init is the OpenStack-family first-boot agent (analog of
cloud-init) used by OpenShift Virt, OpenStack, and many KVM-based
clouds for Windows VMs. Detection is install-path based and not gated
on hypervisor.

- `data.version` -- parsed from the "Cloudbase-Init version:" line.
- `data.last_run_outcome` -- `succeeded` iff the log ends with
  "Plugins execution done", otherwise `failed` or `unknown`.
- `data.plugins[]` -- ordered list of plugin invocations with start
  timestamps and stages (PRE_NETWORKING, PRE_METADATA_DISCOVERY, MAIN).
- `data.local_scripts[]` -- per-script outcome. Each entry has
  `exit_code`, `stdout_bytes`, `stderr_bytes`, and `stderr_had_content`.
  **The silent-failure pattern is `exit_code = 0` AND
  `stderr_had_content = true`.** Cloudbase-Init's
  fileexecutils plugin reports the script as "ended with exit code: 0"
  even when stderr contains a fatal Start-ScheduledTask /
  CommandNotFoundException-class error. The collector flags this combo
  as a `warning` in `collection_errors`; that is your starting point
  for "why did first-boot succeed in the log but the host is broken."
- `data.reboots_initiated[]` -- timestamps of every "Rebooting" line
  in the log. Cross-reference with `summary/boot_timeline.json` ->
  `boots[].shutdown_initiator = "cloudbase_init"`.
- `data.metadata_service`, `data.instance_id` -- which metadata
  service handed off the userdata (NoCloudConfigDriveService etc.)
  and the cloud-side instance UUID.

Raw artifacts:
- `raw/cloudbase_init/log/cloudbase-init.log` (5 MB tail) -- the
  authoritative source for the last run. Re-read it directly when
  the summary points at a suspicious plugin or script.
- `raw/cloudbase_init/log/cloudbase-init-unattend.log` (1 MB tail).
- `raw/cloudbase_init/conf/cloudbase-init.conf` and
  `cloudbase-init-unattend.conf`.
- `raw/cloudbase_init/LocalScripts/*` -- the actual PowerShell
  scripts cloudbase-init invokes at first boot, with sha256 in
  `summary/cloudbase_init.json -> data.local_scripts_inventory[]` so
  you can correlate against the gold image build pipeline. These are
  small, static scripts; capturing the contents (not just the
  inventory) means you can read the actual `Start-ScheduledTask -TaskName SaltHighState`
  call site in `02-highstate.ps1` from inside the bundle.
- `raw/cloudbase_init/userdata.txt` (best-effort; NoCloud cidata is
  typically unmounted post-boot so absence is normal). Passed through
  the standard password/secret/token redaction pass.

### Registry exports (`raw/registry/*.reg`)

Plain text but UTF-16 LE with BOM (reg.exe writes that format). Open with
any editor; a grep of the key path locates the value.

### Minidumps (`raw/dumps/*.dmp`)

Open in WinDbg or `dotnet-dump analyze`. The bundle does not include
symbols; the consumer needs the public symbol server (or a private one for
non-Microsoft binaries).

### SQL self-dumps (`raw/role_specific/sql_dumps/<instance>/SQLDump<NNNN>.*`)

When SQL Server hits an in-process exception it drops three companions in
its LOG dir: `SQLDump<NNNN>.mdmp` (binary minidump), `SQLDump<NNNN>.txt`
(plain-text stack and short-stack signatures), and `SQLDump<NNNN>.log`
(additional log). The `.txt` is the easiest first read; it carries:

```
This file is generated by Microsoft SQL Server ...
... ExceptionAddress, ExceptionCode, FaultingInstruction, etc.
... Short Stack Dump
... module!function frames
```

Match the `<NNNN>` against the matching `Critical_sqlservr.exe` Report.wer
under `raw/wer/reports/` for the WER side of the same crash. Open the
`.mdmp` in WinDbg with the SQL public symbols if a deeper view is needed.

## Known caveats

- The **Security** channel is collected in **minimal-summary mode** by
  default. The raw EVTX (`raw/eventlogs/Security.evtx`) is exported with
  the standard window filter, but the per-event aggregation in
  `events_summary.json` is skipped: the Security channel block has
  `summary_mode = "minimal_metadata_only"`, all aggregate fields
  (`total`, `top_events`, `timeline_5min`, etc) are null/empty, and a
  `live_log_record_count` + `live_log_file_size_bytes` from the live log
  metadata (no scan) are included. Drop this if you need top-events
  aggregates: change `SummaryMode = 'minimal'` to `'full'` for Security in
  `Get-DiagEventLogs.ps1`. Why this is the default: on busy Security logs
  the Get-WinEvent scan dominates total bundle time (measured 645 seconds
  on a 192MB / 323k-event log) while the resulting top-events list is
  always 4624/4634 logon noise. Real Security analysis goes against the
  raw EVTX with `wevtutil qe` filtered by SID, EventID, or source IP.
- `manifest.size_budget.zip_compressed_bytes` is always `0` inside the
  bundle. The bundle is sealed before the ZIP exists. The real compressed
  size is whatever this ZIP file is on disk.
- `manifest.redactions_applied: []` means "no redaction patterns matched
  in the four scanned files", not "redaction was disabled". Redaction is
  always on; the scan list is intentionally narrow.
- `manifest.time_window.perf_from_utc` and `perf_to_utc` are present only
  when the Performance collector ran successfully.
- `manifest.baseline.available = false` is the default state for hosts
  with no baseline ever captured. Not an error.
- Empty `raw/` subdirectories are normal -- the collector creates the
  layout up front and leaves the directory if its collector found no
  eligible content (no dumps, no GPO output under non-elevated runs, etc.).
- `transcript/collector.log` is line-delimited JSON, one entry per event,
  not pretty-printed JSON. Parse line-by-line.
- `manifest.collection.elevation = User` means several collectors degraded:
  `gpresult` produces no file, some service state is unreadable, dcdiag
  and certain registry exports are absent. Plan re-collection under
  Administrator or SYSTEM if a category came back empty.
- `manifest.collection.elevation = Administrator` is the typical ad-hoc
  invocation; works for the great majority of artifacts but a small
  number of SYSTEM-only paths can be partially readable: certain
  registry hives (HKEY_USERS subkeys for inactive profiles), hidden
  scheduled-task ACLs, and a handful of Security log entries written
  with restrictive DACLs. The production Salt-invoked collection path
  runs as SYSTEM so unattended bundles are uniformly complete.
  Re-collect under SYSTEM (`PsExec -s` or via a one-shot scheduled
  task) only if a specific Administrator-collected bundle is missing
  the field you need.
