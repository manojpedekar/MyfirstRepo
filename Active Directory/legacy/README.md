# Legacy Active Directory scripts (superseded)

These scripts have been **superseded by consolidated, parameterized tools** in the parent
`Active Directory/` folder. They are retained here only for rollback and change history, per the
repository versioning policy. **Do not use them for new work** — use the active tools instead.

## Mapping: legacy → active replacement

### Server / computer inventory
| Legacy script | Replaced by | Notes |
|---|---|---|
| `Export_AD_Data_With_ADWS.ps1` | `Get-ADServerInventory_v1.ps1` | single domain, OU + cluster flag |
| `Export_Mutliple_AD_Data_With_ADWS.ps1` | `Get-ADServerInventory_v1.ps1` | multi-domain |
| `Export_Multiple_AD_Data_Exclude_Cluster_With_ADWS.ps1` | `Get-ADServerInventory_v1.ps1 -ExcludeClusters` | had a bug: `$timestamp` was never defined, so the output filename lost its timestamp |
| `Export_AD_Data_Without_ADWS.ps1` | `Get-ADServerInventory_v1_WS2008R2.ps1` | DirectorySearcher / no-ADWS path; hardcoded DC removed |

The four exports did the same job with different knobs. The active tool takes `-Domain` (array),
`-ExcludeClusters`, and `-IncludeOU`; queries domains in parallel on PowerShell 7+; and always
writes a timestamped, folder-auto-creating CSV with logging.

### Group membership export
| Legacy script | Replaced by | Notes |
|---|---|---|
| `Export_Userlist_from_DoaminLocal_SG.ps1` | `Get-ADGroupMemberReport_v1.ps1` | flat `member` expansion resolved via Global Catalog (default) |
| `Export_Userlist_from_SG_Recursive.ps1` | `Get-ADGroupMemberReport_v1.ps1 -Recursive` | recursive expansion (same-forest only) |

### Home-directory / departed-user report
| Legacy script | Replaced by | Notes |
|---|---|---|
| `Departed_users_Information.ps1` | `Get-HomeDirUserStatus_v1.ps1` | status only |
| `Departed_users_FolderReport.ps1` | `Get-HomeDirUserStatus_v1.ps1 -IncludeFolderStats` | adds SizeMB + LastModified (the expensive scan is now opt-in) |

`FolderReport` was a strict superset of `Information`; both are collapsed into one tool.

### RDS / Terminal-Services profile export
| Legacy script | Replaced by | Notes |
|---|---|---|
| `EXport_Userlist_with_TerminalProfilePath.ps1` | `Get-ADUserRdsProfile_v1.ps1` | **was broken** (a stray `Or` line prevented it from running) and did a per-user ADSI bind over *all* users; rewrite adds `-SearchBase`/`-LdapFilter` scoping and parallel binds on PS7 |

### GPO export & search
| Legacy script | Replaced by |
|---|---|
| `Export_GPO_Find_GPO.ps1` | `Export_GPO_Find_GPO_v2.ps1` |
| `Search-GPOReports.ps1` | `Search-GPOReports_v2.ps1` |

The `_v2` GPO scripts add per-domain subfolders, GUID-collision-safe file names, logging,
structured return objects, recursive search, and match-context trimming.

---

_Moved to `legacy/` during the Active Directory folder consolidation. See git history for details._
