# DiagBundle -- Windows Server Diagnostic Bundle Collector

> Project context for Claude Code. This file captures the design decisions made
> before implementation began so future sessions don't re-ask answered questions.

## Project goal

Build a PowerShell module, **DiagBundle**, that collects a one-shot diagnostic
bundle from a Windows Server for analysis by an AI agent. The bundle is a ZIP
containing:

- Pre-aggregated JSON summaries optimized for LLM consumption
- Raw artifacts (EVTX, CBS.log, perf BLG, etc.) preserved for forensic value
  and human follow-up
- A manifest describing every artifact with provenance, schema version, and
  checksums

Primary scenarios:

1. **Post-patch troubleshooting** -- what changed, what failed, what's pending
2. **General performance investigation** -- current state, trends, top consumers
3. **Forensic preservation** -- raw event logs and supporting files captured at
   the time of the incident, before they roll over

## Target environment

- ~50,000 Windows Server VMs (VMware + OpenShift) across global datacenters
  (Singapore, Tokyo, Kansas City, St. Louis, London, Wales)
- 180+ Active Directory domains
- Mixed Windows Server versions (2016, 2019, 2022; some 2012 R2 lingering)
- Existing tooling: Salt for patch orchestration, Citrix VDA infrastructure,
  file servers with Resilio Sync + DFS namespaces, AWS EC2 with SSM
- Existing module distribution pipeline: GitHub -> Artifactory NuGet feed ->
  GPO-deployed PSRepository. **DiagBundle ships through this same pipeline.**

## Locked design decisions

These have been agreed and should not be re-litigated without explicit cause:

