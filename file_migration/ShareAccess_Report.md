# Share Access Report — `G:\Group_Windt132k` (server WINDT142K3)

**Source:** `ShareAccessLogs\OpenFiles_Master.csv` (hourly `openfiles /query` snapshots)
**Collection window:** 2026-07-07 09:50 → 2026-07-11 01:00 (67 snapshots)
**Report compiled:** 2026-07-13

> Note: snapshots after 2026-07-11 01:00 exist but contain no open-file rows
> (weekend / off-hours — only the `openfiles` INFO header was captured).

---

## 1. Overview

| Metric | Value |
|---|---|
| Valid share-open records | 3,345 |
| Distinct snapshots | 67 |
| Distinct users | 16 |
| Server (host) | 1 — `WINDT142K3` |
| Share root in use | `G:\Group_Windt132k\Shared` (100% of activity) |
| Write-mode opens | 659 (19.7%) — remainder read-only |

Each record is a point-in-time observation of a handle open through the share,
not a distinct file event, so counts reflect **how persistently** something was
held open across hourly snapshots, not raw open/close events.

## 2. Users

**Top users by observed open handles:**

| User | Opens | Wrote? |
|---|---:|:--:|
| WEI.JIANG | 1,621 | read-only |
| TFEBLES | 265 | ✔ (19) |
| BMCADOO | 262 | ✔ (129) |
| RKUMAR3 | 167 | ✔ (82) |
| DBETTERS | 164 | ✔ (95) |
| KZIADIE | 160 | ✔ (41) |
| KCARTA | 146 | ✔ (77) |
| JCACCAVA | 128 | ✔ (52) |
| MPARLAPI | 99 | ✔ (17) |
| NLUKONIS | 97 | ✔ (44) |
| MMCMANUS | 91 | ✔ (43) |
| TRUSTEK | 48 | ✔ (24) |
| RFREYTAG | 36 | ✔ (24) |
| KBRAY | 26 | ✔ (12) |
| PMUGASHU | 21 | read-only |
| APRATHEP | 14 | read-only |

- **WEI.JIANG dominates (48% of all records)** but is entirely read-only — the
  pattern (many sequential folder handles in one snapshot) looks like recursive
  browsing/indexing/backup rather than editing. Worth confirming whether this is
  a person or a service/scan account before scheduling any cutover.
- **Active editors (writers):** BMCADOO, DBETTERS, RKUMAR3, KCARTA, JCACCAVA are
  the heaviest writers — these are the users most likely to be interrupted by a
  migration cutover.

## 3. Data locations (migration hot spots)

| Area | Opens | Share |
|---:|---:|---|
| `Shared\REIT Team` | 2,451 | 73% |
| `Shared\ANICO` | 478 | 14% |
| `Shared\MarylandCare` | 136 | 4% |
| `Shared\KofC` | 128 | 4% |
| `Shared\RLI Conversion` | 110 | 3% |
| `Shared\reports` | 10 | <1% |

**`REIT Team` is by far the busiest area** (chiefly the *Rompsen*, *Peachtree*,
*Saluda Grade*, and *SG Capital* sub-folders). It should be treated as the
highest-risk, highest-coordination folder for the migration.

## 4. Timing (best cutover window)

**Activity by date:** peaks Jul 8 (1,164) and Jul 10 (1,093); Jul 9 (891).

**Activity by hour (local server time):**

- **Business hours 09:00–17:00 are heavy** (220–330 opens/hr, peak ~14:00).
- Meaningful tail 18:00–21:00 (110–164/hr) — likely offshore/late shift.
- **Quiet window 22:00–07:00** (13–31 opens/hr, mostly stray/idle handles).

➡️ **Recommended cutover window: 22:00–06:00**, ideally on a weekend
(post-07-11 snapshots show near-zero activity), to minimize open-handle
conflicts.

## 5. File types in use

Genuine document formats among open files:

| Type | Opens |
|---|---:|
| `.xlsx` | 570 |
| `.pdf` | 144 |
| `.xlsm` | 63 |
| `.xls` | 17 |
| `.msg` | 6 |
| `.docx` | 3 |
| `.csv` | 3 |
| `.tmp` / `~$` lock files | few |

Workload is **Excel-dominated** (xlsx/xlsm/xls ≈ 650) plus PDFs. The `~$…` and
`.tmp` entries are Office lock files — expected, and a reliable signal of a file
being actively edited at snapshot time.

## 6. Caveats

- `openfiles` counts **handles per snapshot**, not unique open/close events; a
  file held open all day is counted once per hour. Treat numbers as *relative
  intensity*, not absolute usage.
- The tool reported the local-files warning (`'maintain objects list'` flag not
  enabled) — this only affects *locally* opened files; **remotely opened share
  files (what we care about for migration) are fully captured.**
- Small "extensions" seen in raw parsing (`.2026`, `.26`, `.06`, `.30`) are
  **date-named folders**, not file types — excluded above.
- Only one server (`WINDT142K3`) appears; if other nodes host shares, run the
  collector there too before finalizing the migration plan.
