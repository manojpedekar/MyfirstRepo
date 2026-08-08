# Legacy share-tooling (older OS versions)

These target **older Windows Server versions that lack the modern SMB PowerShell
cmdlets** (`Get-SmbShare`, `Get-SmbOpenFile`, ...) used by the current tools one level up.
Kept for environments that still run Server 2003 / 2008 / 2008 R2. Prefer the modern tools
whenever the target server supports them.

## Current (modern) tools — use these when possible

Located in the parent folder, for **Windows Server 2012+ / PowerShell 5.1+**:

| Tool | Purpose |
|---|---|
| `Manage-Shares_v2.ps1` | Share inventory & management (permissions, sizes, activity, disable/enable) |
| `Manage-ShareUsage_v2.ps1` | Share usage via open-file snapshots (Collect / Summarize / Analyze) |
| `Manage-ShareAudit_v2.ps1` | Share usage via Security-log auditing — authoritative, file-level (Enable / Report / Disable) |

## File in this folder

| File | Runtime | Notes |
|---|---|---|
| `Manage-ShareLegacy.cmd` | Batch — **no PowerShell required** | Runs on Server 2003, 2008, and 2008 R2. Uses only native `openfiles.exe`, `wmic`, and `dir`. |

`Manage-ShareLegacy.cmd` replaces three earlier scripts that were merged into it:

- `Collect-ShareAccess.cmd` (Server 2003 collector)      -> **COLLECT** mode
- `Collect-ShareOpenFiles-2k8.ps1` (Server 2008 R2)      -> **COLLECT** mode
- `Windows_2k3_FolderOrShare_details.ps1` (size helper)  -> **DETAILS** mode

Merged into batch (not PowerShell) on purpose: Server 2003 has no PowerShell by default,
so a `.cmd` using only in-box tools is the one form guaranteed to run on every target.

## Usage

```bat
:: Snapshot open share handles and append to a master CSV (schedule hourly)
Manage-ShareLegacy.cmd COLLECT
Manage-ShareLegacy.cmd COLLECT C:\temp\ShareUsageLogs

:: Size / file count / folder count for one path (optional CSV output)
Manage-ShareLegacy.cmd DETAILS "G:\Group_Windt132k\Shared\REIT Team\Rompsen"
Manage-ShareLegacy.cmd DETAILS "G:\Group_Windt132k\Shared" C:\temp\folder_details.csv
```

Schedule the COLLECT mode hourly:

```bat
schtasks /create /tn "ShareAccessSnapshot" ^
  /tr "\"C:\Scripts\Manage-ShareLegacy.cmd\" COLLECT" ^
  /sc hourly /ru SYSTEM /rl HIGHEST
```

## Notes

- **Schema compatibility:** COLLECT emits the `openfiles.exe` schema
  (`SnapshotTime, Hostname, ID, AccessedBy, Type, Locks, OpenMode, OpenFile`).
  `Manage-ShareUsage_v2.ps1 -Action Analyze` detects this schema (via the `OpenMode`
  column) so legacy-collected data feeds the modern analyzer.
- **DETAILS byte total** is parsed from the `dir /s` grand-total line and strips the en-US
  thousands separator; on other locales the byte figure may not strip cleanly, but the
  file/folder **counts are always exact**. (Batch `SET /A` is 32-bit and would overflow on
  large trees, so `dir` does the summation instead.)
- **`openfiles`** lists files opened over the network by default — correct for a file share.
  Local-process opens require `openfiles /local on` + reboot (not needed here).
- When a server hosting this is retired/upgraded, migrate it to the modern tools and remove
  this folder.
