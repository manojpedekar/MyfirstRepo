function Get-DiagDrivers {
    <#
    .SYNOPSIS
        Inventory drivers via pnputil, Win32_PnPSignedDriver, driverquery, and fltmc.

    .DESCRIPTION
        Captures four complementary views of host drivers:

        1) pnputil.exe /enum-drivers -- DriverStore packages (third-party and
           OEM drivers staged in the FileRepository, identified by .inf name).
        2) Get-CimInstance Win32_PnPSignedDriver -- drivers currently bound to
           devices, including in-box Microsoft drivers, with signer.
        3) driverquery.exe /v /fo csv -- ALL kernel-mode and file-system
           drivers (including filter drivers / AV minifilters / storage
           filters not bound to a PnP device), with current State, Status,
           Start Mode, and Driver Type.
        4) fltmc.exe filters + instances -- file-system minifilter inventory
           with altitudes and per-volume attachments. High-leverage for
           AV / EDR / backup-driver compatibility investigations.

        These views answer different questions:
          - pnputil    -> what is AVAILABLE to install (DriverStore)
          - PnPSigned  -> what is BOUND to a device right now
          - driverquery -> what kernel-mode modules are LOADED right now
          - fltmc      -> what file-system minifilters are intercepting I/O

        Outputs raw/drivers/* and summary/drivers.json. Runs in parallel with
        peer collectors.

    .PARAMETER WorkingDirectory
        Mandatory. Absolute path to the bundle staging root. The collector
        writes into the existing summary\ and raw\drivers\ subdirectories.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables
        with path/category/type/description and per-type metadata), Errors
        (array of hashtables with collector/reason/severity), DurationSeconds
        ([int]).

    .EXAMPLE
        Get-DiagDrivers -WorkingDirectory $bundleRoot

    .NOTES
        Writes:
          - summary/drivers.json                          (schema 1.1)
          - raw/drivers/pnputil_enum_drivers.txt
          - raw/drivers/driverquery.csv
          - raw/drivers/fltmc_filters.txt
          - raw/drivers/fltmc_instances.txt

        pnputil output parsing is line-based on the documented "Key: Value"
        format; an entry begins with "Published Name:". The Driver Version
        line "MM/DD/YYYY V.V.V.V" is split into driver_date (ISO yyyy-MM-dd)
        and driver_version. On non-US locale boxes the raw date string is
        kept verbatim if the parse fails.

        driverquery /v /fo csv ships raw plus a kernel_drivers projection
        with module_name, display_name, driver_type, start_mode, state,
        status, path, link_date, description. Driver Type values include
        "Kernel" and "File System" -- filter by driver_type='File System'
        AND state='Running' to find loaded minifilters and intersect with
        fltmc_filters output for full coverage.

        fltmc filters output is plain text (no clean parser); ship raw and
        let the consumer grep. The "Altitude" column is the canonical sort
        key for filter ordering -- AV / EDR drivers typically sit in the
        300000-330000 range; backup drivers in the 180000-190000 range.

        Win32_PnPSignedDriver projection includes device_name, driver_provider,
        driver_version, driver_date, inf_name, is_signed, signer, class_guid,
        manufacturer. Multiple bindings of the same driver to different
        devices appear as separate entries; consumer can dedupe by
        inf_name + driver_version if needed.

        pnputil exits non-zero on locked-down hosts where the DriverStore is
        not enumerable for non-admins; the collector logs that as a warning
        and proceeds. Win32_PnPSignedDriver, driverquery, and fltmc typically
        work without elevation but driverquery returns reduced detail when
        not elevated.

        Never throws. On fatal abort returns Success=$false with populated
        Errors.
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

    function _ParsePnputilEnumDrivers([string[]] $lines) {
        # Emit each parsed record as it is completed; the caller wraps with
        # @() to collect into an array. This avoids the array-wrapping
        # gotchas of returning $drivers via ", $drivers" through the PS
        # function output stream.
        $current = $null
        foreach ($raw in $lines) {
            $line = "$raw".TrimEnd()
            if ([string]::IsNullOrWhiteSpace($line)) {
                if ($current) { $current; $current = $null }
                continue
            }
            if ($line -notmatch '^\s*(\S[^:]*?):\s+(.*)$') { continue }
            $key = $Matches[1].Trim()
            $val = $Matches[2].Trim()
            if ($key -eq 'Published Name') {
                if ($current) { $current }
                $current = [ordered]@{}
            }
            if (-not $current) { continue }
            $normKey = ($key.ToLower() -replace '\s+', '_')
            if ($key -eq 'Driver Version' -and $val -match '^(\d{1,2}/\d{1,2}/\d{4})\s+(\S+)$') {
                $rawDate = $Matches[1]
                $current['driver_version'] = $Matches[2]
                $dt = [DateTime]::MinValue
                if ([DateTime]::TryParseExact($rawDate, 'M/d/yyyy', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$dt)) {
                    $current['driver_date'] = $dt.ToString('yyyy-MM-dd')
                } else {
                    $current['driver_date'] = $rawDate
                }
            } else {
                $current[$normKey] = $val
            }
        }
        if ($current) { $current }
    }

    try {
        $rawDir = Join-Path $WorkingDirectory 'raw\drivers'
        if (-not (Test-Path $rawDir)) {
            try { New-Item -ItemType Directory -Path $rawDir -Force | Out-Null } catch {
                $result.Errors += @{ collector = 'Get-DiagDrivers'; reason = "Could not create $rawDir : $($_.Exception.Message)"; severity = 'error' }
                return $result
            }
        }

        $pnputilOut = Join-Path $rawDir 'pnputil_enum_drivers.txt'
        $pnputilLines = @()
        try {
            # Force a string[] regardless of whether the host renders the
            # native exe output as one big string or one item per line.
            $pnputilLines = @((Invoke-DiagTimed -Collector 'Get-DiagDrivers' -Step 'pnputil /enum-drivers' -Action { & pnputil.exe /enum-drivers 2>&1 }) -join "`n" -split "\r?\n")
            if ($LASTEXITCODE -ne 0) {
                $result.Errors += @{
                    collector = 'Get-DiagDrivers'
                    artifact  = 'raw/drivers/pnputil_enum_drivers.txt'
                    reason    = "pnputil /enum-drivers exit ${LASTEXITCODE}: $(($pnputilLines | Select-Object -First 3) -join '; ')"
                    severity  = 'warning'
                }
            }
            [System.IO.File]::WriteAllText($pnputilOut, ($pnputilLines -join "`r`n"), [System.Text.UTF8Encoding]::new($false))
            $result.Artifacts += @{
                path        = 'raw/drivers/pnputil_enum_drivers.txt'
                category    = 'drivers_pnputil'
                type        = 'raw'
                description = 'pnputil /enum-drivers raw output (DriverStore packages)'
            }
        } catch {
            $result.Errors += @{
                collector = 'Get-DiagDrivers'
                artifact  = 'raw/drivers/pnputil_enum_drivers.txt'
                reason    = $_.Exception.Message
                severity  = 'warning'
            }
        }

        $pnputilDrivers = @()
        if ($pnputilLines.Count -gt 0) {
            $pnputilDrivers = @(_ParsePnputilEnumDrivers $pnputilLines)
        }

        $signedDrivers = @()
        try {
            $signedDrivers = @(Invoke-DiagTimed -Collector 'Get-DiagDrivers' -Step 'Get-CimInstance Win32_PnPSignedDriver' -Action {
                Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop
            } | ForEach-Object {
                [ordered]@{
                    device_name     = "$($_.DeviceName)"
                    driver_provider = "$($_.DriverProviderName)"
                    driver_version  = "$($_.DriverVersion)"
                    driver_date     = if ($_.DriverDate) { $_.DriverDate.ToUniversalTime().ToString('yyyy-MM-dd') } else { $null }
                    inf_name        = "$($_.InfName)"
                    is_signed       = [bool]$_.IsSigned
                    signer          = "$($_.Signer)"
                    class_guid      = "$($_.ClassGuid)"
                    manufacturer    = "$($_.Manufacturer)"
                }
            })
        } catch {
            $result.Errors += @{ collector = 'Get-DiagDrivers'; reason = "Win32_PnPSignedDriver query failed: $($_.Exception.Message)"; severity = 'warning' }
        }

        # driverquery /v /fo csv: kernel-mode and file-system drivers including
        # those not bound to a PnP device (filter drivers, AV/EDR minifilters,
        # storage filter drivers). Has current State + Status, missing from
        # Win32_PnPSignedDriver.
        $kernelDrivers = @()
        $dqOut = Join-Path $rawDir 'driverquery.csv'
        try {
            $dqRaw = (Invoke-DiagTimed -Collector 'Get-DiagDrivers' -Step 'driverquery /v /fo csv' -Action { & driverquery.exe /v /fo csv 2>&1 }) -join "`n"
            [System.IO.File]::WriteAllText($dqOut, $dqRaw, [System.Text.UTF8Encoding]::new($false))
            $result.Artifacts += @{
                path        = 'raw/drivers/driverquery.csv'
                category    = 'drivers_driverquery'
                type        = 'raw'
                description = 'driverquery /v /fo csv -- all kernel-mode and FS drivers with state, type, path'
            }
            try {
                # driverquery CSV pads every value to a fixed column width, so
                # every field arrives with trailing whitespace. Trim during
                # projection so consumer filters like state='Running' actually
                # match without surprise.
                $kernelDrivers = @($dqRaw | ConvertFrom-Csv -ErrorAction Stop | ForEach-Object {
                    [ordered]@{
                        module_name  = "$($_.'Module Name')".Trim()
                        display_name = "$($_.'Display Name')".Trim()
                        driver_type  = "$($_.'Driver Type')".Trim()
                        start_mode   = "$($_.'Start Mode')".Trim()
                        state        = "$($_.State)".Trim()
                        status       = "$($_.Status)".Trim()
                        path         = "$($_.Path)".Trim()
                        link_date    = "$($_.'Link Date')".Trim()
                        description  = "$($_.Description)".Trim()
                    }
                })
            } catch {
                $result.Errors += @{ collector = 'Get-DiagDrivers'; reason = "driverquery CSV parse failed: $($_.Exception.Message)"; severity = 'warning' }
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagDrivers'; artifact = 'raw/drivers/driverquery.csv'; reason = $_.Exception.Message; severity = 'warning' }
        }

        # File system filter manager: minifilter list and per-volume instances.
        # High-leverage for AV / EDR / backup-driver investigations.
        try {
            $fltFilters = (Invoke-DiagTimed -Collector 'Get-DiagDrivers' -Step 'fltmc filters' -Action { & fltmc.exe filters 2>&1 }) -join "`r`n"
            $fltOut = Join-Path $rawDir 'fltmc_filters.txt'
            [System.IO.File]::WriteAllText($fltOut, $fltFilters, [System.Text.UTF8Encoding]::new($false))
            $result.Artifacts += @{
                path        = 'raw/drivers/fltmc_filters.txt'
                category    = 'drivers_fltmc_filters'
                type        = 'raw'
                description = 'fltmc filters -- loaded file-system minifilters with altitude'
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagDrivers'; artifact = 'raw/drivers/fltmc_filters.txt'; reason = $_.Exception.Message; severity = 'warning' }
        }
        try {
            $fltInstances = (Invoke-DiagTimed -Collector 'Get-DiagDrivers' -Step 'fltmc instances' -Action { & fltmc.exe instances 2>&1 }) -join "`r`n"
            $fltOut = Join-Path $rawDir 'fltmc_instances.txt'
            [System.IO.File]::WriteAllText($fltOut, $fltInstances, [System.Text.UTF8Encoding]::new($false))
            $result.Artifacts += @{
                path        = 'raw/drivers/fltmc_instances.txt'
                category    = 'drivers_fltmc_instances'
                type        = 'raw'
                description = 'fltmc instances -- per-volume minifilter attachments'
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagDrivers'; artifact = 'raw/drivers/fltmc_instances.txt'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $data = [ordered]@{
            schema_version = '1.1'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data           = [ordered]@{
                pnputil_count        = $pnputilDrivers.Count
                pnputil_drivers      = $pnputilDrivers
                signed_drivers_count = $signedDrivers.Count
                signed_drivers       = $signedDrivers
                kernel_drivers_count = $kernelDrivers.Count
                kernel_drivers       = $kernelDrivers
            }
        }

        $sumPath = Join-Path $WorkingDirectory 'summary\drivers.json'
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($sumPath, $json, [System.Text.UTF8Encoding]::new($false))

        $result.Artifacts += @{
            path           = 'summary/drivers.json'
            category       = 'drivers'
            schema_version = '1.1'
            type           = 'derived'
            description    = "PnP DriverStore ($($pnputilDrivers.Count)) + bound device drivers ($($signedDrivers.Count)) + kernel-mode/FS drivers ($($kernelDrivers.Count))"
            row_count      = $pnputilDrivers.Count + $signedDrivers.Count + $kernelDrivers.Count
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagDrivers'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
