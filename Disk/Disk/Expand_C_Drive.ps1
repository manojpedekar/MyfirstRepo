$servers = Get-Content "E:\Manoj\saltupgrade\servers.txt"
$LogPath = "E:\Manoj\saltupgrade\DiskExtendLogs"

New-Item -ItemType Directory -Path $LogPath -Force | Out-Null

foreach ($Server in $Servers) {

    Write-Host "`n===== Processing $Server =====" -ForegroundColor Cyan

    try {
        Invoke-Command -ComputerName $Server -ScriptBlock {

            $ErrorActionPreference = "Stop"

            $drive = Get-Partition -DriveLetter C
            $disk = Get-Disk -Number $drive.DiskNumber

            Write-Output "Disk Number: $($disk.Number)"

            # Get max supported size
            $size = Get-PartitionSupportedSize -DriveLetter C

            Write-Output "Current Size: $([math]::Round($drive.Size/1GB,2)) GB"
            Write-Output "Max Supported: $([math]::Round($size.SizeMax/1GB,2)) GB"

            if ($drive.Size -lt $size.SizeMax) {

                Resize-Partition -DriveLetter C -Size $size.SizeMax

                $newSize = (Get-Partition -DriveLetter C).Size

                Write-Output "SUCCESS: Extended to $([math]::Round($newSize/1GB,2)) GB"
            }
            else {
                Write-Output "SKIPPED: Already at max size"
            }

        } | Out-File "$LogPath\$Server.txt"

        Write-Host "[SUCCESS] $Server" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAILED] $Server : $_" -ForegroundColor Red
    }
}
