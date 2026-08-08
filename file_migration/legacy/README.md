# Legacy share-tooling (older OS versions)

These scripts target **older Windows Server versions that lack the modern SMB PowerShell
cmdlets** (`Get-SmbShare`, `Get-SmbOpenFile`, ...) used by the current tools one level up.
They are kept for environments that still run these OSes. Prefer the modern tools whenever
the target server supports them.

## Current (modern) tools — use these when possible

Located in the parent folder, for **Windows Server 2012+ / PowerShell 5.1+**:

| Tool | Purpose |
|---|---|
| `Manage-Shares_v2.ps1` | Share inventory & management (permissions, sizes, activity, disable/enable) |
| `Manage-ShareUsage_v2.ps1` | Share usage via open-file snapshots (Collect / Summarize / Analyze) |
| `Manage-ShareAudit_v2.ps1` | Share usage via Security-log auditing — authoritative, file-level (Enable / Report / Disable) |

## Files in this folder

| File | OS | Why it can't use the modern tools |
|---|---|---|
| `Collect-ShareOpenFiles-2k8.ps1` | Server 2008 / 2008 R2 (PowerShell 2.0) | No `Get-SmbOpenFile` (SMB module is 2012+) and no `Export-Csv -Append` (PS 3.0+). Uses `openfiles.exe` + manual CSV append instead. |
| `Collect-ShareAccess.cmd` | Server 2003 | No PowerShell SMB cmdlets at all. Pure batch using native `openfiles` + `wmic`. |
| `Windows_2k3_FolderOrShare_details.ps1` | Server 2003 | Minimal size / file-count helper for a single path. |

## Notes

- **Schema compatibility:** the `openfiles.exe`-based collectors emit an
  `AccessedBy / OpenMode / OpenFile`-style schema. `Manage-ShareUsage_v2.ps1 -Action Analyze`
  detects that schema (via the presence of an `OpenMode` column) and reports write-mode
  activity from it, so legacy-collected data can still be analyzed with the modern tool.
- **Scheduling:** the collectors are meant to run hourly via Task Scheduler (2008 R2) or
  `schtasks` (2003); see the header comments in each file for the exact command.
- When a server hosting one of these is retired/upgraded, migrate it to the modern tools and
  retire the corresponding file here.