| # | Decision | Value |
|---|----------|-------|
| 1 | Trigger model | **On-demand only.** Invoked manually, via Salt, or via WinRM. No scheduled task or event-triggered collection. |
| 2 | Default time window | **24 hours**, with `-WindowHours <int>` parameter to extend |
| 3 | Redaction policy | **Conservative.** Mask password/secret/token/apikey patterns in command lines and known sensitive registry values. Don't redact aggressively. |
| 4 | Baseline-aware diff | **Yes.** Maintain a small `C:\ProgramData\DiagBundle\baseline\` with last-known-good service inventory, autoruns, scheduled tasks, top-process list. Diff included in summary if baseline exists; no-op if not. |
| 5 | Crash artifact inclusion | **Include WER cabs and minidumps if present and dated within one week of the collection time window.** Index-only otherwise. Total cap (suggested 50MB) flagged in manifest. |
| 6 | Distribution | **PowerShell module with semantic version tracking**, shipped through the existing GitHub -> Artifactory -> GPO PSRepository pipeline |
| 7 | Output | **One ZIP per collection.** Filename: `<hostname>_<YYYYMMDD-HHMMSS>_diagbundle.zip` |
| 8 | Total size budget | Soft target 100-500MB compressed. Hard ceiling 2GB; collector trims oldest-first when exceeded and logs truncation in `collection_errors`. |

## Architecture overview

```
Invoke-DiagBundle.ps1 (public entry point)
  +- New-WorkingDirectory
  +- Initialize-Manifest
  +- Run collectors (each writes artifacts + appends to manifest + logs)
  |   +- Inventory       (host identity, OS, hardware, uptime, firmware_type and secure_boot via Confirm-SecureBootUEFI with registry fallback; data.cloud block populated from Salt grains when available)
  |   +- Drivers         (pnputil /enum-drivers DriverStore packages + Win32_PnPSignedDriver bound drivers)
  |   +- Patching        (HotFix, update history via Microsoft.Update.Session, pending reboot incl. SCCM via root\ccm\ClientSDK, WSUS/WUfB policy + WU client state, CBS.log tail, WindowsUpdate.etl)
  |   +- EventLogs       (EVTX raw + summary JSON, filtered; boot_timeline built here from System EVTX with kernel-event-12 as canonical boot time)
  |   +- Performance     (60s Get-Counter snapshot + BLG, baseline BLG if present) [serial, blocks 60s]
  |   +- Services        (state, startup type, account, dependencies)
  |   +- Processes       (top by CPU, memory, handles, threads; full path, command line, parent)
  |   +- Storage         (volumes, free space, VSS, dump file presence)
  |   +- Network         (ipconfig, route, listening ports, DNS, firewall)
  |   +- AD              (domain join, GPO refresh, gpresult, w32tm, dcdiag if DC)
  |   +- WER             (ReportArchive/ReportQueue, optional cab inclusion per decision #5)
  |   +- Registry        (WindowsUpdate policies, pending reboot keys, autoruns)
  |   +- ScheduledTasks  (full XML export + expected-task absence check driven by Resources/expected_tasks.json)
  |   +- Salt            (install state, tolerant YAML parse of minion conf, PKI inventory, TCP probes to master 4505/4506, live salt-call --local probes incl. state.show_top, patching automation logs, PDQ peer detection)
  |   \- Roles           (dispatches to role-specific: IIS, SQL, Citrix, DFSR, Hypervisor [VMware/Hyper-V/KVM via plugin table], Cloudbase-Init)
  +- Reconcile last_boot_utc  (cross-collector: if Win32_OperatingSystem.LastBootUpTime disagrees with boot_timeline's kernel-event-12 start_utc by >60s, trust the kernel event and patch manifest.host.last_boot_utc and summary/inventory.json. Preserves the CIM value and delta for traceability. Catches the OpenShift Virt RTC quirk where boot stamps come from a pre-NTP-correction wall clock.)
  +- Apply-Redactions
  +- Compute-Checksums
  +- Finalize-Manifest
  \- Compress-Bundle
```

Collectors run **serial** in v1.0; runspace-based parallelism is deferred.
Most of the wall-clock cost is EVTX export and the 60-second perf sample,
so parallelism gains less than the diagram appears to promise. Performance
runs **last** because it blocks for the 60-second sample window. Each
collector is isolated -- failure in one MUST NOT abort the bundle. All
errors are caught and logged to `manifest.collection_errors` so the agent
can distinguish "missing because not applicable" from "missing because failed."

## Public API

Single exported function: `Invoke-DiagBundle`.

| Parameter | Default | Notes |
|---|---|---|
| `-WindowHours <int>` | 24 | Range 1-720. Time window for event logs and other time-bounded collectors. |
| `-OutputPath <string>` | `C:\ProgramData\DiagBundle\output` | Directory the ZIP is written to. |
| `-Scenario <set>` | `general` | Set: `post_patch`, `performance`, `general`, `forensic`. **Hint only** -- stamped into `manifest.collection.scenario_hint`. Does NOT gate which collectors run; every scenario collects all. |
| `-SkipCollector <string[]>` | `@()` | Names matching the suffix after `Get-Diag` (`Inventory`, `Drivers`, `Patching`, `Services`, `Processes`, `Storage`, `Network`, `AD`, `Registry`, `ScheduledTasks`, `EventLogs`, `WER`, `Salt`, `Roles`, `Performance`). Useful for `-SkipCollector Performance` during iteration to avoid the 60s block. |
| `-IncludeCrashArtifacts <bool>` | `$true` | Per locked decision #5. |
| `-MaxBundleBytes <long>` | 2GB | Range 100MB-10GB. Hard ceiling on raw bytes; trim oldest-first when exceeded. |
| `-SkipNetworkTests <bool>` | `$false` | When `$true`, skip collector probes that initiate outbound network traffic: Get-DiagPatching's WSUS interrogation (HTTP) and Get-DiagSalt's TCP probes to the configured Salt master ports 4505/4506. Live `salt-call --local` probes are NOT gated by this flag (they are process-local). Use in environments where the collector must not initiate outbound traffic. |
| `-ProblemDescription <string>` | (none) | Optional operator narrative stamped into `manifest.collection.problem_description`. Cap 8 KB UTF-8; control chars stripped except CR/LF/TAB; redacted. Mutually exclusive with `-ProblemDescriptionFile`. |
| `-ProblemDescriptionFile <path>` | (none) | UTF-8 text file (max 1 MB) holding the description. Same final 8 KB cap as the string form. |
| `-PromptForProblem` | switch | Open a modal STA WinForms textbox for the operator. Requires `[System.Environment]::UserInteractive`; throws under SYSTEM / Salt / WinRM / SSM. May be combined with the string params (they prefill the textbox). Cancel records `source = prompt_cancelled`. |

Returns `[pscustomobject]` with `BundleId`, `ZipPath`, `ZipBytes`, `StartedUtc`, `CompletedUtc`, `DurationSeconds`.

Progress: top-level `Write-Progress` (Id=1) ticks once per collector + per
post-step. `Get-DiagEventLogs` and `Get-DiagPerformance` emit child progress
(Id=2 -ParentId 1) for per-channel and "blocking 60s" status. Set
`$ProgressPreference = 'SilentlyContinue'` before the call when running
under Salt/SSM where stdout is captured.

## Repo structure

```
DiagBundle/
+-- DiagBundle.psd1              # module manifest (version, exports, deps)
+-- DiagBundle.psm1              # module loader (recursively dot-sources Private/ + Public/)
+-- Public/
|   \-- Invoke-DiagBundle.ps1    # the only exported function
+-- Private/
|   +-- Collectors/
|   |   +-- Get-DiagInventory.ps1
|   |   +-- Get-DiagDrivers.ps1
|   |   +-- Get-DiagPatching.ps1
|   |   +-- Get-DiagEventLogs.ps1
|   |   +-- Get-DiagPerformance.ps1
|   |   +-- Get-DiagServices.ps1
|   |   +-- Get-DiagProcesses.ps1
|   |   +-- Get-DiagStorage.ps1
|   |   +-- Get-DiagNetwork.ps1
|   |   +-- Get-DiagAD.ps1
|   |   +-- Get-DiagWER.ps1
|   |   +-- Get-DiagRegistry.ps1
|   |   +-- Get-DiagScheduledTasks.ps1
|   |   +-- Get-DiagSalt.ps1
|   |   +-- Get-DiagRoles.ps1
|   |   \-- Roles/
|   |       +-- Get-DiagRoleIIS.ps1
|   |       +-- Get-DiagRoleSQL.ps1
|   |       +-- Get-DiagRoleCitrix.ps1
|   |       +-- Get-DiagRoleDFSR.ps1
|   |       +-- Get-DiagRoleHypervisor.ps1
|   |       +-- Get-DiagRoleCloudbaseInit.ps1
|   |       \-- Hypervisor/                 # per-platform plugins dispatched by Get-DiagRoleHypervisor
|   |           +-- _DiagHvCommon.ps1
|   |           +-- Get-DiagHvVMware.ps1
|   |           +-- Get-DiagHvHyperV.ps1
|   |           \-- Get-DiagHvKvm.ps1
|   +-- Manifest/
|   |   +-- Initialize-DiagManifest.ps1
|   |   +-- Add-DiagArtifact.ps1
|   |   \-- Complete-DiagManifest.ps1
|   +-- Redaction/
|   |   \-- Invoke-DiagRedaction.ps1
|   +-- Baseline/
|   |   +-- Get-DiagBaseline.ps1
|   |   +-- Update-DiagBaseline.ps1
|   |   \-- Compare-DiagBaseline.ps1
|   \-- Util/
|       +-- Write-DiagLog.ps1
|       +-- Get-DiagChecksum.ps1
|       +-- Compress-DiagBundle.ps1
|       +-- Build-DiagBootTimeline.ps1
|       +-- Get-DiagTimezone.ps1
|       +-- Invoke-DiagTimed.ps1
|       +-- Probe-DiagWsus.ps1
|       +-- Resolve-DiagProblemDescription.ps1
|       +-- Show-DiagProblemPrompt.ps1
|       \-- Show-DiagProblemPrompt.Child.ps1
+-- Resources/                   # static files copied verbatim into every bundle
|   +-- README.md                # consumer orientation, drill-down recipes, caveats
|   +-- expected_tasks.json      # data-driven expected-task list for Get-DiagScheduledTasks (seed: SaltHighState)
|   \-- prompts/                 # per-scenario investigation scaffolds
|       +-- post_patch.md
|       +-- performance_regression.md
|       +-- general_triage.md
|       \-- forensic_preservation.md
+-- Schemas/
|   \-- manifest.schema.json     # JSON Schema for manifest.json
+-- Tests/
|   +-- Unit/                    # Pester tests against synthetic fixtures
|   \-- Integration/             # Tests against captured real fixtures
+-- Fixtures/                    # Captured EVTX/CBS/perf samples for tests
+-- docs/
|   \-- plans/
|       +-- initial-design.md    # this design, expanded
|       \-- 2026-05-11-collector-gaps-cloudbaseinit-salt.md   # post-investigation plan + decisions D1-D9
\-- README.md
```

## ZIP layout (output)

```
hostname_YYYYMMDD-HHMMSS_diagbundle.zip
+-- manifest.json                       # entry point -- agent reads this first
+-- summary/                            # AI-friendly, pre-aggregated JSON
|   +-- inventory.json                  # schema 1.1: + data.cloud block (Salt-grain-derived image/project/etc.)
|   +-- drivers.json
|   +-- patching.json
|   +-- events_summary.json             # schema 1.1: + detected_platform + interesting_providers index
|   +-- boot_timeline.json              # per-boot records, gaps, anomalies; canonical last_boot source for cross-collector reconciliation
|   +-- processes.json
|   +-- services.json
|   +-- perf_summary.json
|   +-- storage.json
|   +-- network.json
|   +-- ad_context.json
|   +-- crashes_wer.json                # schema 1.3: + kernel_dumps block (CrashControl policy + LiveKernelReports inventory)
|   +-- roles_apps.json
|   +-- hypervisor.json                 # platform detection + guest agent + paravirt drivers + time-sync
|   +-- salt.json                       # schema 1.2: install state, masters, PKI inventory, master TCP probes, live salt-call probes
|   +-- salt_grains.json                # full grains.items output as JSON (when salt-call probe succeeded)
|   +-- cloudbase_init.json             # last-run summary: version, plugins, LocalScripts exit codes, reboots (when Cloudbase-Init installed)
|   +-- scheduled_tasks.json            # expected-task absence check (driven by Resources/expected_tasks.json)
|   \-- baseline_diff.json              # only if baseline exists
+-- raw/                                # forensic preservation, untransformed
|   +-- eventlogs/
|   |   +-- System.evtx
|   |   +-- Application.evtx
|   |   +-- Security.evtx               # filtered at copy time via XPath
|   |   +-- Setup.evtx
|   |   +-- Microsoft-Windows-WindowsUpdateClient%4Operational.evtx
|   |   +-- Microsoft-Windows-Servicing.evtx
|   |   \-- ... (other operational channels)
|   +-- cbs/
|   |   +-- CBS.log                     # tail if >50MB
|   |   \-- CbsPersist_*.log            # most recent 1-2 archives
|   +-- windowsupdate/
|   |   +-- WindowsUpdate.etl.*
|   |   \-- ReportingEvents.log         # WUA reporting events (1MB tail when oversize)
|   +-- drivers/
|   |   +-- pnputil_enum_drivers.txt    # DriverStore packages (third-party + OEM)
|   |   +-- driverquery.csv             # all kernel-mode + FS drivers, with State/Status/Path
|   |   +-- fltmc_filters.txt           # loaded file-system minifilters (altitude)
|   |   \-- fltmc_instances.txt         # per-volume minifilter attachments
|   +-- perf/
|   |   +-- snapshot.blg
|   |   \-- baseline.blg                # if rotating collector exists
|   +-- wer/
|   |   +-- ReportArchive_index.csv
|   |   \-- reports/                    # one subdir per in-window report; full contents per locked decision #5
|   |       \-- <report_dirname>/
|   |           +-- Report.wer          # text manifest (always present)
|   |           +-- Report.cab          # only if WER assembled it
|   |           \-- ... (memory.hdmp, sysdata.xml, etc., subject to per-report cap)
|   +-- netsh/
|   |   +-- ipconfig.txt
|   |   +-- route.txt
|   |   +-- netstat.txt
|   |   \-- firewall.txt
|   +-- gpo/
|   |   +-- gpresult.html
|   |   \-- gpresult.xml
|   +-- registry/
|   |   +-- windowsupdate_policies.reg     # SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
|   |   +-- windowsupdate_client_state.reg # SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate
|   |   +-- pending_reboot_cbs.reg         # CBS\RebootPending leaf
|   |   +-- pending_reboot_au.reg          # WU\Auto Update\RebootRequired leaf
|   |   +-- sccm_reboot_data.reg           # SMS\Mobile Client\Reboot Management\RebootData
|   |   \-- autoruns_export.csv            # Win32_StartupCommand inventory
|   +-- tasks/
|   |   \-- scheduled_tasks.xml
|   +-- dumps/
|   |   +-- minidump_index.csv
|   |   +-- *.dmp                       # only if within window per decision #5
|   |   \-- livekernelreports/          # in-window LKR files under LkrCopyCapBytes (default 1GB)
|   +-- salt/                           # conf/minion, conf/minion_id, conf/minion.d/*, conf/grains, minion_log_tail.log, probes/, patching_automation/ (PKI private key never read)
|   +-- cloudbase_init/                 # log/*.log (5MB+1MB tails), conf/*.conf, LocalScripts/* contents + sha256, userdata.txt (best-effort, redacted)
|   \-- role_specific/
|       +-- iis_w3svc_lastday/
|       +-- sql_errorlog/
|       +-- sql_dumps/                  # SQLDump<NNNN>.{mdmp,txt,log} per instance, within window/cap
|       +-- citrix_*.txt
|       +-- dfsr_health.xml
|       \-- hypervisor/                 # <platform>/  -- vmware/, hyperv/, kvm/  agent logs + paravirt registry + installer logs
+-- transcript/
|   \-- collector.log                   # PowerShell transcript + structured JSON log
+-- README.md                           # bundle orientation for cold consumers
+-- prompts/                            # investigation scaffolds (one per Scenario)
|   +-- post_patch.md
|   +-- performance_regression.md
|   +-- general_triage.md
|   \-- forensic_preservation.md
\-- checksums.txt                       # SHA256 of every file
```

**Why split summary/ from raw/:** The agent loads `manifest.json` and the
`summary/` files into context first (small, structured, opinionated). It
references `raw/` files by path only when summary data hints at something
worth investigating deeper. Raw is also what a human takes if they pick up
the case from the agent.

## Manifest schema (current: v1.3)

The manifest is the contract between collector and agent. Pin
`schema_version` from day one and treat it as a stability commitment. See
`Schemas/manifest.schema.json` for the formal JSON Schema, and
`Resources/README.md` for the change log of bumps (1.0 -> 1.1 added
`boot_timeline.json` / `salt.json` and structured `time_zone`; 1.1 -> 1.2
added `collection.problem_description`; 1.2 -> 1.3 added `timings`
block). Per-summary schema versions are independent of the manifest
version and are tracked in `Resources/README.md`.

```json
{
  "schema_version": "1.3",
  "bundle_id": "uuid",
  "host": {
    "computer_name": "...",
    "fqdn": "...",
    "domain": "...",
    "os_version": "10.0.20348.2402",
    "os_caption": "Microsoft Windows Server 2022 Datacenter",
    "install_date": "2023-04-15T08:12:00Z",
    "last_boot_utc": "2026-04-25T03:14:22Z"
  },
  "collection": {
    "collector_version": "1.0.0",
    "started_utc": "2026-04-27T14:00:00Z",
    "completed_utc": "2026-04-27T14:02:22Z",
    "duration_seconds": 142,
    "scenario_hint": "post_patch",
    "elevation": "SYSTEM",
    "powershell_version": "5.1.20348.2400"
  },
  "time_window": {
    "events_from_utc": "2026-04-26T14:00:00Z",
    "events_to_utc": "2026-04-27T14:00:00Z",
    "window_hours": 24,
    "perf_from_utc": "2026-04-27T14:00:00Z",
    "perf_to_utc": "2026-04-27T14:01:00Z"
  },
  "artifacts": [
    {
      "path": "summary/events_summary.json",
      "category": "events_summary",
      "schema_version": "1.0",
      "type": "derived",
      "source_artifacts": ["raw/eventlogs/System.evtx", "raw/eventlogs/Application.evtx"],
      "row_count": 312,
      "size_bytes": 88421,
      "sha256": "...",
      "description": "Aggregated error/warning events, 24h window, top 200 by count"
    },
    {
      "path": "raw/eventlogs/System.evtx",
      "category": "eventlog_raw",
      "channel": "System",
      "type": "raw",
      "events_count": 8421,
      "events_from_utc": "...",
      "events_to_utc": "...",
      "size_bytes": 22118400,
      "sha256": "..."
    }
  ],
  "collection_errors": [
    {
      "artifact": "summary/sql_*.json",
      "collector": "Get-DiagRoleSQL",
      "reason": "SQL Server detected but Get-DbaInstance failed: <error>",
      "severity": "warning"
    }
  ],
  "redactions_applied": [
    "powershell_command_password_args",
    "connection_strings"
  ],
  "size_budget": {
    "raw_uncompressed_bytes": 412000000,
    "summary_uncompressed_bytes": 1840000,
    "zip_compressed_bytes": 78000000,
    "truncations": []
  },
  "baseline": {
    "available": true,
    "captured_utc": "2026-04-20T14:00:00Z",
    "diff_artifact": "summary/baseline_diff.json"
  }
}
```

### Manifest contract caveats

- `size_budget.zip_compressed_bytes` is **always `0` inside the bundle**.
  The manifest is sealed before the ZIP exists; the real value is returned
  via the `Invoke-DiagBundle` result object (`ZipBytes`). Consumers that
  need the compressed size should stat the ZIP themselves.
- `time_window.perf_from_utc` / `perf_to_utc` are present only when the
  Performance collector ran successfully (absent when skipped or failed).
- `redactions_applied` is an empty array, not absent, when no redaction
  patterns matched.
- `baseline.available = false` is the no-baseline state; `baseline` is
  always present.

## Summary file conventions

All `summary/*.json` files share these conventions:

- UTF-8, no BOM
- ISO-8601 UTC timestamps everywhere (`Z` suffix, never local time)
- Top-level object with `schema_version`, `host`, `collected_utc`, `data`
- Truncation, when applied, is explicit:
  `"truncated_to": 200, "total_available": 4127, "sort_key": "count_desc"`
- Counts always present alongside samples -- even when shipping only top-N,
  include the full count so the agent knows it's seeing a sample

### events_summary.json -- highest-leverage file

For each channel collected:

- Total event count, error count, warning count
- Top N (50) `EventID + Provider` combinations by count, each with:
  - First/last timestamp
  - One canonical message text (representative)
  - Count
- Timeline histogram: events per 5-minute bucket
- Boot markers (6005/6006/6008/1074) called out separately, never truncated
- Setup/Servicing/WindowsUpdateClient channels: full ordered list of
  install/uninstall/reboot events in window -- low volume, high value, do not
  truncate

The agent's drill-down path: read summary -> identify suspicious EventID ->
call `wevtutil qe` or `Get-WinEvent -Path` against the raw EVTX with an XPath
filter to retrieve the full records. The collector does not need to ship a
parsed-EVTX JSON for every event.

## Implementation conventions

### PowerShell

- Target **PowerShell 5.1** for compatibility with the full server fleet.
  Use 7.x features only behind capability checks.
- All public function parameters use `[CmdletBinding()]` and PascalCase names.
- All collectors are functions in `Private/Collectors/`, named `Get-Diag<Category>`.
- Each collector returns a structured result object:
  `@{ Success = $bool; Artifacts = @(); Errors = @(); DurationSeconds = $n }`
- No `Write-Host`. Use `Write-DiagLog` (writes to transcript and structured log).
- Use `Write-Progress` for user-visible progress: top-level `Id=1` in the
  orchestrator, child `Id=2 -ParentId 1` inside slow collectors. Don't strip
  it during a "no console output" cleanup; respects `$ProgressPreference`.
- Catch all exceptions in collectors; never let one collector fail the bundle.
- Use approved verbs (Get, New, Invoke, etc.). `Get-Verb` if unsure.
- ASCII only (code points U+0020 through U+007E plus tab/newline/CR) in
  source files, log messages, and manifest content. Reformat any Unicode
  encountered from external sources (event log messages, registry values).
- **`Sort-Object`/`Group-Object`/`Measure-Object -Property <name>` does
  not reach `[ordered]@{}` keys in PS 5.1.** These cmdlets resolve
  `-Property` via type-member reflection, which does not see
  `OrderedDictionary` keys. The result is a silent no-op (sort returns
  input order) or a silent throw mid-pipeline (measure aborts the
  enclosing statement). When the input is an array of ordered hashtables,
  use a calculated property to access the key explicitly:

      $arr | Sort-Object -Property @{Expression={ [double]($_[$key]) }} -Descending
      $arr | Measure-Object -Property @{Expression={ $_[$key] }} -Sum

  Or extract the value with `ForEach-Object` before the aggregation:

      ($arr | ForEach-Object { [int]$_.total } | Measure-Object -Sum).Sum

  `Where-Object` and `Select-Object` are unaffected -- they dispatch
  through PowerShell's member adapter, which sees dictionary keys. Only
  the `-Property` argument on Sort/Group/Measure is affected. Three real
  bugs from this anti-pattern were caught and fixed during the first
  production bundle review (2026-04-28); add new ones to that list if you
  hit the same trap.
- **`System.Diagnostics.ProcessStartInfo.ArgumentList` is .NET Core /
  5+ only.** PowerShell 5.1 runs on .NET Framework 4.x, which exposes
  only `.Arguments` (single string). Using `ArgumentList.Add(...)` on
  PS 5.1 silently fails with "You cannot call a method on a null-valued
  expression." Same failure class as the Sort/Group/Measure trap above:
  the API looks right and parses fine, but does nothing useful at
  runtime. When launching a process with multiple arguments, build a
  quoted argument string and assign it to `.Arguments`:

      $quoted = $args | ForEach-Object {
          if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
      }
      $proc.StartInfo.Arguments = ($quoted -join ' ')

  Caught during the 2026-05-11 validation: the first salt-call probe
  rollout failed all five probes with the null-method error because
  `_RunSaltCallProbe` and the inventory cloud-grains probe both used
  `ArgumentList.Add(...)`. Fixed in 1.4.1.

### Error handling

- Every `try` has a `catch` that logs the error class, message, and stack to
  the structured log AND adds an entry to `manifest.collection_errors`.
- Severity levels: `info`, `warning`, `error`. `error` means the collector
  produced no output for its category.
- Never throw from a collector -- always return the result object with
  `Success = $false` and populated `Errors`.

### Testing

- Pester 5.x.
- Unit tests use synthetic fixtures (small JSON/XML/text files in `Fixtures/`).
- Integration tests use real captured EVTX/CBS/perf samples -- capture from
  representative roles (DC, file server, IIS host, SQL host, Citrix VDA).
- CI runs unit tests on every commit; integration tests on tagged builds.

### Versioning

- Semantic versioning (MAJOR.MINOR.PATCH).
- `manifest.schema_version` is independent of module version. Bump schema
  version only on breaking changes to the manifest contract.
- Module version in `DiagBundle.psd1` and stamped into
  `manifest.collection.collector_version`.

## Explicit non-goals (v1.0)

These have been considered and ruled out. Do not add them without revisiting
the decision here:

- **WU DataStore.edb** (`C:\Windows\SoftwareDistribution\DataStore\DataStore.edb`).
  ESE database, locked open by `wuauserv`, 50-500MB+, requires VSS via
  `esentutl /y /vss`. The COM-derived `update_history` (last 200 entries
  from `Microsoft.Update.Session.QueryHistory`) covers post-patch
  troubleshooting without it. Revisit only if forensic preservation of WUA
  internal state becomes a documented need.
- **Parsed-EVTX JSON for every event.** Events are summarized by
  EventID+Provider in `summary/events_summary.json`; the full records stay
  in raw EVTX and the agent drills in via `wevtutil qe` / `Get-WinEvent -Path`.
- **DataStore.edb-derived "scan history" / Delivery Optimization peer state.**
  Same lock and size concerns as DataStore.edb itself; low diagnostic value
  outside narrow scenarios.
- **Driver update history as a separate artifact.** Already in
  `update_history` -- not separated.

## Open items for implementation

These are known unknowns to resolve during implementation, not blockers:

1. **Module name prefix** -- confirm whether the org convention is bare
   `DiagBundle` or a prefixed name like `SSC.DiagBundle`. Check existing
   modules in the Artifactory feed.
2. **Code signing** -- determine signing cert and signing step in the build
   pipeline. Required for execution under restrictive policies.
3. **Test fixture capture** -- write a small helper script to capture
   sanitized fixtures from each representative role. Store in `Fixtures/`
   with redactions applied.
4. **Role detection** -- finalize the detection logic for IIS, SQL, Citrix,
   DFSR. Prefer feature/service presence over registry sniffing. Cloudbase-Init
   is the documented exception: its service goes to Stopped after the
   one-shot first-boot run, so service presence misses post-run hosts;
   install-path detection (`C:\Program Files\Cloudbase Solutions\Cloudbase-Init\`)
   plus the service is the correct combined signal.
5. **CBS.log tail strategy** -- confirm 50MB tail threshold; may need to be
   smaller for bundle size discipline.
6. **EVTX channel list** -- finalize the canonical list of operational
   channels to collect. Start with what's in the architecture overview;
   expand based on real-world bundle review.
7. **Baseline rotation** -- define when baseline is updated. Options:
   manual (`Update-DiagBaseline`), opportunistic (after a "clean" collection),
   scheduled (weekly via separate task). Lean toward manual + opportunistic.
8. **Bundle delivery** -- out of scope for the module itself. Caller (Salt
   state, support engineer, etc.) decides what to do with the ZIP. Module
   writes ZIP to a configurable output path (default `C:\ProgramData\DiagBundle\output\`).

## Working with this codebase

When implementing:

- Follow the locked decisions table above. If a decision needs revisiting,
  update this doc explicitly with rationale.
- Read `docs/plans/initial-design.md` for the long-form design rationale and
  the conversation history that produced these decisions.
- Use the `review-plan` skill (in `/mnt/skills/user/review-plan/`) when a
  plan document in `docs/plans/` needs adversarial review against the
  actual code.
- Keep `manifest.schema.json` and the manifest builder code in lockstep.
  Schema changes are contract changes -- bump `schema_version` and document.
- **Rule: keep `Resources/README.md` and `Resources/prompts/*.md` in sync
  with this doc, in the same commit.** CLAUDE.md is the source of truth;
  the in-bundle docs are a consumer-facing distillation that ships
  verbatim in every collection. When any of the following changes here,
  update `DiagBundle/Resources/` to match:
  - Severity vocabulary, manifest contract caveats, drill-down recipes,
    or ZIP layout -> `Resources/README.md`.
  - `Scenario` ValidateSet (add or remove a value) -> add or remove the
    matching `Resources/prompts/<scenario>.md`.
  - New collector or new summary file -> `Resources/README.md` "Bundle
    layout" section, plus any prompt that references the new data.
  - Manifest `schema_version` bump -> `Resources/README.md` opening
    paragraph.

  Test of the rule: a consumer holding only the ZIP, with no module
  source and no CLAUDE.md, must be able to navigate it. If they cannot,
  the README is wrong, not the consumer.
- Capture real fixtures early. Synthetic tests are fast but miss the
  pathological cases (huge Security logs, corrupt CBS state, missing
  channels, locked files).

## Related projects in this org

- **CollectNTFSPerms** (C++ NTFS scanner) -- same manifest-driven ZIP pattern
  inspired this design. Worth reviewing its manifest format for consistency.
- **CLAWS** (C# ASP.NET Core ingest + analysis) -- potential downstream
  consumer of DiagBundle ZIPs if we extend it for diagnostic ingest. Not in
  scope for v1.
- **ADInventory** (PowerShell module) -- another module in the same
  distribution pipeline; reference for module conventions and packaging.
