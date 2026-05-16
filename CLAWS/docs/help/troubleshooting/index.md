# Troubleshooting

This section helps you diagnose and resolve common issues with the collection and upload tools.

## Quick Diagnosis

| Symptom | Likely Cause | Article |
|---------|--------------|---------|
| Collection fails to start | Permission or module issue | [Collector Issues](collector-issues.md) |
| Collection errors/warnings | Access denied, network | [Collector Issues](collector-issues.md) |
| Upload fails immediately | File format, size | [Upload Failures](upload-failures.md) |
| Upload fails during processing | Validation, data issues | [Validation Errors](validation-errors.md) |
| Data missing after upload | Partial collection | [Collector Issues](collector-issues.md) |

## In This Section

| Article | Description |
|---------|-------------|
| [Collector Issues](collector-issues.md) | Problems running NTFS or AD collectors |
| [Upload Failures](upload-failures.md) | Upload and processing failures |
| [Validation Errors](validation-errors.md) | Data validation errors |

## General Troubleshooting Steps

### Step 1: Check the Logs

**Collection logs** are in your output ZIP file:
```powershell
Expand-Archive "C:\Output\SERVER_20260112.zip" -DestinationPath "C:\Temp\Review"
Get-Content "C:\Temp\Review\CollectionLog.txt"
```

**Upload logs** are viewable in the web application:
1. Go to **Upload Status**
2. Click on your upload
3. Review the log tab

### Step 2: Identify the Error

Look for specific error messages:
- `Access denied` - Permission issue
- `File not found` - Path or module issue
- `Validation failed` - Data format issue
- `Connection failed` - Network issue

### Step 3: Search This Documentation

Use the search feature or browse relevant troubleshooting articles.

### Step 4: Contact Support

If you can't resolve the issue:
- Gather error messages and logs
- Note what you were trying to do
- Contact GlobalWindowsServers@sscinc.com

## Common Quick Fixes

### PowerShell Execution Policy

```powershell
# Check current policy
Get-ExecutionPolicy

# Set to allow scripts (if Restricted)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Module Not Found

```powershell
# Verify module path
Get-ChildItem "C:\Tools\CollectNTFSPerms\*.psd1"

# Import with full path
Import-Module "C:\Tools\CollectNTFSPerms\CollectNTFSPerms.psd1"
```

### Access Denied

- Run PowerShell as Administrator
- Verify you have permissions to the target path
- Check for explicit deny ACEs

### Upload Too Large

- Check file size limits in [Large Files](../uploading/large-files.md)
- Reduce collection scope
- Split into multiple collections

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
