# Windows Server Edition Upgrade: Standard → Datacenter

## Overview

This Salt state automates the upgrade of Windows Server editions from **Standard** to **Datacenter** using DISM and KMS product keys. The state is designed to be idempotent—running it multiple times against the same server is safe.

**State File:** `ssnc-win_upgrade_edition.sls`

---

## What This State Does

1. **Detects** current OS version and edition
2. **Skips upgrade** if already running Datacenter edition
3. **Upgrades** to Datacenter using DISM with appropriate KMS key
4. **Activates** Windows license via KMS after upgrade
5. **Handles failures** gracefully with error reporting
6. **Optionally reboots** server to finalize upgrade (can be triggered explicitly)

---

## Supported Windows Server Versions

| OS Version | Product Key |
|-----------|------------|
| Windows Server 2012 | 48HP8-DN98B-MYWDG-T2DCC-8W83P |
| Windows Server 2012 R2 | W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9 |
| Windows Server 2016 | CB7KF-BWN84-R7R2Y-793K2-8XDDG |
| Windows Server 2019 | WMDGN-G9PQG-XVVXX-R3X43-63DFG |
| Windows Server 2022 | WX4NM-KYWYW-QJJR4-XV3QB-6VM33 |
| Windows Server 2025 | D764K-2NDRG-47T6Q-P8T8W-YP6DF |

> **Note:** KMS keys are defined once in the Jinja template at the top of the state file and injected into PowerShell at render time (single source of truth).

---

## Prerequisites

- Salt minion running on target Windows Server
- Administrative privileges on the target server
- DISM utility available (standard on Windows Server)
- KMS server accessible for license activation
- Network connectivity to perform download/activation

---

## Usage

### Remote Execution (from Salt Master)

```bash
# Apply to single server
salt 'server-name' state.apply ssnc-win_upgrade_edition

# Apply to all servers matching pattern
salt 'web-*' state.apply ssnc-win_upgrade_edition

# Apply to multiple servers
salt -L 'server1,server2,server3' state.apply ssnc-win_upgrade_edition

# Test mode (show what would change)
salt 'server-name' state.apply ssnc-win_upgrade_edition test=True
```

### Local Execution (on the server itself)

```bash
salt-call --local state.apply ssnc-win_upgrade_edition
```

---

## Execution Flow

### Stage 1: OS Detection
- Identifies current OS version and edition
- Outputs OS information for logging

### Stage 2: Edition Upgrade
- **Condition:** Only runs if **not** already Datacenter
- **Action:** Uses DISM with `/Set-Edition:ServerDatacenter`
- **Key Mapping:** Matches OS version to correct KMS product key
- **Quiet Mode:** Runs without user prompts (`/Quiet /NoRestart`)
- **Result:** Prepares system for activation

### Stage 3: License Activation
- **Condition:** Only runs if upgrade succeeded
- **Action:** Runs Windows Software Licensing Manager (`slmgr.vbs /ato`)
- **Purpose:** Activates the new edition via KMS

### Stage 4: Failure Handling
- If any step fails, marks execution as failed with error message
- Administrator must investigate DISM logs on the server

### Stage 5: Optional Reboot
- **Triggering Condition:** Only if Datacenter edition confirmed
- **Behavior:** Schedules reboot in 60 seconds
- **Can be disabled:** Comment out the `server_reboot_for_upgrade` state if immediate reboot not desired

---

## Important Notes

### ⚠️ Reboot Requirement
- DISM edition upgrades require a **system reboot** to take full effect
- The state schedule a 60-second countdown reboot after successful upgrade
- Running services will be interrupted; coordinate with system owners before execution

### Idempotency
- Safe to run repeatedly; skips if already Datacenter
- Use test mode to validate before production run: `test=True`

### Network & KMS Connectivity
- Server must reach KMS server during/after upgrade for activation
- Without KMS connectivity, upgrade succeeds but activation fails
- Ensure firewall rules permit KMS traffic (TCP 1688) before upgrade

### Logging
- All output captured in Salt state logs
- Additional details available in Windows DISM logs at: `C:\Windows\Logs\DISM\dism.log`

---

## Example Scenarios

### Scenario 1: Upgrade Server with Immediate Reboot
```bash
salt 'web-prod-01' state.apply ssnc-win_upgrade_edition
# Server will upgrade and reboot after 60 seconds
```

### Scenario 2: Dry-Run Before Applying to Production
```bash
salt 'web-prod-01' state.apply ssnc-win_upgrade_edition test=True
```

### Scenario 3: Bulk Upgrade Multiple Servers
```bash
salt 'datacenter:*' state.apply ssnc-win_upgrade_edition -C
# Requires compound target matching configured
```

---

## Troubleshooting

### Upgrade Reports "Already Datacenter"
- **Cause:** Server already running Datacenter edition
- **Action:** None required; state completed successfully

### Activation Fails
```powershell
# Manual KMS activation:
cscript //nologo C:\Windows\System32\slmgr.vbs /ato

# Check license status:
cscript //nologo C:\Windows\System32\slmgr.vbs /dli
```

### DISM Upgrade Fails
- Check `C:\Windows\Logs\DISM\dism.log` for details
- Verify correct KMS key for your OS version
- Ensure server has internet connectivity

### "Unsupported OS Version" Error
- OS version not in the supported list (see table above)
- Add support by updating KMS keys in the state file

---

## Modification Guide

### Adding a New Windows Server Version

Edit the Jinja variables at the top of `ssnc-win_upgrade_edition.sls`:

```yaml
{%- set kms_keys = {
  '2012':   '48HP8-DN98B-MYWDG-T2DCC-8W83P',
  ...
  '2026':   'YOUR-NEW-KMS-KEY-HERE'
} -%}
```

Then add the version to the switch statement in the `os_edition_upgrade` state.

### Disabling Automatic Reboot

Comment out or delete the `server_reboot_for_upgrade` state section if you want manual control over reboot timing.

### Changing Reboot Delay

Modify the shutdown command in `server_reboot_for_upgrade`:
```yaml
/t 60  # Change 60 to your desired seconds
```

---

## Related Files

- **PowerShell Scripts:** 
  - `OS_Edition_Change_Reboot.ps1` — Direct PowerShell upgrade with reboot
  - `OS_Edition_Change_Without_Reboot.ps1` — Direct PowerShell upgrade without reboot

---

## References

- [Microsoft DISM Documentation](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-windows-offline-servicing-command-line-options)
- [Windows Server Product Keys](https://docs.microsoft.com/en-us/windows-server/get-started/kms-client-activation-keys)
- [Salt Documentation](https://docs.saltproject.io/)

---

## Version History

- **v2.0** (Current) — Jinja-templated KMS keys, clean state dependencies, support for Server 2025, renamed to `ssnc-win_upgrade_edition.sls`
