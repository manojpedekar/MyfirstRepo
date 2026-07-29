$info_diskdrive_basic = foreach ($disk in Get-CimInstance Win32_DiskDrive) {

    $partitions = Get-CimAssociatedInstance `
        -InputObject $disk `
        -Association Win32_DiskDriveToDiskPartition

    foreach ($partition in $partitions) {

        $volumes = Get-CimAssociatedInstance `
            -InputObject $partition `
            -Association Win32_LogicalDiskToPartition

        foreach ($volume in $volumes) {
            [PSCustomObject]@{
                Disk        = $disk.DeviceID
                DiskModel  = $disk.Model
                SerialID   = $disk.SerialNumber
                Partition  = $partition.Name
                RawSizeGB  = [math]::Round($partition.Size / 1GB, 2)
                DriveLetter= $volume.DeviceID
                VolumeName = $volume.VolumeName
                SizeGB     = [math]::Round($volume.Size / 1GB, 2)
                FreeGB     = [math]::Round($volume.FreeSpace / 1GB, 2)
            }
        }
    }
}
$info_diskdrive_basic | Select-Object driveletter,disk,partition,serialid