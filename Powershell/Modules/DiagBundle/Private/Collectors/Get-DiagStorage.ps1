function Get-DiagStorage {
    <#
    .SYNOPSIS
        Capture volumes, physical disks, VSS shadows, page files, and dump files.

    .DESCRIPTION
        Enumerate volumes via Get-Volume with a Win32_LogicalDisk fallback for
        older hosts. Add Get-PhysicalDisk where available, list VSS shadow copies
        via vssadmin list shadows, page files via Win32_PageFileUsage, and any
        .dmp files in %windir%\Minidump plus %windir%\MEMORY.DMP. Emit
        summary/storage.json. Runs in parallel with peer collectors. vssadmin
        and reading the dump locations require administrator privileges; under
        non-admin those sections degrade to empty rather than failing the bundle.

    .PARAMETER WorkingDirectory
        Mandatory. Absolute path to the bundle staging root. The collector writes
        into the existing summary\ subdirectory.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with
        path/category/type/description and per-type metadata), Errors (array of
        hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagStorage -WorkingDirectory $bundleRoot

    .NOTES
        Writes:
          - summary/storage.json

        Get-Volume failures fall back to Win32_LogicalDisk fixed disks only.
        Get-PhysicalDisk and vssadmin failures are swallowed silently; their
        sections come back empty. Dump files are indexed by path and size only;
        the .dmp bytes themselves are handled by Get-DiagWER. Never throws;
        populates Errors and returns Success=$false on fatal abort.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory
    )

    $started = Get-Date
    $result = [pscustomobject]@{
        Success         = $false
        Artifacts       = @()
        Errors          = @()
        DurationSeconds = 0
    }
    $fmt = 'yyyy-MM-ddTHH:mm:ss.fffZ'

    try {
        $volumes = @()
        try {
            $volumes = @(Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter } | ForEach-Object {
                [ordered]@{
                    drive_letter   = "$($_.DriveLetter):"
                    file_system    = $_.FileSystem
                    label          = $_.FileSystemLabel
                    size_gb        = [math]::Round($_.Size / 1GB, 1)
                    free_gb        = [math]::Round($_.SizeRemaining / 1GB, 1)
                    free_pct       = if ($_.Size -gt 0) { [math]::Round(($_.SizeRemaining / $_.Size) * 100, 1) } else { 0 }
                    health_status  = "$($_.HealthStatus)"
                    drive_type     = "$($_.DriveType)"
                }
            })
        } catch {
            $volumes = @(Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
                [ordered]@{
                    drive_letter  = $_.DeviceID
                    file_system   = $_.FileSystem
                    label         = $_.VolumeName
                    size_gb       = [math]::Round($_.Size / 1GB, 1)
                    free_gb       = [math]::Round($_.FreeSpace / 1GB, 1)
                    free_pct      = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
                    health_status = 'Unknown'
                    drive_type    = 'Fixed'
                }
            })
        }

        $physicalDisks = @()
        try {
            $physicalDisks = @(Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
                [ordered]@{
                    friendly_name = $_.FriendlyName
                    media_type    = "$($_.MediaType)"
                    bus_type      = "$($_.BusType)"
                    size_gb       = [math]::Round($_.Size / 1GB, 1)
                    health_status = "$($_.HealthStatus)"
                    operational   = "$($_.OperationalStatus -join ', ')"
                }
            })
        } catch { }

        # Disk -> partition traversal so the consumer can see how a volume
        # actually lives on hardware (or virtual disk, or storage spaces pool).
        $disks = @()
        try {
            $disks = @(Invoke-DiagTimed -Collector 'Get-DiagStorage' -Step 'Get-Disk + per-disk Get-Partition' -Action {
                Get-Disk -ErrorAction Stop
            } | ForEach-Object {
                $diskNum = [int]$_.Number
                $partitions = @()
                try {
                    $partitions = @(Get-Partition -DiskNumber $diskNum -ErrorAction Stop | ForEach-Object {
                        [ordered]@{
                            number       = [int]$_.PartitionNumber
                            drive_letter = if ($_.DriveLetter) { "$($_.DriveLetter):" } else { $null }
                            mount_points = @($_.AccessPaths | Where-Object { $_ -and $_ -notmatch '^\\\\\?\\Volume\{' })
                            size_gb      = [math]::Round($_.Size / 1GB, 2)
                            offset_bytes = [int64]$_.Offset
                            type         = "$($_.Type)"
                            gpt_type     = if ($_.GptType) { "$($_.GptType)" } else { $null }
                            mbr_type     = if ($_.MbrType) { [int]$_.MbrType } else { $null }
                            is_boot      = [bool]$_.IsBoot
                            is_system    = [bool]$_.IsSystem
                            is_active    = [bool]$_.IsActive
                            is_hidden    = [bool]$_.IsHidden
                        }
                    })
                } catch { }
                [ordered]@{
                    number               = $diskNum
                    friendly_name        = "$($_.FriendlyName)"
                    serial_number        = "$($_.SerialNumber)"
                    partition_style      = "$($_.PartitionStyle)"
                    operational_status   = "$($_.OperationalStatus)"
                    health_status        = "$($_.HealthStatus)"
                    bus_type             = "$($_.BusType)"
                    size_gb              = [math]::Round($_.Size / 1GB, 2)
                    allocated_size_gb    = [math]::Round($_.AllocatedSize / 1GB, 2)
                    is_boot              = [bool]$_.IsBoot
                    is_system            = [bool]$_.IsSystem
                    is_clustered         = [bool]$_.IsClustered
                    is_offline           = [bool]$_.IsOffline
                    is_readonly          = [bool]$_.IsReadOnly
                    number_of_partitions = [int]$_.NumberOfPartitions
                    partitions           = $partitions
                }
            })
        } catch {
            $result.Errors += @{ collector = 'Get-DiagStorage'; reason = "Get-Disk failed: $($_.Exception.Message)"; severity = 'warning' }
        }

        # Storage Spaces -- only present when the role/feature is installed.
        $virtualDisks = @()
        if (Get-Command -Name Get-VirtualDisk -ErrorAction SilentlyContinue) {
            try {
                $virtualDisks = @(Get-VirtualDisk -ErrorAction SilentlyContinue | ForEach-Object {
                    [ordered]@{
                        friendly_name      = "$($_.FriendlyName)"
                        resiliency_setting = "$($_.ResiliencySettingName)"
                        operational_status = "$($_.OperationalStatus -join ', ')"
                        health_status      = "$($_.HealthStatus)"
                        size_gb            = [math]::Round($_.Size / 1GB, 2)
                        allocated_size_gb  = [math]::Round($_.AllocatedSize / 1GB, 2)
                        footprint_gb       = if ($_.FootprintOnPool) { [math]::Round($_.FootprintOnPool / 1GB, 2) } else { $null }
                        provisioning_type  = "$($_.ProvisioningType)"
                    }
                })
            } catch { }
        }

        $storagePools = @()
        if (Get-Command -Name Get-StoragePool -ErrorAction SilentlyContinue) {
            try {
                $storagePools = @(Get-StoragePool -ErrorAction SilentlyContinue |
                    Where-Object { -not $_.IsPrimordial } | ForEach-Object {
                    [ordered]@{
                        friendly_name      = "$($_.FriendlyName)"
                        operational_status = "$($_.OperationalStatus -join ', ')"
                        health_status      = "$($_.HealthStatus)"
                        size_gb            = [math]::Round($_.Size / 1GB, 2)
                        allocated_size_gb  = [math]::Round($_.AllocatedSize / 1GB, 2)
                        is_clustered       = [bool]$_.IsClustered
                    }
                })
            } catch { }
        }

        $shadows = @()
        try {
            $vss = Invoke-DiagTimed -Collector 'Get-DiagStorage' -Step 'vssadmin list shadows' -Action { & vssadmin list shadows 2>&1 }
            if ($LASTEXITCODE -eq 0) {
                $shadowCount = ($vss | Select-String -Pattern 'Shadow Copy ID:' -SimpleMatch | Measure-Object).Count
                $shadows = @(@{ count = $shadowCount; raw_lines = $vss.Count })
            }
        } catch { }

        $pageFiles = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue | ForEach-Object {
            [ordered]@{
                path             = $_.Name
                allocated_mb     = [int]$_.AllocatedBaseSize
                current_usage_mb = [int]$_.CurrentUsage
                peak_usage_mb    = [int]$_.PeakUsage
            }
        })

        $dumpDirs = @(
            Join-Path $env:windir 'Minidump'
            Join-Path $env:windir 'MEMORY.DMP'
        )
        $dumps = @()
        foreach ($d in $dumpDirs) {
            if (Test-Path -LiteralPath $d) {
                if ((Get-Item -LiteralPath $d).PSIsContainer) {
                    Get-ChildItem -Path $d -Filter '*.dmp' -ErrorAction SilentlyContinue | ForEach-Object {
                        $dumps += [ordered]@{
                            path     = $_.FullName
                            size_mb  = [math]::Round($_.Length / 1MB, 1)
                            modified_utc = $_.LastWriteTimeUtc.ToString($fmt)
                        }
                    }
                } else {
                    $i = Get-Item -LiteralPath $d
                    $dumps += [ordered]@{
                        path     = $i.FullName
                        size_mb  = [math]::Round($i.Length / 1MB, 1)
                        modified_utc = $i.LastWriteTimeUtc.ToString($fmt)
                    }
                }
            }
        }

        # Update readiness flag: cumulative-update installs typically need
        # ~15 GB on the system drive. Surface this explicitly so the agent
        # does not have to compute it from volumes[].
        $systemDrive = $env:SystemDrive
        $systemVolume = @($volumes | Where-Object { $_['drive_letter'] -eq $systemDrive }) | Select-Object -First 1
        $systemFreeGb = if ($systemVolume) { [double]$systemVolume['free_gb'] } else { $null }
        $wuThresholdGb = 15.0
        $wuBlocked = ($null -ne $systemFreeGb -and $systemFreeGb -lt $wuThresholdGb)
        $lowSpace = @($volumes | Where-Object {
            $f = [double]$_['free_pct']
            $g = [double]$_['free_gb']
            ($f -lt 10) -or ($g -lt 5)
        } | ForEach-Object { [ordered]@{ drive_letter = $_['drive_letter']; free_gb = $_['free_gb']; free_pct = $_['free_pct'] } })

        $updateReadiness = [ordered]@{
            system_drive             = $systemDrive
            system_free_gb           = $systemFreeGb
            wu_threshold_gb          = $wuThresholdGb
            wu_blocked_by_free_space = $wuBlocked
            low_space_volumes        = $lowSpace
        }

        # Some VMs (especially with multiple SCSI controllers) report several
        # "Disk 0" entries with distinct serial numbers -- the disk Number
        # field is not a reliable unique identifier. Surface a count by
        # serial so the consumer can see the disparity at a glance.
        $disksUniqueBySerial = @($disks |
            Where-Object { -not [string]::IsNullOrEmpty($_['serial_number']) } |
            Group-Object { $_['serial_number'] }).Count

        $data = [ordered]@{
            schema_version = '1.1'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data           = [ordered]@{
                disks                       = $disks
                disks_count                 = $disks.Count
                disks_unique_count_by_serial = $disksUniqueBySerial
                volumes                     = $volumes
                virtual_disks               = $virtualDisks
                storage_pools               = $storagePools
                physical_disks              = $physicalDisks
                shadows                     = $shadows
                page_files                  = $pageFiles
                dump_files                  = $dumps
                update_readiness            = $updateReadiness
            }
        }

        $path = Join-Path $WorkingDirectory 'summary\storage.json'
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))

        $result.Artifacts += @{
            path           = 'summary/storage.json'
            category       = 'storage'
            schema_version = '1.1'
            type           = 'derived'
            description    = 'Disks (with partition traversal), volumes, virtual disks, storage pools, physical disks, VSS shadows, page files, dumps, update readiness'
        }
        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagStorage'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
