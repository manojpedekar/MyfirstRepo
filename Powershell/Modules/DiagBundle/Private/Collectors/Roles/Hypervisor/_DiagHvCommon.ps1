function _CopyAgentLogs {
    <#
    .SYNOPSIS
        Copy log files matching one or more glob patterns from a guest-agent
        directory into the bundle, register artifacts, and update the
        log_count / log_total_bytes accumulators on the shared HvData.
    .NOTES
        Caps total bytes at 50 MB by default to mirror the IIS/SQL log copy
        budget. Newest-first ordering means the most relevant logs land
        first if the cap is hit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $SrcDir,
        [Parameter(Mandatory)] [string]   $DstDir,
        [Parameter(Mandatory)] [string[]] $Patterns,
        [Parameter(Mandatory)] [ref]      $HvData,
        [Parameter(Mandatory)] [ref]      $Result,
        [Parameter(Mandatory)] [string]   $ArtifactCategory,
        [Parameter(Mandatory)] [string]   $BundlePathPrefix,
        [Parameter()]          [long]     $MaxBytes = 50MB
    )
    if (-not (Test-Path -LiteralPath $SrcDir)) { return }
    if (-not (Test-Path -LiteralPath $DstDir)) {
        try { New-Item -ItemType Directory -Force -Path $DstDir | Out-Null } catch { return }
    }
    $files = @()
    foreach ($pat in $Patterns) {
        $files += @(Get-ChildItem -LiteralPath $SrcDir -File -Filter $pat -ErrorAction SilentlyContinue)
    }
    $files = @($files | Sort-Object LastWriteTime -Descending)

    $running = 0L
    foreach ($f in $files) {
        if (($running + $f.Length) -gt $MaxBytes) { continue }
        try {
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $DstDir $f.Name) -Force -ErrorAction Stop
            $running += $f.Length
            $Result.Value.Artifacts += @{
                path        = "$BundlePathPrefix/$($f.Name)"
                category    = $ArtifactCategory
                type        = 'raw'
                description = "Hypervisor guest-agent log: $($f.Name)"
            }
            $HvData.Value.guest_agent_log_count       += 1
            $HvData.Value.guest_agent_log_total_bytes += [long]$f.Length
        } catch {
            $Result.Value.Errors += @{
                collector = 'Get-DiagRoleHypervisor'
                artifact  = "$BundlePathPrefix/$($f.Name)"
                reason    = $_.Exception.Message
                severity  = 'warning'
            }
        }
    }
}

function _CopyInstallerLogsInWindow {
    <#
    .SYNOPSIS
        Copy guest-agent / paravirt-driver installer logs from %TEMP% and
        %WINDIR%\Temp that fall within the time window. Installer hangs
        across patch reboots are a known cross-hypervisor failure mode;
        these logs are typically <1 MB each.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]]  $Patterns,
        [Parameter(Mandatory)] [string]    $DstDir,
        [Parameter(Mandatory)] [DateTime]  $Cutoff,
        [Parameter(Mandatory)] [ref]       $HvData,
        [Parameter(Mandatory)] [ref]       $Result,
        [Parameter(Mandatory)] [string]    $BundlePathPrefix
    )
    if (-not (Test-Path -LiteralPath $DstDir)) {
        try { New-Item -ItemType Directory -Force -Path $DstDir | Out-Null } catch { return }
    }
    $files = @()
    $tempRoots = @()
    if ($env:TEMP)   { $tempRoots += $env:TEMP }
    $sysTemp = Join-Path $env:windir 'Temp'
    if (Test-Path -LiteralPath $sysTemp) { $tempRoots += $sysTemp }

    foreach ($root in $tempRoots) {
        foreach ($pat in $Patterns) {
            $files += @(Get-ChildItem -LiteralPath $root -File -Filter $pat -ErrorAction SilentlyContinue)
        }
    }
    $files = @($files | Where-Object { $_.LastWriteTime -ge $Cutoff } | Sort-Object LastWriteTime -Descending)

    foreach ($f in $files) {
        try {
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $DstDir $f.Name) -Force -ErrorAction Stop
            $Result.Value.Artifacts += @{
                path        = "$BundlePathPrefix/$($f.Name)"
                category    = 'hypervisor_installer_log'
                type        = 'raw'
                description = "Hypervisor agent installer log: $($f.Name)"
            }
            $HvData.Value.installer_log_count += 1
        } catch {
            $Result.Value.Errors += @{
                collector = 'Get-DiagRoleHypervisor'
                artifact  = "$BundlePathPrefix/$($f.Name)"
                reason    = $_.Exception.Message
                severity  = 'warning'
            }
        }
    }
}

