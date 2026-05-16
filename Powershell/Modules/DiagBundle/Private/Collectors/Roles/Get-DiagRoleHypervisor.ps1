function Get-DiagRoleHypervisor {
    <#
    .SYNOPSIS
        Detect the underlying hypervisor and dispatch to the platform-specific
        guest-agent collector. Hypervisor-agnostic; supports VMware ESXi,
        Microsoft Hyper-V, KVM/OpenShift Virtualization, and is extensible to
        additional platforms via the plugin table.

    .DESCRIPTION
        Reads Win32_ComputerSystem.Manufacturer and Win32_BIOS to identify
        the hypervisor. Writes a common summary/hypervisor.json regardless of
        platform (so consumers index one path) plus platform-specific raw
        artifacts under raw/role_specific/hypervisor/<platform>/. On a
        physical host or unknown manufacturer it emits a stub summary and
        exits Success without invoking any plugin.

        Plugin contract (each plugin in Roles/Hypervisor/Get-DiagHv<Platform>.ps1):
            Get-DiagHv<Platform> -WorkingDirectory <string>
                                 -RawDir <string>
                                 -WindowHours <int>
                                 -HvData <ref>     # mutate in place
                                 -Result <ref>     # append .Artifacts / .Errors

        Plugin is responsible for: detecting the install path, capturing
        version/build, copying agent logs, exporting platform-specific
        registry, capturing paravirt driver inventory, NIC advanced
        properties, and time-sync provider state. All external-command and
        file-copy work wraps in Invoke-DiagTimed.

    .PARAMETER WorkingDirectory
        Root of the staging tree. summary/hypervisor.json and
        raw/role_specific/hypervisor/<platform>/ land beneath it.

    .PARAMETER WindowHours
        Lookback in hours for time-bounded artifacts (installer logs).
        Defaults to 168 (7 days).

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array), Errors
        (array), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagRoleHypervisor -WorkingDirectory 'C:\ProgramData\DiagBundle\work\bundle-001' -WindowHours 24

    .NOTES
        Get-DiagRoles is the dispatcher and registers this collector as the
        'hypervisor' entry. Detection runs unconditionally; physical hosts
        report `is_virtualized = false` and exit cheaply. The plugin table
        is matched in declaration order; first match wins. Adding a new
        platform is one new row plus one new plugin file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $WorkingDirectory,
        [Parameter()]          [int]    $WindowHours = 168
    )

    $started = Get-Date
    $result = [pscustomobject]@{
        Success         = $false
        Artifacts       = @()
        Errors          = @()
        DurationSeconds = 0
    }
    $fmt = 'yyyy-MM-ddTHH:mm:ss.fffZ'

    # Detection table. First match wins. Add a new platform by appending
    # one row plus a Get-DiagHv<Platform>.ps1 plugin file.
    $platformTable = @(
        @{ Platform = 'vmware';   Plugin = 'Get-DiagHvVMware';
           ManufacturerLike = 'VMware*'; ModelLike = $null }
        @{ Platform = 'hyperv';   Plugin = 'Get-DiagHvHyperV';
           ManufacturerLike = 'Microsoft Corporation'; ModelLike = 'Virtual Machine*' }
        @{ Platform = 'kvm';      Plugin = 'Get-DiagHvKvm';
           ManufacturerLike = 'Red Hat*';            ModelLike = $null }
        @{ Platform = 'kvm';      Plugin = 'Get-DiagHvKvm';
           ManufacturerLike = 'QEMU*';               ModelLike = $null }
        @{ Platform = 'kvm';      Plugin = 'Get-DiagHvKvm';
           ManufacturerLike = 'Bochs';               ModelLike = $null }
    )

    try {
        $cs   = $null
        $bios = $null
        try { $cs   = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop }      catch { }
        try { $bios = Get-CimInstance Win32_BIOS           -ErrorAction SilentlyContinue } catch { }

        $mfg   = if ($cs) { "$($cs.Manufacturer)" } else { '' }
        $model = if ($cs) { "$($cs.Model)" }        else { '' }

        $matched = $null
        foreach ($p in $platformTable) {
            if ($mfg -like $p.ManufacturerLike -and (-not $p.ModelLike -or $model -like $p.ModelLike)) {
                $matched = $p
                break
            }
        }

        $hvData = [ordered]@{
            detected_platform           = if ($matched) { $matched.Platform } else { 'unknown' }
            is_virtualized              = $true
            manufacturer                = $mfg
            model                       = $model
            bios_version                = if ($bios) { "$($bios.SMBIOSBIOSVersion)" } else { $null }
            serial_or_uuid              = if ($bios) { "$($bios.SerialNumber)" } else { $null }
            firmware_type               = $null
            guest_agent_installed       = $false
            guest_agent_name            = $null
            guest_agent_version         = $null
            guest_agent_install_path    = $null
            guest_agent_log_count       = 0
            guest_agent_log_total_bytes = 0
            paravirt_drivers            = @()
            paravirt_nic_advanced       = @()
            time_sync_provider_text     = $null
            registry_export_path        = $null
            installer_log_count         = 0
            platform_specific           = [ordered]@{}
        }

        if (-not $matched) {
            # Physical-host heuristic: well-known physical-vendor patterns.
            # The list is conservative; an unknown vendor remains
            # `is_virtualized = $true` with `detected_platform = unknown`
            # so the agent knows we did not affirm virtualization either way.
            $physicalHints = @('Surface*','OptiPlex*','PowerEdge*','ProLiant*','ThinkSystem*','UCS*','PRIMERGY*','iDataPlex*','Synergy*')
            $modelMatch = $false
            if ($model) {
                foreach ($hint in $physicalHints) {
                    if ($model -like $hint) { $modelMatch = $true; break }
                }
            }
            if ($modelMatch) {
                $hvData.is_virtualized    = $false
                $hvData.detected_platform = 'physical'
            }
            _WriteHypervisorSummary -WorkingDirectory $WorkingDirectory -Data $hvData -Result ([ref]$result) -Fmt $fmt
            $result.Success = $true
            return $result
        }

        $rawDir = Join-Path $WorkingDirectory 'raw\role_specific\hypervisor'
        if (-not (Test-Path -LiteralPath $rawDir)) {
            New-Item -ItemType Directory -Force -Path $rawDir | Out-Null
        }

        $pluginCmd = Get-Command -Name $matched.Plugin -ErrorAction SilentlyContinue
        if (-not $pluginCmd) {
            $result.Errors += @{
                collector = 'Get-DiagRoleHypervisor'
                reason    = "Plugin $($matched.Plugin) not loaded for platform $($matched.Platform)"
                severity  = 'warning'
            }
        } else {
            try {
                & $matched.Plugin `
                    -WorkingDirectory $WorkingDirectory `
                    -RawDir           $rawDir `
                    -WindowHours      $WindowHours `
                    -HvData           ([ref]$hvData) `
                    -Result           ([ref]$result)
            } catch {
                $result.Errors += @{
                    collector = 'Get-DiagRoleHypervisor'
                    reason    = "Plugin $($matched.Plugin) failed: $($_.Exception.Message)"
                    severity  = 'warning'
                }
            }
        }

        _WriteHypervisorSummary -WorkingDirectory $WorkingDirectory -Data $hvData -Result ([ref]$result) -Fmt $fmt
        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagRoleHypervisor'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }
    return $result
}

function _WriteHypervisorSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $WorkingDirectory,
        [Parameter(Mandatory)]          $Data,
        [Parameter(Mandatory)] [ref]    $Result,
        [Parameter(Mandatory)] [string] $Fmt
    )
    $sumData = [ordered]@{
        schema_version = '1.0'
        host           = @{ computer_name = $env:COMPUTERNAME }
        collected_utc  = (Get-Date).ToUniversalTime().ToString($Fmt)
        data           = $Data
    }
    $sumDir = Join-Path $WorkingDirectory 'summary'
    if (-not (Test-Path -LiteralPath $sumDir)) {
        New-Item -ItemType Directory -Force -Path $sumDir | Out-Null
    }
    $sumPath = Join-Path $sumDir 'hypervisor.json'
    [System.IO.File]::WriteAllText($sumPath, ($sumData | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
    $Result.Value.Artifacts += @{
        path           = 'summary/hypervisor.json'
        category       = 'hypervisor'
        schema_version = '1.0'
        type           = 'derived'
        description    = "Hypervisor: $($Data.detected_platform); guest agent: $($Data.guest_agent_name) $($Data.guest_agent_version)"
    }
}
