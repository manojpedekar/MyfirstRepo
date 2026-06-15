# Windows Server Edition Upgrade - Implementation Guide

## Overview
This refactored Salt state file addresses security, reliability, and operational concerns in the original script.

---

## Key Changes

### 1. ✅ KMS Keys → Encrypted Pillar
**Problem**: Hardcoded KMS keys exposed in state file  
**Solution**: Moved to separate pillar file with encryption support

**Setup**:
```bash
# Create pillar directory structure
mkdir -p /etc/salt/pillar/windows_server

# Create pillar file
cp windows_server_upgrade_pillar.sls /etc/salt/pillar/windows_server/upgrade.sls

# Reference in top.sls
# windows_servers:
#   - windows_server.upgrade

# Encrypt the pillar (SaltStack Enterprise)
salt-run pillar.show_top
salt-call pillar.items
```

**To use real KMS keys**:
```sls
windows_server_upgrade:
  kms_keys:
    '2012':   'ENCRYPTED{YOUR_2012_KEY}'
    '2012R2': 'ENCRYPTED{YOUR_2012R2_KEY}'
```

---

### 2. ✅ Proper Reboot Sequencing
**Problem**: Edition change requires reboot before activation; original sequence would fail  
**Solution**: Multi-stage pipeline

```
Stage 1: Detect OS
   ↓
Stage 2: Upgrade Edition (DISM)
   ↓
Stage 3: First Reboot (let system apply edition)
   ↓
Stage 4: Validate Edition (confirm it worked)
   ↓
Stage 5: Activate KMS (now on correct edition)
   ↓
Stage 6: Final Reboot (if needed for activation)
   ↓
Stage 7: Final Validation (confirm complete success)
```

**Why this matters**: DISM changes don't take effect until reboot. Activating before reboot fails.

---

### 3. ✅ DISM Output Captured
**Problem**: `/Quiet` flag hides errors; hard to debug  
**Solution**: 
- Removed `/Quiet` flag
- Added `/LogPath` for detailed logging
- Output visible in Salt logs
- Capture exit codes properly

```powershell
dism /online /Set-Edition:ServerDatacenter `
     /ProductKey:$key `
     /AcceptEula `
     /LogPath:"C:\Windows\Logs\DISM\Server-Upgrade.log"

$exitCode = $LASTEXITCODE
if ($exitCode -eq 0) {
    Write-Output "✓ DISM upgrade completed successfully"
} else {
    Write-Error "✗ DISM upgrade failed with exit code: $exitCode"
}
```

---

### 4. ✅ Post-Upgrade Validation
**Problem**: No verification that edition actually changed  
**Solution**: New state `validate_edition_after_upgrade`

```powershell
$edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
if ($edition -eq 'ServerDatacenter') {
    Write-Output "✓ Edition upgrade validated: $edition"
    exit 0
} else {
    Write-Error "✗ Expected ServerDatacenter, got: $edition"
    exit 1
}
```

This catches:
- DISM failures that returned 0 erroneously
- Partial upgrades
- Registry inconsistencies

---

### 5. ✅ Increased Reboot Delay
**Before**: 60 seconds (too short for graceful shutdown)  
**After**: 300 seconds (5 minutes, configurable via pillar)

**Why**:
- Allows running services time to shut down gracefully
- Users get time to save work
- Reduces corruption risk

```sls
reboot_delay_seconds: 300  # 5 minutes
```

---

### 6. ✅ Better Error Handling

| Error State | Behavior | Notes |
|---|---|---|
| `os_edition_upgrade_failed` | Hard fail | DISM error - check logs |
| `os_edition_upgrade_validation_failed` | Hard fail | Edition didn't change after reboot |
| `os_activation_failed` | Soft fail* | KMS issue, but system IS upgraded |

*Soft fail allows manual KMS troubleshooting without re-running upgrade

---

### 7. ✅ Enhanced Logging

**Console output indicators**:
```
✓ Success (green checkmark)
✗ Error (red X)
✅ Final success
❌ Final failure
━━━━ Section separators
```

**Log files created**:
- Salt execution logs (via `salt` command)
- DISM detailed log: `C:\Windows\Logs\DISM\Server-Upgrade.log`

**Pre/Post activation status**:
```powershell
cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli  # Before
# ... activation ...
cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli  # After
```

---

## Deployment Steps

### Step 1: Setup Pillars
```bash
# Copy pillar file
sudo cp windows_server_upgrade_pillar.sls \
  /etc/salt/pillar/windows_server/upgrade.sls

