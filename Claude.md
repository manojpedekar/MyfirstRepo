# Repository CLAUDE.md

These instructions apply only to this repository and supplement the Global `CLAUDE.md`.

---

# Repository Purpose

This repository is dedicated exclusively to **Microsoft Windows Server administration, PowerShell automation, enterprise infrastructure engineering, and operational tooling**.

Unless explicitly instructed otherwise:

* Target Microsoft Windows Server only.
* Use PowerShell as the primary scripting language.
* Assume an enterprise production environment.
* Produce solutions suitable for Windows Server administrators and infrastructure engineers.

Do not generate solutions for Linux, macOS, Bash, Python, Go, Java, Node.js, Kubernetes, or other non-Windows technologies unless explicitly requested.

---

# Target Environment

Assume solutions may be used in environments containing:

* Windows Server 2008 R2
* Windows Server 2012 / 2012 R2
* Windows Server 2016
* Windows Server 2019
* Windows Server 2022
* Windows Server 2025 (when applicable)

Enterprise environments may include:

* Hundreds or thousands of servers
* Multiple Active Directory domains
* Multiple forests
* Trusted domains
* File Servers
* Failover Clusters
* Hyper-V
* WSUS
* DFS
* SMB
* Enterprise storage platforms

Design accordingly.

---

# Microsoft-First Approach

Always prefer Microsoft-native technologies.

Examples include:

* Windows PowerShell
* PowerShell
* Active Directory
* Group Policy
* WinRM
* PowerShell Remoting
* WMI
* CIM
* DISM
* Windows Event Logs
* Performance Monitor
* Task Scheduler
* Hyper-V
* Failover Clustering
* DFS
* SMB
* Storage Spaces
* Windows Server Backup
* Windows Update
* WSUS
* RSAT
* Windows Admin Center
* Microsoft Defender

Only recommend third-party software when:

* It provides a significant technical advantage.
* It reduces operational complexity.
* No Microsoft-native alternative exists.

Whenever recommending third-party software:

* Explain why it is preferred.
* Identify the Microsoft-native alternative.
* Explain trade-offs.

---

# Solution Design

Before writing any PowerShell script, function, or module:

Spend time designing the solution.

Evaluate:

* Maintainability
* Reliability
* Security
* Performance
* Scalability
* Backward compatibility
* Operational supportability
* Ease of troubleshooting
* Ease of future enhancements

For non-trivial requests:

Briefly explain:

* The proposed design
* Why it was selected
* Any assumptions
* Compatibility considerations
* Potential limitations

Then implement the solution.

---

# PowerShell Standards

Follow Microsoft's official PowerShell design guidelines.

Use:

* Approved PowerShell verbs
* Verb-Noun naming
* PascalCase
* Full cmdlet names
* Named parameters
* CmdletBinding()
* Parameter validation
* PowerShell objects instead of formatted text whenever practical
* Comment-based help for reusable/public functions

Never:

* Invent PowerShell verbs.
* Use aliases such as:

  * ls
  * gci
  * cat
  * %
  * ?
  * select

---

# Script Structure

Unless another structure is more appropriate:

1. Comment-based help
2. Parameters
3. Variables
4. Helper functions
5. Main processing
6. Cleanup
7. Summary

Use `#region` blocks for larger scripts.

---

# Script Versioning

Never modify an existing released script.

Whenever changes are requested:

* Preserve the existing version.
* Create the next version.

Examples:

* Inventory_v1.ps1
* Inventory_v2.ps1
* Inventory_v3.ps1

This preserves rollback capability and change history.

---

# Windows Server Compatibility

Whenever a script requires:

* PowerShell 5.1+
* PowerShell 7+
* Windows Server 2016+

Also create a Windows Server 2008 R2 compatible version whenever reasonably possible.

Example:

* Get-ServerInventory_v2.ps1
* Get-ServerInventory_v2_WS2008R2.ps1

Clearly document any unavoidable feature differences.

---

# Output Standards

Unless otherwise specified:

Default output folder:

C:\temp\

Automatically create the folder if necessary.

Store:

* Reports
* CSV files
* JSON
* XML
* Logs
* Exported data

in this location.

---

# Timestamp Standards

All script output should be timestamped.

Apply timestamps to:

* Console output
* Log files
* Reports
* Status messages
* Error messages where practical

Use:

yyyy-MM-dd HH:mm:ss

---

# Logging Standards

Scripts should log:

* Script start
* Script completion
* Errors
* Warnings
* Important informational events
* Summary statistics

Logging should be clear, consistent, and useful for troubleshooting.

---

# Error Handling

Use structured error handling.

Prefer:

* Try
* Catch
* Finally

Do not silently suppress exceptions.

Return meaningful error information.

---

# Performance

Whenever processing multiple servers or independent tasks:

Always evaluate whether parallel execution will improve performance.

When supported:

* Use parallel execution.
* Use configurable throttle limits.
* Avoid overwhelming remote systems.

When backward compatibility is required:

Provide a sequential implementation.

---

# Configuration

Avoid hardcoded values whenever practical.

Prefer:

* Parameters
* Configuration files
* Variables

over embedded values.

---

# Security

Never:

* Hardcode passwords.
* Hardcode secrets.
* Store credentials in plain text.

Use:

* PSCredential
* SecureString
* Windows integrated authentication

where appropriate.

---

# Output Objects

Whenever practical:

Return PowerShell objects.

Avoid formatting output inside reusable functions.

Formatting belongs at the presentation layer.

---

# Testing Expectations

Before considering any solution complete:

Verify:

* Parameter validation
* Logging
* Error handling
* Expected output
* Edge cases
* Backward compatibility (when applicable)

---

# Explanation Standards

For complex implementations:

Include:

* Design overview
* Assumptions
* Compatibility notes
* Limitations
* Operational considerations

End with a concise **TL;DR** summary.

---

# Repository Quality Checklist

Before completing any implementation, verify that it:

✓ Targets Microsoft Windows Server.

✓ Uses PowerShell as the primary implementation language.

✓ Follows Microsoft PowerShell naming conventions.

✓ Uses approved PowerShell verbs.

✓ Prefers Microsoft-native technologies.

✓ Creates a new version instead of modifying an existing script.

✓ Produces timestamped output.

✓ Uses `C:\temp\` as the default output location unless instructed otherwise.

✓ Includes meaningful logging.

✓ Implements structured error handling.

✓ Returns PowerShell objects whenever practical.

✓ Creates a Windows Server 2008 R2 compatible version when required.

✓ Evaluates parallel execution for multi-server operations.

✓ Is maintainable, secure, and production-ready.

✓ Includes a TL;DR for lengthy explanations.

The objective is to produce enterprise-quality Windows Server automation that is consistent, maintainable, scalable, and aligned with Microsoft best practices.
