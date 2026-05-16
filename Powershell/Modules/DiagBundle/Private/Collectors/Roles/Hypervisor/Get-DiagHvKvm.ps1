function Get-DiagHvKvm {
    <#
    .SYNOPSIS
        KVM / OpenShift Virtualization (KubeVirt) / RHV guest collector.
        Detects qemu-guest-agent install path and version, copies its log
        files, captures virtio-win installer logs in window, exports VirtIO
        and QEMU registry hives, and inventories the VirtIO paravirt driver
        family.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $WorkingDirectory,
        [Parameter(Mandatory)] [string] $RawDir,
        [Parameter(Mandatory)] [int]    $WindowHours,
        [Parameter(Mandatory)] [ref]    $HvData,
        [Parameter(Mandatory)] [ref]    $Result
    )

    $platformDir = Join-Path $RawDir 'kvm'
    if (-not (Test-Path -LiteralPath $platformDir)) {
        New-Item -ItemType Directory -Force -Path $platformDir | Out-Null
    }
    $cutoff = (Get-Date).AddHours(-1 * $WindowHours)

    $HvData.Value.guest_agent_name = 'qemu-guest-agent'

    foreach ($candidate in @('C:\Program Files\Qemu-ga','C:\Program Files\QEMU\Qemu-ga')) {
        if (Test-Path -LiteralPath $candidate) {
            $HvData.Value.guest_agent_installed    = $true
            $HvData.Value.guest_agent_install_path = $candidate
            break
        }
    }
    if ($HvData.Value.guest_agent_installed) {
        $bin = Join-Path $HvData.Value.guest_agent_install_path 'qemu-ga.exe'
        if (Test-Path -LiteralPath $bin) {
            try {
                $HvData.Value.guest_agent_version = "$((Get-Item -LiteralPath $bin -ErrorAction Stop).VersionInfo.FileVersion)"
            } catch { }
        }
    }

    foreach ($srcDir in @($HvData.Value.guest_agent_install_path,
                           'C:\ProgramData\Qemu-ga',
                           (Join-Path $env:windir 'Temp\qemu-ga'))) {
        if (-not $srcDir) { continue }
        if (-not (Test-Path -LiteralPath $srcDir)) { continue }
        _CopyAgentLogs -SrcDir $srcDir `
                       -DstDir (Join-Path $platformDir 'agent_logs') `
                       -Patterns 'qemu-ga.log*','*.txt' `
                       -HvData $HvData -Result $Result `
                       -ArtifactCategory 'hypervisor_agent_log' `
                       -BundlePathPrefix 'raw/role_specific/hypervisor/kvm/agent_logs'
    }

    _CopyInstallerLogsInWindow -Patterns 'virtio-win*.log','virtio*.log' `
                               -DstDir (Join-Path $platformDir 'installer_logs') `
                               -Cutoff $cutoff `
                               -HvData $HvData -Result $Result `
                               -BundlePathPrefix 'raw/role_specific/hypervisor/kvm/installer_logs'

    foreach ($pair in @(
        @{ Key = 'HKLM\SOFTWARE\Red Hat'; Name = 'redhat_registry.reg'; Description = 'reg export HKLM\SOFTWARE\Red Hat' },
        @{ Key = 'HKLM\SOFTWARE\QEMU';    Name = 'qemu_registry.reg';   Description = 'reg export HKLM\SOFTWARE\QEMU'    }
    )) {
        $regOut = Join-Path $platformDir $pair.Name
        Invoke-DiagTimed -Collector 'Get-DiagHvKvm' -Step "reg export $($pair.Key)" -Action {
            & reg.exe export $pair.Key $regOut /y 2>&1
        } | Out-Null
        if (Test-Path -LiteralPath $regOut) {
            $Result.Value.Artifacts += @{
                path        = "raw/role_specific/hypervisor/kvm/$($pair.Name)"
                category    = 'hypervisor_registry'
                type        = 'raw'
                description = $pair.Description
            }
        }
    }

    if ($HvData.Value.guest_agent_install_path) {
        _AddBinaryVersionInfo -InstallPath $HvData.Value.guest_agent_install_path -BinaryName 'qemu-ga.exe' -HvData $HvData
    }

    _CapturePvDrivers   -Names 'viostor','vioscsi','netkvm','vioser','balloon','vioinput','viogpudo','viorng' -HvData $HvData
    _CaptureNicAdvanced -InterfaceLike '*VirtIO*' -HvData $HvData
    _CaptureTimeSyncProvider -HvData $HvData

    $ovirtAgent = 'C:\Program Files\oVirt Guest Agent'
    if (Test-Path -LiteralPath $ovirtAgent) {
        $HvData.Value.platform_specific['ovirt_legacy_agent_present'] = $true
    }
}
