# RDS License Servers & Network Zones — Grafana Dashboard

Maps **RDS license servers** (per Active Directory domain, from **Microsoft SQL Server**) to their
**network zone** (from **MySQL**), joining by **IP address / subnet containment**.

- **File:** `RDS-License-Zone-Dashboard_v1.json`
- **Grafana:** v10.x / v11.x (schema version 39)
- **Data sources:** one MSSQL, one MySQL (separate instances — selected at import via dashboard variables)

---

## How it works

Grafana **cannot** perform an "IP-in-subnet" join *across two separate data sources* — its panel
transformations only do **exact-match** joins, not CIDR/range containment. This dashboard works around
that as follows:

1. **`$domain`** (variable, MSSQL) — the domain picker.
2. **`$rds_ip`** (variable, MSSQL, *hidden*, multi-value) — distinct IPs of the RDS license servers in
   `$domain`. Grafana automatically re-runs this whenever `$domain` changes (chained variable).
3. The **MySQL zone query** receives that IP list (`${rds_ip:csv}`), expands it to rows with
   `JSON_TABLE`, and resolves each IP to a zone using **exact-IP match OR CIDR containment**
   (`INET_ATON` bit math). Its output has an exact `ip_address` key.
4. The **combined panel** (Mixed datasource) joins the MSSQL RDS rows and the MySQL zone rows on the
   exact `ip_address` column via a `joinByField` transformation.

```
$domain ─▶ [MSSQL] RDS servers + IPs ─▶ $rds_ip (hidden) ─▶ [MySQL] IP→zone ─▶ join on IP ─▶ combined table
```

---

## Placeholders to replace

Edit the JSON (or the panels/variables in the UI) to match your real schema.

### MSSQL — RDS license DB
Table `dbo.RdsLicenseServers` with columns:

| Placeholder   | Meaning                          |
|---------------|----------------------------------|
| `Domain`      | AD domain (FQDN or short name)   |
| `ServerName`  | RDS license server hostname      |
| `IpAddress`   | Server IPv4 address              |
| `LicenseType` | e.g. Per Device / Per User       |
| `Status`      | e.g. Activated / Pending         |

### MySQL — network-zone DB
Table `network_zones` with columns:

| Placeholder    | Meaning                                                        |
|----------------|----------------------------------------------------------------|
| `zone_id`      | Network zone identifier                                        |
| `zone_name`    | Network zone display name                                      |
| `ip_or_subnet` | Either a single IPv4 (`10.1.1.5`) **or** CIDR (`10.1.0.0/16`)  |

> If your zone table already splits network and mask into separate columns, adjust the
> `SUBSTRING_INDEX(... '/' ...)` logic accordingly. If it stores start/end IP ranges instead of CIDR,
> replace the containment test with `INET_ATON(jt.ip) BETWEEN INET_ATON(start_ip) AND INET_ATON(end_ip)`.

---

## Import

1. **Grafana → Dashboards → New → Import.**
2. Upload `RDS-License-Zone-Dashboard_v1.json`.
3. When prompted, map the two datasource variables:
   - **RDS DB (MSSQL)** → your SQL Server datasource
   - **Zone DB (MySQL)** → your MySQL datasource
4. Open the dashboard, pick a **Domain**, and the panels populate.

Provisioning-as-code alternative: drop the JSON in a provisioning path referenced by a
`dashboards` provider YAML, and pre-create the two datasources so their UIDs resolve.

---

## Assumptions & limitations

- **IPv4 only.** `INET_ATON` does not handle IPv6. For IPv6, switch to `INET6_ATON` and compare
  128-bit values (VARBINARY(16) masking).
- **Current-state data**, not time series — the dashboard time range is not used in the queries.
- **Read-only** SQL. Grant the Grafana service accounts `SELECT` only on the relevant objects.
- One IP may match multiple overlapping zones; the combined join will then show multiple rows for that
  server. Add a tie-breaker (e.g. most-specific mask) in the MySQL query if zones overlap.
- Column/table names are **placeholders** — the dashboard will error until they match your schema.

---

## TL;DR

Pick a domain → see its RDS license servers (MSSQL) with each server's network zone (MySQL), joined by
IP/subnet. The cross-source subnet match is done in MySQL (because Grafana can't range-join across
sources), then merged to the RDS table on the exact IP. Replace the placeholder table/column names,
import the JSON, and select your two datasources.
