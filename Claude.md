# Windows Server Repository Instructions

These instructions apply only to this repository and supplement the global `CLAUDE.md`.

---

# Repository Scope

This repository is dedicated exclusively to **Microsoft Windows Server administration, automation, scripting, and infrastructure engineering**.

Unless explicitly requested otherwise:

* Target Microsoft Windows Server only.
* Use PowerShell as the primary scripting language.
* Assume an enterprise production environment.
* Produce solutions suitable for Windows Server administrators.

---

# Preferred Technologies

Always prioritize Microsoft-native technologies.

Examples include:

* PowerShell
* Windows Server Roles and Features
* Active Directory
* Group Policy
* WinRM
* WMI/CIM
* DISM
* Windows Admin Center
* Hyper-V
* Failover Clustering
* DFS
* SMB
* WSUS
* Windows Update
* Windows Event Logs
* Performance Monitor
* Task Scheduler
* Windows Defender
* Microsoft Defender
* RSAT
* Storage Spaces
* Windows Server Backup

Only recommend third-party products when they provide a clear benefit or when no Microsoft-native solution exists.

When recommending third-party software:

* Explain why it is preferred.
* Mention the Microsoft-native alternative.
* Describe the trade-offs.

---

# Script Versioning

Never modify an existing released script.

Create the next version instead.

Examples:

```
Inventory_v1.ps1
Inventory_v2.ps1
Inventory_v3.ps1
```

---

# Windows Server Compatibility

If a script targets PowerShell 5.1+, PowerShell 7+, or newer Windows Server versions, also create a Windows Server 2008 R2 compatible version whenever reasonably possible.

Example:

```
Inventory_v2.ps1
Inventory_v2_WS2008R2.ps1
```

Avoid unsupported cmdlets in the compatibility version.

---

# Default Output Location

Unless otherwise specified:

```
C:\temp\
```

Create the folder automatically if it does not exist.

Store logs, reports, exports, and generated files there by default.

---

# Timestamping

All output should be timestamped.

This includes:

* Console messages
* Log files
* CSV exports
* Reports
* Error messages where practical

Use:

```
yyyy-MM-dd HH:mm:ss
```

---

# Parallel Processing

Whenever a script processes multiple computers, servers, or independent tasks:

* Evaluate whether parallel execution is appropriate.
* Prefer parallel execution when it improves performance.
* Use configurable throttle limits.
* Provide a sequential fallback when required for older PowerShell versions.

---

# PowerShell Naming Standards

Follow Microsoft's official naming conventions.

Examples:

Functions:

* Get-ServerInventory
* Test-ServerConnectivity
* Invoke-HealthCheck
* Export-InventoryReport

Use only approved PowerShell verbs.

Never invent verbs.

Use descriptive PascalCase variable and parameter names.

Avoid aliases.

---

# Script Design

Scripts should:

* Validate inputs.
* Handle errors gracefully.
* Produce useful log messages.
* Return PowerShell objects whenever practical.
* Be modular and reusable.
* Follow a consistent coding style.

---

# Enterprise Standards

Assume scripts will run in large enterprise environments managing many Windows Servers.

Design for:

* Reliability
* Security
* Scalability
* Backward compatibility
* Ease of maintenance
* Operational support

Prefer solutions that minimize manual intervention and are suitable for automation at scale.
