# Quick Start Guide

Get your first collection uploaded in about 5 minutes.

## Prerequisites

Before you begin, ensure you have:

- Windows Server 2016 or later (or Windows 10/11 for testing)
- PowerShell 5.1 or PowerShell 7.x
- Administrator rights on the target server
- Network access to this web application

## Step 1: Download the Collector

1. Log in to this web application
2. On the Home page, click the **Download** button for either:
   - **CollectNTFSPerms** - For file system permissions
   - **ADInventory** - For Active Directory data
3. Save the .zip file to your server

## Step 2: Extract and Import

Open PowerShell as Administrator and run:

```powershell
# Extract the collector (adjust path as needed)
Expand-Archive -Path "C:\Downloads\CollectNTFSPerms.zip" -DestinationPath "C:\Tools\CollectNTFSPerms"

# Import the module
Import-Module "C:\Tools\CollectNTFSPerms\CollectNTFSPerms.psd1"
```

For AD Inventory:
```powershell
Expand-Archive -Path "C:\Downloads\ADInventory.zip" -DestinationPath "C:\Tools\ADInventory"
Import-Module "C:\Tools\ADInventory\ADInventory.psd1"
```

## Step 3: Run a Collection

### For NTFS Permissions

```powershell
# Collect permissions for a single path
Invoke-NTFSPermissionCollection -Path "D:\Shares" -OutputPath "C:\Output"
```

### For AD Inventory

```powershell
# Collect AD inventory for the current domain
Invoke-ADInventoryCollection -OutputPath "C:\Output"
```

The collector will create a .zip file in the output directory.

## Step 4: Upload Your Collection

1. Return to this web application
2. Click **Upload** in the navigation menu
3. Click **Choose File** and select your .zip file
4. Click **Upload**
5. Wait for processing to complete (you'll see progress updates)

## Step 5: Verify Success

After processing completes:

1. Check the status shows **Completed**
2. Review the import statistics
3. Your data is now available for analysis

## What's Next?

- [NTFS Collector Parameters](../ntfs-collector/parameters.md) - Customize your collection
- [AD Inventory Permissions](../ad-inventory/permissions.md) - Understand required permissions
- [Troubleshooting](../troubleshooting/index) - If something went wrong

## Common First-Time Issues

| Issue | Solution |
|-------|----------|
| "Module not found" | Ensure you extracted the full .zip and are importing the .psd1 file |
| "Access denied" | Run PowerShell as Administrator |
| "Upload failed" | Check file size limits and network connectivity |

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
