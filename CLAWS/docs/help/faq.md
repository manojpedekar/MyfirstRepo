# Frequently Asked Questions

Common questions about the NTFS Permissions and AD Inventory collection tools.

## General Questions

### What are these tools for?

These tools help you inventory and analyze:
- **NTFS Permissions** - File and folder permissions on Windows servers
- **AD Inventory** - Active Directory users, groups, and configuration

The collected data is uploaded to a central web application for analysis and reporting.

### Do I need special software?

No. The collectors are PowerShell modules that run on standard Windows systems. You only need:
- Windows Server 2016+ or Windows 10/11
- PowerShell 5.1 or 7.x
- Administrator rights (for NTFS) or Domain Users (for AD)

### How often should I run collections?

Recommendations:
- **NTFS Permissions**: Weekly or monthly, depending on change frequency
- **AD Inventory**: Weekly for most environments

### How long does a collection take?

It depends on the data volume:
- **NTFS**: ~10,000-50,000 folders per minute
- **AD**: ~50,000-100,000 objects per minute

A typical file server takes 10-30 minutes. Large environments may take hours.

## NTFS Collector Questions

### What permissions do I need to run the NTFS collector?

Local Administrator on the server where you're collecting. This ensures you can read all folder ACLs.

### Can I collect from remote servers?

Yes, but it's recommended to run the collector locally on each file server for best performance.

### Does the collector modify any files?

No. The collector is read-only. It never modifies files, folders, or permissions.

### What if some folders are inaccessible?

The collector logs access denied errors and continues. You can review skipped folders in the collection log.

### How do I reduce collection time?

- Use `-MaxDepth` to limit folder depth
- Use `-ExcludeFolders` to skip unnecessary folders
- Use `-IncludeInherited:$false` to skip inherited permissions

## AD Inventory Questions

### What permissions do I need for AD collection?

Domain Users membership is typically sufficient. See [AD Permissions](ad-inventory/permissions.md) for details.

### Can I collect from trusted domains?

Yes. Use the `-Domain` parameter to specify other domains. You need read access in those domains.

### What AD data is collected?

Users, groups, computers, OUs, group memberships, forest/domain configuration, trusts, sites, subnets, and domain controllers.

### Is sensitive data collected?

The collector does not collect passwords or password hashes. It collects object attributes that are readable by Domain Users.

## Upload Questions

### What file formats are accepted?

Only .zip files created by the official collectors are accepted.

### What's the maximum file size?

Default maximum is 3 GB compressed (configurable by administrators).

### How long does upload processing take?

Typically 5-30 minutes depending on collection size. Large collections may take longer.

### Can I upload the same server multiple times?

Yes. New uploads replace previous data from the same source while maintaining history.

### What happens if upload fails?

You'll see an error message with details. Check [Troubleshooting](troubleshooting/) for solutions.

## API Questions

### How do I get an API key?

1. Log in to the web application
2. Go to Account > API Keys
3. Click Create New Key
4. Copy the key (shown only once)

### Do API keys expire?

API keys can have expiration dates set when created. Check your key settings in the web interface.

### Can I have multiple API keys?

Yes. You can create multiple keys for different uses (e.g., different servers or scripts).

## Security Questions

### Is data encrypted in transit?

Yes, if you're using HTTPS (default). All uploads are encrypted via TLS.

### Who can see my data?

Access is controlled by your administrators. Only authorized users can view collected data.

### Is the collector signed?

The collector modules are not code-signed. You may need to adjust execution policy or unblock the files after download.

### Can I audit who uploaded data?

Yes. All uploads are logged with username, timestamp, and source information.

## Troubleshooting Quick Reference

| Issue | Solution |
|-------|----------|
| "Module not found" | Import with full path: `Import-Module "C:\Tools\...\*.psd1"` |
| "Execution policy" | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| "Access denied" | Run PowerShell as Administrator |
| "File too large" | Use `-MaxDepth` or split collections |
| "Server not operational" | Check network connectivity to domain controllers |

## Still Have Questions?

If your question isn't answered here:

1. Check the relevant documentation section
2. Review [Troubleshooting](troubleshooting/)
3. Contact: **GlobalWindowsServers@sscinc.com**

---

*Content maintained by the Global Windows Servers Team*
