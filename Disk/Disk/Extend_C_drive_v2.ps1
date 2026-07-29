$servers = Get-Content "E:\Manoj\saltupgrade\servers.txt"
$LogPath = "E:\Manoj\saltupgrade\DiskExtendLogs"

New-Item -ItemType Directory -Path $LogPath -Force | Out-Null

foreach ($Server in $Servers) {

    Write-Host "`n===== Processing $Server =====" -ForegroundColor Cyan

    try {
        Invoke-Command -ComputerName $Server -ScriptBlock {

            $ErrorActionPreference = "Stop"

            Write-Output "---- Initial Check ----"

            $drive = Get-Partition -DriveLetter C
            $size = Get-PartitionSupportedSize -DriveLetter C

            Write-Output "Current Size: $([math]::Round($drive.Size/1GB,2)) GB"
            Write-Output "Max Size: $([math]::Round($size.SizeMax/1GB,2)) GB"

            # If no extendable space, try rescan
            if ($drive.Size -ge $size.SizeMax) {

                Write-Output "No extendable space detected. Attempting disk rescan..."

                # Rescan disks
                Update-HostStorageCache

                Start-Sleep -Seconds 5

                # Re-check after rescan
                $size = Get-PartitionSupportedSize -DriveLetter C

                Write-Output "Post-rescan Max Size: $([math]::Round($size.SizeMax/1GB,2)) GB"
            }

            # Extend if possible
            if ($drive.Size -lt $size.SizeMax) {

                Resize-Partition -DriveLetter C -Size $size.SizeMax

                $newSize = (Get-Partition -DriveLetter C).Size

                Write-Output "SUCCESS: Extended to $([math]::Round($newSize/1GB,2)) GB"
            }
            else {
                Write-Output "SKIPPED: Still no extendable space"
            }

        } | Out-File "$LogPath\$Server.txt"

        Write-Host "[SUCCESS] $Server" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAILED] $Server : $_" -ForegroundColor Red
    }
}