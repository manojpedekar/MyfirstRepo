# WSUS

Tooling and infrastructure for SS&C's Windows Server Update Services (WSUS)
deployment: server configuration, computer-target-group automation, a
custom SUSDB-Reports reporting database, and Grafana dashboards over it.

## Components

### `Module/SSNCWSUS/`

The canonical PowerShell module. Import it once and use the exported
functions from anywhere:

```powershell
Import-Module .\Module\SSNCWSUS\SSNCWSUS.psd1
```

The module covers:

- Server setup: `Install-WSUSServer`, `Install-WSUSFeatures`,
  `Initialize-WSUSDisks`, `Set-SSNCReplicaWSUSSettings`
- Database: `Invoke-WSUSQuery`, `Build-*` SQL builders, `Get-WSUSConfig`
- Target groups & approval rules: `New-WSUSTargetGroup`,
  `Add-/Remove-TargetGroupToApprovalRule`, `Publish-AppIDData`
- Events: `Insert-NewWSUSEvents` (forwards local WID events upstream)
- Lower-level: `Connect-WSUS`, `Test-IsUsingWindowsInternalDatabase`,
  `Test-IISWebsiteExists`, the `WSUSQueryBuilder` class

### `Scripts/`

Operational scripts grouped by lifecycle stage:

- `Server-Setup/` - bring up a new WSUS server
- `Maintenance/` - day-2 ops (cleanup, content moves, force check-in)
- `Client/` - client-side troubleshooting
- `Catalog-Import/` - pulling updates from the MS Update Catalog into WSUS
- `Reporting/` - extracting data for the reporting database

### `Database/`

SQL artifacts.

- `SUSDB-Setup/` - server-side WID/SUSDB tuning (memory, indexes, reindex)
- `SUSDB_Reports/` - the custom reporting database that aggregates events
  across the WSUS topology (tables, views, stored procedures, functions,
  indexes). The folder name keeps the underscore to match the actual SQL
  database name.
- `AdHoc-Queries/` - one-off SQL useful enough to keep

### `Grafana/`

Dashboard JSON exports. Import via Grafana UI or API.

### `Topology/`

`wsusservers.dot` + `Makefile` to regenerate the topology SVG via Graphviz:

```bash
cd Topology && make
```

## Deployment order

1. Provision a Windows Server, attach two raw disks (small for OS+DB
   data, large for WSUS content).
2. Run `Scripts/Server-Setup/Configure-WSUS-Server.ps1` (orchestrator).
3. Apply `Database/SUSDB-Setup/*.sql` to the WID instance.
4. Apply `Database/SUSDB_Reports/CreateDatabase_SUSDB_Reports.sql`,
   then the contents of `Functions/`, `Indexes/`, `StoredProcedures/`,
   and `Views/`.
5. Import the Grafana dashboards in `Grafana/`.
6. Schedule `Insert-NewWSUSEvents` on each downstream server to feed
   the upstream reports DB (`wsusupstream.ssnc-corp.cloud`).
