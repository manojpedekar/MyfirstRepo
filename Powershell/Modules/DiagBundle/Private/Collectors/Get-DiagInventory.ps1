function Get-DiagInventory {
    <#
    .SYNOPSIS
        Collect host identity, OS, hardware, and uptime into summary/inventory.json.

    .DESCRIPTION
        Query CIM for Win32_OperatingSystem, Win32_ComputerSystem, Win32_BIOS, and
        Win32_Processor. Emit a single derived artifact, summary/inventory.json, with
        host identity (name, FQDN, domain, role), OS version and install date, last
        boot time, hardware (manufacturer, model, serial, BIOS, CPU, memory), and
        uptime in hours. Runs early in the pipeline; other collectors do not depend
        on it. Standard user privileges suffice; CIM read access is required.

    .PARAMETER WorkingDirectory
        Mandatory. Absolute path to the bundle staging root. The collector writes
        into the existing summary\ subdirectory.

    .PARAMETER WindowHours
        Optional. Integer time window in hours. Default 24. Accepted for pipeline
        symmetry; this collector does not currently use it.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with
        path/category/type/description and per-type metadata), Errors (array of
        hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagInventory -WorkingDirectory $bundleRoot

    .NOTES
        Writes:
          - summary/inventory.json

        Never throws; populates Errors and returns Success=$false on fatal abort.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter()]
        [int] $WindowHours = 24
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
        $os   = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cs   = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-CimInstance Win32_BIOS           -ErrorAction SilentlyContinue
        $cpu  = @(Get-CimInstance Win32_Processor    -ErrorAction SilentlyContinue)

        # Gap 12 fix (2026-05-11 review): Win32_OperatingSystem LastBootUpTime
        # and InstallDate come back from CIM as DateTime objects. The CIM
        # cmdlets sometimes hand back Kind=Unspecified values that have
        # already been adjusted to local time, so a subsequent
        # .ToUniversalTime() is a no-op and the published UTC string ends
        # up being local-clock time stamped with a Z. Cross-check against
        # the original WMI string (CIM_DATETIME has the timezone offset
        # encoded as +/-MMM minutes) via ManagementDateTimeConverter, which
        # returns a DateTime with Kind=Local; .ToUniversalTime() on that is
        # safe. Fall back to the .NET-converted DateTime if the raw string
        # is not available.
        function _CimToUtc {
            param($CimInstance, [string] $PropertyName)
            $raw = $null
            try {
                $prop = $CimInstance.CimInstanceProperties[$PropertyName]
                if ($null -ne $prop) { $raw = [string]$prop.Value }
            } catch { }
            if ($raw -and $raw -match '^\d{14}\.\d{6}[+-]\d{3}$') {
                try {
                    $dt = [System.Management.ManagementDateTimeConverter]::ToDateTime($raw)
                    return $dt.ToUniversalTime()
                } catch { }
            }
            $fallback = $CimInstance.$PropertyName
            if ($fallback -is [DateTime]) {
                if ($fallback.Kind -eq [DateTimeKind]::Unspecified) {
                    # Assume CIM gave us a local clock value
                    return [DateTime]::SpecifyKind($fallback, [DateTimeKind]::Local).ToUniversalTime()
                }
                return $fallback.ToUniversalTime()
            }
            return $null
        }

        $bootUtc    = _CimToUtc -CimInstance $os -PropertyName 'LastBootUpTime'
        $installUtc = _CimToUtc -CimInstance $os -PropertyName 'InstallDate'

        # Firmware type + Secure Boot state.
        #   Confirm-SecureBootUEFI on UEFI: returns $true (enabled) / $false (disabled).
        #   On legacy BIOS: throws "not supported on this platform"-style message.
        #   On UEFI without elevation: throws "Access was denied" -- read the
        #     SecureBoot State registry key as a no-elevation fallback.
        $firmwareType = 'unknown'
        $secureBoot   = 'unknown'
        $sbDetectErr  = $null
        try {
            $sb = Confirm-SecureBootUEFI -ErrorAction Stop
            $firmwareType = 'UEFI'
            $secureBoot   = if ($sb) { 'enabled' } else { 'disabled' }
        } catch {
            $msg = "$($_.Exception.Message)"
            if ($msg -match 'not supported|Cmdlet not supported|0xC0000079|0xC000007E') {
                $firmwareType = 'BIOS'
                $secureBoot   = 'not_applicable'
            } elseif ($msg -match 'Access was denied|elevated privileges|elevated') {
                $secureBoot   = 'requires_elevation'
                $sbDetectErr  = 'access denied -- run elevated to read firmware variables'
                # Registry fallback. Presence of the SecureBoot\State key is
                # itself the UEFI signal; the value tells us enabled/disabled.
                try {
                    $rv = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\SecureBoot\State' -Name UEFISecureBootEnabled -ErrorAction Stop
                    $firmwareType = 'UEFI'
                    $secureBoot   = if ([int]$rv.UEFISecureBootEnabled -eq 1) { 'enabled' } else { 'disabled' }
                    $sbDetectErr  = $null
                } catch {
                    # Key absent (BIOS) or unreadable. Leave firmwareType=unknown.
                }
            } else {
                $sbDetectErr = $msg.Substring(0, [Math]::Min($msg.Length, 200))
            }
        }

        $domainRoleNames = @{
            0 = 'StandaloneWorkstation'
            1 = 'MemberWorkstation'
            2 = 'StandaloneServer'
            3 = 'MemberServer'
            4 = 'BackupDomainController'
            5 = 'PrimaryDomainController'
        }

        # Gap 10 (2026-05-11 review): pull cloud metadata via salt-call
        # --local grains.get for the seven ssnc_cloud_* / ssnc_environment
        # grains. Best-effort: any failure leaves cloud=null. Cloud-image
        # identity is the most actionable single field when triaging a
        # "this VM was built broken" complaint and lives only in Salt
        # grains today; surfacing it in inventory.json means we see it
        # whether or not Salt is otherwise relevant to the investigation.
        $cloud = $null
        try {
            $saltCallExe = $null
            foreach ($p in @(
                'C:\Program Files\Salt Project\Salt\salt-call.exe',
                'C:\Program Files\Salt Project\Salt\salt-call.bat',
                'C:\salt\salt-call.exe'
            )) {
                if (Test-Path -LiteralPath $p) { $saltCallExe = $p; break }
            }
            if ($saltCallExe) {
                # ProcessStartInfo.ArgumentList is .NET Core/5+ only;
                # PS 5.1 has only .Arguments (string).
                $cliArgs = @('--local', '--out=json', 'grains.item',
                             'ssnc_cloud_image', 'ssnc_cloud_platform',
                             'ssnc_cloud_account_name', 'ssnc_cloud_project_name',
                             'ssnc_cloud_subproject_name', 'ssnc_datacenter',
                             'ssnc_cloud_id', 'ssnc_environment')
                $proc = New-Object System.Diagnostics.Process
                $proc.StartInfo.FileName               = $saltCallExe
                $proc.StartInfo.Arguments              = ($cliArgs -join ' ')
                $proc.StartInfo.UseShellExecute        = $false
                $proc.StartInfo.RedirectStandardOutput = $true
                $proc.StartInfo.RedirectStandardError  = $true
                $proc.StartInfo.CreateNoWindow         = $true
                [void]$proc.Start()
                $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
                if ($proc.WaitForExit(15000) -and $proc.ExitCode -eq 0) {
                    $out = $stdoutTask.Result
                    try {
                        $obj = $out | ConvertFrom-Json -ErrorAction Stop
                        $g = $obj.local
                        if ($g) {
                            $cloud = [ordered]@{
                                image       = [string]$g.ssnc_cloud_image
                                platform    = [string]$g.ssnc_cloud_platform
                                account     = [string]$g.ssnc_cloud_account_name
                                project     = [string]$g.ssnc_cloud_project_name
                                subproject  = [string]$g.ssnc_cloud_subproject_name
                                datacenter  = [string]$g.ssnc_datacenter
                                instance_id = [string]$g.ssnc_cloud_id
                                environment = [string]$g.ssnc_environment
                            }
                        }
                    } catch { }
                }
                try { $proc.Dispose() } catch { }
            }
        } catch {
            # Non-fatal: cloud block stays null
        }

        $data = [ordered]@{
            schema_version = '1.1'
            host           = [ordered]@{
                computer_name = $env:COMPUTERNAME
                fqdn          = ("{0}.{1}" -f $cs.DNSHostName, $cs.Domain).TrimEnd('.')
                domain        = [string]$cs.Domain
                workgroup     = if ($cs.PartOfDomain) { $null } else { [string]$cs.Workgroup }
                os_version    = [string]$os.Version
                os_caption    = [string]$os.Caption
                install_date  = if ($installUtc) { $installUtc.ToString($fmt) } else { $null }
                last_boot_utc = if ($bootUtc)    { $bootUtc.ToString($fmt) }    else { $null }
                domain_role   = $domainRoleNames[[int]$cs.DomainRole]
            }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data           = [ordered]@{
                manufacturer    = [string]$cs.Manufacturer
                model           = [string]$cs.Model
                serial_number   = if ($bios) { [string]$bios.SerialNumber } else { $null }
                bios_version    = if ($bios) { [string]$bios.SMBIOSBIOSVersion } else { $null }
                firmware_type        = $firmwareType
                secure_boot          = $secureBoot
                secure_boot_detect_error = $sbDetectErr
                logical_cores   = [int]$cs.NumberOfLogicalProcessors
                physical_cpus   = $cpu.Count
                cpu_models      = @($cpu | ForEach-Object { $_.Name } | Where-Object { $_ })
                memory_gb       = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
                uptime_hours    = if ($bootUtc) { [math]::Round(((Get-Date).ToUniversalTime() - $bootUtc).TotalHours, 1) } else { $null }
                system_locale   = [string]$os.Locale
                time_zone       = (Get-DiagTimezone -WindowHours $WindowHours)
                primary_owner   = [string]$cs.PrimaryOwnerName
                last_logged_user = [string]$cs.UserName
                cloud           = $cloud
            }
        }

        $path = Join-Path $WorkingDirectory 'summary\inventory.json'
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))

        $result.Artifacts += @{
            path           = 'summary/inventory.json'
            category       = 'inventory'
            schema_version = '1.1'
            type           = 'derived'
            description    = 'Host identity, OS, hardware, uptime, cloud metadata grains'
        }
        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagInventory'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
