<#
.SYNOPSIS
    Collects physical disk, SCSI address, partition and volume details for the local server.

.DESCRIPTION
    Enumerates every physical disk via Win32_DiskDrive and performs a LEFT JOIN to its
    partitions and logical volumes. Because enumeration is driven by the disk (not the
    volume), disks that are OFFLINE, RAW/uninitialized, or that have partitions with no
    logical volume / drive letter are still reported (the original v1 script dropped them
    because it only emitted rows from the innermost volume loop).

    SCSI addressing (Port / Bus / TargetId / LUN) is read from Win32_DiskDrive. When the
    Storage module is available (Windows Server 2012+ / PowerShell 3.0+), Get-Disk is
    correlated by disk number to add Online/Offline state, operational status and partition
    style. On older hosts (e.g. Windows Server 2008 R2) those columns are populated with
    "N/A" and the rest of the report still works.

.PARAMETER OutputPath
    Folder where the CSV report is written. Defaults to C:\temp. Created if it does not exist.

.PARAMETER NoCsv
    Suppress CSV export and only return objects to the pipeline / console.

.OUTPUTS
    PSCustomObject per disk/partition/volume combination.

.EXAMPLE
    .\Get_Disk_Details_SN_PartitionID_v2.ps1

.EXAMPLE
    .\Get_Disk_Details_SN_PartitionID_v2.ps1 -OutputPath D:\Reports -NoCsv

.NOTES
    Compatible with Windows PowerShell 2.0+ (WMI path). Get-Disk enrichment requires
    the Storage module (Windows Server 2012+).
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = 'C:\temp',

    [Parameter()]
    [switch]$NoCsv
)

#region Helpers
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] $Message"
}
#endregion Helpers

#region Main
try {
    Write-Log "Starting disk detail collection on '$env:COMPUTERNAME'."

    # --- Build a lookup of Get-Disk state, keyed by disk number, when the Storage module exists.
    $diskStateByNumber = @{}
    if (Get-Command -Name Get-Disk -ErrorAction SilentlyContinue) {
        try {
            foreach ($d in Get-Disk -ErrorAction Stop) {
                $diskStateByNumber[[int]$d.Number] = $d
            }
            Write-Log "Get-Disk enrichment enabled ($($diskStateByNumber.Count) disk(s))."
        }
        catch {
            Write-Log "Get-Disk failed; continuing with WMI data only. $($_.Exception.Message)" -Level WARN
        }
    }
    else {
        Write-Log "Get-Disk not available (legacy OS). Online/Offline state will be reported as N/A." -Level WARN
    }

    # --- Enumerate physical disks. This drives the report so no disk is skipped.
    $diskDrives = @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop)
    Write-Log "Found $($diskDrives.Count) physical disk(s)."

    $results = foreach ($disk in $diskDrives) {

        # Correlate to Get-Disk by number (Win32_DiskDrive.Index == Get-Disk.Number).
        $state = $null
        if ($null -ne $disk.Index) { $state = $diskStateByNumber[[int]$disk.Index] }

        # SCSI address components live on Win32_DiskDrive.
        $scsiAddress = '{0}:{1}:{2}:{3}' -f `
            $disk.SCSIPort, $disk.SCSIBus, $disk.SCSITargetId, $disk.SCSILogicalUnit

        # Base template shared by every row produced for this disk.
        $base = [ordered]@{
            ComputerName    = $env:COMPUTERNAME
            DiskNumber      = $disk.Index
            Disk            = $disk.DeviceID
            DiskModel       = $disk.Model
            SerialID        = ($disk.SerialNumber -replace '\s', '')
            InterfaceType   = $disk.InterfaceType
            DiskSizeGB      = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 2) } else { $null }
            SCSIPort        = $disk.SCSIPort
            SCSIBus         = $disk.SCSIBus
            SCSITargetId    = $disk.SCSITargetId
            SCSILogicalUnit = $disk.SCSILogicalUnit
            SCSIAddress     = $scsiAddress
            IsOffline       = if ($state) { $state.IsOffline }        else { 'N/A' }
            OperationalStat = if ($state) { $state.OperationalStatus } else { 'N/A' }
            PartitionStyle  = if ($state) { $state.PartitionStyle }    else { 'N/A' }
        }

        # Attach partitions (LEFT JOIN).
        $partitions = @(Get-CimAssociatedInstance -InputObject $disk `
                -Association Win32_DiskDriveToDiskPartition -ErrorAction SilentlyContinue)

        if ($partitions.Count -eq 0) {
            # No partitions (RAW / uninitialized / offline) -> still emit one row for the disk.
            [PSCustomObject]($base + [ordered]@{
                    Partition  = $null
                    RawSizeGB  = $null
                    DriveLetter = $null
                    VolumeName = $null
                    SizeGB     = $null
                    FreeGB     = $null
                })
            continue
        }

        foreach ($partition in $partitions) {
            $volumes = @(Get-CimAssociatedInstance -InputObject $partition `
                    -Association Win32_LogicalDiskToPartition -ErrorAction SilentlyContinue)

            if ($volumes.Count -eq 0) {
                # Partition with no logical volume / drive letter -> still emit the partition row.
                [PSCustomObject]($base + [ordered]@{
                        Partition  = $partition.Name
                        RawSizeGB  = if ($partition.Size) { [math]::Round($partition.Size / 1GB, 2) } else { $null }
                        DriveLetter = $null
                        VolumeName = $null
                        SizeGB     = $null
                        FreeGB     = $null
                    })
                continue
            }

            foreach ($volume in $volumes) {
                [PSCustomObject]($base + [ordered]@{
                        Partition  = $partition.Name
                        RawSizeGB  = if ($partition.Size) { [math]::Round($partition.Size / 1GB, 2) } else { $null }
                        DriveLetter = $volume.DeviceID
                        VolumeName = $volume.VolumeName
                        SizeGB     = if ($volume.Size) { [math]::Round($volume.Size / 1GB, 2) } else { $null }
                        FreeGB     = if ($volume.FreeSpace) { [math]::Round($volume.FreeSpace / 1GB, 2) } else { $null }
                    })
            }
        }
    }

    # --- Output.
    if (-not $NoCsv) {
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
            Write-Log "Created output folder '$OutputPath'."
        }
        $stamp   = Get-Date -Format 'yyyy-MM-dd_HHmmss'
        $csvFile = Join-Path $OutputPath "DiskDetails_${env:COMPUTERNAME}_$stamp.csv"
        $results | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
        Write-Log "Report written to '$csvFile'."
    }

    Write-Log "Collection complete. $($results.Count) row(s) generated."
    $results
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" -Level ERROR
    throw
}
#endregion Main
