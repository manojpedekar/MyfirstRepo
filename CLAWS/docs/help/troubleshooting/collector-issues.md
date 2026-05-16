# Troubleshooting Collector Issues

Solutions for common problems when running the NTFS or AD Inventory collectors.

## Module Loading Issues

### "The specified module was not found"

**Cause:** PowerShell can't find the module file.

**Solutions:**

```powershell
# Verify the extraction path exists
Test-Path "C:\Tools\CollectNTFSPerms\CollectNTFSPerms.psd1"

# Use the full path to import
Import-Module "C:\Tools\CollectNTFSPerms\CollectNTFSPerms.psd1"

# If path has spaces, use quotes
Import-Module "C:\My Tools\CollectNTFSPerms\CollectNTFSPerms.psd1"
```

### "File cannot be loaded because running scripts is disabled"

**Cause:** PowerShell execution policy is Restricted.

**Solutions:**

```powershell
# Check current policy
Get-ExecutionPolicy

# Set to RemoteSigned (recommended)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or bypass for single session
PowerShell -ExecutionPolicy Bypass
```

### "Publisher could not be verified"

**Cause:** Downloaded files are blocked by Windows.

**Solution:**

```powershell
# Unblock all files in the module folder
Get-ChildItem -Path "C:\Tools\CollectNTFSPerms" -Recurse | Unblock-File
```

## Access Denied Errors

### "Access to the path is denied"

**Cause:** Insufficient permissions to read the target path.

**Solutions:**

1. **Run as Administrator**
   ```powershell
   # Right-click PowerShell > Run as Administrator
   ```

2. **Check folder permissions**
   ```powershell
   # View ACL on problem folder
   Get-Acl "D:\ProtectedFolder" | Format-List
   ```

3. **Exclude inaccessible folders**
   ```powershell
   Invoke-NTFSPermissionCollection -Path "D:\Shares" -OutputPath "C:\Output" `
       -ExcludePaths @("D:\Shares\ProtectedFolder")
   ```

### Access denied on specific folders

The collector continues past access denied errors by default. Check the log:

```powershell
# Review errors in collection log
Expand-Archive "C:\Output\SERVER.zip" -DestinationPath "C:\Temp"
Select-String -Path "C:\Temp\CollectionLog.txt" -Pattern "Access denied"
```

## AD Collection Issues

### "The server is not operational"

**Cause:** Cannot connect to domain controller.

**Solutions:**

1. **Check network connectivity**
   ```powershell
   Test-NetConnection -ComputerName "dc01.company.com" -Port 389
   ```

2. **Verify DNS resolution**
   ```powershell
   Resolve-DnsName "company.com"
   ```

3. **Check domain membership**
   ```powershell
   (Get-WmiObject Win32_ComputerSystem).PartOfDomain
   ```

### "Cannot contact any domain controller"

**Cause:** Network or firewall blocking LDAP traffic.

**Required ports:**

| Port | Protocol | Service |
|------|----------|---------|
| 389 | TCP/UDP | LDAP |
| 636 | TCP | LDAPS |
| 3268 | TCP | Global Catalog |
| 88 | TCP/UDP | Kerberos |
| 53 | TCP/UDP | DNS |

### "Insufficient access rights"

**Cause:** Account lacks read permission in AD.

**Solutions:**

1. **Verify your access**
   ```powershell
   # Test basic AD access
   Get-ADUser -Filter * -ResultSetSize 1
   ```

2. **Check group membership**
   ```powershell
   whoami /groups
   ```

3. **Use alternate credentials**
   ```powershell
   $cred = Get-Credential
   Invoke-ADInventoryCollection -Credential $cred -OutputPath "C:\Output"
   ```

## Performance Issues

### Collection is very slow

**Causes and solutions:**

| Cause | Solution |
|-------|----------|
| Large number of folders | Use `-MaxDepth` to limit |
| Network latency | Collect locally on file server |
| Disk I/O bottleneck | Use local SSD for output |
| Many ACL entries | Use `-IncludeInherited:$false` |

### Collection runs out of memory

**Solution:** Collect paths separately:

```powershell
$paths = @("D:\Shares\Dept1", "D:\Shares\Dept2", "D:\Shares\Dept3")
foreach ($path in $paths) {
    Invoke-NTFSPermissionCollection -Path $path -OutputPath "C:\Output"
    [GC]::Collect()  # Free memory between collections
}
```

## Output Issues

### No output file created

**Causes:**

1. Collection failed before completion
2. Output path doesn't exist
3. No write permission to output path

**Solutions:**

```powershell
# Verify output path exists
Test-Path "C:\Output"

# Create if needed
New-Item -ItemType Directory -Path "C:\Output" -Force

# Check write permission
New-Item -ItemType File -Path "C:\Output\test.txt" -Force
Remove-Item "C:\Output\test.txt"
```

### Output file is corrupt

**Cause:** Collection was interrupted or disk issue.

**Solutions:**

1. **Re-run the collection**
2. **Check disk health**
   ```powershell
   Get-Volume
   ```
3. **Use a different output location**

## Version Compatibility

### "Minimum version required" error

**Cause:** Collector version is too old for the web application.

**Solution:**

1. Download the latest collector from the web application
2. Extract and replace the old module
3. Re-import the module

```powershell
# Check current version
Get-Module CollectNTFSPerms | Select-Object Version

# Download new version and replace
Remove-Item "C:\Tools\CollectNTFSPerms" -Recurse -Force
Expand-Archive "C:\Downloads\CollectNTFSPerms-new.zip" -DestinationPath "C:\Tools\CollectNTFSPerms"
```

## Getting Help

If these solutions don't resolve your issue:

1. **Gather information:**
   - Error message (exact text)
   - Collection log file
   - PowerShell version (`$PSVersionTable`)
   - Module version (`Get-Module CollectNTFSPerms`)

2. **Contact support:**
   - Email: GlobalWindowsServers@sscinc.com
   - Include all gathered information

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