# Update /etc/salt/pillar/top.sls
sudo cat >> /etc/salt/pillar/top.sls << 'EOF'
windows_servers:
  - windows_server.upgrade
EOF
```

### Step 2: Setup State File
```bash
# Copy state file
sudo cp windows_server_upgrade_refactored.sls \
  /etc/salt/states/windows_server_upgrade.sls

# Or reference in your existing orchestration
```

### Step 3: Test (Dry Run)
```bash
# Test on a single minion
sudo salt 'target-server' state.apply windows_server_upgrade test=True

# Review output without making changes
```

### Step 4: Deploy
```bash
# Apply the upgrade
sudo salt 'target-server' state.apply windows_server_upgrade

# Monitor with:
sudo salt 'target-server' cmd.run 'Get-WindowsEdition -Online' shell=powershell
```

### Step 5: Verify
```bash
# Check final state
sudo salt 'target-server' cmd.run \
  'Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" | Select-Object EditionID' \
  shell=powershell

# Check activation
sudo salt 'target-server' cmd.run \
  'cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli' \
  shell=cmd
```

---

## Troubleshooting

### Problem: "No KMS key resolved"
**Cause**: Pillar data not loaded or OS version not matched  
**Fix**:
```bash
# Verify pillar is loaded
salt 'target' pillar.items | grep kms_keys

# Check OS caption
salt 'target' cmd.run 'Get-CimInstance Win32_OperatingSystem | Select-Object Caption' shell=powershell
```

### Problem: Edition validation fails after reboot
**Cause**: DISM didn't complete properly  
**Fix**:
```powershell
# Manual check
Get-WindowsEdition -Online

# Manual upgrade retry
dism /online /Set-Edition:ServerDatacenter /ProductKey:XXXXX /AcceptEula

# Review DISM log
type C:\Windows\Logs\DISM\Server-Upgrade.log
```

### Problem: Activation fails with "0xC004F069"
**Cause**: KMS server not reachable  
**Fix**:
```powershell
# Test KMS connectivity
nslookup _vlmcs._tcp.dc._msdcs.yourdomain.com

# Set KMS server manually
cscript slmgr.vbs /skms kms-server.yourdomain.com:1688

# Retry activation
cscript slmgr.vbs /ato
```

---

## Security Notes

### Pillar Encryption
- Use `salt-call pillar.items` to verify encrypted data is loaded
- Store pillar master private key in secure location
- Consider using external secret store (Vault, AWS Secrets Manager)

### KMS Key Security
- Never commit unencrypted KMS keys to version control
- Rotate keys periodically
- Audit access to pillar data

### DISM Logs
- May contain sensitive info; restrict access to `/Windows/Logs/DISM/`
- Archive and clean up old logs regularly

---

## Alternative: windows_update.install Module

If you prefer to avoid DISM complexity:

```yaml
# Alternative approach using Salt's windows_update module
upgrade_via_update_module:
  module.run:
    - name: cmd.run
    - text: 'Add-WindowsCapability -Online -Name "ServerCore.AppCompatibility~~~~0.0.1.0" -Source "D:\sources\sxs"'
```

**Pros**:
- Salt handles reboot orchestration
- Built-in monitoring

**Cons**:
- Less direct control over process
- DISM still used under the hood
- Requires Windows Update infrastructure

---

## Migration from Old Script

1. Backup current state file
2. Install new `windows_server_upgrade_refactored.sls`
3. Create pillar with encrypted KMS keys
4. Test on non-production system
5. Deploy to production with monitoring
6. Document any custom KMS key management

---

## Success Criteria

✅ Final state shows `ServerDatacenter` edition  
✅ Windows activation status shows "Licensed"  
✅ DISM log shows no errors  
✅ System is reachable after upgrade  
✅ All running services restart correctly  

