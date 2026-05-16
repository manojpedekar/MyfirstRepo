# NTFS Collector Examples

Real-world examples for common collection scenarios using CollectNTFSPerms.exe.

## Basic Examples

### Collect a Single Folder

```cmd
CollectNTFSPerms.exe D:\FileShares D:\Output\fileshares.db
```

### Collect with Path Containing Spaces

```cmd
CollectNTFSPerms.exe "E:\File Server\Department Data" E:\Output\departments.db
```

### Collect All Fixed Disks

```cmd
CollectNTFSPerms.exe --allfixeddisks C:\Output\full_inventory.db
```

### Collect from Remote Share

```cmd
CollectNTFSPerms.exe "\\FileServer01\Data" C:\Output\server01.db --RemoteComputer FileServer01
```

## Pre-Scan Testing

### Test Access Before Full Collection

```cmd
REM Test access first
CollectNTFSPerms.exe --testaccess D:\Shares

REM If acceptable, run full collection
CollectNTFSPerms.exe D:\Shares D:\Output\shares.db
```

### Check if Path Would Be Excluded

```cmd
REM Test various paths
CollectNTFSPerms.exe --testexclude "C:\System Volume Information"
CollectNTFSPerms.exe --testexclude "C:\$Recycle.Bin"
CollectNTFSPerms.exe --testexclude "D:\Data\.snapshot"
CollectNTFSPerms.exe --testexclude "D:\Data\Backups"
```

## Output Customization

### Keep Database Uncompressed

```cmd
CollectNTFSPerms.exe D:\Shares D:\Output\permissions.db --NoZip
```

Use this when:
- You need to query the database immediately after collection
- You'll compress the file separately
- Compression time is a concern on large databases

### Collect Explicit Permissions Only

```cmd
CollectNTFSPerms.exe D:\Shares D:\Output\permissions.db --ExplicitOnly
```

Use this when:
- You only care about explicitly-set permissions
- You want smaller output files
- Faster collection time is more important than inheritance data

### Combined Options

```cmd
CollectNTFSPerms.exe --allfixeddisks C:\Output\inventory.db --ExplicitOnly --NoZip
```

## Troubleshooting Examples

### Enable Debug Logging

```cmd
CollectNTFSPerms.exe D:\Shares D:\Output\permissions.db --Debug
```

Creates `CollectNTFSPerms.debug` file with detailed trace output.

### Debug with Test Access

```cmd
CollectNTFSPerms.exe --testaccess "\\Server\Share" --Debug
```

## Automation Examples

### Simple Batch File

```batch
@echo off
REM File: C:\Scripts\CollectPerms.cmd

set OUTPUT_DIR=C:\Output
set TOOL_DIR=C:\Tools\CollectNTFSPerms

REM Ensure output directory exists
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

REM Run collection
cd /d "%TOOL_DIR%"
CollectNTFSPerms.exe D:\Shares "%OUTPUT_DIR%\%COMPUTERNAME%_shares.db"

echo Collection complete. Output: %OUTPUT_DIR%
dir "%OUTPUT_DIR%\*.zip" /od
```

### All Fixed Disks with Date Stamp

```batch
@echo off
REM File: C:\Scripts\WeeklyCollection.cmd

set OUTPUT_DIR=C:\Output
set TOOL_DIR=C:\Tools\CollectNTFSPerms

REM Get date in YYYYMMDD format
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /format:list') do set datetime=%%I
set DATESTAMP=%datetime:~0,8%

REM Run collection
cd /d "%TOOL_DIR%"
CollectNTFSPerms.exe --allfixeddisks "%OUTPUT_DIR%\%COMPUTERNAME%_%DATESTAMP%.db"

echo Collection complete.
```

### With Network Copy

```batch
@echo off
REM File: C:\Scripts\CollectAndCopy.cmd

set OUTPUT_DIR=C:\Output
set NETWORK_SHARE=\\CentralServer\Collections
set TOOL_DIR=C:\Tools\CollectNTFSPerms

cd /d "%TOOL_DIR%"
CollectNTFSPerms.exe --allfixeddisks "%OUTPUT_DIR%\%COMPUTERNAME%.db"

REM Copy latest ZIP to network
for /f "delims=" %%F in ('dir /b /od "%OUTPUT_DIR%\*.zip" 2^>nul') do set LATEST=%%F
if defined LATEST (
    copy /y "%OUTPUT_DIR%\%LATEST%" "%NETWORK_SHARE%\"
    echo Copied %LATEST% to %NETWORK_SHARE%
)
```

### PowerShell Wrapper Script

