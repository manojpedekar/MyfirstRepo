function Get-DiagHvHyperV {
    <#
    .SYNOPSIS
        Hyper-V guest collector. Hyper-V Integration Services are built into
        Windows so there is no separate install path or log directory; we
        capture the IC version registry, key IC binary FileVersionInfo, and
        the paravirt driver inventory. Hypervisor-specific EVTX channels
        (Microsoft-Windows-Hyper-V-*) are auto-discovered by A23 in
        Get-DiagEventLogs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $WorkingDirectory,
        [Parameter(Mandatory)] [string] $RawDir,
        [Parameter(Mandatory)] [int]    $WindowHours,
        [Parameter(Mandatory)] [ref]    $HvData,
        [Parameter(Mandatory)] [ref]    $Result
    )

    $platformDir = Join-Path $RawDir 'hyperv'
    if (-not (Test-Path -LiteralPath $platformDir)) {
        New-Item -ItemType Directory -Force -Path $platformDir | Out-Null
    }

    $HvData.Value.guest_agent_name      = 'Hyper-V Integration Services'
    $HvData.Value.guest_agent_installed = $true

    try {
        $is = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Virtual Machine\Auto' -ErrorAction Stop
        if ($is.PSObject.Properties['IntegrationServicesVersion']) {
            $HvData.Value.guest_agent_version = "$($is.IntegrationServicesVersion)"
        }
        if ($is.PSObject.Properties['IntegrationComponents']) {
            $HvData.Value.platform_specific['integration_components_state'] = "$($is.IntegrationComponents)"
        }
    } catch { }

    $regOut = Join-Path $platformDir 'hyperv_registry.reg'
    Invoke-DiagTimed -Collector 'Get-DiagHvHyperV' -Step 'reg export HyperV guest' -Action {
        & reg.exe export 'HKLM\SOFTWARE\Microsoft\Virtual Machine' $regOut /y 2>&1
    } | Out-Null
    if (Test-Path -LiteralPath $regOut) {
        $HvData.Value.registry_export_path = 'raw/role_specific/hypervisor/hyperv/hyperv_registry.reg'
        $Result.Value.Artifacts += @{
            path        = 'raw/role_specific/hypervisor/hyperv/hyperv_registry.reg'
            category    = 'hypervisor_registry'
            type        = 'raw'
            description = 'reg export HKLM\SOFTWARE\Microsoft\Virtual Machine'
        }
    }

    foreach ($bin in 'vmicsvc.exe','vmcompute.exe','vmwp.exe') {
        $candidate = Join-Path $env:windir "system32\$bin"
        if (Test-Path -LiteralPath $candidate) {
            _AddBinaryVersionInfo -InstallPath (Split-Path -Parent $candidate) -BinaryName $bin -HvData $HvData
        }
    }

    _CapturePvDrivers   -Names 'vmbus','vmbusr','netvsc','storvsc','hyperv','vid' -HvData $HvData
    _CaptureNicAdvanced -InterfaceLike '*Hyper-V*' -HvData $HvData
    _CaptureTimeSyncProvider -HvData $HvData
}
