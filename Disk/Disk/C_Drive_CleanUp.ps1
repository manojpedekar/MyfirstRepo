$LogPath = "E:\Manoj\saltupgrade\CleanupLogs"
New-Item -ItemType Directory -Path $LogPath -Force | Out-Null

$servers = Get-Content "E:\Manoj\saltupgrade\servers.txt"

foreach ($Server in $Servers) {

    Write-Host "`n===== Cleaning $Server =====" -ForegroundColor Cyan

    try {
        Invoke-Command -ComputerName $Server -ScriptBlock {

            $Before = (Get-PSDrive C).Free

            Write-Output "Free space BEFORE cleanup: $([math]::Round($Before/1GB,2)) GB"

            # Stop Windows Update service (for cache cleanup)
            Stop-Service wuauserv -Force -ErrorAction SilentlyContinue

            # Cleanup paths
            $paths = @(
                "C:\Windows\Temp\*",
                "C:\Users\*\AppData\Local\Temp\*",
                "C:\Windows\SoftwareDistribution\Download\*",
                "C:\Windows\Logs\CBS\*",
                "C:\Windows\Prefetch\*"
            )

            foreach ($path in $paths) {
                Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
            }

            # Delete old log files (>7 days)
            Get-ChildItem -Path C:\ -Include *.log, *.etl -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
            Remove-Item -Force -ErrorAction SilentlyContinue

            # Clear Recycle Bin
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue

            # Start Windows Update service back
            Start-Service wuauserv -ErrorAction SilentlyContinue

            $After = (Get-PSDrive C).Free

            Write-Output "Free space AFTER cleanup: $([math]::Round($After/1GB,2)) GB"
            Write-Output "Freed space: $([math]::Round(($After - $Before)/1GB,2)) GB"

        } | Out-File "$LogPath\$Server.txt"

        Write-Host "[SUCCESS] $Server" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAILED] $Server : $_" -ForegroundColor Red
    }
}