```powershell
# File: C:\Scripts\Run-NTFSCollection.ps1

param(
    [string]$Path = $null,
    [switch]$AllDisks,
    [switch]$ExplicitOnly,
    [string]$OutputDir = "C:\Output"
)

$toolPath = "C:\Tools\CollectNTFSPerms\CollectNTFSPerms.exe"
$dateStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$dbFile = Join-Path $OutputDir "$env:COMPUTERNAME`_$dateStamp.db"

# Build arguments
$args = @()

if ($AllDisks) {
    $args += "--allfixeddisks"
    $args += $dbFile
} elseif ($Path) {
    $args += "`"$Path`""
    $args += $dbFile
} else {
    Write-Error "Specify either -Path or -AllDisks"
    exit 1
}

if ($ExplicitOnly) {
    $args += "--ExplicitOnly"
}

# Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Run collection
Write-Host "Starting collection..."
Write-Host "Command: $toolPath $($args -join ' ')"

$process = Start-Process -FilePath $toolPath -ArgumentList $args -Wait -PassThru -NoNewWindow

if ($process.ExitCode -eq 0) {
    Write-Host "Collection completed successfully!" -ForegroundColor Green

    # Find the output file (will be .zip after compression)
    $zipFile = $dbFile -replace '\.db$', '.zip'
    if (Test-Path $zipFile) {
        Write-Host "Output: $zipFile"
        Write-Host "Size: $((Get-Item $zipFile).Length / 1MB) MB"
    } elseif (Test-Path $dbFile) {
        Write-Host "Output: $dbFile"
        Write-Host "Size: $((Get-Item $dbFile).Length / 1MB) MB"
    }
} else {
    Write-Error "Collection failed with exit code: $($process.ExitCode)"
}
```

Usage:
```powershell
# Collect specific path
.\Run-NTFSCollection.ps1 -Path "D:\Shares"

# Collect all disks
.\Run-NTFSCollection.ps1 -AllDisks

# Collect all disks with explicit only
.\Run-NTFSCollection.ps1 -AllDisks -ExplicitOnly
```

### Multiple Servers via PowerShell Remoting

```powershell
# File: C:\Scripts\Collect-MultiServer.ps1

$servers = @("FileServer01", "FileServer02", "FileServer03")
$networkShare = "\\CentralServer\Collections"

foreach ($server in $servers) {
    Write-Host "Starting collection on $server..." -ForegroundColor Cyan

    Invoke-Command -ComputerName $server -ScriptBlock {
        $toolPath = "C:\Tools\CollectNTFSPerms\CollectNTFSPerms.exe"
        $dbPath = "C:\Output\$env:COMPUTERNAME.db"

        & $toolPath --allfixeddisks $dbPath
    }

    # Copy output to central location
    $zipFile = "\\$server\C$\Output\$server.zip"
    if (Test-Path $zipFile) {
        Copy-Item $zipFile -Destination $networkShare -Force
        Write-Host "Copied $zipFile to $networkShare" -ForegroundColor Green
    }
}

Write-Host "All collections complete!" -ForegroundColor Green
```

## Performance Optimization

### For Very Large File Systems

```cmd
REM Use explicit-only for faster collection
CollectNTFSPerms.exe --allfixeddisks C:\Output\inventory.db --ExplicitOnly

REM Or skip compression to save time (compress later)
CollectNTFSPerms.exe --allfixeddisks C:\Output\inventory.db --NoZip
```

### Output to Fast Local SSD

```cmd
REM Write to local SSD, then move to network
CollectNTFSPerms.exe D:\Shares C:\SSD_Temp\permissions.db
move C:\SSD_Temp\permissions.zip \\NetworkShare\Collections\
```

## Remote Share Collection

### Basic Remote Share

```cmd
CollectNTFSPerms.exe "\\FileServer01\DataShare" C:\Output\server01.db --RemoteComputer FileServer01
```

### Multiple Remote Shares (Batch)

```batch
@echo off
REM Collect from multiple remote shares

CollectNTFSPerms.exe "\\Server1\Share1" C:\Output\server1_share1.db --RemoteComputer Server1
CollectNTFSPerms.exe "\\Server1\Share2" C:\Output\server1_share2.db --RemoteComputer Server1
CollectNTFSPerms.exe "\\Server2\Data" C:\Output\server2_data.db --RemoteComputer Server2
```

## Task Scheduler Setup

### Create Scheduled Task via PowerShell

```powershell
# Create weekly NTFS collection task

$action = New-ScheduledTaskAction `
    -Execute "C:\Tools\CollectNTFSPerms\CollectNTFSPerms.exe" `
    -Argument "--allfixeddisks C:\Output\weekly_inventory.db" `
    -WorkingDirectory "C:\Tools\CollectNTFSPerms"

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 12) `
    -StartWhenAvailable `
    -DontStopOnIdleEnd

Register-ScheduledTask `
    -TaskName "Weekly NTFS Collection" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings
```

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
