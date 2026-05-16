# Installing the NTFS Collector

This guide walks you through downloading and installing CollectNTFSPerms.exe.

## Download

1. Log in to the NTFSPermsUploader web application
2. On the Home page, locate the **Downloads** section
3. Click **Download CollectNTFSPerms**
4. Save the .zip file to your server

> **Tip:** Save the collector to a central location like `C:\Tools\CollectNTFSPerms\` for easy access.

## Contents of the Download

The download ZIP file contains:

| File | Description | Required |
|------|-------------|----------|
| `CollectNTFSPerms.exe` | Main NTFS permissions collector | Yes |
| `TestNTFSPath.exe` | Path troubleshooting utility | Optional |
| `sqlite3.dll` | SQLite database library | **Yes - CRITICAL** |

## Runtime Dependencies

**CRITICAL:** `sqlite3.dll` must be present in the same directory as `CollectNTFSPerms.exe`.

If the DLL is missing, you will see this error:
```
Application failed to load. Please ensure that the sqlite3.dll is available in the application path
```

## Installation

### Option 1: Extract to Local Folder (Recommended)

```powershell
# Create tools directory if needed
New-Item -ItemType Directory -Path "C:\Tools\CollectNTFSPerms" -Force

# Extract the collector
Expand-Archive -Path "C:\Downloads\CollectNTFSPerms.zip" -DestinationPath "C:\Tools\CollectNTFSPerms"

# Verify extraction
Get-ChildItem "C:\Tools\CollectNTFSPerms"
```

Expected output:
```
Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a----         1/12/2026   2:30 PM         524288 CollectNTFSPerms.exe
-a----         1/12/2026   2:30 PM         262144 TestNTFSPath.exe
-a----         1/12/2026   2:30 PM        1048576 sqlite3.dll
```

### Option 2: Add to System PATH

For convenience, add the installation directory to your system PATH:

```powershell
# Add to PATH for current user
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
$newPath = "$currentPath;C:\Tools\CollectNTFSPerms"
[Environment]::SetEnvironmentVariable("PATH", $newPath, "User")

# Restart your command prompt to use the new PATH
```

## Verify Installation

Test that the executable runs correctly:

```cmd
C:\Tools\CollectNTFSPerms\CollectNTFSPerms.exe

REM Expected output:
REM CollectNTFSPerms v1.8.0
REM NTFS Permissions Collection Utility
REM Build: [date time]
REM
REM DESCRIPTION
REM     Collects NTFS folder permissions and stores them in a SQLite database.
REM ...
```

## System Requirements

| Requirement | Details |
|-------------|---------|
| Operating System | Windows Server 2008 or later, Windows 7/8/10/11 |
| Architecture | x64 (64-bit) |
| C+ Runtime | None (Static CRT) |
| .NET Framework | Not Required |
| Permissions | Administrator recommended for full disk/volume information |
| Disk Space | Varies by scan size; typically 1-20 GB for large file systems |

## Unblocking Downloaded Files

Windows may block files downloaded from the internet:

```powershell
# Unblock all files in the extracted folder
Get-ChildItem -Path "C:\Tools\CollectNTFSPerms" -Recurse | Unblock-File
```

Or right-click each file in Windows Explorer, select Properties, and check "Unblock".

## Updating the Collector

To update to a new version:

1. Download the latest version from the web application
2. Stop any running collections
3. Replace the old files with the new ones
4. Verify the version:

```cmd
CollectNTFSPerms.exe 2>&1 | findstr /C:"CollectNTFSPerms v"
```

## Troubleshooting Installation

| Problem | Solution |
|---------|----------|
| "sqlite3.dll is not found" | Ensure sqlite3.dll is in the same folder as the .exe |
| "Application failed to load" | Check that sqlite3.dll is present and not corrupted |
| "Access is denied" | Unblock the downloaded files (see above) |
| "Not a valid Win32 application" | Ensure you're using the x64 version on a 64-bit system |
| Nothing happens when running | Check Windows Event Viewer for crash details |

## Network Deployment

For deploying to multiple servers:

```powershell
# Copy to multiple servers
$servers = @("FileServer01", "FileServer02", "FileServer03")
$sourcePath = "C:\Downloads\CollectNTFSPerms.zip"

foreach ($server in $servers) {
    # Create destination folder
    Invoke-Command -ComputerName $server -ScriptBlock {
        New-Item -ItemType Directory -Path "C:\Tools\CollectNTFSPerms" -Force
    }

    # Copy and extract
    Copy-Item $sourcePath -Destination "\\$server\C$\Tools\CollectNTFSPerms.zip"
    Invoke-Command -ComputerName $server -ScriptBlock {
        Expand-Archive -Path "C:\Tools\CollectNTFSPerms.zip" -DestinationPath "C:\Tools\CollectNTFSPerms" -Force
        Remove-Item "C:\Tools\CollectNTFSPerms.zip"
    }
}
```

## Next Steps

- [Usage Guide](usage.md) - Learn how to run collections
- [Parameters Reference](parameters.md) - See all available options
- [Examples](examples.md) - Common collection scenarios

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