function _AddBinaryVersionInfo {
    <#
    .SYNOPSIS
        Append FileVersionInfo for one guest-agent binary to
        HvData.platform_specific.binaries[]. Useful when the agent's manifest
        version disagrees with what is actually deployed on disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $InstallPath,
        [Parameter(Mandatory)] [string] $BinaryName,
        [Parameter(Mandatory)] [ref]    $HvData
    )
    if (-not $InstallPath) { return }
    $candidate = Join-Path $InstallPath $BinaryName
    if (-not (Test-Path -LiteralPath $candidate)) { return }
    try {
        $f = Get-Item -LiteralPath $candidate -ErrorAction Stop
        $vi = $f.VersionInfo
        $entry = [ordered]@{
            name             = $BinaryName
            path             = $f.FullName
            file_version     = "$($vi.FileVersion)"
            product_version  = "$($vi.ProductVersion)"
            file_description = "$($vi.FileDescription)"
            length_bytes     = [long]$f.Length
            modified_utc     = $f.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
        if (-not $HvData.Value.platform_specific.Contains('binaries')) {
            $HvData.Value.platform_specific['binaries'] = @()
        }
        $HvData.Value.platform_specific['binaries'] += ,$entry
    } catch { }
}

function _CapturePvDrivers {
    <#
    .SYNOPSIS
        Populate HvData.paravirt_drivers from Win32_PnPSignedDriver, matching
        a list of canonical driver service names for the platform. Each
        entry: {name, file, version, link_date, state}.
    .NOTES
        Win32_PnPSignedDriver is the bound-driver view (matches what the
        kernel actually loaded). DeviceName/DriverName lookup is loose because
        the canonical names supplied by callers do not always match the
        DeviceName surface; we match against InfName / DriverName / DeviceName.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Names,
        [Parameter(Mandatory)] [ref]      $HvData
    )
    try {
        $all = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop
    } catch { return }
    foreach ($n in $Names) {
        $matches = @($all | Where-Object {
            ($_.InfName -like "$n*") -or ($_.DriverName -like "$n*") -or ($_.DeviceName -like "*$n*")
        })
        foreach ($m in $matches) {
            $entry = [ordered]@{
                name        = $n
                inf_name    = "$($m.InfName)"
                driver_name = "$($m.DriverName)"
                device_name = "$($m.DeviceName)"
                version     = "$($m.DriverVersion)"
                date        = if ($m.DriverDate) { ([DateTime]$m.DriverDate).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                provider    = "$($m.DriverProviderName)"
                signer      = "$($m.Signer)"
                hardware_id = "$($m.HardWareID)"
            }
            $HvData.Value.paravirt_drivers += ,$entry
        }
    }
}

function _CaptureNicAdvanced {
    <#
    .SYNOPSIS
        For each NetAdapter whose interface description matches the like
        pattern, capture its advanced properties (RSS / LRO / offload knobs)
        into HvData.paravirt_nic_advanced.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $InterfaceLike,
        [Parameter(Mandatory)] [ref]    $HvData
    )
    if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) { return }
    try {
        $nics = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -like $InterfaceLike })
        foreach ($n in $nics) {
            $props = @()
            try {
                $advanced = Get-NetAdapterAdvancedProperty -Name $n.Name -ErrorAction SilentlyContinue
                foreach ($p in @($advanced)) {
                    $props += ,([ordered]@{
                        registry_keyword = "$($p.RegistryKeyword)"
                        display_name     = "$($p.DisplayName)"
                        display_value    = "$($p.DisplayValue)"
                        registry_value   = if ($p.RegistryValue) { "$($p.RegistryValue -join ',')" } else { '' }
                    })
                }
            } catch { }
            $HvData.Value.paravirt_nic_advanced += ,([ordered]@{
                name                  = "$($n.Name)"
                interface_description = "$($n.InterfaceDescription)"
                status                = "$($n.Status)"
                link_speed            = "$($n.LinkSpeed)"
                mac_address           = "$($n.MacAddress)"
                advanced_properties   = $props
            })
        }
    } catch { }
}

function _CaptureTimeSyncProvider {
    <#
    .SYNOPSIS
        Capture w32tm /query /providers and /query /status as a single
        free-form text blob in HvData.time_sync_provider_text. Host-time-sync
        conflict with W32Time is a classic patch-window gotcha; the raw text
        is small and the analyst can grep it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ref] $HvData
    )
    try {
        $providers = Invoke-DiagTimed -Collector 'Get-DiagRoleHypervisor' -Step 'w32tm /query /providers' -Action {
            & w32tm /query /providers 2>&1
        }
        $status = Invoke-DiagTimed -Collector 'Get-DiagRoleHypervisor' -Step 'w32tm /query /status' -Action {
            & w32tm /query /status 2>&1
        }
        $HvData.Value.time_sync_provider_text = (@(
            '--- w32tm /query /providers ---'
            ($providers -join "`r`n")
            ''
            '--- w32tm /query /status ---'
            ($status -join "`r`n")
        ) -join "`r`n")
    } catch { }
}
